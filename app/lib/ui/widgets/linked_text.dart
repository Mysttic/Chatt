import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/links.dart';

import '../styles.dart';

/// Treść wiadomości: odnośniki klikalne, szukany napis podświetlony.
///
/// Odnośnik jest tu **napisem ze zdarzeniem**, a nie niczym więcej: dotknięcie
/// woła [onTapLink], a to (patrz `link_confirm.dart`) najpierw pyta, czy na
/// pewno przejść. Nic się nie otwiera samo i nic z adresu nie jest wykonywane.
///
/// Podświetlenie szukanego napisu i odnośnik potrafią na siebie zachodzić,
/// dlatego tekst jest cięty na kawałki po wszystkich granicach naraz, a styl
/// każdego kawałka powstaje ze złożenia obu.
class LinkedText extends StatefulWidget {
  final String text;
  final TextStyle style;

  /// Szukany napis do podświetlenia. Pusty znaczy „nikt nie szuka".
  final String query;

  /// Tło i kolor podświetlenia. Bez niego szukanie nic nie zaznacza.
  final TextStyle? highlightStyle;

  /// Czy w ogóle szukać odnośników. Nazwa pliku ich nie potrzebuje.
  final bool linkify;

  final void Function(Uri uri) onTapLink;

  const LinkedText({
    super.key,
    required this.text,
    required this.style,
    required this.onTapLink,
    this.query = '',
    this.highlightStyle,
    this.linkify = true,
  });

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<LinkedText> {
  /// Po jednym rozpoznawaczu dotknięć na odnośnik. Trzymamy je, bo każdy
  /// trzeba potem zwolnić; zostawione zbierałyby się przy każdym przewinięciu
  /// listy dymków.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void didUpdateWidget(LinkedText stary) {
    super.didUpdateWidget(stary);
    if (stary.text != widget.text || stary.linkify != widget.linkify) {
      _clearRecognizers();
    }
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  void _clearRecognizers() {
    for (final rozpoznawacz in _recognizers) {
      rozpoznawacz.dispose();
    }
    _recognizers.clear();
  }

  /// Zakresy, w których siedzi szukany napis.
  List<(int, int)> _highlights() {
    final needle = widget.query.toLowerCase();
    if (needle.isEmpty || widget.highlightStyle == null) return const [];
    final lower = widget.text.toLowerCase();
    final wynik = <(int, int)>[];
    var start = 0;
    while (true) {
      final gdzie = lower.indexOf(needle, start);
      if (gdzie < 0) break;
      wynik.add((gdzie, gdzie + needle.length));
      start = gdzie + needle.length;
    }
    return wynik;
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();

    final linki = widget.linkify ? findLinks(widget.text) : const <LinkSpan>[];
    final podswietlenia = _highlights();
    if (linki.isEmpty && podswietlenia.isEmpty) {
      return Text(widget.text, style: widget.style);
    }

    final kolorOdnosnika = _linkColor(context);
    final stylOdnosnika = TextStyle(
      color: kolorOdnosnika,
      decoration: TextDecoration.underline,
      decorationColor: kolorOdnosnika,
    );

    // Wszystkie granice naraz: początki i końce odnośników oraz podświetleń.
    final granice = <int>{0, widget.text.length};
    for (final link in linki) {
      granice
        ..add(link.start)
        ..add(link.end);
    }
    for (final (od, do_) in podswietlenia) {
      granice
        ..add(od)
        ..add(do_);
    }
    final punkty = granice.toList()..sort();

    final rozpoznawacze = <LinkSpan, TapGestureRecognizer>{};
    final kawalki = <InlineSpan>[];
    for (var i = 0; i < punkty.length - 1; i++) {
      final od = punkty[i];
      final do_ = punkty[i + 1];
      if (do_ <= od) continue;

      LinkSpan? link;
      for (final kandydat in linki) {
        if (kandydat.start <= od && kandydat.end >= do_) {
          link = kandydat;
          break;
        }
      }
      final podswietlony =
          podswietlenia.any((zakres) => zakres.$1 <= od && zakres.$2 >= do_);

      var styl = widget.style;
      if (link != null) styl = styl.merge(stylOdnosnika);
      if (podswietlony) styl = styl.merge(widget.highlightStyle);

      TapGestureRecognizer? rozpoznawacz;
      if (link != null) {
        rozpoznawacz = rozpoznawacze.putIfAbsent(link, () {
          final adres = link!.uri;
          final nowy = TapGestureRecognizer()
            ..onTap = () => widget.onTapLink(adres);
          _recognizers.add(nowy);
          return nowy;
        });
      }

      kawalki.add(TextSpan(
        text: widget.text.substring(od, do_),
        style: styl,
        recognizer: rozpoznawacz,
        // Bez tego czytnik ekranu przeczytałby adres jak zwykły tekst.
        semanticsLabel: link?.text,
      ));
    }

    return Text.rich(TextSpan(children: kawalki));
  }

  /// Kolor odnośnika. Na własnym dymku tło ma kolor stylu, na którym zwykły
  /// kolor odnośnika bywa nieczytelny: bierzemy wtedy kolor napisu i tylko
  /// podkreślamy.
  Color _linkColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final naDymku = widget.style.color;
    if (naDymku == null) return scheme.primary;
    // Kontrast napisu z tłem jest już dobrany, więc trzymamy się go.
    return naDymku == ChattTokens.of(context).onBubbleMine
        ? naDymku
        : scheme.primary;
  }
}
