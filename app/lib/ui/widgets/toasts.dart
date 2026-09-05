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
library;

import 'package:flutter/material.dart';

/// Jeden komunikat w kolejce.
class ToastMessage {
  /// Rośnie, nigdy się nie powtarza, służy tylko za klucz widgetu.
  final int id;
  final String text;

  /// Opcjonalny przycisk (dziś: „Kopiuj" przy ścieżce pliku na Androidzie).
  final String? actionLabel;
  final VoidCallback? onAction;

  final Duration duration;

  const ToastMessage({
    required this.id,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.duration = const Duration(seconds: 4),
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
    Duration duration = const Duration(seconds: 4),
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
/// nie należy do żadnego ekranu i przeżywa jego zamknięcie.
void showToast(
  String text, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) =>
    chattToasts.show(text,
        actionLabel: actionLabel, onAction: onAction, duration: duration);

/// Nakładka z kolejką komunikatów. Wpinana raz, w `MaterialApp.builder`, obok
/// `PromptOverlay`, dzięki czemu działa na każdym ekranie i nie wymaga
/// `Scaffold`a.
class ToastHost extends StatelessWidget {
  final Widget child;

  const ToastHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: ValueListenableBuilder<List<ToastMessage>>(
              valueListenable: chattToasts,
              builder: (context, messages, _) => Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final message in messages)
                      _ToastCard(key: ValueKey(message.id), message: message),
                  ],
                ),
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

  const _ToastCard({super.key, required this.message});

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _life = AnimationController(
    vsync: this,
    duration: widget.message.duration,
  );

  @override
  void initState() {
    super.initState();
    _life.forward().whenComplete(() {
      if (mounted) chattToasts.dismiss(widget.message.id);
    });
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = widget.message;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(12),
        elevation: 6,
        child: InkWell(
          // Kliknięcie zamyka od razu: komunikat ma nie stać na drodze ani
          // sekundy dłużej, niż użytkownik chce.
          onTap: () => chattToasts.dismiss(message.id),
          borderRadius: BorderRadius.circular(12),
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
                            chattToasts.dismiss(message.id);
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
