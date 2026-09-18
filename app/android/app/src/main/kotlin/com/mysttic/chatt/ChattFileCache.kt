package com.mysttic.chatt

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import java.util.UUID

/**
 * Kopie plików wskazanych przez `content://` w katalogu cache aplikacji.
 *
 * Kopia jest konieczna, bo cudze `content://` jest ważne krótko (prawo do
 * niego znika razem z zawartością schowka albo z zamkniętym oknem wyboru),
 * a wysyłka, także ponowiona po nieudanej próbie, czyta plik zwykłą ścieżką.
 *
 * Plik płynie przez bufor, więc jego rozmiar jest obojętny dla pamięci:
 * wczytanie 150 MB do tablicy bajtów kończyło się `OutOfMemoryError`
 * i zabiciem aplikacji (patrz [ChattFilePicker]).
 *
 * Wołane z wątku roboczego: kopiowanie z karty pamięci potrafi zająć sekundy,
 * a ekran ma w tym czasie odpowiadać.
 */
object ChattFileCache {
    /** Bufor kopiowania: 256 KB idzie szybko przy 150 MB i nic nie znaczy w pamięci. */
    private const val bufferSize = 256 * 1024

    /**
     * Kopia pliku spod [uri] w `cache/<subdir>/<uuid>/<nazwa>`. Losowy katalog
     * pozwala wysłać dwa różne pliki o tej samej nazwie. Zwraca null, gdy
     * dostawca treści odmówił; taki plik wypada z listy.
     *
     * [fallbackName] to nazwa dla pliku, którego dostawca nie nazwał.
     *
     * [typed] dokłada rozszerzenie z typu MIME, gdy nazwy nie ma albo nie ma
     * w niej kropki. Włącza to wyłącznie wklejanie ze schowka, gdzie obrazek
     * zwykle przychodzi bez nazwy. Wybór pliku z dysku zostawia nazwę taką,
     * jaką podał dostawca: tam nazwa jest prawdziwa, a zgadywanie kończyłoby
     * się plikami w rodzaju `kopia.bak.bin`.
     */
    fun copy(
        context: Context,
        uri: Uri,
        subdir: String,
        fallbackName: String,
        typed: Boolean = false,
    ): String? {
        val dir = File(File(context.cacheDir, subdir), UUID.randomUUID().toString())
        return try {
            dir.mkdirs()
            check(dir.isDirectory) { "brak katalogu ${dir.path}" }
            val target = File(dir, displayName(context, uri, fallbackName, typed))
            context.contentResolver.openInputStream(uri).use { input ->
                checkNotNull(input) { "brak strumienia" }
                target.outputStream().use { output -> input.copyTo(output, bufferSize) }
            }
            target.path
        } catch (error: Exception) {
            // Cofnięte prawo do URI, padnięty dostawca, brak miejsca.
            // Kopia w połowie nie ma prawa pójść do rozmówcy.
            dir.deleteRecursively()
            null
        }
    }

    /**
     * Nazwa pliku od dostawcy treści (`DISPLAY_NAME`). Dostawca może tam
     * wpisać cokolwiek, także separator katalogu, więc zostaje ostatni człon;
     * przy braku nazwy plik dostaje [fallbackName].
     *
     * Przy [typed] rozszerzenie dokłada się z typu MIME. Obrazek skopiowany
     * w przeglądarce zwykle nie ma nazwy w ogóle, a bez rozszerzenia druga
     * strona zobaczy plik, którego system nie umie otworzyć: GIF pod nazwą
     * `obraz.png` trafi do dekodera PNG.
     */
    private fun displayName(
        context: Context,
        uri: Uri,
        fallbackName: String,
        typed: Boolean,
    ): String {
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
        val nazwana = clean.isNotEmpty() && clean != "." && clean != ".."
        if (!typed) return if (nazwana) clean else fallbackName

        val extension = MimeTypeMap.getSingleton()
            .getExtensionFromMimeType(context.contentResolver.getType(uri).orEmpty())
        if (extension.isNullOrEmpty()) return if (nazwana) clean else fallbackName
        if (!nazwana) return fallbackName.substringBeforeLast('.') + ".$extension"
        return if (clean.contains('.')) clean else "$clean.$extension"
    }
}
