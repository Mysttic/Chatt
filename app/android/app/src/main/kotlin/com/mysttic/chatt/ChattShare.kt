package com.mysttic.chatt

import android.app.Activity
import android.content.ClipData
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.Person
import androidx.core.content.IntentCompat
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import kotlin.concurrent.thread

/**
 * Udostępnianie do Chatta z innych aplikacji (issue #60), kanał `chatt/share`.
 *
 * Przyjęcie: [ShareActivity] oddaje tu intencję z systemowego okna
 * „Udostępnij". Tekst jedzie od razu, pliki kopiujemy w tle do
 * `cache/udostepnione/` od pierwszej chwili, tak jak wybrane spinaczem
 * ([ChattFileCache]). Dart dostaje zapowiedź (`take`): tekst, liczbę plików
 * i rozmówcę, jeśli wskazano go wprost w oknie systemu. Kopie bierze
 * (`files`) do pokazania nad polem wiadomości i do wysyłki, a po rezygnacji
 * każe je skasować (`discard`).
 *
 * Prawo do cudzego `content://` należy do okna, które dostało intencję,
 * i znika razem z nim. [ShareActivity] znika od razu, więc intencja do okna
 * Chatta niesie te same adresy w ClipData z prawem do odczytu: system
 * przypisuje je wtedy także [MainActivity] i kopiowanie trwa dalej.
 *
 * Przyjmujemy wyłącznie `content://`. Zwykła ścieżka (`file://`) pozwoliłaby
 * obcej aplikacji wskazać plik z prywatnego katalogu Chatta, na przykład
 * bazę rozmów, który proces Chatta sam przeczyta. `content://` z własnego
 * FileProvidera zostaje: sięga tylko do korzeni z `res/xml/file_paths.xml`
 * i tędy idzie przekazanie dalej odebranego pliku („Udostępnij" w Chatcie).
 *
 * W drugą stronę idą rozmowy, które system pokazuje wprost w oknie
 * „Udostępnij" (Android 10+) i po przytrzymaniu ikony Chatt (`setTargets`):
 * skróty długowieczne z kategorią z `res/xml/shortcuts.xml`, identyfikator
 * to guid rozmówcy. Stuknięcie w skrót na ekranie głównym otwiera rozmowę.
 *
 * Stan żyje w wątku głównym, poza samym kopiowaniem.
 */
object ChattShare {
    private const val CHANNEL = "chatt/share"

    /** Podkatalog cache na kopie, osobny, jak `wybrane` i `wklejone`. */
    private const val SUBDIR = "udostepnione"

    /** Kategoria skrótów rozmów, ta sama co w `res/xml/shortcuts.xml`. */
    private const val CATEGORY = "com.mysttic.chatt.category.ROZMOWA"

    /** Akcja intencji, którą [ShareActivity] wyciąga okno Chatta na wierzch. */
    private const val ACTION_FORWARD = "com.mysttic.chatt.UDOSTEPNIJ"

    /** Guid rozmówcy w intencji skrótu rozmowy. */
    private const val EXTRA_PEER = "chatt.peer"

    /** Pliki jednej przyjętej treści. */
    private class Share(val id: String) {
        /** Kopie (ścieżka, nazwa, rozmiar); null, dopóki kopiowanie trwa. */
        var files: List<Map<String, Any>>? = null

        /** Dart czeka na kopie (`files`), a kopiowanie jeszcze trwa. */
        val waiting = mutableListOf<MethodChannel.Result>()

