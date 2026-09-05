package com.mysttic.chatt

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

/**
 * Okno aplikacji podpina się do silnika trzymanego w [ChattApplication],
 * zamiast tworzyć własny. Zamknięcie okna nie ubija wtedy Darta, więc
 * nasłuch w tle przeżywa (dopóki żyje proces, patrz [ChattService]).
 */
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        askForNotifications()
    }

    /** Od Androida 13 bez zgody nie pokażemy nic o nowej wiadomości. */
    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        FlutterEngineCache.getInstance().get(ChattApplication.ENGINE_ID)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    /**
     * Kanały i wtyczki są już podpięte przy tworzeniu silnika, domyślna
     * implementacja rejestrowałaby je drugi raz.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) = Unit
}
