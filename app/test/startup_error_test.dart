import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/core/secret_store.dart';
import 'package:chatt/core/startup_error.dart';

/// Gdy schowek systemowy nie odwinie klucza, historia jest nie do odczytania
/// i jedynym wyjściem jest zacząć od nowa. Kasowanie ma wtedy sięgnąć bazy
/// i klucza, a zatrzymać się na odebranych plikach: to jedyna rzecz, którą
/// da się jeszcze uratować.
void main() {
  test('reset zabiera bazę i klucz, zostawia odebrane pliki', () async {
    final dir = Directory.systemTemp.createTempSync('chatt-reset');
    addTearDown(() => dir.deleteSync(recursive: true));

    for (final nazwa in const [
      'chatt.key',
      'chatt.db',
      'chatt.db-wal',
      'chatt.db-shm',
      'chatt.sqlite',
    ]) {
      File(p.join(dir.path, nazwa)).writeAsStringSync('x');
    }
    final odebrane = Directory(p.join(dir.path, 'received'))
      ..createSync(recursive: true);
    final plik = File(p.join(odebrane.path, 'zdjecie.png'))
      ..writeAsStringSync('bajty');
    final raport = File(p.join(dir.path, startupErrorFileName))
      ..writeAsStringSync('slad');

    await resetUnreadableDatabase(directory: dir.path);

    for (final nazwa in const [
      'chatt.key',
      'chatt.db',
      'chatt.db-wal',
      'chatt.db-shm',
      'chatt.sqlite',
    ]) {
      expect(File(p.join(dir.path, nazwa)).existsSync(), isFalse,
          reason: '$nazwa miało zniknąć');
    }
    expect(plik.existsSync(), isTrue, reason: 'odebrane pliki zostają');
    expect(raport.existsSync(), isTrue, reason: 'raport awarii zostaje');
  });

  test('reset na pustym katalogu nie wywala się', () async {
    final dir = Directory.systemTemp.createTempSync('chatt-reset-pusty');
    addTearDown(() => dir.deleteSync(recursive: true));
    await resetUnreadableDatabase(directory: dir.path);
    expect(dir.existsSync(), isTrue);
  });

  // Przycisk wołał `showDialog` z kontekstem stanu, czyli sponad MaterialApp,
  // gdzie nie ma jeszcze nawigatora. Kliknięcie kończyło się wtedy wyjątkiem
  // w logu i niczym na ekranie.
  testWidgets('„Start over" otwiera pytanie o potwierdzenie', (tester) async {
    await tester.pumpWidget(StartupErrorApp(
      error: const DatabaseKeyUnavailable('/dane/chatt.key'),
      logPath: '/dane/chatt-startup-error.txt',
    ));
    await tester.pump();

    expect(find.text('Start over'), findsOneWidget);
    await tester.tap(find.text('Start over'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Start over?'), findsOneWidget);
    expect(find.text('Delete and start over'), findsOneWidget);

    // Anulowanie zamyka okno i niczego nie kasuje.
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Start over?'), findsNothing);
  });

  testWidgets('przy innym błędzie nie ma czego resetować', (tester) async {
    await tester.pumpWidget(
      const StartupErrorApp(error: 'coś zupełnie innego'),
    );
    await tester.pump();

    expect(find.text('Start over'), findsNothing);
    expect(find.textContaining('Report this at'), findsOneWidget);
  });
}
