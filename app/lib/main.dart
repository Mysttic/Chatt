import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/background_service.dart';
import 'core/languages.dart';
import 'core/share_intake.dart';
import 'core/startup_error.dart';
import 'core/tray.dart';
import 'data/db.dart';
import 'l10n/app_localizations.dart';
import 'services/app_log.dart';
import 'services/app_services.dart';
import 'services/providers.dart';
import 'ui/remote_input_desktop.dart';
import 'ui/remote_input_mobile.dart';
import 'ui/share_shortcuts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _start();
  } catch (blad, slad) {
    // Wszystko poniżej dzieje się przed pierwszą klatką, a okno pokazuje się
    // dopiero po niej. Bez tego przechwycenia proces zostawał żywy i niewidoczny.
    final plik = await saveStartupError(blad, slad);
    runApp(StartupErrorApp(error: blad, logPath: plik));
  }
}

Future<void> _start() async {
  // Windows: krzyżyk ma chować okno do zasobnika, a nie kończyć nasłuchu.
  // Musi być przed pierwszą klatką, bo od niej można już kliknąć krzyżyk.
  await TrayIcon.instance.attach();

  // Cały stos (baza, serwer, discovery) startuje przed pierwszą klatką:
  // od tego momentu urządzenie jest widoczne w sieci i przyjmuje wiadomości.
  final services = await AppServices.start(
    // Wpisy dziennika aplikacji także na konsoli, ale tylko w buildzie debug.
    logToConsole: kDebugMode,
    // Wiadomość, która przyszła przy zamkniętym oknie, ma dać znać
    // powiadomieniem. Gdy aplikacja jest na wierzchu, widać ją i tak.
    onIncomingMessage: (peer, preview, conversationId) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }
      BackgroundService.notifyMessage(
        title: peer.name,
        body: preview,
        id: conversationId,
      );
    },
  );

  // Od tej chwili błąd, którego nikt nie złapał, trafia do dziennika
  // aplikacji. Awaria sprzed tej chwili kończy się ekranem awarii startu
  // i plikiem `chatt-startup-error.txt` (patrz [main]).
  logUncaughtErrors(services.log);

  // Wyjście z menu zasobnika (także przed instalatorem aktualizacji) kończy
  // proces bez sprzątania serwisu, a Android potrafi zakończyć go bez
  // żadnego sygnału. Dziennik i historia pisania zapisują więc to, co
  // trzymają w pamięci, przed wyjściem i przy każdym zejściu w tło.
  TrayIcon.instance.beforeQuit = () async {
    services.log.info(LogArea.app, 'App stopping');
    await services.typingJournal.flush();
    await services.log.flush();
  };
  WidgetsBinding.instance.addObserver(_ZapisPrzyTle(services));

  // Windows: pasek „Pisze: …" ze Stopem i ikona w zasobniku przez całą
  // zgodę na zdalną klawiaturę, także przy schowanym oknie.
  AppLocalizations? biezaceTeksty;
  final klawiatura = Platform.isWindows
      ? (RemoteInputDesktop(services, texts: () => biezaceTeksty)..attach())
      : null;
  // Android: pasek klawiatury Chatt i stałe powiadomienie, wybór klawiatury
  // po zgodzie, powiadomienie o karcie przy zamkniętym oknie.
  final klawiaturaMobilna = Platform.isAndroid
      ? (RemoteInputMobile(services, texts: () => biezaceTeksty)..attach())
      : null;

  // Android: udostępnianie z innych aplikacji (issue #60). Treść, która
  // uruchomiła aplikację, czeka już w kanale; ostatnie rozmowy idą do
  // systemowego okna „Udostępnij" i pod przytrzymaną ikonę Chatt.
  if (Platform.isAndroid) {
    unawaited(ShareIntake.instance.attach());
    ShareShortcuts(services, ShareIntake.instance).attach();
  }

  // Android: usługa pierwszoplanowa trzyma proces (a z nim serwer i
  // discovery) także po zamknięciu okna. Teksty jej powiadomienia biorą się
  // z języka wybranego w aplikacji, więc odświeżamy je przy każdej zmianie.
  AppLanguage? ostatniJezyk;
  services.db.watchSettings().listen(
    (ustawienia) async {
      if (ustawienia.language == ostatniJezyk) return;
      ostatniJezyk = ustawienia.language;
      try {
        final teksty = await AppLocalizations.delegate.load(
          ustawienia.language.effectiveLocale,
        );
        biezaceTeksty = teksty;
        await BackgroundService.start(
          title: teksty.backgroundServiceTitle,
          body: teksty.backgroundServiceBody,
        );
        // Menu ikony w zasobniku też idzie za językiem aplikacji.
        await TrayIcon.instance.apply(
          tooltip: teksty.trayTooltip,
          showLabel: teksty.trayShow,
          quitLabel: teksty.trayQuit,
        );
        klawiatura?.refreshTexts();
        klawiaturaMobilna?.refreshTexts();
      } catch (blad, slad) {
        services.log.error(
            LogArea.app, 'Applying the app language to system surfaces failed',
            error: blad, stack: slad);
      }
    },
    // Zamknięta albo uszkodzona baza: teksty powiadomienia i zasobnika
    // zostają w ostatnim języku, a ślad trafia do dziennika.
    onError: (Object blad, StackTrace slad) => services.log.error(
        LogArea.app, 'Settings watcher failed: language',
        error: blad, stack: slad),
  );

  runApp(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: const ChattApp(),
    ),
  );
}

/// Zapis dziennika aplikacji i historii pisania przy każdym zejściu
/// aplikacji w tło: Android potrafi potem zakończyć proces bez sygnału.
class _ZapisPrzyTle with WidgetsBindingObserver {
  _ZapisPrzyTle(this._services);

  final AppServices _services;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_services.typingJournal.flush());
      unawaited(_services.log.flush());
    }
  }
}
