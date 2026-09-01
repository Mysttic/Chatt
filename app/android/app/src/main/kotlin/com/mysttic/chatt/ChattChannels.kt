package com.mysttic.chatt

import android.content.Context
import android.content.Intent
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Kanały platformowe aplikacji. Instalowane na silniku Fluttera trzymanym
 * w cache'u ([ChattApplication]), a nie w aktywności — dzięki temu działają
 * także wtedy, gdy okno aplikacji jest zamknięte, a proces trzyma usługa
 * pierwszoplanowa.
 */
object ChattChannels {
    private const val filesChannel = "chatt/files"
    private const val backgroundChannel = "chatt/background"

    fun install(context: Context, engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger

        MethodChannel(messenger, filesChannel).setMethodCallHandler { call, result ->
            val path = call.argument<String>("path")
            if (path == null) {
                result.error("no_path", "Brak ścieżki pliku", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "open" -> result.success(sendFile(context, path, share = false))
                "share" -> result.success(sendFile(context, path, share = true))
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, backgroundChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> result.success(
                    ChattService.start(
                        context,
                        call.argument<String>("title"),
                        call.argument<String>("body"),
                    )
                )
                "stop" -> {
                    ChattService.stop(context)
                    result.success(true)
                }
                "notify" -> {
                    ChattNotifications.showMessage(
                        context,
                        call.argument<String>("title") ?: "Chatt",
                        call.argument<String>("body") ?: "",
                        call.argument<Int>("id") ?: 0,
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Android nie pozwala podać innej aplikacji zwykłej ścieżki (od API 24
     * leci FileUriExposedException), więc plik wychodzi jako content://
     * z FileProvidera, z jednorazowym prawem do odczytu.
     */
    private fun sendFile(context: Context, path: String, share: Boolean): Boolean {
        val file = File(path)
        if (!file.exists()) return false
        return try {
            val uri = FileProvider.getUriForFile(
                context, "${context.packageName}.fileprovider", file)
            val type = mimeTypeOf(file.name)
            val intent = if (share) {
                Intent(Intent.ACTION_SEND).apply {
                    setType(type)
                    putExtra(Intent.EXTRA_STREAM, uri)
                }
            } else {
                Intent(Intent.ACTION_VIEW).apply { setDataAndType(uri, type) }
            }
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // Chooser zamiast gołego startActivity: bez niego brak aplikacji
            // obsługującej typ pliku kończy się wyjątkiem zamiast komunikatem.
            // NEW_TASK, bo startujemy z kontekstu aplikacji, nie z aktywności.
            val chooser = Intent.createChooser(intent, if (share) "Udostępnij" else "Otwórz")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(chooser)
            true
        } catch (error: Exception) {
            false
        }
    }

    private fun mimeTypeOf(name: String): String {
        val extension = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: "application/octet-stream"
    }
}
