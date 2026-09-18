import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyEvent, LogicalKeyboardKey;

/// Ctrl+V dla całego ekranu, także wtedy, gdy nikt na nim nie ma ogniska.
///
/// Zdarzenie zawsze idzie dalej, więc wklejanie tekstu zostaje takie, jakie
/// było: [onPaste] dokłada się do niego, a nie zastępuje. Tekst wklei Flutter,
/// a plik ze schowka dołoży ten, kto o to poprosił.
///
/// Uchwyt jest globalny ([FocusManager.addEarlyKeyEventHandler]), a nie wpięty
/// w drzewo widgetów, bo inaczej nie działałby najczęstszy przypadek: skopiuj
/// plik w Eksploratorze, wróć do aplikacji, Ctrl+V. Świeżo otwarty ekran nie ma
/// nigdzie ogniska, a uchwyt w drzewie dostaje klawisze wyłącznie od tego, co
/// ognisko ma.
///
/// Globalny znaczy jednak „słyszy też cudze klawisze". Oddajemy je jednemu:
/// **cudzemu polu tekstowemu**, bo tam Ctrl+V ma znaczenie i to znaczenie jest
/// całe. Bez tego Ctrl+V w pasku szukania albo w polu sąsiedniego panelu
/// (szerokie okno ma listę rozmów i rozmowę obok siebie) wysyłałby pliki tam,
/// gdzie nikt o to nie prosił. Wszystko inne, od braku ogniska po przycisk na
/// karcie nad aplikacją, znaczy, że o ten skrót nikt się nie bije.
///
/// Drugi warunek: nad ekranem nic nie stoi.
class PasteShortcut extends StatefulWidget {
  final VoidCallback onPaste;
  final Widget child;

  const PasteShortcut({super.key, required this.onPaste, required this.child});

  @override
  State<PasteShortcut> createState() => _PasteShortcutState();
}

class _PasteShortcutState extends State<PasteShortcut> {
  /// Ognisko wewnątrz [PasteShortcut.child]. Węzeł sam go nie bierze i nie
  /// wchodzi w kolejność tabulatora; jest po to, żeby dało się zapytać, czy
  /// ognisko siedzi pod nami.
  final _wnetrze = FocusNode(debugLabel: 'PasteShortcut');

  /// Trasa, na której stoi ten ekran. Gdy nie jest wierzchnia, nad nami leży
  /// karta, okno dialogowe albo inny ekran i klawisze nie są nasze.
  ModalRoute<Object?>? _trasa;

  /// Bez powtórzeń, bo przytrzymany Ctrl+V ma wkleić raz, i z dokładnym
  /// zestawem klawiszy, więc Ctrl+Shift+V tu nie wejdzie.
  static const _skrot = SingleActivator(LogicalKeyboardKey.keyV,
      control: true, includeRepeats: false);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_naKlawisz);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _trasa = ModalRoute.of(context);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_naKlawisz);
    _wnetrze.dispose();
    super.dispose();
  }

  KeyEventResult _naKlawisz(KeyEvent event) {
    if (_skrot.accepts(event, HardwareKeyboard.instance) &&
        _trasa?.isCurrent != false &&
        !_cudzePoleTekstowe) {
      widget.onPaste();
    }
    // Zawsze, bez wyjątku: `handled` albo `skipRemainingHandlers` odebrałoby
    // zdarzenie skrótom tekstowym Fluttera i Ctrl+V przestałoby wklejać tekst.
    return KeyEventResult.ignored;
  }

  /// Czy ognisko trzyma pole tekstowe spoza [PasteShortcut.child]. Poznać je
  /// po tym, że węzeł ogniska siedzi w `EditableText`: tak zbudowane są
  /// wszystkie pola Fluttera, od `TextField` po `SelectableText`.
  bool get _cudzePoleTekstowe {
    if (_wnetrze.hasFocus) return false;
    final kontekst = FocusManager.instance.primaryFocus?.context;
    return kontekst != null &&
        kontekst.findAncestorStateOfType<EditableTextState>() != null;
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _wnetrze,
        canRequestFocus: false,
        skipTraversal: true,
        child: widget.child,
      );
}
