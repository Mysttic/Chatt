import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/remote_input.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/ui/remote_input_desktop.dart';

/// Własne okno Chatta na Windows: kod natywny nie pyta o nie UI Automation
/// (odpowiadałby na to czekający wątek platformy), więc rodzaj pola z fokusem
/// podaje aplikacja z drzewa widżetów.
void main() {
  testWidgets('pole z fokusem: tekst, hasło, tylko do odczytu, przycisk',
      (tester) async {
    final tekst = FocusNode();
    final haslo = FocusNode();
    final odczyt = FocusNode();
    final przycisk = FocusNode();
    addTearDown(() {
      for (final wezel in [tekst, haslo, odczyt, przycisk]) {
        wezel.dispose();
      }
    });
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Column(children: [
          TextField(focusNode: tekst),
          TextField(focusNode: haslo, obscureText: true),
          TextField(focusNode: odczyt, readOnly: true),
          TextButton(
              focusNode: przycisk, onPressed: () {}, child: const Text('OK')),
        ]),
      ),
    ));
    expect(focusedFieldKind(), RemoteInputField.none, reason: 'nic z fokusem');

    tekst.requestFocus();
    await tester.pump();
    expect(focusedFieldKind(), RemoteInputField.text);

    haslo.requestFocus();
    await tester.pump();
    expect(focusedFieldKind(), RemoteInputField.password);

    odczyt.requestFocus();
    await tester.pump();
    expect(focusedFieldKind(), RemoteInputField.none,
        reason: 'w polu tylko do odczytu nic się nie wpisze');

    przycisk.requestFocus();
    await tester.pump();
    expect(focusedFieldKind(), RemoteInputField.none);
  });

  test('kanał: własne okno dostaje rodzaj pola z aplikacji, każde inne '
      'zostaje przy odpowiedzi natywnej', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const kanal = MethodChannel('chatt/remoteinput');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var odpowiedz = <String, Object?>{};
    messenger.setMockMethodCallHandler(kanal, (call) async => odpowiedz);
    RemoteInputChannel.debugSupported = true;
    RemoteInputChannel.ownWindowField = () => RemoteInputField.password;
    addTearDown(() {
      messenger.setMockMethodCallHandler(kanal, null);
      RemoteInputChannel.debugSupported = null;
      RemoteInputChannel.ownWindowField = null;
    });
    const ujscie = RemoteInputChannel();

    odpowiedz = {
      'active': true,
      'field': 'none',
      'app': 'chatt.exe',
      'appLabel': 'Chatt',
      'ownApp': true,
      'ownWindow': true,
    };
    final cel = await ujscie.status();
    expect(cel.field, RemoteInputField.password);
    expect(cel.active, isTrue);
    expect(cel.ownApp, isTrue);
    expect(cel.app, 'chatt.exe');
    expect(cel.appLabel, 'Chatt');

    odpowiedz = {...odpowiedz, 'applied': true};
    final wynik = await ujscie.apply(const [RemoteInputOp.insert('a')]);
    expect(wynik.applied, isTrue);
    expect(wynik.target.field, RemoteInputField.password);

    // Inna instancja Chatta albo inny program: pole z UI Automation.
    odpowiedz = {
      'active': true,
      'field': 'text',
      'app': 'chatt.exe',
      'ownApp': true,
      'ownWindow': false,
    };
    expect((await ujscie.status()).field, RemoteInputField.text);

    // Nic się nie wpisze: aplikacja pola nie dopowiada.
    odpowiedz = {'active': false, 'field': 'none', 'ownWindow': true};
    expect((await ujscie.status()).field, RemoteInputField.none);

    // Bez aplikacji (np. Android) zostaje odpowiedź natywna.
    RemoteInputChannel.ownWindowField = null;
    odpowiedz = {'active': true, 'field': 'none', 'ownWindow': true};
    expect((await ujscie.status()).field, RemoteInputField.none);
  });
}
