import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Co ile pytamy znane urządzenia, czy wciąż odpowiadają.
const Duration presenceInterval = Duration(seconds: 30);

/// Obecność rozmówców: guid urządzenia -> czy odpowiada pod ostatnio znanym
/// adresem. Brak wpisu znaczy, że jeszcze nie zdążyliśmy zapytać.
///
/// Pytaniem jest GET /info z dwusekundowym limitem, to samo, którym nagłówek
/// rozmowy sprawdza rozmówcę. Wszystkie lecą naraz, więc jedno milczące
/// urządzenie nie opóźnia odpowiedzi o pozostałych.
///
/// Strumień chodzi tylko wtedy, gdy patrzy na niego jakiś ekran: pukanie do
/// całej listy co pół minuty przy zgaszonym ekranie kosztowałoby baterię,
/// a nikt by tego nie zobaczył. Odliczanie do kolejnej rundy trzymamy jako
/// [Timer], żeby zamknięcie ekranu zdejmowało je od razu.
final presenceProvider = StreamProvider.autoDispose<Map<String, bool>>((ref) {
  final services = ref.watch(appServicesProvider);
  final wyjscie = StreamController<Map<String, bool>>();
  Timer? nastepnaRunda;
  var zyje = true;

  Future<void> runda() async {
    final peers = await services.db.allPeers();
    final wyniki = await Future.wait(
      peers.map((peer) async =>
          MapEntry(peer.guid, await services.isPeerOnline(peer))),
    );
    if (!zyje) return;
    wyjscie.add(Map.fromEntries(wyniki));
    nastepnaRunda = Timer(presenceInterval, runda);
  }

  ref.onDispose(() {
    zyje = false;
    nastepnaRunda?.cancel();
    wyjscie.close();
  });

  runda();
  return wyjscie.stream;
});
