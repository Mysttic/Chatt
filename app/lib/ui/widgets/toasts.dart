/// Krótkie komunikaty („skopiowano", „nie udało się otworzyć pliku") pokazywane
/// w prawym górnym rogu okna.
///
/// Dlaczego nie `SnackBar`: ten wyskakuje na dole i przykrywa dokładnie to,
/// czego użytkownik właśnie użył, czyli na liście rozmów przycisk „W pobliżu",
/// a w rozmowie pole tekstowe. Komunikat o tym, co się przed chwilą stało, nie
/// ma prawa zasłaniać miejsca, w którym się to działo.
///
/// Pasek pod tekstem odlicza czas do zniknięcia, więc widać, ile go zostało,
/// zamiast zgadywać, czy karta zaraz zniknie sama.
///
/// Karta wchodzi i schodzi w ruchu stylu ([ChattMotion]): wjeżdża w górę na
/// swoje miejsce i się pojawia, przy wyjściu znika (w Ciszy i Precyzji
/// zjeżdża przy tym w dół).
library;

import 'package:flutter/material.dart';
import '../styles.dart';
import 'motion.dart';

/// Jeden komunikat w kolejce.
class ToastMessage {
  /// Rośnie, nigdy się nie powtarza, służy tylko za klucz widgetu.
  final int id;
  final String text;

  /// Opcjonalny przycisk (dziś: „Kopiuj" przy ścieżce pliku na Androidzie).
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Czas na ekranie; null: czas stylu ([ChattMotion.toastHold]), ustalany
  /// przez kartę, bo kolejka nie zna motywu.
  final Duration? duration;

  const ToastMessage({
    required this.id,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.duration,
  });
}

/// Kolejka komunikatów. Globalna, bo komunikat ma się pokazać także wtedy, gdy
/// ekran, który go wywołał, zdążył już zniknąć (skasowanie rozmowy zamyka
/// ekran, a napis „usunięto" ma zostać). Z tego samego powodu nie ma tu
/// `BuildContext` ani zależności od `Navigatora`.
class ToastController extends ValueNotifier<List<ToastMessage>> {
  ToastController() : super(const []);

  /// Więcej naraz robi się ścianą tekstu w rogu; najstarszy ustępuje miejsca.
  static const int maxVisible = 3;

  int _nextId = 0;

  ToastMessage show(
    String text, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final message = ToastMessage(
      id: _nextId++,
      text: text,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
    final next = [...value, message];
    value = next.length > maxVisible
        ? next.sublist(next.length - maxVisible)
        : next;
    return message;
  }

  void dismiss(int id) {
    value = value.where((m) => m.id != id).toList(growable: false);
  }

  /// Czyszczenie między testami: bez tego kolejka przeciekałaby z testu
  /// do testu, bo kontroler jest globalny.
  void clear() => value = const [];
}

/// Jedna instancja na proces. Widok czyta ją przez [ToastHost].
final ToastController chattToasts = ToastController();

/// Skrót do [ToastController.show]. Świadomie bez `BuildContext`: komunikat
/// nie należy do żadnego ekranu i przeżywa jego zamknięcie. Bez [duration]
/// karta stoi tyle, ile każe styl.
void showToast(
  String text, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) =>
    chattToasts.show(text,
        actionLabel: actionLabel, onAction: onAction, duration: duration);

/// Nakładka z kolejką komunikatów. Wpinana raz, w `MaterialApp.builder`, obok
/// `PromptOverlay`, dzięki czemu działa na każdym ekranie i nie wymaga
/// `Scaffold`a.
class ToastHost extends StatefulWidget {
  final Widget child;

