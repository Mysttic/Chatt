import 'dart:async';

import 'package:window_manager/window_manager.dart';

import '../core/remote_input.dart';
import '../core/tray.dart';
import '../l10n/app_localizations.dart';
import '../services/app_services.dart';

/// Okno aplikacji widziane z zewnątrz: czy jest na ekranie, i jak je wyciągnąć
/// albo schować. Osobno, żeby test nie potrzebował wtyczki okna.
abstract class DesktopWindow {
  Future<bool> isShown();
  Future<bool> isMinimized();
  Future<void> show();
  Future<void> hide();
  Future<void> minimize();
}

class _WindowManagerWindow implements DesktopWindow {
  const _WindowManagerWindow();

  @override
  Future<bool> isShown() => windowManager.isVisible();

  @override
  Future<bool> isMinimized() => windowManager.isMinimized();

  @override
  Future<void> show() => TrayIcon.instance.showWindow();

  @override
  Future<void> hide() => windowManager.hide();

  @override
  Future<void> minimize() => windowManager.minimize();
}

/// Dodatek klawiatury na Windows poza oknem aplikacji.
///
/// Przez całą zgodę widać pływający pasek „Pisze: …" ze Stopem i inną ikonę
/// w zasobniku, także wtedy, gdy okno Chatta siedzi schowane. Karta zgody,
/// która przyszła przy schowanym oknie, wyciąga je na wierzch, a po decyzji
/// okno wraca tam, skąd przyszło: wskazane wcześniej pole na tym komputerze
/// znowu ma fokus.
///
/// Przy wyłączonym dodatku nic z tego się nie dzieje, bo nie ma ani zgody,
/// ani kart.
class RemoteInputDesktop {
  final AppServices services;

  /// Teksty w języku wybranym w aplikacji. `null`, dopóki baza nie powie,
  /// jaki to język.
  final AppLocalizations? Function() texts;
  final DesktopWindow window;
  final Future<bool> Function({required String text, required String stop})
      showIndicator;
  final Future<bool> Function() hideIndicator;
  final Future<void> Function({String? tooltip, String? stopLabel}) setTray;

  RemoteInputDesktop(
    this.services, {
    required this.texts,
    DesktopWindow? window,
    Future<bool> Function({required String text, required String stop})?
        showIndicator,
    Future<bool> Function()? hideIndicator,
    Future<void> Function({String? tooltip, String? stopLabel})? setTray,
  })  : window = window ?? const _WindowManagerWindow(),
        showIndicator = showIndicator ?? RemoteInputChannel.showIndicator,
        hideIndicator = hideIndicator ?? RemoteInputChannel.hideIndicator,
        setTray = setTray ?? TrayIcon.instance.setTyping;

  /// Co wisi na pasku: ostatni pokazany tekst, `null` = pasek schowany.
  String? _shown;

  /// Jak wyglądało okno, zanim karta zgody je wyciągnęła. `null` = karta go
  /// nie ruszała.
  _Before? _pulled;

  /// Kolejka zmian, żeby szybkie „jest zgoda, nie ma zgody" nie wyprzedzały
  /// się nawzajem w drodze do strony natywnej.
  Future<void> _queue = Future.value();

  void attach() {
    services.incomingRemoteInput.addListener(_onIncoming);
    services.pendingRemoteInput.addListener(_onPending);
    RemoteInputChannel.listen(onStop: services.stopIncomingRemoteInput);
    TrayIcon.instance.onStopTyping = services.stopIncomingRemoteInput;
  }

  void detach() {
    services.incomingRemoteInput.removeListener(_onIncoming);
    services.pendingRemoteInput.removeListener(_onPending);
  }

  /// Zmiana języka: pasek i zasobnik dostają nowe napisy.
  void refreshTexts() {
    _shown = null;
    _onIncoming();
  }

  void _run(Future<void> Function() krok) {
    _queue = _queue.then((_) => krok()).catchError((Object _) {});
  }

  /// Ostatnie zmiany doszły do strony natywnej (dla testów).
  Future<void> get settled => _queue;

  void _onIncoming() {
    final grant = services.incomingRemoteInput.value;
    final l = texts();
    if (grant == null || l == null) {
      if (_shown == null) return;
      _shown = null;
      _run(() async {
        await hideIndicator();
        await setTray();
      });
      return;
    }
    final app = grant.target.appLabel.isNotEmpty
        ? grant.target.appLabel
        : grant.target.app;
    final text = (grant.target.active && app.isNotEmpty)
        ? l.remoteInputBarTarget(grant.peerName, app)
        : l.remoteInputActive(grant.peerName);
    if (text == _shown) return;
    _shown = text;
    final stop = l.remoteInputStop;
    final trayStop = l.trayRemoteInputStop;
    final tooltip = l.remoteInputActive(grant.peerName);
    _run(() async {
      await showIndicator(text: text, stop: stop);
      await setTray(tooltip: tooltip, stopLabel: trayStop);
    });
  }

  void _onPending() {
    final czeka = services.pendingRemoteInput.value.isNotEmpty;
    _run(() async {
      if (czeka && _pulled == null) {
        final widoczne = await window.isShown();
        final zminimalizowane = await window.isMinimized();
        if (widoczne && !zminimalizowane) return;
        _pulled = zminimalizowane ? _Before.minimized : _Before.hidden;
        await window.show();
      } else if (!czeka && _pulled != null) {
        final przed = _pulled;
        _pulled = null;
        if (przed == _Before.minimized) {
          await window.minimize();
        } else {
          await window.hide();
        }
      }
    });
  }
}

enum _Before { hidden, minimized }
