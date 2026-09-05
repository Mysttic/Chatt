package com.mysttic.chatt

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Usługa pierwszoplanowa: jedyny sposób, żeby Android nie ubił procesu po
 * zamknięciu okna. Trzyma przy życiu proces z silnikiem Fluttera, w którym
 * siedzi serwer wiadomości i responder discovery. Stąd stałe powiadomienie:
 * bez niego system nie zgodziłby się na nasłuch w tle.
 *
 * Poza procesem trzyma jeszcze blokady Wi-Fi, bo sam żywy proces nie
 * wystarczy: bez MulticastLock układ Wi-Fi odsiewa pakiety rozgłoszeniowe
 * zanim dojdą do aplikacji, czyli ginie discovery. WifiLock ma trzymać radio
 * z dala od głębokiego oszczędzania przy zgaszonym ekranie, ale od Androida 13
 * jest bezużyteczny (szczegóły przy [acquireWifiLocks]), tam broni nas już
 * tylko wyjątek od optymalizacji baterii, o który prosimy z ustawień.
 */
class ChattService : Service() {

    private var title = "Chatt"
    private var body = ""
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        acquireWifiLocks()
    }

    override fun onDestroy() {
        releaseWifiLocks()
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Teksty przychodzą z Darta, żeby szły za językiem wybranym
        // w aplikacji, a nie za językiem systemu.
        intent?.getStringExtra(EXTRA_TITLE)?.let { title = it }
        intent?.getStringExtra(EXTRA_BODY)?.let { body = it }
        startForeground(NOTIFICATION_ID, buildNotification())
        // Gdyby system nas jednak ubił (skrajny brak pamięci), niech wróci.
        return START_STICKY
    }

    /**
     * Obie blokady biorą kontekst aplikacji, a nie usługi, bo usługa może
     * zniknąć wcześniej niż blokada, a wtedy trzymanie referencji do niej
     * byłoby wyciekiem. Bez zliczania referencji: bierzemy raz i oddajemy raz.
     */
    private fun acquireWifiLocks() {
        val wifi = applicationContext.getSystemService(WifiManager::class.java) ?: return
        try {
            multicastLock = wifi.createMulticastLock("chatt-discovery").apply {
                setReferenceCounted(false)
                acquire()
            }
            // WifiLock bierzemy tylko do Androida 12 włącznie. Jedyny tryb
            // działający przy zgaszonym ekranie to HIGH_PERF, a od Androida 13
            // system przyjmuje go i ignoruje (sprawdzone: `dumpsys wifi`
            // pokazuje wtedy „0 full high perf"). LOW_LATENCY nie zastępuje go
            // wcale, jest aktywny wyłącznie dla aplikacji na wierzchu.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                @Suppress("DEPRECATION")
                wifiLock = wifi.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                    "chatt-nasluch",
                ).apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } catch (error: Exception) {
            // Brak Wi-Fi (np. tylko sieć komórkowa) albo producent zabrał
            // blokady, aplikacja ma działać dalej, tylko gorzej w tle.
        }
    }

    private fun releaseWifiLocks() {
        try {
            multicastLock?.takeIf { it.isHeld }?.release()
            wifiLock?.takeIf { it.isHeld }?.release()
        } catch (error: Exception) {
            // Zwolnienie już zwolnionej blokady, nie ma czym się przejmować.
        }
        multicastLock = null
        wifiLock = null
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Nasłuch w sieci",
                // LOW: bez dźwięku i wibracji, to tylko informacja o działaniu.
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.description = "Informacja o tym, że Chatt odbiera wiadomości w tle"
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }

        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(openApp)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "chatt_nasluch"
        private const val NOTIFICATION_ID = 1

        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"

        fun start(context: Context, title: String?, body: String?): Boolean = try {
            val intent = Intent(context, ChattService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_BODY, body)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            true
        } catch (error: Exception) {
            // Np. limity startu usług w tle, aplikacja ma działać dalej.
            false
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ChattService::class.java))
        }
    }
}
