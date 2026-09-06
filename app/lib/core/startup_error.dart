import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'env.dart';
import 'secret_store.dart';

/// Co robić, gdy aplikacja wywali się przed pierwszą klatką.
///
/// Okno na Windowsie pokazuje się dopiero po pierwszej klatce (patrz
/// `windows/runner/flutter_window.cpp`), a `main` startuje cały stos przed
/// `runApp`. Wyjątek po drodze kończył więc tak: proces żyje, okna nie ma,
/// w dzienniku zdarzeń nic, bo z punktu widzenia systemu nic się nie stało.
/// Diagnoza takiej ciszy zajmuje godziny, więc awaria startu ma odtąd własny
/// ekran i własny plik.
///
/// Napisy są po angielsku i nie idą przez tłumaczenia: język wybrany przez
/// użytkownika siedzi w bazie, a to właśnie ona mogła się nie otworzyć.
const String startupErrorFileName = 'chatt-startup-error.txt';

/// Zapisuje treść awarii obok danych aplikacji i zwraca ścieżkę pliku.
///
/// Gdy katalog danych jest tym, co się zepsuło, plik ląduje w katalogu
/// tymczasowym systemu. `null` znaczy, że nie udało się zapisać nigdzie,
/// i wtedy zostaje sam ekran.
Future<String?> saveStartupError(Object error, StackTrace stack) async {
  final tresc = StringBuffer()
    ..writeln('Chatt did not start.')
    ..writeln(DateTime.now().toIso8601String())
    ..writeln()
    ..writeln(error)
    ..writeln()
    ..writeln(stack);

  for (final katalog in await _kandydaci()) {
    try {
      final plik = File(p.join(katalog, startupErrorFileName));
      plik.parent.createSync(recursive: true);
      plik.writeAsStringSync(tresc.toString(), flush: true);
      return plik.path;
    } catch (_) {
      // Następny katalog z listy.
    }
  }
  return null;
}

/// Kasuje bazę i klucz, zostawiając odebrane pliki.
///
/// Wołane tylko wtedy, gdy klucza nie da się odwinąć, czyli gdy historia jest
/// nie do odczytania i tak. Bez tego aplikacja odmawiałaby startu bez końca,
/// a jedynym wyjściem byłoby czyszczenie danych z ustawień systemu, które
/// zabiera przy okazji odebrane pliki.
Future<void> resetUnreadableDatabase({String? directory}) async {
  final katalog = directory ??
      ChattEnv.dataDir ??
      (await getApplicationDocumentsDirectory()).path;
  for (final nazwa in const ['chatt.key', 'chatt.db', 'chatt.sqlite']) {
    for (final ogon in const ['', '-wal', '-shm', '-journal']) {
      final plik = File(p.join(katalog, '$nazwa$ogon'));
      if (plik.existsSync()) plik.deleteSync();
    }
  }
}

Future<List<String>> _kandydaci() async {
  final lista = <String>[];
  final zEnv = ChattEnv.dataDir;
  if (zEnv != null) lista.add(zEnv);
  try {
    lista.add((await getApplicationDocumentsDirectory()).path);
  } catch (_) {
    // Brak kanału platformy albo katalogu. Zostaje katalog tymczasowy.
  }
  lista.add(Directory.systemTemp.path);
  return lista;
}

/// Ekran zamiast aplikacji, gdy start się nie powiódł.
///
/// Ma być zrozumiały bez czytania kodu i ma dać się skopiować w całości,
/// bo pierwsze, co robi użytkownik, to wysyła to komuś dalej.
class StartupErrorApp extends StatefulWidget {
  final Object error;
  final String? logPath;

  const StartupErrorApp({super.key, required this.error, this.logPath});

  @override
  State<StartupErrorApp> createState() => _StartupErrorAppState();
}

class _StartupErrorAppState extends State<StartupErrorApp> {
  bool _zresetowane = false;

  Object get error => widget.error;
  String? get logPath => widget.logPath;

  /// Odzyskanie ma sens tylko dla klucza, którego nie da się odwinąć: przy
  /// każdej innej awarii kasowanie bazy zabrałoby czytelną historię.
  bool get _doOdzyskania => error is DatabaseKeyUnavailable;

  Future<void> _reset() async {
    final zgoda = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Start over?'),
        content: const Text(
          'The conversation history cannot be read without the key, so this '
          'deletes the database and starts the app from scratch with a new '
          'identity. Received files stay on disk. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete and start over'),
          ),
        ],
      ),
    );
    if (zgoda != true) return;
    await resetUnreadableDatabase();
    if (mounted) setState(() => _zresetowane = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF512BD4)),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Chatt did not start')),
        // Do góry, a nie na środek: na telefonie wyśrodkowanie zostawiało
        // pół ekranu pustki nad pierwszym zdaniem.
        body: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Something failed before the window could open, so the app '
                    'stopped here instead of disappearing without a trace.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        '$error',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (logPath != null) ...[
                    const Text('The whole report, with the stack trace:'),
                    const SizedBox(height: 6),
                    SelectableText(
                      logPath!,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_zresetowane)
                    Text(
                      'Done. Close Chatt and open it again to start from '
                      'scratch. Received files are still on disk.',
                      style: Theme.of(context).textTheme.titleMedium,
                    )
                  else if (_doOdzyskania) ...[
                    Text(
                      'Nothing can recover the history from here: the key it '
                      'was encrypted with is gone. Starting over deletes the '
                      'database and leaves received files on disk.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Start over'),
                    ),
                  ] else
                    Text(
                      'Conversation history and received files are untouched. '
                      'Report this at github.com/Mysttic/Chatt together with '
                      'the text above.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