  const ToastHost({super.key, required this.child});

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<ToastHost> {
  /// Karty na ekranie: kolejka i karty, które wypadły z niej bez swojego
  /// wyjścia (nadmiar ponad [ToastController.maxVisible]) i jeszcze
  /// schodzą w ruchu stylu.
  late List<ToastMessage> _karty = [...chattToasts.value];
  final _wypadly = <int>{};

  @override
  void initState() {
    super.initState();
    chattToasts.addListener(_kolejka);
  }

  @override
  void dispose() {
    chattToasts.removeListener(_kolejka);
    super.dispose();
  }

  void _kolejka() {
    final wKolejce = {for (final m in chattToasts.value) m.id};
    final naEkranie = {for (final m in _karty) m.id};
    setState(() {
      for (final id in naEkranie) {
        if (!wKolejce.contains(id)) _wypadly.add(id);
      }
      _karty = [
        ..._karty,
        for (final m in chattToasts.value)
          if (!naEkranie.contains(m.id)) m,
      ];
    });
  }

  /// Karta skończyła wyjście: znika z ekranu i z kolejki.
  void _zeszla(int id) {
    setState(() {
      _karty = [
        for (final m in _karty)
          if (m.id != id) m,
      ];
      _wypadly.remove(id);
    });
    chattToasts.dismiss(id);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final message in _karty)
                    _ToastCard(
                      key: ValueKey(message.id),
                      message: message,
                      leaving: _wypadly.contains(message.id),
                      onGone: () => _zeszla(message.id),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToastCard extends StatefulWidget {
  final ToastMessage message;

  /// Karta wypadła z kolejki: schodzi od razu.
  final bool leaving;

  /// Wyjście skończone.
  final VoidCallback onGone;

  const _ToastCard({
    super.key,
    required this.message,
    required this.leaving,
    required this.onGone,
  });

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with TickerProviderStateMixin {
  /// Wejście (w przód) i wyjście (w tył) karty, czasy ze stylu.
  late final AnimationController _ruch = motionController(vsync: this);

  /// Odliczanie czasu na ekranie, z niego pasek pod tekstem. Też
  /// z zachowanym czasem: przy systemowym „usuń animacje” zwykły kontroler
  /// skróciłby komunikat do ułamka sekundy.
  late final AnimationController _life = motionController(vsync: this);

  bool _ruszyla = false;
  bool _znika = false;

  @override
  void didUpdateWidget(_ToastCard old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) _zniknij();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final m = ChattMotion.of(context);
    _ruch
      ..duration = m.toastIn
      ..reverseDuration = m.toastOut;
    if (_ruszyla) return;
    _ruszyla = true;
    // Czas na ekranie ustalony raz: zmiana stylu w trakcie nie zaczyna
    // odliczania od nowa. Liczy się od pokazania karty, wejście biegnie
    // w jego trakcie, a po nim rusza wyjście: „znika po 3,2 s” z projektu
    // stylu to chwila startu wyjścia.
    _life.duration = widget.message.duration ?? m.toastHold;
    _ruch.forward();
    _life.forward().whenComplete(_zniknij);
  }

  /// Każde zamknięcie (koniec czasu, kliknięcie, przycisk, nadmiar
  /// w kolejce) idzie przez wyjście stylu; z ekranu i z kolejki karta
  /// znika dopiero po nim.
  void _zniknij() {
    if (!mounted || _znika) return;
    _znika = true;
    _life.stop();
    _ruch.reverse().whenComplete(() {
      if (mounted) widget.onGone();
    });
  }

  @override
  void dispose() {
    _ruch.dispose();
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = ChattMotion.of(context);
    return MotionTransition(
      animation: _ruch,
      shift: m.toastShift,
      // Ciepło znika samym przenikaniem.
      exitShift: m.toastExitShift ? m.toastShift : 0,
      child: _karta(context, m),
    );
  }

  Widget _karta(BuildContext context, ChattMotion m) {
    final scheme = Theme.of(context).colorScheme;
    final message = widget.message;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.inverseSurface,
        borderRadius:
            BorderRadius.circular(ChattTokens.of(context).radiusField),
        elevation: 6,
        child: InkWell(
          // Kliknięcie zamyka: komunikat ma nie stać na drodze ani sekundy
          // dłużej, niż użytkownik chce.
          onTap: _zniknij,
          // Najechanie i fokus w czasie stylu.
          hoverDuration: m.hover,
          borderRadius:
              BorderRadius.circular(ChattTokens.of(context).radiusField),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: () {
                final width = MediaQuery.sizeOf(context).width - 24;
                return width < 360 ? width : 360.0;
              }(),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      14, 12, message.actionLabel == null ? 14 : 6, 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          message.text,
                          style: TextStyle(color: scheme.onInverseSurface),
                        ),
                      ),
                      if (message.actionLabel != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            // Karta w wyjściu nie przyjmuje już akcji.
                            if (_znika) return;
                            _zniknij();
                            message.onAction?.call();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.inversePrimary,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(message.actionLabel!),
                        ),
                      ],
                    ],
                  ),
                ),
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12)),
                  child: AnimatedBuilder(
                    animation: _life,
                    builder: (context, _) => LinearProgressIndicator(
                      value: 1 - _life.value,
                      minHeight: 3,
                      backgroundColor: Colors.transparent,
                      color: scheme.inversePrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
