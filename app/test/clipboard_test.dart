import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/core/clipboard.dart';

/// Wklejanie plików idzie kanałem `chatt/clipboard` (Windows: runner, Android:
/// `ChattClipboard.kt`). Tu sprawdzamy kontrakt po stronie Darta: cokolwiek
/// powie platforma, ekran rozmowy dostaje listę ścieżek albo pustą listę,
/// nigdy wyjątku, bo to wisi na Ctrl+V i na pozycji w menu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const kanal = MethodChannel('chatt/clipboard');
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(kanal, null);
    messenger.setMockMethodCallHandler(pathProvider, null);
  });

  group('clipboardHasFiles', () {
    test('oddaje odpowiedź platformy', () async {
      MethodCall? odebrane;
      messenger.setMockMethodCallHandler(kanal, (call) async {
        odebrane = call;
        return true;
      });

      expect(await clipboardHasFiles(), isTrue);
      expect(odebrane?.method, 'hasFiles');
    });

    test('pusty schowek to false', () async {
      messenger.setMockMethodCallHandler(kanal, (_) async => false);
      expect(await clipboardHasFiles(), isFalse);
    });

    test('błąd platformy to false, bez wyjątku', () async {
      messenger.setMockMethodCallHandler(kanal, (_) async {
        throw PlatformException(code: 'schowek');
      });
      expect(await clipboardHasFiles(), isFalse);
    });

    test('brak kanału (Linux, test widgetowy) to false', () async {
      expect(await clipboardHasFiles(), isFalse);
    });
  });

  group('pasteClipboardFiles', () {
    test('oddaje ścieżki z kanału i podaje nazwę dla obrazka', () async {
      MethodCall? odebrane;
      messenger.setMockMethodCallHandler(kanal, (call) async {
        odebrane = call;
        return [r'C:\Users\ktos\raport.pdf', r'C:\Temp\chatt\wklejone\1\obraz.png'];
      });

      expect(await pasteClipboardFiles(imageName: 'obraz.png'),
          [r'C:\Users\ktos\raport.pdf', r'C:\Temp\chatt\wklejone\1\obraz.png']);
      expect(odebrane?.method, 'pasteFiles');
      expect(odebrane?.arguments, {'name': 'obraz.png'});
    });

    test('nazwa obrazka schodzi do samej nazwy pliku', () async {
      MethodCall? odebrane;
      messenger.setMockMethodCallHandler(kanal, (call) async {
        odebrane = call;
        return <String>[];
      });

      await pasteClipboardFiles(imageName: '../../etc/passwd');
      expect(odebrane?.arguments, {'name': 'passwd'});
    });

    test('sam tekst w schowku to pusta lista', () async {
      messenger.setMockMethodCallHandler(kanal, (_) async => <String>[]);
      expect(await pasteClipboardFiles(imageName: 'obraz.png'), isEmpty);
    });

    test('błąd platformy to pusta lista, bez wyjątku', () async {
      messenger.setMockMethodCallHandler(kanal, (_) async {
        throw PlatformException(code: 'schowek');
      });
      expect(await pasteClipboardFiles(imageName: 'obraz.png'), isEmpty);
    });

    test('brak kanału to pusta lista', () async {
      expect(await pasteClipboardFiles(imageName: 'obraz.png'), isEmpty);
    });
  });

  group('saveInsertedContent', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('chatt-schowek-test');
      messenger.setMockMethodCallHandler(pathProvider, (call) async =>
          call.method == 'getTemporaryDirectory' ? temp.path : null);
    });

    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('zapisuje bajty i bierze rozszerzenie z typu MIME', () async {
      final bytes = Uint8List.fromList([0x47, 0x49, 0x46, 0x38]);

      final path = await saveInsertedContent(bytes,
          mimeType: 'image/gif', name: 'obraz.png');

      expect(path, isNotNull);
      expect(p.basename(path!), 'obraz.gif');
      expect(File(path).readAsBytesSync(), bytes);
    });

    test('nieznany typ zostawia nazwę taką, jaka przyszła', () async {
      final path = await saveInsertedContent(Uint8List.fromList([1, 2, 3]),
          mimeType: 'application/x-czegos-takiego', name: 'obraz.png');

      expect(p.basename(path!), 'obraz.png');
    });

    test('dwa wklejenia nie nadpisują się nawzajem', () async {
      final bytes = Uint8List.fromList([1]);
      final pierwsze = await saveInsertedContent(bytes,
          mimeType: 'image/png', name: 'obraz.png');
      final drugie = await saveInsertedContent(bytes,
          mimeType: 'image/png', name: 'obraz.png');

      expect(pierwsze, isNot(drugie));
      expect(File(pierwsze!).existsSync(), isTrue);
      expect(File(drugie!).existsSync(), isTrue);
    });

    test('brak katalogu tymczasowego to null, bez wyjątku', () async {
      messenger.setMockMethodCallHandler(pathProvider, (_) async {
        throw PlatformException(code: 'brak');
      });

      expect(
          await saveInsertedContent(Uint8List.fromList([1]),
              mimeType: 'image/png', name: 'obraz.png'),
          isNull);
    });
  });
}
