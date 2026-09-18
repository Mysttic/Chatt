import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/ui/widgets/paste_shortcut.dart';

/// Ctrl+V na ekranie rozmowy jest wpięty globalnie, a nie w drzewo widgetów,
/// bo świeżo otwarta rozmowa nie ma nigdzie ogniska. Globalny uchwyt słyszy
/// jednak także klawisze, które nie są jego, więc rzecz do sprawdzenia jest
/// jedna: kiedy [PasteShortcut] się odzywa, a kiedy siedzi cicho.
void main() {
  late int wklejenia;

  setUp(() => wklejenia = 0);

  /// Ekran z polem w pasku (jak szukanie w rozmowie) i polem w środku
  /// (jak pole wiadomości). Tylko to drugie leży pod [PasteShortcut].
  Future<void> ekran(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const TextField(key: Key('pasek')),
            ),
            body: PasteShortcut(
              onPaste: () => wklejenia++,
              child: const TextField(key: Key('wiadomosc')),
            ),
          ),
        ),
      );

  Future<void> ctrlV(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('bez ogniska gdziekolwiek: wkleja', (tester) async {
    await ekran(tester);

    await ctrlV(tester);

    expect(wklejenia, 1);
  });

  testWidgets('ognisko w środku: wkleja', (tester) async {
    await ekran(tester);
    await tester.tap(find.byKey(const Key('wiadomosc')));
    await tester.pump();

    await ctrlV(tester);

    expect(wklejenia, 1);
  });

  testWidgets('ognisko w pasku nad ekranem: cisza', (tester) async {
    await ekran(tester);
    await tester.tap(find.byKey(const Key('pasek')));
    await tester.pump();

    await ctrlV(tester);

    expect(wklejenia, 0);
  });

  testWidgets('ognisko na przycisku poza ekranem: i tak wkleja',
      (tester) async {
    // Karta z prośbą o plik wisi nad całą aplikacją i zabiera ognisko swojemu
    // przyciskowi, żeby dało się ją przyjąć Enterem. To nie jest pole
    // tekstowe, więc Ctrl+V dalej należy do rozmowy pod spodem.
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Scaffold(
              body: PasteShortcut(
                onPaste: () => wklejenia++,
                child: const TextField(key: Key('wiadomosc')),
              ),
            ),
            Positioned(
              top: 0,
              child: ElevatedButton(
                autofocus: true,
                onPressed: () {},
                child: const Text('Przyjmij'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(tester.binding.focusManager.primaryFocus?.debugLabel,
        isNot('PasteShortcut'));

    await ctrlV(tester);

    expect(wklejenia, 1);
  });

  testWidgets('samo V i sam Ctrl: cisza', (tester) async {
    await ekran(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(wklejenia, 0);
  });

  testWidgets('Ctrl+Shift+V to nie ten skrót', (tester) async {
    await ekran(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(wklejenia, 0);
  });

  testWidgets('puszczenie klawisza nie liczy się drugi raz', (tester) async {
    await ekran(tester);

    await ctrlV(tester);
    await ctrlV(tester);

    expect(wklejenia, 2, reason: 'dwa wciśnięcia, nie cztery zdarzenia');
  });

  testWidgets('z czymś na wierzchu: cisza', (tester) async {
    await ekran(tester);
    final nawigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(nawigator.push(
      MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
    ));
    await tester.pumpAndSettle();

    await ctrlV(tester);

    expect(wklejenia, 0);
  });

  testWidgets('po zdjęciu z drzewa: cisza', (tester) async {
    await ekran(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    await ctrlV(tester);

    expect(wklejenia, 0);
  });

  testWidgets('zdarzenie idzie dalej, więc tekst wkleja się jak zawsze',
      (tester) async {
    // Schowek z tekstem i ognisko w polu: po Ctrl+V w polu ma być tekst.
    // Gdyby uchwyt zwrócił `handled`, skróty tekstowe Fluttera nigdy by go
    // nie zobaczyły.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': 'wklejony tekst'};
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final kontroler = TextEditingController();
    addTearDown(kontroler.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PasteShortcut(
            onPaste: () => wklejenia++,
            child: TextField(controller: kontroler, autofocus: true),
          ),
        ),
      ),
    );
    await tester.pump();

    await ctrlV(tester);
    await tester.pumpAndSettle();

    expect(kontroler.text, 'wklejony tekst');
    expect(wklejenia, 1, reason: 'plik ze schowka dokłada się do tekstu');
  });
}
