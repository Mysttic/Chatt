import 'dart:async';
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/share_intake.dart';
import '../data/db.dart';
import '../services/app_log.dart';
import '../services/app_services.dart';
import 'styles.dart';
import 'widgets/common.dart' show initialsOf;

/// Ile ostatnich rozmów system dostaje do okna „Udostępnij" i pod
/// przytrzymaną ikonę Chatt.
const shareTargetCount = 4;

/// Bok awatara skrótu w pikselach. Ikona skrótu to pełny kwadrat 108 dp,
/// z którego system pokazuje środkowe 72 dp w kształcie ikon launchera;
/// 288 px to 108 dp przy największej gęstości, jaką system zachowuje.
const _bok = 288.0;

/// Rozmowy w systemowym oknie „Udostępnij" (issue #60).
///
/// System dostaje [shareTargetCount] ostatnich rozmów z nazwą i awatarem
/// w kolorach wybranego stylu, a lista idzie do niego od nowa, gdy zmieni się
/// kolejność rozmów, nazwa któregoś rozmówcy albo styl. Pierwsza lista po
/// starcie idzie zawsze: system mógł zgubić poprzednią.
///
/// Tylko Android: gdzie indziej kanału nie ma i [ShareIntake.setTargets]
/// odpowiada „nie".
class ShareShortcuts {
  ShareShortcuts(this._services, this._intake);

  final AppServices _services;
  final ShareIntake _intake;

  StreamSubscription<List<ConversationSummary>>? _rozmowy;
  StreamSubscription<Setting>? _ustawienia;
  List<ConversationSummary>? _ostatnie;
  AppStyle? _styl;
  Timer? _zwloka;

  /// Odcisk listy, którą system już ma: styl, guidy i nazwy po kolei.
  String? _opublikowane;

  void attach() {
    _rozmowy = _services.db.watchConversationSummaries().listen(
      (rozmowy) {
        _ostatnie = rozmowy;
        _zaplanuj();
      },
      onError: (Object blad, StackTrace slad) => _services.log.error(
          LogArea.app, 'Share targets: conversation watcher failed',
          error: blad, stack: slad),
    );
    _ustawienia = _services.db.watchSettings().listen(
      (ustawienia) {
        if (ustawienia.style == _styl) return;
        _styl = ustawienia.style;
        _zaplanuj();
      },
      onError: (Object blad, StackTrace slad) => _services.log.error(
          LogArea.app, 'Share targets: settings watcher failed',
          error: blad, stack: slad),
    );
  }

  /// Seria zmian (przywracana historia, kilka wiadomości naraz) daje jedną
  /// listę, gdy rozmowy przestaną się przestawiać. System ogranicza liczbę
  /// takich zmian, gdy aplikacja jest w tle.
  void _zaplanuj() {
    _zwloka?.cancel();
    _zwloka = Timer(const Duration(seconds: 2), () => unawaited(_opublikuj()));
  }

  Future<void> _opublikuj() async {
    final styl = _styl;
    final rozmowy = _ostatnie;
    if (styl == null || rozmowy == null) return;
    final cele = shareTargetsFrom(rozmowy);
    final odcisk = [
      styl.name,
      for (final cel in cele) '${cel.guid}=${cel.label}',
    ].join('\n');
    if (odcisk == _opublikowane) return;
    _opublikowane = odcisk;

    final tokeny = chattTokens(styl, Brightness.light);
    final kroj = fontFamilyOf(styl);
    final skroty = <ShareTarget>[];
    for (final cel in cele) {
      skroty.add(ShareTarget(
        peerGuid: cel.guid,
        label: cel.label,
        icon: await shortcutIcon(cel.label, tokeny, kroj),
      ));
    }
    if (await _intake.setTargets(skroty)) return;
    // Odmowa (limit w tle, brak kanału): kolejna zmiana spróbuje od nowa.
    _opublikowane = null;
  }

  Future<void> dispose() async {
    _zwloka?.cancel();
    await _rozmowy?.cancel();
    await _ustawienia?.cancel();
  }
}

/// Rozmowy do okna „Udostępnij": pierwsze [shareTargetCount] z listy, która
/// idzie już od ostatniej. Nazwa jest ta, którą widać w Chatcie.
@visibleForTesting
List<({String guid, String label})> shareTargetsFrom(
        List<ConversationSummary> rozmowy) =>
    [
      for (final rozmowa in rozmowy.take(shareTargetCount))
        (guid: rozmowa.peer.guid, label: rozmowa.peer.displayName),
    ];

/// Awatar rozmówcy jako PNG do skrótu rozmowy: inicjały na kolorze stylu,
/// jak na liście rozmów. Kwadrat bez zaokrągleń, bo kształt nadaje system.
/// `null`, gdy rysowanie się nie udało; system pokaże wtedy ikonę Chatta.
Future<Uint8List?> shortcutIcon(
    String name, ChattTokens tokens, String fontFamily) async {
  // Inicjały w tej samej proporcji do widocznego koła, co w aplikacji.
  const widoczne = _bok * 72 / 108;
  final kolory = tokens.avatarFor(name);
  final nagranie = ui.PictureRecorder();
  final plotno = Canvas(nagranie);
  plotno.drawRect(
      Offset.zero & const Size.square(_bok), Paint()..color = kolory.background);
  final tekst = TextPainter(
    text: TextSpan(
      text: initialsOf(name),
      style: TextStyle(
        color: kolory.foreground,
        fontFamily: fontFamily,
        fontSize: widoczne * 0.34,
        fontWeight: tokens.avatarWeight,
        letterSpacing: widoczne * 0.34 * 0.02,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tekst.paint(
      plotno, Offset((_bok - tekst.width) / 2, (_bok - tekst.height) / 2));
  tekst.dispose();
  final obraz =
      await nagranie.endRecording().toImage(_bok.toInt(), _bok.toInt());
  try {
    final dane = await obraz.toByteData(format: ui.ImageByteFormat.png);
    return dane?.buffer.asUint8List();
  } catch (_) {
    return null;
  } finally {
    obraz.dispose();
  }
}
