package com.mysttic.chatt

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

/**
 * Wklejanie plików i obrazków ze schowka.
 *
 * Dwa pytania, bo koszt każdego jest inny. [hasFiles] ogląda **sam opis**
 * schowka: od Androida 12 to jedyny odczyt, po którym system nie pokazuje
 * „aplikacja wkleiła ze schowka" i nie zapisuje niczego w uprawnieniach.
 * Dzięki temu pozycja „Wklej" może się pokazywać wtedy i tylko wtedy, gdy jest
 * co wklejać, bez oskarżania aplikacji o podglądanie schowka.
 *
 * [pasteFiles] sięga po zawartość i dopiero to jest odczytem. Prawo do cudzego
 * `content://` nadaje sam `getPrimaryClip()` i znika, gdy schowek się zmieni,
 * więc kopiujemy od razu; prawo trwałe (`takePersistableUriPermission`) nie
 * wchodzi w grę, bo schowek nie nadaje flagi, która by na to pozwalała.
 *
 * Od Androida 10 schowek czyta wyłącznie aplikacja, której okno ma skupienie.
 * Bez niego wraca null i false, i tak też to traktujemy: „nic tam nie ma",
 * a nie błąd. Wołane ze stuknięcia w spinacz, więc skupienie jest.
 */
object ChattClipboard {
    /** Podkatalog cache na kopie, osobny od wyboru plików, żeby dało się go sprzątać. */
    private const val subdir = "wklejone"

    private val mainThread = Handler(Looper.getMainLooper())

    private fun manager(context: Context): ClipboardManager? =
        context.applicationContext.getSystemService(ClipboardManager::class.java)

    /**
     * Czy w schowku leży coś do dołączenia. Decyduje typ MIME z opisu:
     * wszystko, czego typ nie zaczyna się od `text/`, ma zawartość, którą da
     * się zapisać jako plik.
     *
     * `text/uri-list` zostaje po stronie „nie": tak opisany bywa goły adres
     * `https://`, a wtedy pozycja „Wklej" zapaliłaby się i nie zrobiła nic.
     * Kosztem jest plik tekstowy skopiowany w menedżerze plików, którego opis
     * (`text/plain`) jest nie do odróżnienia od skopiowanego napisu. Zostaje
     * dla niego zwykły wybór pliku.
     */
    fun hasFiles(context: Context): Boolean = attachable(
        try {
            manager(context)?.primaryClipDescription
        } catch (error: Exception) {
            null
        }
    )

    /**
     * Kopie plików ze schowka w cache aplikacji; do Darta wraca lista ścieżek.
     * Pusta lista znaczy „nic z tego" i jest normalną odpowiedzią: pusty
     * schowek, sam tekst, brak skupienia albo odmowa dostawcy treści.
     *
     * [fallbackName] to nazwa dla zawartości, której dostawca nie nazwał
     * (zwykle obrazek skopiowany w przeglądarce).
     */
    fun pasteFiles(context: Context, fallbackName: String, result: MethodChannel.Result) {
        val clip = try {
            manager(context)?.primaryClip
        } catch (error: Exception) {
            null
        }
        // Ten sam warunek co w [hasFiles], na opisie tego właśnie schowka.
        // Bez niego wkleiłby się blob z tekstem, który przeglądarka wystawia
        // jako content://, gdy skopiowany napis nie mieści się w schowku.
        val uris = if (clip == null || !attachable(clip.description)) {
            emptyList()
        } else {
            (0 until clip.itemCount).mapNotNull { contentUri(clip.getItemAt(it)) }
        }
        if (uris.isEmpty()) {
            result.success(emptyList<String>())
            return
        }

        val app = context.applicationContext
        // Kopiowanie poza wątkiem głównym, tak jak przy wyborze plików.
        thread(name = "chatt-schowek") {
            val paths = uris.mapNotNull {
                ChattFileCache.copy(app, it, subdir, fallbackName, typed = true)
            }
            // Wynik kanału wolno oddać tylko z wątku głównego.
            mainThread.post { result.success(paths) }
        }
    }

    private fun attachable(description: ClipDescription?): Boolean {
        if (description == null) return false
        for (i in 0 until description.mimeTypeCount) {
            if (!description.getMimeType(i).startsWith("text/")) return true
        }
        return false
    }

    /**
     * URI pozycji, o ile da się je otworzyć. Porównanie schematu bez
     * ignorowania wielkości liter jest celowe: system nadaje prawo do odczytu
     * i otwiera strumień dokładnie dla `content`, więc `CONTENT://` i tak by
     * nie zadziałało.
     */
    private fun contentUri(item: ClipData.Item?): Uri? {
        val uri = item?.uri ?: return null
        return if (uri.scheme == ContentResolver.SCHEME_CONTENT) uri else null
    }
}
