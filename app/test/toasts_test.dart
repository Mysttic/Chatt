import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/ui/widgets/toasts.dart';

/// Kolejka komunikatów w rogu okna: kolejność, limit, znikanie po czasie
/// i po kliknięciu.
///
/// Osobny plik świadomie. Wystarczy jeden `testWidgets` w pliku, żeby
/// `TestWidgetsFlutterBinding` podmienił `HttpClient` na atrapę odpowiadającą
/// 400 dla **całego** zestawu, a obok, w peer_prefs_test.dart, stoją testy
/// dwóch instancji rozmawiających po prawdziwym gnieździe.
void main() {
  group('kolejka komunikatów', () {
    setUp(chattToasts.clear);
    tearDown(chattToasts.clear);

    test('komunikaty ustawiają się w kolejce i znikają po identyfikatorze', () {
      final pierwszy = chattToasts.show('raz');
      chattToasts.show('dwa');

      expect(chattToasts.value.map((m) => m.text), ['raz', 'dwa']);

      chattToasts.dismiss(pierwszy.id);
      expect(chattToasts.value.map((m) => m.text), ['dwa']);
    });

    test('najstarszy ustępuje miejsca, żeby róg nie zarósł tekstem', () {
      for (final tekst in ['raz', 'dwa', 'trzy', 'cztery']) {
        chattToasts.show(tekst);
      }

      expect(chattToasts.value, hasLength(ToastController.maxVisible));
      expect(chattToasts.value.map((m) => m.text), ['dwa', 'trzy', 'cztery']);
    });

    testWidgets('karta znika sama po swoim czasie', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: ToastHost(child: SizedBox.shrink()),
      ));

      showToast('zapisano', duration: const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('zapisano'), findsOneWidget);

      // W połowie odliczania karta ma jeszcze stać.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('zapisano'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('zapisano'), findsNothing);
      expect(chattToasts.value, isEmpty,
          reason: 'kolejka nie może rosnąć w nieskończoność');
    });

    testWidgets('kliknięcie zamyka od razu', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: ToastHost(child: SizedBox.shrink()),
      ));

      showToast('skopiowano', duration: const Duration(minutes: 1));
      await tester.pump();

      await tester.tap(find.text('skopiowano'));
      await tester.pump();

      expect(find.text('skopiowano'), findsNothing);
    });
  });
}
