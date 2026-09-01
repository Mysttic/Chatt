import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/background_service.dart';
import 'data/db.dart';
import 'l10n/app_localizations.dart';
import 'services/app_services.dart';
import 'services/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cały stos (baza, serwer, discovery) startuje przed pierwszą klatką —
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
      _jezykInterfejsu(ustawienia.language),
    );
    await BackgroundService.start(
      title: teksty.backgroundServiceTitle,
      body: teksty.backgroundServiceBody,
    );
  });

  runApp(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: const ChattApp(),
    ),
  );
}

/// Język do tekstów spoza drzewa widgetów (powiadomienie usługi). `system`
/// bierzemy z systemu, ale tylko jeśli mamy dla niego tłumaczenie.
Locale _jezykInterfejsu(AppLanguage wybor) {
  switch (wybor) {
    case AppLanguage.polish:
      return const Locale('pl');
    case AppLanguage.english:
      return const Locale('en');
    case AppLanguage.system:
      final systemowy = PlatformDispatcher.instance.locale.languageCode;
      return AppLocalizations.supportedLocales
              .any((l) => l.languageCode == systemowy)
          ? Locale(systemowy)
          : const Locale('en');
  }
}
