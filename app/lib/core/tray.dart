import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Ikona w zasobniku Windows razem z tym, co z niej wynika: zamknięcie okna
/// chowa aplikację zamiast ją kończyć, a nasłuch chodzi dalej.
///
/// Bez tego Chatt na pulpicie nasłuchuje wyłącznie z otwartym oknem, czyli
/// w praktyce rzadko, a na Androidzie tę rolę pełni usługa pierwszoplanowa.
class TrayIcon with TrayListener, WindowListener {
  TrayIcon._();

  static final TrayIcon instance = TrayIcon._();

  /// Tylko Windows. Na Androidzie zasobnika nie ma, a na Linuksie i macOS
  /// aplikacja nie jest wydawana, więc nie ma czego obiecywać.
  static bool get supported => Platform.isWindows;

  bool _iconReady = false;

  /// Napisy z [apply], potrzebne przy każdym przebudowaniu menu.
  String _tooltip = 'Chatt';
  String _showLabel = '';
  String _quitLabel = '';

  /// Trwa pisanie z innego urządzenia: ikona ma inny wygląd, podpowiedź mówi,
  /// kto pisze, a w menu jest Stop. `null` znaczy, że nikt nie pisze.
  String? _typingTooltip;
  String? _typingStopLabel;
  String _iconPath = 'assets/tray_icon.ico';

  /// Wołane przez pozycję „Zatrzymaj zdalną klawiaturę" w menu.
  void Function()? onStopTyping;

  /// Przechwycenie zamknięcia okna. Woła się raz, przed `runApp`, bo od tej
  /// chwili użytkownik może kliknąć krzyżyk.
  Future<void> attach() async {
    if (!supported) return;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    trayManager.addListener(this);
  }

  /// Ikona i menu. Osobno od [attach], bo napisy idą za językiem wybranym
  /// w aplikacji i zmieniają się w trakcie działania.
  Future<void> apply({
    required String tooltip,
    required String showLabel,
    required String quitLabel,
  }) async {
    if (!supported) return;
    _tooltip = tooltip;
    _showLabel = showLabel;
    _quitLabel = quitLabel;
    await _rebuild();
  }

  /// Pisanie z innego urządzenia trwa ([tooltip] i [stopLabel] podane) albo
  /// się skończyło (oba `null`). Na PC obsługiwanym dotykiem zasobnik jest
  /// mały, więc ikona zmienia wygląd, a Stop siedzi także w jej menu.
  Future<void> setTyping({String? tooltip, String? stopLabel}) async {
    if (!supported) return;
    _typingTooltip = tooltip;
    _typingStopLabel = stopLabel;
    await _rebuild();
  }

  Future<void> _rebuild() async {
    final tooltip = _typingTooltip ?? _tooltip;
    final icon = _typingTooltip == null
        ? 'assets/tray_icon.ico'
        : 'assets/tray_icon_typing.ico';
    // Podpowiedź przed ikoną, choć wygląda to na odwróconą kolejność:
    // wtyczka przepisuje zapamiętaną podpowiedź do zgłoszenia ikony, a
    // Windows zapisuje tę pierwszą wartość u siebie na stałe (widać ją potem
    // na liście ikon zasobnika). Ustawiona dopiero po ikonie zostawia tam
    // śmieci z niezainicjowanego bufora.
    await trayManager.setToolTip(tooltip);
    if (!_iconReady || icon != _iconPath) {
      await trayManager.setIcon(icon);
      _iconReady = true;
      _iconPath = icon;
      await trayManager.setToolTip(tooltip);
    }
    final stop = _typingStopLabel;
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: _show, label: _showLabel),
      if (stop != null) MenuItem(key: _stopTyping, label: stop),
      MenuItem.separator(),
      MenuItem(key: _quit, label: _quitLabel),
    ]));
  }

  static const _show = 'pokaz';
  static const _stopTyping = 'zatrzymaj-pisanie';
  static const _quit = 'zamknij';

  @override
  void onWindowClose() {
    // Krzyżyk chowa okno. Wyjście z programu jest w menu ikony: inaczej
    // nasłuch kończyłby się przy pierwszym odruchowym zamknięciu.
    windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _show:
        showWindow();
      case _stopTyping:
        onStopTyping?.call();
      case _quit:
        quit();
    }
  }

  /// Wyciąga okno z zasobnika (albo z paska zadań) na wierzch.
  Future<void> showWindow() async {
    if (!supported) return;
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  /// Krok przed końcem programu: zapis tego, co dziennik aplikacji i historia
  /// pisania trzymają jeszcze w pamięci. Ustawia go `main.dart`.
  Future<void> Function()? beforeQuit;

  /// Kończy program.
  ///
  /// Woła to menu ikony w zasobniku, a przy aktualizacji także ekran ustawień:
  /// instalator wgrywa się w miejsce działającej aplikacji, więc ta musi mu
  /// zejść z drogi. [beforeQuit] dostaje na to najwyżej dwie sekundy.
  Future<void> quit() async {
    if (!supported) return;
    try {
      await beforeQuit?.call().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Zapis się nie zdążył albo padł: wyjście i tak ma się odbyć.
    }
    // Zdjęcie blokady zamykania: dopiero teraz zamknięcie okna ma skończyć
    // proces, bo tego właśnie użytkownik chce.
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await windowManager.close();
  }
}
