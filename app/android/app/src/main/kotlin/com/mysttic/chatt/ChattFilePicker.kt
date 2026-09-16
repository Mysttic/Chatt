package com.mysttic.chatt

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference
import java.util.UUID
import kotlin.concurrent.thread

/**
 * Wybór plików do wysłania: systemowe okno (ACTION_OPEN_DOCUMENT), potem
 * kopia każdego zaznaczonego pliku w katalogu cache aplikacji. Do Darta
 * wraca lista ścieżek do tych kopii.
 *
 * Własny kod, bo `file_selector` na Androidzie wczytuje cały zaznaczony plik
 * do tablicy bajtów i przesyła go kanałem do Darta, który bierze z tego samą
 * ścieżkę. Przy pliku 150 MB kończyło się to `OutOfMemoryError` w wątku
 * głównym (sterta Javy ma zwykle 256 MB) i zabiciem aplikacji. Tutaj plik
 * płynie przez bufor w wątku roboczym, więc jego rozmiar jest obojętny dla
 * pamięci i dla płynności ekranu.
 *
 * Kopia jest konieczna: `content://` od innej aplikacji jest ważne krótko,
 * a wysyłka (także ponowiona po nieudanej próbie) czyta plik zwykłą ścieżką.
 *
 * Stan ([activity], [pending]) żyje wyłącznie w wątku głównym: tam działa
 * kanał, cykl życia aktywności i jej `onActivityResult`.
 */
object ChattFilePicker {
    /** Kod żądania; wtyczki Fluttera używają małych liczb, ten się z nimi nie zbiega. */
    private const val requestCode = 0x4348

    /** Podkatalog cache na kopie, osobny, żeby dało się go kiedyś sprzątać. */
    private const val subdir = "wybrane"

    /** Bufor kopiowania: 256 KB idzie szybko przy 150 MB i nic nie znaczy w pamięci. */
    private const val bufferSize = 256 * 1024

    private var activity: WeakReference<Activity>? = null
    private var pending: MethodChannel.Result? = null
    private val mainThread = Handler(Looper.getMainLooper())

    /** [MainActivity] melduje się, gdy jest widoczna: tylko ona może otworzyć okno wyboru. */
    fun attach(host: Activity) {
        activity = WeakReference(host)
    }

    fun detach(host: Activity) {
        if (activity?.get() === host) activity = null
    }

    /**
     * Okno aplikacji kończy życie przy otwartym wyborze (zmiecione z listy
     * zadań): wynik już nie przyjdzie, więc Dart dostaje pustą listę teraz.
     */
    fun cancel() {
        pending?.success(emptyList<String>())
        pending = null
    }

    /** Otwiera okno wyboru. [result] dostanie listę ścieżek, po anulowaniu pustą. */
    fun pick(result: MethodChannel.Result) {
        val host = activity?.get()
        if (host == null) {
            result.error("no_activity", "Okno aplikacji jest zamknięte", null)
            return
        }
        if (pending != null) {
            // Drugie stuknięcie w spinacz, gdy okno wyboru już się otwiera.
            result.error("busy", "Okno wyboru plików jest już otwarte", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        try {
            host.startActivityForResult(intent, requestCode)
            pending = result
        } catch (error: ActivityNotFoundException) {
            result.error("no_picker", "Brak aplikacji do wyboru plików", null)
        }
    }

    /**
     * Wynik z [MainActivity.onActivityResult]. Zwraca true, gdy kod żądania
     * był nasz; pozostałe wyniki należą do wtyczek Fluttera.
     */
    fun onActivityResult(context: Context, code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != requestCode) return false
        val result = pending ?: return true
        pending = null

        val uris = if (resultCode == Activity.RESULT_OK) urisOf(data) else emptyList()
        if (uris.isEmpty()) {
            result.success(emptyList<String>())
            return true
        }
        val app = context.applicationContext
        // Kopiowanie poza wątkiem głównym: 150 MB z karty SD potrafi zająć
        // sekundy, a ekran ma w tym czasie odpowiadać.
        thread(name = "chatt-wybor-plikow") {
            val paths = uris.mapNotNull { copyToCache(app, it) }
            // Wynik kanału wolno oddać tylko z wątku głównego.
            mainThread.post { result.success(paths) }
        }
        return true
    }

    /** Kilka plików przychodzi w ClipData, jeden w `data`. */
    private fun urisOf(data: Intent?): List<Uri> {
        if (data == null) return emptyList()
        val clip = data.clipData
        if (clip != null) {
            return (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
        }
        return listOfNotNull(data.data)
    }

    /**
     * Kopia pliku spod [uri] w `cache/wybrane/<uuid>/<nazwa>`. Losowy katalog
     * pozwala wysłać dwa różne pliki o tej samej nazwie. Zwraca null, gdy
     * dostawca treści odmówił; taki plik wypada z listy.
     */
    private fun copyToCache(context: Context, uri: Uri): String? {
        val dir = File(File(context.cacheDir, subdir), UUID.randomUUID().toString())
        return try {
            dir.mkdirs()
            check(dir.isDirectory) { "brak katalogu ${dir.path}" }
            val target = File(dir, displayName(context, uri))
            context.contentResolver.openInputStream(uri).use { input ->
                checkNotNull(input) { "brak strumienia" }
                target.outputStream().use { output -> input.copyTo(output, bufferSize) }
            }
            target.path
        } catch (error: Exception) {
            // Kopia w połowie nie ma prawa pójść do rozmówcy.
            dir.deleteRecursively()
            null
        }
    }

    /**
     * Nazwa pliku od dostawcy treści (`DISPLAY_NAME`). Dostawca może tam
     * wpisać cokolwiek, także separator katalogu, więc zostaje ostatni człon;
     * przy braku nazwy plik dostaje ogólną.
     */
    private fun displayName(context: Context, uri: Uri): String {
        var name: String? = null
        context.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (column >= 0 && cursor.moveToFirst()) name = cursor.getString(column)
            }
        val clean = name.orEmpty()
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .trim()
        return if (clean.isEmpty() || clean == "." || clean == "..") "plik" else clean
    }
}
