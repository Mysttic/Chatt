package com.mysttic.chatt

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log

/**
 * Wejście z systemowego okna „Udostępnij" (issue #60): tekst, odnośnik albo
 * pliki z innej aplikacji, także wprost do rozmówcy wskazanego w tym oknie.
 *
 * Bez wyglądu i bez Fluttera. Chatt ma jeden silnik, który żyje w procesie
 * i podpina się do [MainActivity]. Druga [MainActivity] w zadaniu cudzej
 * aplikacji zabrałaby ten silnik oknu Chatta. Ta aktywność tylko przekazuje:
 * [ChattShare] przyjmuje treść i zaczyna kopiować pliki, okno Chatta wychodzi
 * na wierzch we własnym zadaniu, a ta aktywność znika w tej samej chwili.
 */
class ShareActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val okno = ChattShare.receive(this, intent)
        // Prawo do pliku da się przekazać oknu Chatta tylko wtedy, gdy
        // dostawca na to pozwala. Gdy nie pozwala, system odmawia otwarcia
        // okna z takim prawem, a okno ma wyjść na wierzch tak czy inaczej:
        // kopie robią się już z prawa tej aktywności.
        if (okno != null && (open(okno) || open(withoutGrants(okno)))) {
            // Aplikacja, która czeka na wynik udostępnienia, dostaje
            // „przyjęte". Bez tego wynik brzmiałby „anulowane".
            setResult(RESULT_OK)
        }
        finish()
    }

    private fun open(okno: Intent): Boolean = try {
        startActivity(okno)
        true
    } catch (error: Exception) {
        Log.w("Chatt", "Nie udało się otworzyć okna Chatta", error)
        false
    }

    private fun withoutGrants(okno: Intent): Intent = Intent(okno).apply {
        clipData = null
        removeFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
}