        /** Użytkownik zrezygnował: kopiowanie staje, kopie idą do kosza. */
        @Volatile
        var discarded = false
    }

    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())

    /** Przyjęte treści, których kopie Dart może jeszcze wziąć albo odrzucić. */
    private val shares = mutableMapOf<String, Share>()

    /**
     * Ostatnia zapowiedź dla Darta (treść albo skrót rozmowy), dopóki jej nie
     * odbierze. Nowsza wypiera starszą.
     */
    private var inbox: Map<String, Any?>? = null

    fun install(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        val kanal = MethodChannel(messenger, CHANNEL)
        kanal.setMethodCallHandler { call, result ->
            when (call.method) {
                "take" -> {
                    result.success(inbox)
                    inbox = null
                }
                "files" -> files(call.argument<String>("id"), result)
                "discard" -> {
                    discard(call.argument<String>("id"))
                    result.success(null)
                }
                "keep" -> {
                    // Pliki poszły do rozmowy. Kopie zostają: wysłana
                    // wiadomość czyta je przy ponowieniu i przy otwieraniu.
                    shares.remove(call.argument<String>("id"))
                    result.success(null)
                }
                "setTargets" -> result.success(
                    setTargets(app, call.argument<List<Map<String, Any?>>>("targets").orEmpty())
                )
                "reportUsed" -> {
                    call.argument<String>("id")?.let { reportUsed(app, it) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        channel = kanal
    }

    /**
     * Przyjęcie intencji z okna „Udostępnij". Zwraca intencję, która wyciąga
     * okno Chatta na wierzch, albo null, gdy to nie było udostępnianie.
     */
    fun receive(activity: Activity, intent: Intent?): Intent? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) {
            return null
        }
        val uris = urisOf(intent)
        val pliki = uris.filter { it.scheme == ContentResolver.SCHEME_CONTENT }
        val share = Share(UUID.randomUUID().toString())

        // Starsza zapowiedź, której Dart nie zdążył odebrać, przepada razem
        // z kopiami: do wyboru rozmowy idzie tylko najnowsze udostępnienie.
        (inbox?.get("id") as? String)?.let { discard(it) }
        if (pliki.isNotEmpty()) {
            shares[share.id] = share
            copyInBackground(activity.applicationContext, share, pliki)
        }
        announce(
            mapOf(
                "kind" to "share",
                "id" to share.id,
                "text" to textOf(intent, hasFiles = uris.isNotEmpty()),
                "count" to pliki.size,
                "skipped" to uris.size - pliki.size,
                // Rozmówca stuknięty wprost w oknie systemu (skrót rozmowy).
                "peer" to intent.getStringExtra(ShortcutManagerCompat.EXTRA_SHORTCUT_ID),
            )
        )

        return Intent(activity, MainActivity::class.java).apply {
            action = ACTION_FORWARD
            // Zadanie Chatta na wierzch, a w nim to samo okno. CLEAR_TOP zdejmuje
            // to, co leży nad nim (na przykład otwarte okno wyboru plików),
            // SINGLE_TOP oddaje intencję istniejącemu oknu.
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            if (pliki.isNotEmpty()) {
                val clip = ClipData.newRawUri("", pliki.first())
                pliki.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
                clipData = clip
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
    }

    /**
     * Intencja okna Chatta. Skrót rozmowy (przytrzymanie ikony Chatt) niesie
     * guid rozmówcy. Okno odtworzone z listy ostatnich zadań dostaje swoją
     * dawną intencję jeszcze raz, więc tę pomijamy.
     */
    fun handleIntent(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val peer = intent.getStringExtra(EXTRA_PEER) ?: return
        announce(mapOf("kind" to "open", "peer" to peer))
    }

    private fun announce(event: Map<String, Any?>) {
        inbox = event
        // Dart odbiera zapowiedź sam (`take`). Przed startem Darta wiadomość
        // czeka w buforze kanału, a gdyby przepadła, Dart i tak pyta przy
        // starcie.
        channel?.invokeMethod("incoming", null)
    }

    /**
     * Adresy plików. Jeden przychodzi w EXTRA_STREAM jako Uri, kilka jako
     * lista. Aplikacje mylą jedno z drugim, więc sprawdzamy obie postaci,
     * a na koniec ClipData.
     */
    private fun urisOf(intent: Intent): List<Uri> {
        val uris = mutableListOf<Uri>()
        IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
            ?.let(uris::add)
        if (uris.isEmpty()) {
            IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                ?.let(uris::addAll)
        }
        if (uris.isEmpty()) {
            val clip = intent.clipData
            if (clip != null) {
                (0 until clip.itemCount).mapNotNullTo(uris) { clip.getItemAt(it).uri }
            }
        }
        return uris.distinct()
    }

    /**
     * Tekst do pola wiadomości. Temat (EXTRA_SUBJECT) tylko wtedy, gdy nie ma
     * ani tekstu, ani plików: przy odnośniku z przeglądarki to tytuł strony,
     * który rozmówca i tak zobaczy w podglądzie.
     */
    private fun textOf(intent: Intent, hasFiles: Boolean): String? {
        val tekst = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            ?: intent.getCharSequenceArrayListExtra(Intent.EXTRA_TEXT)?.joinToString("\n")
        if (!tekst.isNullOrBlank()) return tekst
        if (hasFiles) return null
        return intent.getStringExtra(Intent.EXTRA_SUBJECT)?.takeIf { it.isNotBlank() }
    }

    /**
     * Kopie po kolei, w wątku roboczym: film z karty pamięci potrafi
     * kopiować się sekundy. Plik, którego dostawca nie oddał, wypada.
     */
    private fun copyInBackground(context: Context, share: Share, uris: List<Uri>) {
        thread(name = "chatt-udostepnione") {
            val kopie = mutableListOf<Map<String, Any>>()
            for (uri in uris) {
                if (share.discarded) break
                // Rozszerzenie z typu MIME, gdy dostawca nie dał nazwy z kropką,
                // jak przy schowku: obrazek z przeglądarki przychodzi bez nazwy.
                val path = ChattFileCache.copy(context, uri, SUBDIR, "plik", typed = true)
                    ?: continue
                val plik = File(path)
                kopie += mapOf("path" to path, "name" to plik.name, "size" to plik.length())
            }
            // Wynik kanału wolno oddać tylko z wątku głównego.
            main.post { copied(share, kopie) }
        }
    }

    private fun copied(share: Share, kopie: List<Map<String, Any>>) {
        if (share.discarded) {
            deleteCopies(kopie)
            return
        }
        share.files = kopie
        share.waiting.forEach { it.success(kopie) }
        share.waiting.clear()
    }

    private fun files(id: String?, result: MethodChannel.Result) {
        val share = shares[id]
        val kopie = share?.files
        when {
            share == null -> result.success(emptyList<Any>())
            kopie != null -> result.success(kopie)
            else -> share.waiting += result
        }
    }

    /**
     * Rezygnacja z treści: kopie do kosza. W trakcie kopiowania robi to wątek
     * kopiujący, gdy skończy bieżący plik.
     */
    private fun discard(id: String?) {
        val share = shares.remove(id) ?: return
        share.discarded = true
        share.waiting.forEach { it.success(emptyList<Any>()) }
        share.waiting.clear()
        share.files?.let(::deleteCopies)
    }

    /** Każda kopia ma własny katalog (`udostepnione/<uuid>/`) i znika razem z nim. */
    private fun deleteCopies(kopie: List<Map<String, Any>>) {
        thread(name = "chatt-udostepnione-kosz") {
            for (kopia in kopie) {
                val path = kopia["path"] as? String ?: continue
                File(path).parentFile?.deleteRecursively()
            }
        }
    }

    /**
     * Rozmowy w oknie „Udostępnij" i po przytrzymaniu ikony Chatt, w kolejności
     * od pierwszej. Lista zastępuje poprzednią. Skróty, które z niej wypadły,
     * znikają też z pamięci systemu, która długowieczne trzyma dłużej niż
     * listę skrótów aplikacji. Przypięty do ekranu głównego zostaje, ten
     * usuwa tylko użytkownik.
     */
    private fun setTargets(context: Context, targets: List<Map<String, Any?>>): Boolean = try {
        val limit = ShortcutManagerCompat.getMaxShortcutCountPerActivity(context)
        val skroty = targets.take(limit).mapIndexedNotNull { rank, target ->
            shortcutOf(context, target, rank)
        }
        val obecne = skroty.map { it.id }.toSet()
        val dawne = ShortcutManagerCompat.getShortcuts(
            context,
            ShortcutManagerCompat.FLAG_MATCH_DYNAMIC or ShortcutManagerCompat.FLAG_MATCH_CACHED,
        ).map { it.id }.filter { it !in obecne }
        if (dawne.isNotEmpty()) ShortcutManagerCompat.removeLongLivedShortcuts(context, dawne)
        ShortcutManagerCompat.setDynamicShortcuts(context, skroty)
    } catch (error: Exception) {
        // Limit wywołań w tle albo odmowa systemu. Lista wróci przy
        // następnej zmianie rozmów.
        Log.w("Chatt", "Nie udało się ustawić skrótów rozmów", error)
        false
    }

    private fun shortcutOf(context: Context, target: Map<String, Any?>, rank: Int): ShortcutInfoCompat? {
        val id = target["id"] as? String ?: return null
        val label = (target["label"] as? String)?.takeIf { it.isNotBlank() } ?: return null
        val png = target["icon"] as? ByteArray
        // Awatar rysuje Dart w kolorach stylu, na pełnym kwadracie: system
        // sam przycina go do kształtu ikon.
        val icon = png
            ?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
            ?.let { IconCompat.createWithAdaptiveBitmap(it) }
            ?: IconCompat.createWithResource(context, R.mipmap.ic_launcher)
        return ShortcutInfoCompat.Builder(context, id)
            .setShortLabel(label)
            .setIcon(icon)
            .setIntent(
                Intent(Intent.ACTION_VIEW, null, context, MainActivity::class.java)
                    .putExtra(EXTRA_PEER, id)
            )
            .setLongLived(true)
            .setPerson(Person.Builder().setKey(id).setName(label).setIcon(icon).build())
            .setCategories(setOf(CATEGORY))
            .setRank(rank)
            .build()
    }

    /** Wysłana wiadomość podnosi rozmowę w podpowiedziach systemu. */
    private fun reportUsed(context: Context, id: String) {
        try {
            ShortcutManagerCompat.reportShortcutUsed(context, id)
        } catch (error: Exception) {
            Log.w("Chatt", "Nie udało się zgłosić użycia skrótu", error)
        }
    }
}
