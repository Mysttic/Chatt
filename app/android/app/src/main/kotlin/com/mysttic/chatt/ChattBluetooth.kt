package com.mysttic.chatt

import android.Manifest
import android.app.Activity
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.lang.ref.WeakReference
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

/**
 * Bluetooth jako druga droga dla bajtów Chatta (issue #27).
 *
 * Ten kod nie wie nic o wiadomościach, plikach ani szyfrowaniu. Robi jedną
 * rzecz: doprowadza łącze RFCOMM i przekłada je na zwykłe gniazdo TCP pod
 * 127.0.0.1, po którym strona Dartowa rozmawia `dart:io`. Cała reszta
 * protokołu żyje w `lib/network/bt_link.dart` i tam daje się testować bez
 * radia.
 *
 * Dlaczego mostek: wynik `MethodChannel`
 * wolno oddać tylko z wątku platformy, więc pompa bajtów przez kanał albo
 * blokowałaby interfejs, albo wymagała własnej drogi powrotnej z wątku
 * roboczego. Mostek zdejmuje jedno i drugie: każde wołanie kanału wraca
 * natychmiast, a bajty płyną wątkami, które nikogo nie obchodzą.
 *
 * Kanał `chatt/bluetooth`. Metody dzielą się na trzy rodziny:
 *
 *  - stan radia: `status`, `openSettings`, `discoverable`, `showSelf`
 *  - wyszukiwanie: `scan`, `scanResults`
 *  - łącza: `linkStart`, `linkStop`, `linkConnect`, `linkPoll`, `linkClose`
 *  - pomiar (rozpoznanie, `tool/bt_spike.dart`): `bench*`
 *
 * Żadna z nich nie blokuje dłużej niż na chwilę. Rzeczy, które trwają
 * (nasłuch, łączenie, wyszukiwanie), oddają wynik przez `linkPoll`
 * i `scanResults`.
 *
 * Kanał woła wyłącznie dodatek Bluetooth z ustawień Chatta. Dopóki dodatek
 * jest wyłączony, nic tutaj się nie wykonuje.
 */
object ChattBluetooth {
    private const val channelName = "chatt/bluetooth"

    /** Zwracane z [wykonaj], gdy metoda jest nieznana. */
    private val nieznana = Any()

    private val mainThread = Handler(Looper.getMainLooper())
    private val nextId = AtomicInteger(1)

    /** Kod żądania zgód; 1 należy do powiadomień, 0x4348 do wyboru plików. */
    private const val requestCode = 0x4254

    /** Kod pytania o BLUETOOTH_ADVERTISE przed pokazaniem telefonu. */
    private const val advertiseRequestCode = 0x4255

    /** Kod systemowego okienka widoczności. */
    private const val visibleRequestCode = 0x4256

    /** Na ile sekund telefon pokazuje się w pobliżu; tyle domyślnie daje Android. */
    private const val visibleSeconds = 120

    /** Pamięć o odmowie na stałe (patrz [onPermissionResult]). */
    private const val prefsName = "chatt_bluetooth"
    private const val prefsRefused = "permission_refused"

    /**
     * Okno aplikacji, dopóki jest widoczne: tylko ono może pokazać pytanie
     * o zgodę. Bez niego zostaje ekran ustawień systemu.
     */
    private var activity: WeakReference<Activity>? = null

    // --- łącza ---------------------------------------------------------------

    /**
     * Jedno łącze: gniazdo RFCOMM plus gniazdo nasłuchu TCP, pod które
     * podłącza się strona Dartowa. Bajty przepisują dwa wątki, po jednym
     * na kierunek.
     */
    private class Link(
        val id: Int,
        val peer: String,
        val incoming: Boolean,
        val rfcomm: BluetoothSocket,
        val listener: ServerSocket,
    ) {
        @Volatile var local: Socket? = null
        @Volatile var closed = false

        fun close() {
            if (closed) return
            closed = true
            try { rfcomm.close() } catch (_: IOException) {}
            try { listener.close() } catch (_: IOException) {}
            try { local?.close() } catch (_: IOException) {}
        }
    }

    private val links = ConcurrentHashMap<Int, Link>()

    /**
     * Gniazda w trakcie łączenia. Nieudana próba potrafi dobijać się do
     * urządzenia kilkanaście sekund i przez ten czas zagłusza radio, a przy
     * wyszukiwaniu takich prób jest tyle, ile urządzeń w zasięgu. Zamknięcie
     * gniazda przerywa `connect` natychmiast.
     */
    private val connecting = ConcurrentHashMap<Int, BluetoothSocket>()

