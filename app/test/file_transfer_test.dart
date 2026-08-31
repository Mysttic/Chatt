import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/data/db.dart';
import 'package:chatt/services/app_services.dart';

/// E2E transferu plików między dwiema pełnymi instancjami: streaming, postęp,
/// weryfikacja bajt w bajt, dedupe, odbiorca offline i retry.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory work;
  late AppServices alice;
  late AppServices bob;

  setUp(() async {
    work = Directory.systemTemp.createTempSync('chatt_files');
    alice = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Alicja',
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'alice_received'),
    );
    bob = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Bartek',
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'bob_received'),
    );
  });

  tearDown(() async {
    await alice.dispose();
    await bob.dispose();
    work.deleteSync(recursive: true);
  });

  File makeRandomFile(String name, int bytes) {
    final random = Random(42);
    final file = File(p.join(work.path, name));
    final sink = file.openSync(mode: FileMode.write);
    const chunkSize = 64 * 1024;
    var left = bytes;
    while (left > 0) {
      final chunk = List<int>.generate(min(chunkSize, left), (_) => random.nextInt(256));
      sink.writeFromSync(chunk);
      left -= chunk.length;
    }
    sink.closeSync();
    return file;
  }

  test('plik 3 MB dochodzi w całości, bajt w bajt', () async {
    final source = makeRandomFile('zdjecie.bin', 3 * 1024 * 1024 + 137);
    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final conversation = await alice.openConversationWith(bobAsPeer!);

    await alice.sendFile(conversation, source.path);

    final atAlice = (await alice.db.watchMessages(conversation).first).single;
    expect(atAlice.kind, MessageKind.file);
    expect(atAlice.status, MessageStatus.delivered);
    expect(atAlice.fileName, 'zdjecie.bin');

    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    final atBob = (await bob.db.watchMessages(convAtBob).first).single;
    expect(atBob.kind, MessageKind.file);
    expect(atBob.fileName, 'zdjecie.bin');
    expect(atBob.fileSize, source.lengthSync());

    final saved = File(atBob.filePath!);
    expect(saved.existsSync(), isTrue);
    expect(saved.lengthSync(), source.lengthSync());
    expect(saved.readAsBytesSync(), source.readAsBytesSync(),
        reason: 'zawartość musi być identyczna');
    expect(saved.path, startsWith(p.join(work.path, 'bob_received')));
    expect(File('${atBob.filePath!}.part').existsSync(), isFalse,
        reason: 'plik tymczasowy posprzątany');

    // Retry mimo sukcesu (zgubiony ACK): u Bartka nie przybywa ani wiadomość,
    // ani plik.
    await alice.retryMessage(atAlice.id);
    final bobMessages = await bob.db.watchMessages(convAtBob).first;
    expect(bobMessages, hasLength(1));
    final receivedFiles = Directory(p.join(work.path, 'bob_received'))
        .listSync()
        .whereType<File>()
        .where((f) => !f.path.endsWith('.part'));
    expect(receivedFiles, hasLength(1));
  });

  test('odbiorca offline: failed, retry po powrocie dostarcza', () async {
    final source = makeRandomFile('raport.pdf', 256 * 1024);
    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final conversation = await alice.openConversationWith(bobAsPeer!);

    await bob.server.stop();
    await alice.sendFile(conversation, source.path);
    var message = (await alice.db.watchMessages(conversation).first).single;
    expect(message.status, MessageStatus.failed);

    await bob.server.start(preferredPort: bobAsPeer.port);
    await alice.retryMessage(message.id);
    message = (await alice.db.watchMessages(conversation).first).single;
    expect(message.status, MessageStatus.delivered);

    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    final atBob = (await bob.db.watchMessages(convAtBob).first).single;
    expect(File(atBob.filePath!).lengthSync(), source.lengthSync());
  });

  test('uszkodzone metadane -> 400, serwer żyje dalej', () async {
    final ok = await alice.client.sendFile(
      host: '127.0.0.1',
      port: bob.server.port!,
      headers: {'x-chatt-message-guid': 'x'}, // brak reszty nagłówków
      file: makeRandomFile('smieci.bin', 1024),
    );
    expect(ok, isFalse);
    expect(await alice.client.fetchInfo('127.0.0.1', bob.server.port!), isNotNull);
  });
}
