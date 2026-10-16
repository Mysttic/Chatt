package com.mysttic.chatt

import android.app.KeyguardManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Klawiatura Chatt: ujście dodatku „Klawiatura z PC" na Androidzie.
 *
 * Sama nie ma klawiszy. To pasek 48 dp z napisem, kto pisze i dokąd,
 * z przyciskiem przełączenia klawiatury i ze Stopem. Tekst przychodzi
 * z sieci przez kanał `chatt/remoteinput` ([ChattRemoteInput]) i trafia
 * do pola przez [currentInputConnection], więc działa w każdym polu każdej
 * aplikacji, także w polu hasła i w WebView.
 *
 * Komponent jest w manifeście wyłączony: włącza go wyłącznie przełącznik
 * dodatku w Chatcie, więc przy wyłączonym dodatku Chatt nie figuruje na
 * systemowej liście klawiatur. Działa w procesie aplikacji, obok silnika
 * Fluttera.
 */
class ChattInputMethod : InputMethodService() {

    private var label: TextView? = null
    private var stop: Button? = null

    override fun onCreate() {
        super.onCreate()
        ChattRemoteInput.attachIme(this)
        // Proces mógł wstać właśnie dla klawiatury, a wtedy start usługi
        // pierwszoplanowej z `main()` dostał odmowę. Związana klawiatura
        // jest dla systemu widoczna, więc teraz start przechodzi.
        ChattService.retryStart(this)
    }

    override fun onDestroy() {
        ChattRemoteInput.detachIme(this)
        super.onDestroy()
    }

    override fun onCreateInputView(): View {
        val gestosc = resources.displayMetrics.density
        fun dp(v: Int) = (v * gestosc).toInt()
        val pasek = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Color.parseColor("#512BD4"))
            setPadding(dp(12), 0, dp(6), 0)
            minimumHeight = dp(48)
        }
        val napis = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            layoutParams = LinearLayout.LayoutParams(0, dp(48), 1f)
            gravity = Gravity.CENTER_VERTICAL
        }
        val przelacz = Button(this).apply {
            text = getString(R.string.ime_switch)
            isAllCaps = false
            setOnClickListener { pickKeyboard() }
        }
        val zatrzymaj = Button(this).apply {
            isAllCaps = false
            backgroundTintList = ColorStateList.valueOf(Color.parseColor("#C42B1C"))
            setTextColor(Color.WHITE)
            setOnClickListener { ChattRemoteInput.stopPressed() }
        }
        pasek.addView(napis)
        pasek.addView(przelacz)
        pasek.addView(zatrzymaj)
        // Od Androida 15 okno klawiatury sięga pod pasek nawigacji, a ten
        // rysuje się na nim razem z przyciskami wstecz i przełączania
        // klawiatury. Sprawdzone na emulatorze: globus wypadał na Stopie,
        // a jego strefa dotyku (`tappableElement`, 48 dp) jest dwa razy
        // wyższa od samego paska nawigacji (24 dp). Wcięcie od dołu bierze
        // większe z nich, więc przyciski stoją nad całą tą strefą.
        pasek.setOnApplyWindowInsetsListener { widok, wciecia ->
            val dol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                maxOf(
                    wciecia.getInsets(WindowInsets.Type.navigationBars()).bottom,
                    wciecia.getInsets(WindowInsets.Type.tappableElement()).bottom,
                )
            } else {
                @Suppress("DEPRECATION")
                wciecia.systemWindowInsetBottom
            }
            widok.setPadding(dp(12), 0, dp(6), dol)
            wciecia
        }
        label = napis
        stop = zatrzymaj
        refresh()
        return pasek
    }

    /** W poziomie klawiatura zajęłaby cały ekran i zakryła pole. */
    override fun onEvaluateFullscreenMode(): Boolean = false

    /**
     * Pasek widać zawsze, gdy klawiatura Chatt jest bieżąca, także przy
     * klawiaturze sprzętowej: bez niego nie byłoby Stopu ani przełączenia.
     */
    override fun onEvaluateInputViewShown(): Boolean {
        super.onEvaluateInputViewShown()
        return true
    }

    override fun onShowInputRequested(flags: Int, configChange: Boolean): Boolean =
        ChattRemoteInput.sessionActive || super.onShowInputRequested(flags, configChange)

    override fun onStartInput(attribute: EditorInfo, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        // Ekran blokady z hasłem wpisuje się bieżącą klawiaturą, a ta nie ma
        // klawiszy: wracamy do poprzedniej, żeby dało się odblokować telefon.
        if (getSystemService(KeyguardManager::class.java)?.isKeyguardLocked == true) {
            switchBack()
        }
        ChattService.retryStart(this)
        refresh()
    }

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        // W trakcie zgody ekran ma nie gasnąć: pisze się z drugiego
        // urządzenia, a tu nikt niczego nie dotyka.
        if (ChattRemoteInput.sessionActive) {
            window?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        refresh()
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        window?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onFinishInputView(finishingInput)
    }

    /** Stan zgody zmienił się w Dart: napis, Stop i widoczność paska. */
    fun refresh() {
        val aktywna = ChattRemoteInput.sessionActive
        label?.text = ChattRemoteInput.indicatorText
            ?: if (aktywna) {
                getString(R.string.ime_typing, ChattRemoteInput.peerName)
            } else {
                getString(R.string.ime_idle)
            }
        stop?.text = ChattRemoteInput.stopLabel ?: getString(R.string.ime_stop)
        stop?.visibility = if (aktywna) View.VISIBLE else View.GONE
        if (aktywna) {
            window?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        updateInputViewShown()
    }

    /** Okno wyboru klawiatury. Bieżąca klawiatura ma prawo je pokazać. */
    fun pickKeyboard() {
        getSystemService(InputMethodManager::class.java)?.showInputMethodPicker()
    }

    /** Powrót do klawiatury sprzed klawiatury Chatt. */
    fun switchBack() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            if (switchToPreviousInputMethod()) return
        } else {
            val token = window?.window?.attributes?.token
            @Suppress("DEPRECATION")
            if (token != null &&
                getSystemService(InputMethodManager::class.java)
                    ?.switchToLastInputMethod(token) == true
            ) {
                return
            }
        }
        // Nie ma poprzedniej: niech użytkownik wybierze sam.
        pickKeyboard()
    }
}
