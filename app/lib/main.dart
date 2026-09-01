import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/background_service.dart';
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
  // discovery) także po zamknięciu okna. Na desktopie nic nie robi.
  await BackgroundService.start();

  runApp(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: const ChattApp(),
    ),
  );
}
