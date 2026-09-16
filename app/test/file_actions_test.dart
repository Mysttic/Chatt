import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/file_actions.dart';

/// Wybór plików na Androidzie idzie własnym kanałem `chatt/files`
/// (metoda `pick`), bo `file_selector` wczytywał tam cały plik do pamięci.
/// Tu sprawdzamy kontrakt po stronie Darta: lista ścieżek z kanału wraca
/// jak jest, a każda odmowa (anulowanie, błąd, brak kanału) to pusta lista,
/// żeby spinacz nigdy nie wywalił ekranu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const kanal = MethodChannel('chatt/files');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(kanal, null));

  group('FileActions.pickFiles', () {
    test('oddaje ścieżki kopii z kanału', () async {
      MethodCall? odebrane;
      messenger.setMockMethodCallHandler(kanal, (call) async {
        odebrane = call;
        return ['/cache/wybrane/a/raport.zip', '/cache/wybrane/b/zdjęcie.jpg'];
      });

      expect(await FileActions.pickFiles(),
          ['/cache/wybrane/a/raport.zip', '/cache/wybrane/b/zdjęcie.jpg']);
      expect(odebrane?.method, 'pick');
    });

    test('anulowanie okna to pusta lista', () async {
      messenger.setMockMethodCallHandler(kanal, (_) async => <String>[]);
      expect(await FileActions.pickFiles(), isEmpty);
    });

    test('błąd po stronie Androida to pusta lista, bez wyjątku', () async {
      messenger.setMockMethodCallHandler(kanal, (_) async {
        throw PlatformException(code: 'busy');
      });
      expect(await FileActions.pickFiles(), isEmpty);
    });

    test('brak kanału (pulpit, test widgetowy) to pusta lista', () async {
      expect(await FileActions.pickFiles(), isEmpty);
    });
  });
}