    /** Wyniki dla [linkPoll], zabierane przy każdym odpytaniu. */
    private val ready = mutableListOf<Map<String, Any?>>()
    private val failed = mutableListOf<Map<String, Any?>>()
    private val closed = mutableListOf<Map<String, Any?>>()

    /**
     * Notatki ze strony natywnej, odbierane przez [linkPoll]. Radio nie ma
     * konsoli, a błędy mostka widać inaczej dopiero po skutku.
     */
    private val notes = mutableListOf<String>()

    private fun nota(text: String) {
        // Górna granica, żeby log nie urósł w nieskończoność, gdy nikt nie pyta.
        synchronized(notes) { if (notes.size < 200) notes.add(text) }
    }

    private var server: BluetoothServerSocket? = null
    @Volatile private var listening = false

    // --- wyszukiwanie --------------------------------------------------------

    private val found = LinkedHashMap<String, Map<String, Any?>>()
    @Volatile private var scanning = false
    private var receiver: BroadcastReceiver? = null

    // --- pomiar (rozpoznanie) ------------------------------------------------

    private var benchServer: BluetoothServerSocket? = null
    private var benchSocket: BluetoothSocket? = null
    private var benchInput: InputStream? = null
    private var benchOutput: OutputStream? = null

    /** [MainActivity] melduje się, gdy jest widoczna. */
    fun attach(host: Activity) {
        activity = WeakReference(host)
    }

    fun detach(host: Activity) {
        if (activity?.get() === host) activity = null
    }

