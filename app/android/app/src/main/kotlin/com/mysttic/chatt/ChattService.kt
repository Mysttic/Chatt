package com.mysttic.chatt

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Usługa pierwszoplanowa: jedyny sposób, żeby Android nie ubił procesu po
 * zamknięciu okna. Sama nic nie robi — trzyma tylko przy życiu proces
 * z silnikiem Fluttera, w którym siedzi serwer wiadomości i responder
 * discovery. Stąd stałe powiadomienie: bez niego system nie zgodziłby się
 * na nasłuch w tle.
 */
class ChattService : Service() {

    private var title = "Chatt"
    private var body = ""

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Teksty przychodzą z Darta, żeby szły za językiem wybranym
        // w aplikacji, a nie za językiem systemu.
        intent?.getStringExtra(EXTRA_TITLE)?.let { title = it }
        intent?.getStringExtra(EXTRA_BODY)?.let { body = it }
        startForeground(NOTIFICATION_ID, buildNotification())
        // Gdyby system nas jednak ubił (skrajny brak pamięci), niech wróci.
        return START_STICKY
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
            .setSmallIcon(android.R.drawable.stat_notify_sync)
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
            // Np. limity startu usług w tle — aplikacja ma działać dalej.
            false
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ChattService::class.java))
        }
    }
}
