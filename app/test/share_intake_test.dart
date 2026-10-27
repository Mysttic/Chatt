import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/share_intake.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/ui/share_shortcuts.dart';
import 'package:chatt/ui/styles.dart';

/// Strona natywna kanału `chatt/share` na niby: skrzynka z zapowiedzią,
/// kopie plików do oddania i zapis każdego wywołania.
class _Natywna {
  _Natywna(this.kanal) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanal, _obsluz);
  }

  final MethodChannel kanal;
  Map<String, Object?>? skrzynka;
  final kopie = <String, List<Map<String, Object?>>>{};
  final wywolania = <MethodCall>[];

  Iterable<Object?> argumenty(String metoda) => wywolania
      .where((c) => c.method == metoda)
      .map((c) => (c.arguments as Map)['id'] ?? c.arguments);

  Future<Object?> _obsluz(MethodCall call) async {
    wywolania.add(call);
    switch (call.method) {
      case 'take':
        final zapowiedz = skrzynka;
        skrzynka = null;
        return zapowiedz;
      case 'files':
        return kopie[(call.arguments as Map)['id']] ?? const [];
      case 'setTargets':
        return true;
    }
    return null;
  }

  /// Natywna strona woła Darta: przyszło coś nowego.
  Future<void> zapowiedz() async {
    final wiadomosc =
        const StandardMethodCodec().encodeMethodCall(const MethodCall('incoming'));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(kanal.name, wiadomosc, (_) {});
  }

  void odepnij() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(kanal, null);
}

Map<String, Object?> _udostepnienie(String id,
        {String? text, int count = 0, int skipped = 0, String? peer}) =>
    {
      'kind': 'share',
      'id': id,
      'text': text,
      'count': count,
      'skipped': skipped,
      'peer': peer,
    };

