package com.mysttic.chatt

import android.app.Activity
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
        if (okno != null) {
            try {
                startActivity(okno)
                // Aplikacja, która czeka na wynik udostępnienia, dostaje
                // „przyjęte". Bez tego wynik brzmiałby „anulowane".
                setResult(RESULT_OK)
            } catch (error: Exception) {
                Log.w("Chatt", "Nie udało się otworzyć okna Chatta", error)
            }
        }
        finish()
    }
}
