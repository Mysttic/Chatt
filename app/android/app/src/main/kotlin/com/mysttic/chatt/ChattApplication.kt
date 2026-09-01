package com.mysttic.chatt

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Silnik Fluttera startuje razem z procesem i żyje dłużej niż okno aplikacji.
 * Dzięki temu po zamknięciu ekranu (albo zmieceniu z listy zadań) serwer
 * wiadomości i discovery dalej działają, o ile proces trzyma [ChattService].
 */
class ChattApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
        ChattChannels.install(this, engine)
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    companion object {
        const val ENGINE_ID = "chatt"
    }
}
