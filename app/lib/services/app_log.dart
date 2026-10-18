import 'dart:async';

import 'package:drift/drift.dart' show Value;

import '../data/db.dart';

// Dziennik aplikacji do diagnostyki (issue #50). Leży w zaszyfrowanej
// bazie, obok historii rozmów, i wychodzi z urządzenia tylko eksportem.
//
// Czego tu nie ma i być nie może: treści wiadomości, tekstu z klawiatury,
// kodów parowania, kluczy (tożsamości, sesji, plików, bazy) i tokenów zgód.
// Nazwy urządzeń, adresy i rozmiary plików są, bo bez nich dziennik nie
// powie, z kim i którędy coś się nie udało.

/// Jak długo trzymamy wpisy dziennika.
const Duration appLogRetention = Duration(days: 30);

/// Ile wpisów najwyżej trzymamy, niezależnie od wieku.
const int appLogMaxEntries = 20000;

/// Obszary dziennika. Napisy, bo trafiają do eksportu.
abstract final class LogArea {
  static const app = 'app';
  static const net = 'net';
  static const pair = 'pair';
  static const file = 'file';
  static const history = 'history';
  static const bt = 'bt';
  static const keyboard = 'keyboard';
  static const update = 'update';
  static const error = 'error';
}

/// Dziennik aplikacji jednej instancji [AppServices]. Testy stawiają po kilka
/// instancji w jednym procesie, więc dziennik nie jest globalny.
///
/// Wpisy zbierają się w pamięci i trafiają do bazy paczką po [flushDelay]:
/// zamknięcie aplikacji nie daje żadnego sygnału, więc dłużej nic nie czeka.
class AppLog {
  AppLog(
    this._db, {
    this.flushDelay = const Duration(seconds: 1),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final ChattDb _db;
  final DateTime Function() _now;
  final Duration flushDelay;

  final List<AppLogEntriesCompanion> _pending = [];
  Timer? _timer;
  Future<void> _writes = Future.value();
  bool _closed = false;

  void info(String area, String message) =>
      add(LogLevel.info, area, message);

  void warning(String area, String message,
          {Object? error, StackTrace? stack}) =>
      add(LogLevel.warning, area, message,
          details: describeError(error, stack));

  void error(String area, String message, {Object? error, StackTrace? stack}) =>
      add(LogLevel.error, area, message, details: describeError(error, stack));

  /// Dopisuje wpis. Nic nie czeka i nic nie rzuca.
  void add(LogLevel level, String area, String message, {String? details}) {
    if (_closed) return;
    _pending.add(AppLogEntriesCompanion.insert(
      atMs: _now().millisecondsSinceEpoch,
      level: level,
      area: area,
      message: message,
      details: Value(details),
    ));
    _timer ??= Timer(flushDelay, () => unawaited(flush()));
  }

  /// Zapisuje to, co czeka, i czeka na koniec zapisu.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isNotEmpty) {
      final paczka = List.of(_pending);
      _pending.clear();
      _writes = _writes
          .then((_) => _db.insertLogEntries(paczka))
          .catchError((Object _) {
        // Baza zamknięta albo pełny dysk: dziennik nie ma gdzie zapisać
        // własnej porażki, a aplikacja ma działać dalej.
      });
    }
    return _writes;
  }

  /// Usuwa wpisy starsze niż [appLogRetention] i ponad [appLogMaxEntries].
  Future<int> trim() async {
    if (_closed) return 0;
    try {
      return await _db.trimLog(
        olderThan: _now().subtract(appLogRetention),
        keepAtMost: appLogMaxEntries,
      );
    } catch (_) {
      return 0;
    }
  }

  /// Zapisuje resztę i przestaje przyjmować wpisy.
  Future<void> close() async {
    await flush();
    _closed = true;
  }
}

/// Wyjątek i ślad stosu jako tekst do pola szczegółów. `null`, gdy nie ma
/// ani jednego, ani drugiego.
String? describeError(Object? error, StackTrace? stack) {
  if (error == null && stack == null) return null;
  return [
    if (error != null) '$error',
    if (stack != null) '$stack',
  ].join('\n');
}