    fun install(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, channelName).setMethodCallHandler { call, result ->
            // Trzy metody odpowiadają od razu i bez radia: stan, ustawienia
            // systemu (mają sens właśnie wtedy, gdy zgody brakuje) i odbiór
            // wyników, które i tak już leżą gotowe.
            when (call.method) {
                "status" -> {
                    result.success(status(app))
                    return@setMethodCallHandler
                }
                "openSettings" -> {
                    result.success(openSettings(app))
                    return@setMethodCallHandler
                }
                "openLocationSettings" -> {
                    result.success(openLocationSettings(app))
                    return@setMethodCallHandler
                }
                "linkPoll" -> {
                    result.success(linkPoll())
                    return@setMethodCallHandler
                }
                "requestPermission" -> {
                    result.success(requestPermission(app))
                    return@setMethodCallHandler
                }
                // Okienko otwiera okno aplikacji, więc to musi się dziać
                // na wątku głównym.
                "showSelf" -> {
                    result.success(pokazSie(app))
                    return@setMethodCallHandler
                }
                "scanResults" -> {
                    result.success(scanResults())
                    return@setMethodCallHandler
                }
            }

            val adapter = adapterOf(app)
            if (adapter == null || !adapter.isEnabled) {
                // Radio zgaszone w trakcie szukania potrafi nie przysłać
                // ACTION_DISCOVERY_FINISHED. Zatrzymanie transportu odpina
                // wtedy odbiornik sam.
                if (call.method == "linkStop") {
                    scanning = false
                    odepnij(app)
                }
                result.error("brak_radia", "Bluetooth wyłączony albo niedostępny", null)
                return@setMethodCallHandler
            }
            if (!maZgode(app)) {
                result.error("brak_zgody", "Brak zgody BLUETOOTH_CONNECT", null)
                return@setMethodCallHandler
            }

            // Reszta dotyka gniazd, a wątek główny ma pięć sekund do ANR.
            thread(name = "chatt-bt") {
                var value: Any? = null
                var failure: Exception? = null
                try {
                    value = wykonaj(app, adapter, call)
                } catch (error: Exception) {
                    failure = error
                }
                // Wynik kanału wolno oddać tylko z wątku głównego.
                mainThread.post {
                    val error = failure
                    when {
                        error != null -> result.error("bt", error.toString(), null)
                        value === nieznana -> result.notImplemented()
                        else -> result.success(value)
                    }
                }
            }
        }
    }

    private fun wykonaj(
        context: Context,
        adapter: BluetoothAdapter,
        call: MethodCall,
    ): Any? = when (call.method) {
        "discoverable" -> discoverable(context, call)
        "scan" -> scan(context, adapter)
        "linkStart" -> linkStart(adapter, call)
        "linkStop" -> linkStop(context, adapter)
        "linkConnect" -> linkConnect(adapter, call)
        "linkClose" -> linkClose(call)
        "benchListen" -> benchListen(adapter, call)
        "benchConnect" -> benchConnect(adapter, call)
        "benchSend" -> benchSend(call)
        "benchReceive" -> benchReceive(call)
        "benchPing" -> benchPing(call)
        "benchEcho" -> benchEcho(call)
        "benchClose" -> benchClose()
        else -> nieznana
    }

    // --- łącza ---------------------------------------------------------------

    /**
     * Otwiera nasłuch RFCOMM i przyjmuje kolejnych rozmówców w pętli. Każde
     * przyjęte łącze ląduje w [ready] i czeka tam, aż strona Dartowa odbierze
     * je przez [linkPoll].
     */
    @SuppressLint("MissingPermission")
    private fun linkStart(adapter: BluetoothAdapter, call: MethodCall): Map<String, Any?> {
        if (listening) return mapOf("listening" to true)
        val uuid = UUID.fromString(call.argument<String>("uuid"))
        val name = call.argument<String>("name") ?: "Chatt"
        val secure = call.argument<Boolean>("secure") ?: false

        val listener = if (secure) {
            adapter.listenUsingRfcommWithServiceRecord(name, uuid)
        } else {
            adapter.listenUsingInsecureRfcommWithServiceRecord(name, uuid)
        }
        server = listener
        listening = true

        thread(name = "chatt-bt-accept") {
            while (listening) {
                val socket = try {
                    listener.accept()
                } catch (error: IOException) {
                    // Zamknięcie gniazda nasłuchu wygląda tak samo jak błąd.
                    break
                }
                try {
                    zglos(socket, incoming = true)
                } catch (error: IOException) {
                    try { socket.close() } catch (_: IOException) {}
                }
            }
            listening = false
        }
        // Mapa: strona Dartowa czyta ten sam kształt na obu platformach.
        return mapOf("listening" to true)
    }

    @SuppressLint("MissingPermission")
    private fun linkStop(context: Context, adapter: BluetoothAdapter): Boolean {
        // Szukanie w eterze gaśnie razem z transportem: wyłączony dodatek
        // nie zostawia radia w trakcie zapytania.
        if (scanning) {
            try {
                adapter.cancelDiscovery()
            } catch (_: SecurityException) {
            }
            scanning = false
        }
        odepnij(context)
        synchronized(found) { found.clear() }
        for (socket in connecting.values.toList()) {
            try { socket.close() } catch (_: IOException) {}
        }
        connecting.clear()
        listening = false
        try { server?.close() } catch (_: IOException) {}
        server = null
        for (link in links.values.toList()) rozlacz(link, "transport wyłączony")
        return true
    }

    /**
     * Łączenie idzie własnym wątkiem i melduje się przez [linkPoll], bo
     * RFCOMM potrafi się zastanawiać kilkanaście sekund, a kanał ma wracać
     * od razu. Zwracany identyfikator pozwala poznać swój wynik wśród innych.
     */
    @SuppressLint("MissingPermission")
    private fun linkConnect(adapter: BluetoothAdapter, call: MethodCall): Map<String, Any?> {
        val address = call.argument<String>("address")
            ?: throw IllegalArgumentException("Brak adresu urządzenia")
        val uuid = UUID.fromString(call.argument<String>("uuid"))
        val secure = call.argument<Boolean>("secure") ?: false
        val id = nextId.getAndIncrement()

        thread(name = "chatt-bt-connect") {
            try {
                // Wyszukiwanie zagłusza łącze na cały czas trwania. Od
                // Androida 12 przerwanie cudzego wymaga BLUETOOTH_SCAN,
                // a bez tej zgody odmowa znaczy tylko tyle, że nie mamy
                // czego przerywać.
                try {
                    adapter.cancelDiscovery()
                } catch (_: SecurityException) {
                }
                val device = adapter.getRemoteDevice(address)
                val socket = if (secure) {
                    device.createRfcommSocketToServiceRecord(uuid)
                } else {
                    device.createInsecureRfcommSocketToServiceRecord(uuid)
                }
                connecting[id] = socket
                try {
                    socket.connect()
                } finally {
                    connecting.remove(id)
                }
                zglos(socket, incoming = false, id = id)
            } catch (error: Exception) {
                synchronized(failed) {
                    failed.add(mapOf("id" to id, "error" to error.toString()))
                }
            }
        }
        return mapOf("id" to id)
    }

    /**
     * Gotowe łącze: zakładamy pod nie gniazdo nasłuchu na pętli zwrotnej
     * i czekamy, aż strona Dartowa się podłączy. Dopiero wtedy ruszają
     * pompy, więc żaden bajt z radia nie przepada w międzyczasie.
     */
    @SuppressLint("MissingPermission")
    private fun zglos(socket: BluetoothSocket, incoming: Boolean, id: Int = nextId.getAndIncrement()) {
        // Tylko pętla zwrotna: ten port nie ma prawa być widoczny z sieci.
        val listener = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))
        val link = Link(id, socket.remoteDevice.address, incoming, socket, listener)
        links[id] = link

        thread(name = "chatt-bt-bridge-$id") {
            val local = try {
                // Strona Dartowa ma kilka sekund na odebranie z linkPoll
                // i podłączenie się. Dłuższe czekanie znaczy, że po tamtej
                // stronie nikt już tego łącza nie chce.
                listener.soTimeout = 15000
                listener.accept()
            } catch (error: IOException) {
                rozlacz(link, "Dart nie podłączył się do portu lokalnego")
                return@thread
            }
            local.tcpNoDelay = true
            link.local = local
            try { listener.close() } catch (_: IOException) {}
            nota("lacze $id: mostek stoi, port lokalny ${local.localPort}")

            val fromRadio = socket.inputStream
            val toRadio = socket.outputStream
            val fromDart = local.getInputStream()
            val toDart = local.getOutputStream()
            nota("lacze $id: pompy ruszaja")

            // Drugi kierunek własnym wątkiem: jeden wątek na oba skończyłby
            // się zakleszczeniem przy pierwszym większym pliku.
            thread(name = "chatt-bt-up-$id") {
                przepisz(fromDart, toRadio, link, "dart->radio")
            }
            przepisz(fromRadio, toDart, link, "radio->dart")
        }

        synchronized(ready) {
            ready.add(
                mapOf(
                    "id" to id,
                    "peer" to link.peer,
                    "port" to listener.localPort,
                    "incoming" to incoming,
                )
            )
        }
    }

    private fun przepisz(
        from: InputStream,
        to: OutputStream,
        link: Link,
        label: String,
    ) {
        val buffer = ByteArray(16 * 1024)
        var powod = "$label: lacze zamkniete obok"
        try {
            while (!link.closed) {
                val read = from.read(buffer)
                if (read <= 0) {
                    powod = "$label: read=$read"
                    break
                }
                to.write(buffer, 0, read)
                to.flush()
            }
        } catch (error: IOException) {
            powod = "$label: $error"
        } finally {
            rozlacz(link, powod)
        }
    }

    /**
     * Powód zerwania jedzie do Darta razem z numerem łącza. Bez tego obie
     * strony widzą tylko ciszę tej drugiej i nie da się powiedzieć, która
     * odłożyła słuchawkę pierwsza.
     */
    private fun rozlacz(link: Link, powod: String) = synchronized(link) {
        // Synchronizowane, bo zrywają dwa wątki naraz (po jednym na kierunek)
        // i bez tego oba przechodziły przez sprawdzenie, a powód zapisywał
        // ten, który akurat zdążył drugi.
        if (link.closed) return@synchronized
        nota("lacze ${link.id}: zrywam, $powod")
        link.close()
        links.remove(link.id)
        synchronized(closed) {
            closed.add(mapOf("id" to link.id, "reason" to powod))
        }
    }

    private fun linkClose(call: MethodCall): Boolean {
        val id = call.argument<Int>("id") ?: return false
        nota("lacze $id: Dart kazal zamknac")
        connecting.remove(id)?.let {
            try { it.close() } catch (_: IOException) {}
        }
        links[id]?.let { rozlacz(it, "zamknięte przez Darta") }
        return true
    }

    /**
     * Wszystko, co się wydarzyło od ostatniego pytania. Zabieramy przy
     * odczycie, żeby to samo łącze nie weszło do Darta dwa razy.
     */
    private fun linkPoll(): Map<String, Any?> {
        val a = synchronized(ready) { ready.toList().also { ready.clear() } }
        val b = synchronized(failed) { failed.toList().also { failed.clear() } }
        val c = synchronized(closed) { closed.toList().also { closed.clear() } }
        val d = synchronized(notes) { notes.toList().also { notes.clear() } }
        return mapOf(
            "ready" to a,
            "failed" to b,
            "closed" to c,
            "notes" to d,
            "listening" to listening,
        )
    }

    // --- wyszukiwanie --------------------------------------------------------

    /**
     * Android znajduje urządzenia zapytaniem w eter (inquiry). Odpowiedzi
     * przychodzą rozgłoszeniem systemowym, więc zbieramy je do [found],
     * a strona Dartowa odbiera przez `scanResults`.
     *
     * Bez BLUETOOTH_SCAN nie ma jak szukać: wtedy zostaje lista sparowanych
     * urządzeń ze `status`.
     */
    @SuppressLint("MissingPermission")
    private fun scan(context: Context, adapter: BluetoothAdapter): Map<String, Any?> {
        if (!maZgodeNaSzukanie(context)) {
            return mapOf("scanning" to false, "granted" to false)
        }
        if (scanning) return mapOf("scanning" to true, "granted" to true)

        val app = context.applicationContext
        synchronized(found) { found.clear() }
        // Sparowane urządzenia są znane od razu i nie wymagają eteru.
        for (device in adapter.bondedDevices) zapamietaj(device, bonded = true)

        val odbiorca = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    BluetoothAdapter.ACTION_DISCOVERY_STARTED -> {
                        nota("scan: eter ruszyl")
                    }
                    BluetoothDevice.ACTION_FOUND -> {
                        val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(
                                BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        }
                        if (device != null) {
                            zapamietaj(device, bonded = false)
                            nota("scan: w eterze ${device.address}")
                        }
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                        nota("scan: eter skonczyl, widzianych=${found.size}")
                        scanning = false
                        odepnij(app)
                    }
                }
            }
        }
        receiver = odbiorca
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_STARTED)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        // Od Androida 13 każdy rejestrowany w kodzie odbiornik musi
        // powiedzieć, czy przyjmuje rozgłoszenia spoza aplikacji. Tu musi:
        // ACTION_FOUND przychodzi od usługi Bluetooth, czyli z innego uid,
        // więc przy NOT_EXPORTED nie dociera nic i skan widzi wyłącznie to,
        // co i tak było sparowane. Podszycie się nie wchodzi w grę, bo te
        // rozgłoszenia są systemowo chronione i nikt inny ich nie wyśle.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            app.registerReceiver(odbiorca, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            app.registerReceiver(odbiorca, filter)
        }

        scanning = adapter.startDiscovery()
        nota("scan: startDiscovery=$scanning, sparowanych=${found.size}")
        if (!scanning) odepnij(app)
        return mapOf("scanning" to scanning, "granted" to true)
    }

    @SuppressLint("MissingPermission")
    private fun zapamietaj(device: BluetoothDevice, bonded: Boolean) {
        val name = try {
            device.name
        } catch (error: SecurityException) {
            null
        }
        // Klasa i typ radia układają kolejkę pytania po stronie Darta: adres
        // widziany tylko przez BLE nie przyjmie RFCOMM, a sprawdzenie go
        // kosztowało pełny limit strony.
        val klasa = try {
            device.bluetoothClass?.majorDeviceClass ?: 0
        } catch (error: SecurityException) {
            0
        }
        val typ = try {
            device.type
        } catch (error: SecurityException) {
            BluetoothDevice.DEVICE_TYPE_UNKNOWN
        }
        synchronized(found) {
            found[device.address] = mapOf(
                "address" to device.address,
                "name" to (name ?: device.address),
                "bonded" to bonded,
                "major" to klasa,
                "leOnly" to (typ == BluetoothDevice.DEVICE_TYPE_LE),
            )
        }
    }

    private fun odepnij(context: Context?) {
        val odbiorca = receiver ?: return
        receiver = null
        try {
            context?.applicationContext?.unregisterReceiver(odbiorca)
        } catch (_: IllegalArgumentException) {
            // Już odpięty.
        }
    }

    private fun scanResults(): Map<String, Any?> {
        val lista = synchronized(found) { found.values.toList() }
        return mapOf("scanning" to scanning, "devices" to lista)
    }

    /**
     * Androida to nie dotyczy: proszenie o widoczność okienkiem przy każdym
     * starcie aplikacji byłoby natręctwem. Telefon pokazuje się na żądanie
     * użytkownika, przyciskiem w „W pobliżu" ([pokazSie]). Windows ma tu
     * prawdziwą implementację, bo tam bez tego komputera po prostu nie da się
     * znaleźć.
     */
    private fun discoverable(context: Context, call: MethodCall): Boolean = false

    /**
     * Pokazuje ten telefon urządzeniom w pobliżu na [visibleSeconds] sekund.
     * Bez tego drugi telefon nie znajdzie go w eterze: Android jest widoczny
     * tylko przy otwartym ekranie parowania w ustawieniach. System pozwala na
     * to wyłącznie przez własne okienko z pytaniem, więc decyzja zostaje przy
     * użytkowniku.
     *
     * Od Androida 12 okienko wymaga BLUETOOTH_ADVERTISE. Ta zgoda należy do
     * tej samej grupy co CONNECT i SCAN, więc przy wydanych tamtych system
     * przyznaje ją bez pytania, a okienko otwiera dopiero [onPermissionResult].
     *
     * false znaczy, że nie ma jak zapytać: okno zamknięte albo radio zgaszone.
     */
    private fun pokazSie(context: Context): Boolean {
        val host = activity?.get() ?: return false
        val adapter = adapterOf(context) ?: return false
        if (!adapter.isEnabled) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.BLUETOOTH_ADVERTISE,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                host,
                arrayOf(Manifest.permission.BLUETOOTH_ADVERTISE),
                advertiseRequestCode,
            )
            return true
        }
        return otworzOkienkoWidocznosci(host)
    }

    /**
     * Z wynikiem, bo starsze Androidy bez niego nie znają pytającego
     * i w okienku zamiast nazwy Chatta stoi „aplikacja". Sam wynik nie jest
     * potrzebny: stan widoczności podaje [status].
     */
    @SuppressLint("MissingPermission")
    private fun otworzOkienkoWidocznosci(host: Activity): Boolean = try {
        host.startActivityForResult(
            Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE)
                .putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, visibleSeconds),
            visibleRequestCode,
        )
        true
    } catch (error: Exception) {
        false
    }

    /** Czy telefon jest teraz widoczny w eterze. Bez BLUETOOTH_SCAN nie wiadomo. */
    @SuppressLint("MissingPermission")
    private fun widoczny(adapter: BluetoothAdapter?): Boolean = try {
        adapter?.scanMode == BluetoothAdapter.SCAN_MODE_CONNECTABLE_DISCOVERABLE
    } catch (error: SecurityException) {
        false
    }

    // --- stan radia ----------------------------------------------------------

    private fun status(context: Context): Map<String, Any?> {
        val adapter = adapterOf(context)
        val zgoda = maZgode(context)
        val paired = if (adapter != null && zgoda) {
            try {
                adapter.bondedDevices.map {
                    mapOf("name" to it.name, "address" to it.address)
                }
            } catch (error: SecurityException) {
                emptyList()
            }
        } else {
            emptyList()
        }
        return mapOf(
            "available" to (adapter != null),
            "enabled" to (adapter?.isEnabled ?: false),
            "granted" to zgoda,
            "canScan" to maZgodeNaSzukanie(context),
            "locationOn" to lokalizacjaWlaczona(context),
            "name" to if (zgoda) adapter?.name else null,
            // Od Androida 6 `BluetoothAdapter.getAddress()` zwraca wszystkim
            // 02:00:00:00:00:00, bo prawdziwy adres jest za uprawnieniem
            // systemowym. Telefon nie ma więc jak podać własnego adresu:
            // druga strona odczytuje go z przyjętego połączenia.
            "address" to null,
            "paired" to paired,
            // Telefon pokazuje się tylko na żądanie (`showSelf`); Windows
            // tych pól nie podaje, bo jest widoczny przez cały czas dodatku.
            "canShowSelf" to true,
            "visible" to widoczny(adapter),
        )
    }

    /**
     * Ekran „O aplikacji" w ustawieniach systemu, gdzie użytkownik włącza
     * zgodę „Urządzenia w pobliżu".
     */
    private fun openSettings(context: Context): Boolean = try {
        context.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:${context.packageName}"))
                // NEW_TASK, bo startujemy z kontekstu aplikacji.
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (error: Exception) {
        false
    }

    /**
     * Pyta użytkownika o zgodę na urządzenia w pobliżu. Zwraca false, gdy nie
     * ma czego pytać (okno zamknięte, Android starszy niż 12 albo odmowa na
     * stałe) i wtedy zostaje ekran ustawień systemu.
     *
     * Wynik nie wraca tędy: ekran ustawień Chatta odpytuje stan sam, a pytanie
     * może przeżyć obrót ekranu.
     */
    private fun requestPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        val host = activity?.get() ?: return false
        val zgody = arrayOf(
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN,
        )
        // Po drugiej odmowie Android przestaje pokazywać okienko i zbywa
        // prośbę bez słowa, choć wywołanie przechodzi. Taką odmowę zapisuje
        // [onPermissionResult]; zostaje wtedy ekran ustawień, w którym zgodę
        // da się wydać.
        val pamiec = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val odmowaNaStale = pamiec.getBoolean(prefsRefused, false) && zgody.any {
            ContextCompat.checkSelfPermission(context, it) !=
                PackageManager.PERMISSION_GRANTED &&
                !ActivityCompat.shouldShowRequestPermissionRationale(host, it)
        }
        if (odmowaNaStale) return false
        ActivityCompat.requestPermissions(host, zgody, requestCode)
        return true
    }

    /**
     * Wynik pytania o zgodę, przekazany przez [MainActivity]. Odmowa, przy
     * której system nie chce już wyjaśnień, znaczy odmowę na stałe i zostaje
     * zapamiętana. Okienko zamknięte bez odpowiedzi oddaje pusty wynik
     * i niczego nie zmienia: następnym razem system pokaże je znowu.
     */
    fun onPermissionResult(
        host: Activity,
        code: Int,
        permissions: Array<out String>,
        results: IntArray,
    ) {
        if (code == advertiseRequestCode) {
            // Odmowa niczego nie zapisuje: przycisk zostaje i można spróbować
            // jeszcze raz.
            if (results.isNotEmpty() && results[0] == PackageManager.PERMISSION_GRANTED) {
                otworzOkienkoWidocznosci(host)
            }
            return
        }
        if (code != requestCode || results.isEmpty()) return
        val naStale = permissions.indices.any {
            results[it] != PackageManager.PERMISSION_GRANTED &&
                !ActivityCompat.shouldShowRequestPermissionRationale(host, permissions[it])
        }
        host.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit().putBoolean(prefsRefused, naStale).apply()
    }

    /**
     * Czy system ma włączone usługi lokalizacji.
     *
     * Do wyszukiwania urządzeń Bluetooth nie są potrzebne merytorycznie i od
     * Androida 12 aplikacja deklaruje `neverForLocation`, ale system i tak nie
     * oddaje wtedy ani jednego wyniku. Bez tego sprawdzenia objaw wygląda na
     * „nikogo nie ma w pobliżu" i szuka się go godzinami.
     */
    private fun lokalizacjaWlaczona(context: Context): Boolean {
        val manager = context.getSystemService(LocationManager::class.java)
            ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            manager.isLocationEnabled
        } else {
            @Suppress("DEPRECATION")
            Settings.Secure.getInt(
                context.contentResolver,
                Settings.Secure.LOCATION_MODE,
                Settings.Secure.LOCATION_MODE_OFF,
            ) != Settings.Secure.LOCATION_MODE_OFF
        }
    }

    /** Systemowy ekran lokalizacji. Sami jej nie włączamy: to decyzja użytkownika. */
    private fun openLocationSettings(context: Context): Boolean = try {
        context.startActivity(
            Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                // NEW_TASK, bo startujemy z kontekstu aplikacji.
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (error: Exception) {
        false
    }

    private fun adapterOf(context: Context): BluetoothAdapter? =
        context.getSystemService(BluetoothManager::class.java)?.adapter

    private fun maZgode(context: Context): Boolean {
        // BLUETOOTH_CONNECT pojawiło się w Androidzie 12; wcześniej wystarczy
        // BLUETOOTH z manifestu, którego nikt nie odwołuje w czasie działania.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Do Androida 11 szukanie wymaga zgody na położenie. Chatt o nią nie
     * prosi: tam drugie urządzenie dodaje się po adresie radia.
     */
    private fun maZgodeNaSzukanie(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            // Do Androida 11 wyszukiwanie wymagało zgody na położenie:
            // adres urządzenia w pobliżu mówi, gdzie jesteś.
            return ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
        }
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.BLUETOOTH_SCAN,
        ) == PackageManager.PERMISSION_GRANTED
    }

    // --- pomiar (rozpoznanie, tool/bt_spike.dart) -----------------------------

    @SuppressLint("MissingPermission")
    private fun benchListen(adapter: BluetoothAdapter, call: MethodCall): Map<String, Any?> {
        benchSocket?.let { return mapOf("connected" to true, "peer" to it.remoteDevice.address) }

        val uuid = UUID.fromString(call.argument<String>("uuid"))
        val name = call.argument<String>("name") ?: "Chatt"
        val secure = call.argument<Boolean>("secure") ?: true
        val timeout = call.argument<Int>("timeoutMs") ?: 5000

        val listener = benchServer ?: if (secure) {
            adapter.listenUsingRfcommWithServiceRecord(name, uuid)
        } else {
            adapter.listenUsingInsecureRfcommWithServiceRecord(name, uuid)
        }
        benchServer = listener

        val accepted = try {
            listener.accept(timeout)
        } catch (error: IOException) {
            return mapOf("connected" to false, "peer" to null)
        }
        benchPrzyjmij(accepted)
        try { listener.close() } catch (_: IOException) {}
        benchServer = null
        return mapOf("connected" to true, "peer" to accepted.remoteDevice.address)
    }

    @SuppressLint("MissingPermission")
    private fun benchConnect(adapter: BluetoothAdapter, call: MethodCall): Map<String, Any?> {
        benchSocket?.let { return mapOf("connected" to true, "peer" to it.remoteDevice.address) }

        val address = call.argument<String>("address")
            ?: throw IllegalArgumentException("Brak adresu urządzenia")
        val uuid = UUID.fromString(call.argument<String>("uuid"))
        val secure = call.argument<Boolean>("secure") ?: true

        try {
            adapter.cancelDiscovery()
        } catch (_: SecurityException) {
        }
        val device = adapter.getRemoteDevice(address)
        val fresh = if (secure) {
            device.createRfcommSocketToServiceRecord(uuid)
        } else {
            device.createInsecureRfcommSocketToServiceRecord(uuid)
        }
        fresh.connect()
        benchPrzyjmij(fresh)
        return mapOf("connected" to true, "peer" to fresh.remoteDevice.address)
    }

    private fun benchSend(call: MethodCall): Map<String, Any?> {
        val stream = benchOutput ?: throw IllegalStateException("Brak połączenia")
        val total = call.argument<Int>("bytes") ?: 0
        val chunk = (call.argument<Int>("chunk") ?: 1024).coerceAtLeast(1)

        val buffer = ByteArray(chunk)
        val start = System.nanoTime()
        var done = 0
        while (done < total) {
            val take = minOf(chunk, total - done)
            for (i in 0 until take) buffer[i] = wzorzec(done + i)
            stream.write(buffer, 0, take)
            done += take
        }
        stream.flush()
        return mapOf("bytes" to done, "ms" to msOd(start), "chunk" to chunk)
    }

    private fun benchReceive(call: MethodCall): Map<String, Any?> {
        val stream = benchInput ?: throw IllegalStateException("Brak połączenia")
        val total = call.argument<Int>("bytes") ?: 0

        val buffer = ByteArray(16 * 1024)
        var done = 0
        var hash = fnvStart
        var ok = true
        var started = false
        var start = 0L
        while (done < total) {
            val read = stream.read(buffer, 0, minOf(buffer.size, total - done))
            if (read <= 0) throw IOException("Połączenie zerwane po $done bajtach")
            if (!started) {
                start = System.nanoTime()
                started = true
            }
            for (i in 0 until read) {
                val b = buffer[i]
                if (b != wzorzec(done + i)) ok = false
                hash = fnv(hash, b)
            }
            done += read
        }
        return mapOf("bytes" to done, "ms" to msOd(start), "ok" to ok, "hash" to hash)
    }

    private fun benchPing(call: MethodCall): Map<String, Any?> {
        val out = benchOutput ?: throw IllegalStateException("Brak połączenia")
        val inp = benchInput ?: throw IllegalStateException("Brak połączenia")
        val size = (call.argument<Int>("bytes") ?: 200).coerceAtLeast(1)
        val rounds = (call.argument<Int>("rounds") ?: 20).coerceAtLeast(1)

        val buffer = ByteArray(size) { wzorzec(it) }
        val back = ByteArray(size)
        val start = System.nanoTime()
        repeat(rounds) {
            out.write(buffer)
            out.flush()
            czytajDokladnie(inp, back)
        }
        return mapOf("rounds" to rounds, "ms" to msOd(start), "bytes" to size)
    }

    private fun benchEcho(call: MethodCall): Map<String, Any?> {
        val out = benchOutput ?: throw IllegalStateException("Brak połączenia")
        val inp = benchInput ?: throw IllegalStateException("Brak połączenia")
        val size = (call.argument<Int>("bytes") ?: 200).coerceAtLeast(1)
        val rounds = (call.argument<Int>("rounds") ?: 20).coerceAtLeast(1)

        val buffer = ByteArray(size)
        val start = System.nanoTime()
        repeat(rounds) {
            czytajDokladnie(inp, buffer)
            out.write(buffer)
            out.flush()
        }
        return mapOf("rounds" to rounds, "ms" to msOd(start), "bytes" to size)
    }

    private fun benchClose(): Boolean {
        try { benchInput?.close() } catch (_: IOException) {}
        try { benchOutput?.close() } catch (_: IOException) {}
        try { benchSocket?.close() } catch (_: IOException) {}
        try { benchServer?.close() } catch (_: IOException) {}
        benchInput = null
        benchOutput = null
        benchSocket = null
        benchServer = null
        return true
    }

    private fun benchPrzyjmij(fresh: BluetoothSocket) {
        benchSocket = fresh
        benchInput = fresh.inputStream
        benchOutput = fresh.outputStream
    }

    private fun czytajDokladnie(stream: InputStream, buffer: ByteArray) {
        var done = 0
        while (done < buffer.size) {
            val read = stream.read(buffer, done, buffer.size - done)
            if (read <= 0) throw IOException("Połączenie zerwane po $done bajtach")
            done += read
        }
    }

    private fun msOd(start: Long): Int = ((System.nanoTime() - start) / 1_000_000).toInt()

    /** Wzorzec bajtów: ten sam po obu stronach, więc odbiór sprawdza sam siebie. */
    private fun wzorzec(index: Int): Byte = ((index * 31 + 7) and 0xFF).toByte()

    /** FNV-1a 32-bit, do porównania wyników z dwóch konsol. */
    private const val fnvStart = -2128831035

    private fun fnv(hash: Int, b: Byte): Int = (hash xor (b.toInt() and 0xFF)) * 16777619
}