/// Udostępnianie do Chatta (issue #60): zapowiedzi z kanału, kopie plików,
/// treść czekająca w rozmowie i rozmowy dla okna „Udostępnij".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('zapowiedź z kanału', () {
    test('udostępnienie z tekstem, plikami i rozmówcą', () {
      final prosba = ShareIntake.requestFrom(_udostepnienie('a',
          text: 'https://example.com', count: 2, skipped: 1, peer: 'guid-a'));
      expect(prosba, isA<IncomingShare>());
      final share = prosba! as IncomingShare;
      expect(share.id, 'a');
      expect(share.text, 'https://example.com');
      expect(share.fileCount, 2);
      expect(share.skipped, 1);
      expect(share.peerGuid, 'guid-a');
      expect(share.hasText, isTrue);
      expect(share.isEmpty, isFalse);
    });

    test('pusty rozmówca to wybór rozmowy, sam odstęp to brak tekstu', () {
      final share = ShareIntake.requestFrom(
          _udostepnienie('a', text: '  \n', peer: ''))! as IncomingShare;
      expect(share.peerGuid, isNull);
      expect(share.hasText, isFalse);
      expect(share.isEmpty, isTrue);
    });

    test('skrót rozmowy', () {
      final prosba =
          ShareIntake.requestFrom({'kind': 'open', 'peer': 'guid-b'});
      expect(prosba, isA<OpenConversationRequest>());
      expect((prosba! as OpenConversationRequest).peerGuid, 'guid-b');
    });

    test('niezrozumiała zapowiedź przepada', () {
      expect(ShareIntake.requestFrom({'kind': 'open'}), isNull);
      expect(ShareIntake.requestFrom({'kind': 'share'}), isNull);
      expect(ShareIntake.requestFrom({'kind': 'cos'}), isNull);
      expect(ShareIntake.requestFrom(const {}), isNull);
    });
  });

  group('kanał', () {
    const kanal = MethodChannel('test/share');
    late _Natywna natywna;
    late ShareIntake intake;

    setUp(() {
      natywna = _Natywna(kanal);
      intake = ShareIntake(channel: kanal);
    });
    tearDown(() => natywna.odepnij());

    test('przy starcie odbiera udostępnienie, które uruchomiło aplikację',
        () async {
      natywna.skrzynka = _udostepnienie('a', text: 'hej');
      await intake.attach();
      expect((intake.pending.value! as IncomingShare).text, 'hej');
      // Skrzynka opróżniona: drugi raz tego samego nie dostanie.
      expect(natywna.skrzynka, isNull);
    });

    test('nowsze udostępnienie wypiera nieodebrane starsze razem z kopiami',
        () async {
      await intake.attach();
      expect(intake.pending.value, isNull);

      natywna.skrzynka = _udostepnienie('a', count: 1);
      await natywna.zapowiedz();
      expect((intake.pending.value! as IncomingShare).id, 'a');

      natywna.skrzynka = _udostepnienie('b', text: 'nowsze');
      await natywna.zapowiedz();
      expect((intake.pending.value! as IncomingShare).id, 'b');
      expect(natywna.argumenty('discard'), ['a']);
    });

    test('kopie plików z nazwą i rozmiarem', () async {
      natywna.kopie['a'] = [
        {'path': '/cache/udostepnione/1/foto.jpg', 'name': 'foto.jpg', 'size': 1200},
        {'path': '/cache/udostepnione/2/umowa.pdf', 'name': 'umowa.pdf', 'size': 34},
      ];
      final pliki = await intake.files('a');
      expect(pliki.map((p) => (p.path, p.name, p.size)), [
        ('/cache/udostepnione/1/foto.jpg', 'foto.jpg', 1200),
        ('/cache/udostepnione/2/umowa.pdf', 'umowa.pdf', 34),
      ]);
      expect(await intake.files('nieznane'), isEmpty);
    });

    test('rozmowy dla okna „Udostępnij" jadą po kolei z awatarem', () async {
      final ikona = Uint8List.fromList([1, 2, 3]);
      expect(
          await intake.setTargets([
            ShareTarget(peerGuid: 'g1', label: 'Alicja', icon: ikona),
            const ShareTarget(peerGuid: 'g2', label: 'Bartek'),
          ]),
          isTrue);
      final cele = (natywna.wywolania.single.arguments as Map)['targets'] as List;
      expect(cele, [
        {'id': 'g1', 'label': 'Alicja', 'icon': ikona},
        {'id': 'g2', 'label': 'Bartek', 'icon': null},
      ]);
    });

    test('treść w rozmowie: nowsza wypiera starszą, zabrana znika', () {
      intake.stage(7, const IncomingShare(id: 'a', fileCount: 1));
      intake.stage(7, const IncomingShare(id: 'b', text: 'b'));
      intake.stage(8, const IncomingShare(id: 'c', text: 'c'));
      expect(natywna.argumenty('discard'), ['a']);
      expect(intake.takeStaged(7)!.id, 'b');
      expect(intake.takeStaged(7), isNull);
      expect(intake.staged.value.keys, [8]);
    });
  });

  test('bez kanału (Windows) nic nie rzuca i niczego nie ma', () async {
    final intake = ShareIntake(channel: const MethodChannel('test/brak'));
    await intake.attach();
    expect(intake.pending.value, isNull);
    expect(await intake.files('a'), isEmpty);
    expect(await intake.setTargets(const []), isFalse);
    await intake.discard('a');
    await intake.keep('a');
    await intake.reportUsed('g');
  });

  group('rozmowy dla okna „Udostępnij"', () {
    test('cztery ostatnie, pod nazwą widoczną w Chatcie', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db = ChattDb(NativeDatabase.memory());
      addTearDown(db.close);
      final rozmowy = <ConversationSummary>[];
      for (var i = 0; i < 6; i++) {
        final peer = await db.upsertPeer(
            guid: 'g$i', name: 'Urządzenie $i', welcomeMessage: '', host: '', port: 0);
        rozmowy.add(ConversationSummary(
          conversationId: i,
          peer: i == 1 ? peer.copyWith(alias: const Value('Laptop Ani')) : peer,
          lastBody: null,
          lastAt: null,
          unreadCount: 0,
        ));
      }
      expect(shareTargetsFrom(rozmowy), [
        (guid: 'g0', label: 'Urządzenie 0'),
        (guid: 'g1', label: 'Laptop Ani'),
        (guid: 'g2', label: 'Urządzenie 2'),
        (guid: 'g3', label: 'Urządzenie 3'),
      ]);
      expect(shareTargetsFrom(const []), isEmpty);
    });

    testWidgets('awatar to kwadrat PNG 288 px w kolorach stylu',
        (tester) async {
      final png = (await tester.runAsync(() => shortcutIcon(
          'Laptop Ani',
          chattTokens(AppStyle.cieplo, Brightness.light),
          fontFamilyOf(AppStyle.cieplo))))!;
      // Podpis PNG i wymiary z nagłówka IHDR.
      expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final naglowek = ByteData.sublistView(png, 16, 24);
      expect((naglowek.getUint32(0), naglowek.getUint32(4)), (288, 288));
      final obraz = (await tester.runAsync(() async {
        final kodek = await ui.instantiateImageCodec(png);
        return (await kodek.getNextFrame()).image;
      }))!;
      final piksele = (await tester.runAsync(obraz.toByteData))!;
      // Róg to tło awatara z palety stylu, pełne krycie.
      final kolor = chattTokens(AppStyle.cieplo, Brightness.light)
          .avatarFor('Laptop Ani')
          .background;
      expect(piksele.getUint8(0), (kolor.r * 255).round());
      expect(piksele.getUint8(1), (kolor.g * 255).round());
      expect(piksele.getUint8(2), (kolor.b * 255).round());
      expect(piksele.getUint8(3), 255);
      obraz.dispose();
    });
  });
}
