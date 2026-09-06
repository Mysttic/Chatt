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
    // Podpowiedź przed ikoną, choć wygląda to na odwróconą kolejność:
    // wtyczka przepisuje zapamiętaną podpowiedź do zgłoszenia ikony, a
    // Windows zapisuje tę pierwszą wartość u siebie na stałe (widać ją potem
    // na liście ikon zasobnika). Ustawiona dopiero po ikonie zostawia tam
    // śmieci z niezainicjowanego bufora.
    await trayManager.setToolTip(tooltip);
    if (!_iconReady) {
      await trayManager.setIcon('assets/tray_icon.ico');
      _iconReady = true;
      await trayManager.setToolTip(tooltip);
    }
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: _show, label: showLabel),
      MenuItem.separator(),
      MenuItem(key: _quit, label: quitLabel),
    ]));
  }

  static const _show = 'pokaz';
  static const _quit = 'zamknij';

  @override
  void onWindowClose() {
    // Krzyżyk chowa okno. Wyjście z programu jest w menu ikony: inaczej
    // nasłuch kończyłby się przy pierwszym odruchowym zamknięciu.
    windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() => _showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _show:
        _showWindow();
      case _quit:
        quit();
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// Kończy program.
  ///
  /// Woła to menu ikony w zasobniku, a przy aktualizacji także ekran ustawień:
  /// instalator wgrywa się w miejsce działającej aplikacji, więc ta musi mu
  /// zejść z drogi.
  Future<void> quit() async {
    if (!supported) return;
    // Zdjęcie blokady zamykania: dopiero teraz zamknięcie okna ma skończyć
    // proces, bo tego właśnie użytkownik chce.
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await windowManager.close();
  }
}
