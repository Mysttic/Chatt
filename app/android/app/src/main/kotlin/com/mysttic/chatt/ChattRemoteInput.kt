package com.mysttic.chatt

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.text.InputType
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * Kanał `chatt/remoteinput` na Androidzie: dodatek „Klawiatura z PC".
 *
 * Kontrakt jest ten sam co na Windows (`status`, `apply`, `setSession`,
 * `setImeEnabled`, `showIndicator`, `hideIndicator`, w drugą stronę
 * `stopRequested`), a do tego to, czego wymaga klawiatura: włączenie jej
 * w ustawieniach systemu, okno wyboru klawiatury i schowanie aplikacji po
 * zgodzie, żeby było widać pole, do którego idzie pisanie.
 *
 * Wpisuje [ChattInputMethod], czyli klawiatura Chatt, gdy jest bieżącą
 * klawiaturą i ma związane pole. Bez niej odpowiedź brzmi „nie ma dokąd
 * pisać". Sama rejestracja kanału niczego nie uruchamia.
 */
object ChattRemoteInput {
    private const val CHANNEL = "chatt/remoteinput"
    private const val SWITCH_CHANNEL_ID = "chatt_klawiatura"
    private const val SWITCH_NOTIFICATION_ID = 7301

    /** Dodatek w intencji otwierającej okno: pokaż wybór klawiatury i zejdź. */
    const val EXTRA_PICK_KEYBOARD = "chatt.pickKeyboard"

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var ime: WeakReference<ChattInputMethod>? = null
    private var activity: WeakReference<Activity>? = null
    private val main = Handler(Looper.getMainLooper())

    /** Trwa zgoda (wg Darta). */
    @Volatile var sessionActive = false
        private set
    @Volatile var peerName = ""
        private set

    /** Teksty paska z Darta, w języku aplikacji. `null` = domyślne. */
    @Volatile var indicatorText: String? = null
        private set
    @Volatile var stopLabel: String? = null
        private set

    /** Etapy „pokaż wybór klawiatury, po nim schowaj aplikację". */
    private enum class Picker { NONE, REQUESTED, SHOWN, OPEN }
    private var picker = Picker.NONE

