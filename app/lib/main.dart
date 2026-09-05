import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/background_service.dart';
import 'core/languages.dart';
import 'core/startup_error.dart';
import 'core/tray.dart';
import 'data/db.dart';
import 'l10n/app_localizations.dart';
import 'services/app_services.dart';
import 'services/providers.dart';

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

  // Android: usługa pierwszoplanowa trzyma proces (a z nim serwer i
  // discovery) także po zamknięciu okna. Teksty jej powiadomienia biorą się
  // z języka wybranego w aplikacji, więc odświeżamy je przy każdej zmianie.
  AppLanguage? ostatniJezyk;
  services.db.watchSettings().listen((ustawienia) async {
    if (ustawienia.language == ostatniJezyk) return;
    ostatniJezyk = ustawienia.language;
    final teksty = await AppLocalizations.delegate.load(
      ustawienia.language.effectiveLocale,
    );
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
  });

  runApp(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: const ChattApp(),
    ),
  );
}

