package com.mysttic.chatt

import android.content.Intent
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Otwieranie i udostępnianie odebranych plików. Android nie pozwala podać
 * innej aplikacji zwykłej ścieżki (od API 24 leci FileUriExposedException),
 * więc plik wychodzi jako content:// z FileProvidera, z jednorazowym prawem
 * do odczytu. Własny kanał zamiast wtyczki z pub.dev: to kilkanaście linii,
 * a nie kolejna zależność do pilnowania.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "chatt/files"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("no_path", "Brak ścieżki pliku", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "open" -> result.success(send(path, share = false))
                    "share" -> result.success(send(path, share = true))
                    else -> result.notImplemented()
                }
            }
    }

    private fun send(path: String, share: Boolean): Boolean {
        val file = File(path)
        if (!file.exists()) return false
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
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
            // obsługującej typ pliku kończy się wyjątkiem zamiast komunikatu.
            startActivity(Intent.createChooser(intent, if (share) "Udostępnij" else "Otwórz"))
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