    fun install(context: Context, messenger: BinaryMessenger) {
        appContext = context.applicationContext
        val kanal = MethodChannel(messenger, CHANNEL)
        channel = kanal
        kanal.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(target())
                "apply" -> result.success(apply(call.argument<List<Any?>>("ops")))
                "setSession" -> {
                    setSession(
                        call.argument<Boolean>("active") == true,
                        call.argument<String>("peerName") ?: "",
                    )
                    result.success(emptyMap<String, Any?>())
                }
                "setImeEnabled" -> result.success(
                    mapOf("ok" to setImeEnabled(call.argument<Boolean>("on") == true)),
                )
                "showIndicator" -> {
                    showIndicator(call.argument<String>("text"), call.argument<String>("stop"))
                    result.success(mapOf("ok" to true))
                }
                "hideIndicator" -> {
                    showIndicator(null, null)
                    result.success(mapOf("ok" to true))
                }
                "openImeSettings" -> result.success(mapOf("ok" to openImeSettings()))
                "showImePicker" -> result.success(mapOf("ok" to showPickerNow()))
                "afterAccept" -> result.success(mapOf("ok" to afterAccept()))
                "notifySwitchKeyboard" -> {
                    notifySwitchKeyboard(
                        call.argument<String>("title") ?: "Chatt",
                        call.argument<String>("body") ?: "",
                    )
                    result.success(mapOf("ok" to true))
                }
                else -> result.notImplemented()
            }
        }
    }

    // --- Klawiatura i okno ---------------------------------------------------

    fun attachIme(service: ChattInputMethod) {
        ime = WeakReference(service)
    }

    fun detachIme(service: ChattInputMethod) {
        if (ime?.get() === service) ime = null
    }

    fun attach(window: Activity) {
        activity = WeakReference(window)
    }

    fun detach(window: Activity) {
        if (activity?.get() === window) activity = null
    }

    /** Stop na pasku klawiatury. Dart kończy zgodę i odsyła `setSession`. */
    fun stopPressed() {
        main.post { channel?.invokeMethod("stopRequested", null) }
    }

    /** Intencja z powiadomienia „Przełącz klawiaturę na Chatt". */
    fun handleIntent(window: Activity, intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_PICK_KEYBOARD, false) != true) return
        intent.removeExtra(EXTRA_PICK_KEYBOARD)
        NotificationManagerCompat.from(window).cancel(SWITCH_NOTIFICATION_ID)
        picker = Picker.REQUESTED
        if (window.hasWindowFocus()) onWindowFocus(window, true)
    }

    /**
     * Okno wyboru klawiatury pokaże tylko okno z fokusem, a po jego
     * zamknięciu fokus wraca do aplikacji: wtedy ją chowamy, żeby było widać
     * aplikację z polem, do którego idzie pisanie.
     */
    fun onWindowFocus(window: Activity, hasFocus: Boolean) {
        when (picker) {
            Picker.REQUESTED -> if (hasFocus) {
                window.getSystemService(InputMethodManager::class.java)
                    ?.showInputMethodPicker()
                picker = Picker.SHOWN
            }
            Picker.SHOWN -> if (!hasFocus) picker = Picker.OPEN
            Picker.OPEN -> if (hasFocus) {
                picker = Picker.NONE
                window.moveTaskToBack(true)
            }
            Picker.NONE -> Unit
        }
    }

    private fun showPickerNow(): Boolean {
        val okno = activity?.get()
        if (okno != null && okno.hasWindowFocus()) {
            okno.getSystemService(InputMethodManager::class.java)?.showInputMethodPicker()
            return true
        }
        val klawiatura = ime?.get() ?: return false
        klawiatura.pickKeyboard()
        return true
    }

    /**
     * Zgoda kliknięta w Chatcie: gdy klawiatura Chatt nie jest bieżąca,
     * okno wyboru, a po nim zejście aplikacji na dół; gdy jest, od razu
     * zejście.
     */
    private fun afterAccept(): Boolean {
        val okno = activity?.get() ?: return false
        if (isSelected()) {
            okno.moveTaskToBack(true)
            return true
        }
        picker = Picker.REQUESTED
        if (okno.hasWindowFocus()) onWindowFocus(okno, true)
        return true
    }

    // --- Cel -------------------------------------------------------------------

    private fun context(): Context? = appContext

    private fun component(context: Context) =
        ComponentName(context, ChattInputMethod::class.java)

    private fun isEnabled(): Boolean {
        val context = context() ?: return false
        val imm = context.getSystemService(InputMethodManager::class.java) ?: return false
        val nasza = component(context)
        return imm.enabledInputMethodList.any { it.component == nasza }
    }

    private fun isSelected(): Boolean {
        val context = context() ?: return false
        val biezaca = Settings.Secure.getString(
            context.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD,
        ) ?: return false
        return ComponentName.unflattenFromString(biezaca) == component(context)
    }

    private fun isPassword(info: EditorInfo): Boolean {
        val klasa = info.inputType and InputType.TYPE_MASK_CLASS
        val wariant = info.inputType and InputType.TYPE_MASK_VARIATION
        return (klasa == InputType.TYPE_CLASS_TEXT && (
            wariant == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                wariant == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                wariant == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD)) ||
            (klasa == InputType.TYPE_CLASS_NUMBER &&
                wariant == InputType.TYPE_NUMBER_VARIATION_PASSWORD)
    }

    private fun isMultiLine(info: EditorInfo): Boolean =
        (info.inputType and InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT &&
            (info.inputType and InputType.TYPE_TEXT_FLAG_MULTI_LINE) != 0

    /** Akcja Entera w tym polu albo `null`, gdy Enter ma być zwykłym Enterem. */
    private fun editorAction(info: EditorInfo): Int? {
        if (isMultiLine(info)) return null
        if ((info.imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0) return null
        return when (val akcja = info.imeOptions and EditorInfo.IME_MASK_ACTION) {
            EditorInfo.IME_ACTION_SEARCH, EditorInfo.IME_ACTION_SEND,
            EditorInfo.IME_ACTION_GO, EditorInfo.IME_ACTION_DONE,
            EditorInfo.IME_ACTION_NEXT, EditorInfo.IME_ACTION_PREVIOUS -> akcja
            else -> null
        }
    }

    private fun actionName(info: EditorInfo): String = when (editorAction(info)) {
        EditorInfo.IME_ACTION_SEARCH -> "search"
        EditorInfo.IME_ACTION_SEND -> "send"
        EditorInfo.IME_ACTION_GO -> "go"
        EditorInfo.IME_ACTION_DONE -> "done"
        EditorInfo.IME_ACTION_NEXT -> "next"
        EditorInfo.IME_ACTION_PREVIOUS -> "previous"
        else -> "none"
    }

    private fun appLabel(context: Context, pakiet: String): String = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pakiet, 0)).toString()
    } catch (error: Exception) {
        ""
    }

    private fun target(): MutableMap<String, Any?> {
        val context = context()
        val klawiatura = ime?.get()
        val info = klawiatura?.currentInputEditorInfo
        val polaczone = klawiatura != null && klawiatura.currentInputStarted &&
            klawiatura.currentInputConnection != null && info != null &&
            info.inputType != InputType.TYPE_NULL
        val pakiet = if (polaczone) info?.packageName ?: "" else ""
        val zablokowany = context != null && (
            context.getSystemService(KeyguardManager::class.java)?.isKeyguardLocked == true ||
                context.getSystemService(PowerManager::class.java)?.isInteractive == false)
        // Własne pola Chatta: zdalny Enter nie wyśle wiadomości ani nie
        // kliknie karty z pytaniem.
        val wlasne = context != null && pakiet == context.packageName
        val aktywne = polaczone && !zablokowany && !wlasne
        return mutableMapOf(
            "active" to aktywne,
            "field" to when {
                !polaczone || info == null -> "none"
                isPassword(info) -> "password"
                else -> "text"
            },
            "action" to (if (polaczone && info != null) actionName(info) else "none"),
            "app" to pakiet,
            "appLabel" to (if (context != null && pakiet.isNotEmpty()) appLabel(context, pakiet) else ""),
            "ownApp" to wlasne,
            "locked" to zablokowany,
            "elevated" to false,
            "imeEnabled" to isEnabled(),
            "imeSelected" to isSelected(),
            "bound" to (klawiatura != null),
        )
    }

    // --- Wpisywanie ----------------------------------------------------------------

    private fun apply(ops: List<Any?>?): Map<String, Any?> {
        val przed = target()
        val klawiatura = ime?.get()
        val ic = klawiatura?.currentInputConnection
        val info = klawiatura?.currentInputEditorInfo
        if (ops == null || przed["active"] != true || klawiatura == null || ic == null || info == null) {
            return przed.apply { put("applied", false) }
        }
        var wpisane = true
        ic.beginBatchEdit()
        try {
            for (surowa in ops) {
                val op = surowa as? Map<*, *>
                wpisane = if (op == null) {
                    false
                } else {
                    when (op["t"]) {
                        "insert" -> insert(klawiatura, ic, info, op["s"] as? String ?: "")
                        "bs" -> delete(klawiatura, ic, count(op["n"]), before = true)
                        "del" -> delete(klawiatura, ic, count(op["n"]), before = false)
                        "action" -> action(klawiatura, ic, info)
                        else -> false
                    }
                }
                if (!wpisane) break
            }
        } finally {
            ic.endBatchEdit()
        }
        return target().apply { put("applied", wpisane) }
    }

    private fun count(value: Any?): Int = when (value) {
        is Int -> value
        is Long -> value.toInt()
        else -> 0
    }

    /** Nowa linia w polu jednowierszowym to Enter, jak na klawiaturze. */
    private fun insert(
        klawiatura: ChattInputMethod, ic: InputConnection, info: EditorInfo, tekst: String,
    ): Boolean {
        val linie = tekst.split('\n')
        for ((i, linia) in linie.withIndex()) {
            if (linia.isNotEmpty() && !ic.commitText(linia, 1)) return false
            if (i < linie.size - 1) {
                if (isMultiLine(info)) {
                    if (!ic.commitText("\n", 1)) return false
                } else {
                    enter(klawiatura)
                }
            }
        }
        return true
    }

    /**
     * Kasowanie liczone w punktach kodowych: jedno `bs` zabiera emoji
     * w całości. Zaznaczenie znika jak przy zwykłym Backspace, za pierwszym
     * razem. Pole, które kasowania przez połączenie nie obsługuje, dostaje
     * zwykłe klawisze.
     */
    private fun delete(
        klawiatura: ChattInputMethod, ic: InputConnection, n: Int, before: Boolean,
    ): Boolean {
        if (n < 1 || n > 64) return false
        var zostalo = n
        val zaznaczone = ic.getSelectedText(0)
        if (!zaznaczone.isNullOrEmpty()) {
            if (!ic.commitText("", 1)) return false
            zostalo--
        }
        if (zostalo == 0) return true
        val udane = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            if (before) ic.deleteSurroundingTextInCodePoints(zostalo, 0)
            else ic.deleteSurroundingTextInCodePoints(0, zostalo)
        } else {
            if (before) ic.deleteSurroundingText(zostalo, 0)
            else ic.deleteSurroundingText(0, zostalo)
        }
        if (!udane) {
            val klawisz = if (before) KeyEvent.KEYCODE_DEL else KeyEvent.KEYCODE_FORWARD_DEL
            repeat(zostalo) { klawiatura.sendDownUpKeyEvents(klawisz) }
        }
        return true
    }

    private fun enter(klawiatura: ChattInputMethod) {
        klawiatura.sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER)
    }

    /** Akcja pola (Szukaj, Wyślij, Dalej, Gotowe) albo zwykły Enter. */
    private fun action(klawiatura: ChattInputMethod, ic: InputConnection, info: EditorInfo): Boolean {
        val akcja = editorAction(info)
        if (akcja == null) {
            enter(klawiatura)
            return true
        }
        return ic.performEditorAction(akcja)
    }

    // --- Zgoda i wskaźnik ----------------------------------------------------------

    private fun setSession(active: Boolean, name: String) {
        val bylaAktywna = sessionActive
        sessionActive = active
        peerName = name
        if (!active) {
            indicatorText = null
            appContext?.let { ChattService.setStatus(it, null) }
        }
        val klawiatura = ime?.get()
        klawiatura?.refresh()
        // Koniec zgody: wraca klawiatura, której użytkownik używał wcześniej.
        if (bylaAktywna && !active && isSelected()) klawiatura?.switchBack()
    }

    /** Pasek klawiatury i stałe powiadomienie mówią, kto pisze i dokąd. */
    private fun showIndicator(text: String?, stop: String?) {
        indicatorText = text
        if (stop != null) stopLabel = stop
        ime?.get()?.refresh()
        appContext?.let { ChattService.setStatus(it, text) }
    }

    private fun setImeEnabled(on: Boolean): Boolean {
        val context = appContext ?: return false
        return try {
            context.packageManager.setComponentEnabledSetting(
                component(context),
                if (on) {
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                } else {
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                },
                PackageManager.DONT_KILL_APP,
            )
            true
        } catch (error: Exception) {
            false
        }
    }

    private fun openImeSettings(): Boolean {
        val context = activity?.get() ?: appContext ?: return false
        return try {
            context.startActivity(
                Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (error: Exception) {
            false
        }
    }

    /**
     * Zgoda bez karty („nie pytaj więcej"), a klawiatura Chatt nie jest
     * bieżąca: z tła okna wyboru nie da się pokazać, więc powiadomienie.
     * Jego dotknięcie otwiera Chatta, ten pokazuje wybór i schodzi na dół.
     */
    private fun notifySwitchKeyboard(title: String, body: String) {
        val context = appContext ?: return
        if (isSelected()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val kanal = NotificationChannel(
                SWITCH_CHANNEL_ID,
                context.getString(R.string.ime_channel),
                NotificationManager.IMPORTANCE_HIGH,
            )
            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(kanal)
        }
        val otworz = PendingIntent.getActivity(
            context,
            SWITCH_NOTIFICATION_ID,
            Intent(context, MainActivity::class.java)
                .putExtra(EXTRA_PICK_KEYBOARD, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val powiadomienie = NotificationCompat.Builder(context, SWITCH_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(otworz)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(SWITCH_NOTIFICATION_ID, powiadomienie)
        } catch (error: SecurityException) {
            // brak zgody na powiadomienia
        }
    }
}
