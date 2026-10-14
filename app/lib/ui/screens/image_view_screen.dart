import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../l10n_context.dart';

/// Podgląd zdjęcia na pełnym ekranie: przybliżanie i obracanie bez wychodzenia
/// z aplikacji.
///
/// Własny ekran zamiast systemowego skojarzenia, bo oddanie pliku innej
/// aplikacji wymaga na Androidzie wypuszczenia go przez FileProvider, a
/// zdjęcie leży już na dysku i Flutter umie je narysować sam. Przy okazji
/// najczęstszy przypadek („kliknąłem w zdjęcie") przestaje zależeć od tego,
/// czy w systemie jest czym otworzyć obrazek i czy plik da się wypuścić na
/// zewnątrz.
///
/// Dekoder dostaje wyłącznie plik **już przyjęty** przez użytkownika i leżący
/// na dysku — ten sam warunek, co przy miniaturze w rozmowie. Uszkodzony albo
/// spreparowany obrazek kończy się komunikatem, a nie wywrotką ekranu.
class ImageViewScreen extends StatefulWidget {
  final String path;

  /// Nazwa do paska tytułu: ta od nadawcy, nie ta z dysku (na dysku leży
  /// nazwa z przedrostkiem z identyfikatora wiadomości).
  final String? name;

  /// Akcje do paska. Buduje je ekran rozmowy, bo to on wie, z której
  /// wiadomości pochodzi plik i co wolno z nim zrobić.
  final List<Widget> actions;

  const ImageViewScreen({
    super.key,
    required this.path,
    this.name,
    this.actions = const [],
  });

  @override
  State<ImageViewScreen> createState() => _ImageViewScreenState();
}

class _ImageViewScreenState extends State<ImageViewScreen> {
  /// Największe przybliżenie. Więcej nie ma sensu: powyżej tego widać już
  /// tylko interpolację, bo obrazek jest dekodowany z ograniczonym zapasem.
  static const _maxSkala = 8.0;

  /// Przybliżenie po dwukliku. Jeden gest ma pokazać szczegół, a nie wrzucić
  /// użytkownika w piksele bez możliwości połapania się, gdzie jest.
  static const _skalaDwuklik = 2.5;

  /// Górna granica szerokości dekodowanego obrazu. Zdjęcie z dzisiejszego
  /// telefonu ma kilkadziesiąt megapikseli, a bitmapa to cztery bajty na
  /// piksel: bez tej granicy podgląd potrafiłby zająć setki megabajtów i
  /// zabić aplikację na telefonie.
  static const _maxDekod = 4096;

  final _kontroler = TransformationController();

  /// Obrót w ćwiartkach. Dotyczy **wyłącznie** podglądu: plik na dysku
  /// zostaje dokładnie taki, jaki przyszedł od nadawcy.
  int _cwiartki = 0;

  /// Miejsce ostatniego dwukliku. Osobne pole, bo `onDoubleTap` nie dostaje
  /// współrzędnych, a przybliżyć trzeba w punkt, w który użytkownik stuknął.
  Offset? _stuknieto;

  @override
  void dispose() {
    _kontroler.dispose();
    super.dispose();
  }

  void _obroc() => setState(() => _cwiartki = (_cwiartki + 1) % 4);

  /// Dwuklik przybliża w stuknięty punkt, kolejny wraca do całości.
  void _dwuklik() {
    if (!_kontroler.value.isIdentity()) {
      _kontroler.value = Matrix4.identity();
      return;
    }
    final punkt = _stuknieto;
    if (punkt == null) return;
    // Powiększenie wokół punktu: najpierw przesunięcie, które zostawia ten
    // punkt w miejscu, potem samo skalowanie. Wpisy macierzy zamiast
    // `translate`/`scale`, bo te w kolejnych wydaniach Fluttera zmieniały
    // sygnatury, a tu chodzi o cztery liczby.
    const s = _skalaDwuklik;
    // Bez `setState`: `InteractiveViewer` słucha kontrolera i przerysowuje
    // się sam.
    _kontroler.value = Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s)
      ..setEntry(0, 3, -punkt.dx * (s - 1))
      ..setEntry(1, 3, -punkt.dy * (s - 1));
  }

  @override
  Widget build(BuildContext context) {
    final teksty = context.l10n;
    return CallbackShortcuts(
      bindings: {
        // Na pulpicie zamknięcie podglądu to Esc, nie szukanie strzałki
        // w rogu ekranu.
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.maybePop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.black.withValues(alpha: 0.4),
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              widget.name ?? teksty.fileFallbackName,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                tooltip: teksty.rotate,
                icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
                onPressed: _obroc,
              ),
              ...widget.actions,
            ],
          ),
          body: _body(context, teksty.fileGone, teksty.imageLoadFailed),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, String brakPliku, String zlyObraz) {
    final plik = File(widget.path);
    // Plik mógł zniknąć między otwarciem rozmowy a stuknięciem w miniaturę
    // (użytkownik go skasował, Android sprzątnął cache).
    if (!plik.existsSync()) return _komunikat(brakPliku);

    final media = MediaQuery.of(context);
    // Dekodujemy z dwukrotnym zapasem na przybliżenie, ale nie w pełnej
    // rozdzielczości. `cacheWidth` nigdy nie powiększa, więc obrazek mniejszy
    // niż ekran zostaje sobą.
    final szerokosc = math.min(
      _maxDekod,
      (media.size.width * media.devicePixelRatio * 2).round(),
    );

    return GestureDetector(
      // Na zewnątrz `InteractiveViewer`, żeby współrzędne stuknięcia były
      // liczone względem ekranu, a nie względem już przesuniętego obrazu.
      onDoubleTapDown: (szczegoly) => _stuknieto = szczegoly.localPosition,
      onDoubleTap: _dwuklik,
      child: InteractiveViewer(
        transformationController: _kontroler,
        minScale: 1,
        maxScale: _maxSkala,
        child: SizedBox.expand(
          child: RotatedBox(
            quarterTurns: _cwiartki,
            child: Image.file(
              plik,
              fit: BoxFit.contain,
              cacheWidth: szerokosc,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => _komunikat(zlyObraz),
            ),
          ),
        ),
      ),
    );
  }

  Widget _komunikat(String tekst) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            tekst,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ),
      );
}
