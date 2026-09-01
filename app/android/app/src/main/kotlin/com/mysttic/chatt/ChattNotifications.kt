package com.mysttic.chatt

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Powiadomienia o wiadomościach, które przyszły przy zamkniętym oknie.
 * Osobny kanał od tego, którym [ChattService] informuje o samym nasłuchu:
 * tamten ma być cichy i niewidoczny na co dzień, ten ma zwrócić uwagę.
 */
object ChattNotifications {
    private const val CHANNEL_ID = "chatt_wiadomosci"

    fun showMessage(context: Context, title: String, body: String, id: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Wiadomości",
                NotificationManager.IMPORTANCE_HIGH,
            )
            channel.description = "Nowe wiadomości i pliki od innych urządzeń"
            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }

        val openApp = PendingIntent.getActivity(
            context,
            id,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(openApp)
            .build()

        try {
            // Bez zgody na powiadomienia (Android 13+) system to zignoruje —
            // aplikacja ma działać dalej, tylko po cichu.
            NotificationManagerCompat.from(context).notify(id, notification)
        } catch (error: SecurityException) {
            // brak uprawnienia POST_NOTIFICATIONS
        }
    }
}
