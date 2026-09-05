package com.mysttic.chatt

import android.annotation.SuppressLint
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Kanały platformowe aplikacji. Instalowane na silniku Fluttera trzymanym
 * w cache'u ([ChattApplication]), a nie w aktywności, dzięki czemu działają
 * także wtedy, gdy okno aplikacji jest zamknięte, a proces trzyma usługa
 * pierwszoplanowa.
 */
object ChattChannels {
    private const val filesChannel = "chatt/files"
    private const val backgroundChannel = "chatt/background"
    private const val secretsChannel = "chatt/sekrety"

    /** Nazwa klucza w Keystore. Sam klucz nigdy nie opuszcza Keystore. */
    private const val keystoreAlias = "chatt-klucz-bazy"

    /** GCM: 12 bajtów wektora inicjującego z przodu, 128-bitowy tag z tyłu. */
    private const val ivLength = 12
    private const val tagBits = 128

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
                "save" -> result.success(saveToStore(context, path))
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
                "batteryOptimized" -> result.success(batteryOptimized(context))
                "requestBatteryExemption" -> result.success(requestBatteryExemption(context))
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, secretsChannel).setMethodCallHandler { call, result ->
            val data = call.argument<ByteArray>("data")
            if (data == null) {
                result.error("no_data", "Brak danych", null)
                return@setMethodCallHandler
            }
            try {
                when (call.method) {
                    "protect" -> result.success(protect(data))
                    "unprotect" -> result.success(unprotect(data))
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                // Keystore potrafi odmówić (klucz skasowany po przywróceniu
                // kopii zapasowej, uszkodzony magazyn). Strona Dartowa umie
                // rozpoznać taki błąd i pokazać go użytkownikowi.
                result.error("keystore", error.message, null)
            }
        }
    }

    /**
     * Szyfruje [data] kluczem AES z Keystore, zakładając go przy pierwszym
     * użyciu. Wynik to wektor inicjujący sklejony z szyfrogramem.
     */
    private fun protect(data: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, databaseKey())
        return cipher.iv + cipher.doFinal(data)
    }

    private fun unprotect(data: ByteArray): ByteArray {
        require(data.size > ivLength) { "Blob za krótki" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            databaseKey(),
            GCMParameterSpec(tagBits, data, 0, ivLength),
        )
        return cipher.doFinal(data, ivLength, data.size - ivLength)
    }

    /**
     * Klucz AES trzymany w Keystore. Bez wymogu uwierzytelnienia użytkownika:
     * aplikacja musi otworzyć bazę także wtedy, gdy budzi ją wiadomość przy
     * zablokowanym ekranie.
     */
    private fun databaseKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getEntry(keystoreAlias, null) as? KeyStore.SecretKeyEntry)
            ?.let { return it.secretKey }

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                keystoreAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    /**
     * Czy system nadal usypia aplikację. Usługa pierwszoplanowa broni proces
     * przed ubiciem, ale w trybie Doze i tak potrafi zabrać mu sieć:
     * dopiero wyjątek od optymalizacji baterii to wyłącza.
     */
    private fun batteryOptimized(context: Context): Boolean = try {
        val power = context.getSystemService(PowerManager::class.java)
        power?.isIgnoringBatteryOptimizations(context.packageName)?.not() ?: false
    } catch (error: Exception) {
        false
    }

    // BatteryLife: Google odradza to okienko w aplikacjach ze Sklepu Play,
    // ale tu jest uzasadnione: aplikacja nasłuchuje w sieci lokalnej i nie
    // ma żadnego serwera push, który mógłby ją obudzić.
    @SuppressLint("BatteryLife")
    private fun requestBatteryExemption(context: Context): Boolean = try {
        context.startActivity(
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(Uri.parse("package:${context.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (error: Exception) {
        // Producent wyciął ekran optymalizacji, użytkownikowi zostaje
        // ustawienie systemowe znalezione ręcznie.
        false
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

    /**
     * Kopiuje odebrany plik tam, gdzie użytkownik go szuka: obrazki do Zdjęć,
     * resztę do Pobranych. Od Androida 10 MediaStore nie wymaga do tego
     * żadnego uprawnienia, bo aplikacja dokłada wpis do kolekcji systemowej,
     * a nie pisze po cudzym katalogu.
     *
     * Zwraca nazwę katalogu do pokazania użytkownikowi albo null, gdy się nie
     * udało (starszy Android, brak pliku, odmowa dostawcy treści).
     */
    private fun saveToStore(context: Context, path: String): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val file = File(path)
        if (!file.exists()) return null

        val type = mimeTypeOf(file.name)
        val obrazek = type.startsWith("image/")
        val katalog = if (obrazek) {
            Environment.DIRECTORY_PICTURES + "/Chatt"
        } else {
            Environment.DIRECTORY_DOWNLOADS
        }
        val kolekcja = if (obrazek) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }

        val opis = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, type)
            put(MediaStore.MediaColumns.RELATIVE_PATH, katalog)
            // Wpis niegotowy jest niewidoczny dla galerii, dopóki nie skończymy
            // kopiowania: inaczej dałoby się zobaczyć plik w połowie.
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val resolver = context.contentResolver
        val uri = resolver.insert(kolekcja, opis) ?: return null
        return try {
            resolver.openOutputStream(uri).use { wyjscie ->
                if (wyjscie == null) throw IllegalStateException("brak strumienia")
                file.inputStream().use { it.copyTo(wyjscie) }
            }
            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null,
            )
            katalog
        } catch (error: Exception) {
            // Połowicznie zapisany plik nie ma prawa zostać w galerii.
            resolver.delete(uri, null, null)
            null
        }
    }

    private fun mimeTypeOf(name: String): String {
        val extension = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: "application/octet-stream"
    }
}
