import 'package:chatt/core/file_actions.dart';
import 'package:chatt/core/search.dart';
import 'package:chatt/data/db.dart';
import 'package:flutter_test/flutter_test.dart';

Message _message(String body, {String? fileName}) => Message(
      id: 1,
      messageGuid: 'g',
      conversationId: 1,
      direction: MessageDirection.incoming,
      status: MessageStatus.delivered,
      kind: fileName == null ? MessageKind.text : MessageKind.file,
      body: body,
      fileName: fileName,
      createdAt: DateTime(2026, 9, 3),
    );

ConversationSummary _summary({required String name, String? lastBody}) =>
    ConversationSummary(
      conversationId: 1,
      peer: Peer(
        id: 1,
        guid: 'g',
        name: name,
        welcomeMessage: '',
        host: '192.168.1.10',
        port: 47780,
        verified: false,
        firstSeen: DateTime(2026, 9, 3),
        lastSeen: DateTime(2026, 9, 3),
      ),
      lastBody: lastBody,
      lastAt: DateTime(2026, 9, 3),
      unreadCount: 0,
    );

void main() {
  group('szukanie w rozmowie', () {
    test('pusty napis pasuje do wszystkiego', () {
      expect(messageMatches(_message('cokolwiek'), ''), isTrue);
      expect(messageMatches(_message('cokolwiek'), '   '), isTrue);
    });

    test('wielkość liter nie ma znaczenia', () {
      expect(messageMatches(_message('Do zobaczenia Jutro'), 'JUTRO'), isTrue);
      expect(messageMatches(_message('Do zobaczenia jutro'), 'jutro'), isTrue);
    });

    test('plik szuka się po nazwie, bo to ją widać w dymku', () {
      final plik = _message('📎 raport.pdf', fileName: 'raport.pdf');
      expect(messageMatches(plik, 'raport'), isTrue);
      expect(messageMatches(plik, 'faktura'), isFalse);
    });

    test('to, czego nie ma, nie pasuje', () {
      expect(messageMatches(_message('dzień dobry'), 'wieczór'), isFalse);
    });
  });

  group('szukanie na liście rozmów', () {
    test('po nazwie rozmówcy', () {
      final wiersz = _summary(name: 'Laptop Anny', lastBody: 'cześć');
      expect(conversationMatches(wiersz, 'anny'), isTrue);
      expect(conversationMatches(wiersz, 'bartek'), isFalse);
    });

    test('po ostatniej wiadomości', () {
      final wiersz = _summary(name: 'Bartek', lastBody: 'wysyłam raport');
      expect(conversationMatches(wiersz, 'raport'), isTrue);
    });

    test('rozmowa bez wiadomości nie wywala szukania', () {
      expect(conversationMatches(_summary(name: 'Bartek'), 'raport'), isFalse);
      expect(conversationMatches(_summary(name: 'Bartek'), 'bar'), isTrue);
    });
  });

  group('miniatury', () {
    test('rozpoznajemy obrazki po rozszerzeniu, bez względu na wielkość liter',
        () {
      for (final nazwa in ['zdjecie.jpg', 'A.PNG', 'x.jpeg', 'y.WebP', 'z.gif']) {
        expect(isImageFile(nazwa), isTrue, reason: nazwa);
      }
    });

    test('reszta plików miniatury nie dostaje', () {
      for (final nazwa in ['raport.pdf', 'archiwum.zip', 'film.mp4', 'bez']) {
        expect(isImageFile(nazwa), isFalse, reason: nazwa);
      }
      expect(isImageFile(null), isFalse);
    });

    test('nazwa udająca obrazek w środku nie wystarcza', () {
      // Liczy się rozszerzenie, nie to, co ktoś wpisał w środku nazwy.
      expect(isImageFile('zdjecie.png.exe'), isFalse);
    });
  });
}
