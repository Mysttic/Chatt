part of 'app_services.dart';

// Udostępnianie historii rozmowy (issue #36). Rozmówca, który ma naszą
// wspólną rozmowę, oddaje nam ją po utracie: reinstalacja, nowy telefon,
// „Wyczyść historię", retencja. Zaczyna każda ze stron: udostępniający
// zapowiedzią, ten, kto stracił, prośbą. Zgoda zostaje przy tym, kto ma
// coś przyjąć albo oddać.

/// Prośba o decyzję, pokazywana jako karta.
enum PendingHistoryKind {
  /// Rozmówca chce nam oddać historię: przyjąć czy nie.
  offer,

  /// Rozmówca prosi o naszą historię: oddać czy nie.
  request,
}

class PendingHistory {
  /// Klucz prośby, do [AppServices.respondToHistory].
  final String id;
  final PendingHistoryKind kind;
  final String peerGuid;
  final String peerName;
  final bool fromVerifiedPeer;

  /// Rozmowa z tym rozmówcą, jeśli już jest. Karta jej nie zakłada: odmowa
  /// nie zostawia pustej rozmowy na liście.
  final int? conversationId;

  /// Co obejmuje zapowiedź ([PendingHistoryKind.offer]) albo co by się
  /// oddało ([PendingHistoryKind.request]).
  final HistorySummary? summary;

  /// Przy zapowiedzi: ile dni trzyma wiadomości retencja tego urządzenia
  /// (0 = bez końca). Starsze nie wejdą, karta mówi to wprost.
  final int retentionDays;

  const PendingHistory({
    required this.id,
    required this.kind,
    required this.peerGuid,
    required this.peerName,
    required this.fromVerifiedPeer,
    this.conversationId,
    this.summary,
    this.retentionDays = 0,
  });
}

/// Decyzja na karcie. [acceptWithoutFiles] dotyczy wyłącznie prośby: oddajemy
/// same wiadomości.
enum HistoryDecision { accept, acceptWithoutFiles, reject, noAnswer }

/// Kto decyduje o karcie. W aplikacji użytkownik, w testach podmiana.
typedef HistoryPolicy = Future<HistoryDecision> Function(PendingHistory ask);

/// Polityka testów i narzędzi: każda karta to zgoda.
Future<HistoryDecision> acceptAllHistory(PendingHistory ask) async =>
    HistoryDecision.accept;

/// Czym skończyło się udostępnianie.
enum HistoryShareResult {
  done,

  /// Starszą rozmowę z innym wpisem wolno oddać wyłącznie urządzeniu
  /// z zieloną tarczą.
  needsVerified,
  nothingToShare,
  rejected,
  noAnswer,
  busy,
  olderVersion,
  unreachable,
  cancelled,
  failed,
}

/// Czym skończyła się prośba o historię. [accepted] znaczy, że rozmówca się
/// zgodził i zaraz zacznie oddawać.
enum HistoryRequestResult {
  accepted,
  empty,
  rejected,
  noAnswer,
  busy,
  olderVersion,
  unreachable,
}

/// Co by poszło przy udostępnieniu, do okna wyboru i karty prośby.
class HistoryPreview {
  final int messages;
  final int files;
  final int bytes;

  /// Pliki, których bajtów już nie ma (przeniesione, skasowane, sprzątnięty
  /// cache). Pójdą jako wpisy bez treści.
  final int missingFiles;
  final DateTime? first;
  final DateTime? last;

  const HistoryPreview({
    required this.messages,
    required this.files,
    required this.bytes,
    required this.missingFiles,
    this.first,
    this.last,
  });
}

/// Postęp udostępniania albo przywracania, do paska postępu.
class HistoryTransfer {
  final String peerName;
  final int conversationId;
  final int messagesTotal;
  final int messagesDone;
  final int filesTotal;
  final int filesDone;

  /// Ile wiadomości odpadło przy imporcie (już były, za stare, z przyszłości).
  final int skipped;
  final bool finished;

  const HistoryTransfer({
    required this.peerName,
    required this.conversationId,
    required this.messagesTotal,
    this.messagesDone = 0,
    required this.filesTotal,
    this.filesDone = 0,
    this.skipped = 0,
    this.finished = false,
  });

  HistoryTransfer copyWith({
    int? messagesDone,
    int? filesDone,
    int? skipped,
    bool? finished,
  }) =>
      HistoryTransfer(
        peerName: peerName,
        conversationId: conversationId,
        messagesTotal: messagesTotal,
        messagesDone: messagesDone ?? this.messagesDone,
        filesTotal: filesTotal,
        filesDone: filesDone ?? this.filesDone,
        skipped: skipped ?? this.skipped,
        finished: finished ?? this.finished,
      );
}

/// Zgoda na przyjęcie historii od jednego rozmówcy.
class _HistoryGrant {
  final String peerGuid;
  final String id;
  final String token;
  final int conversationId;
  final HistorySummary summary;

  /// Rozmówca w dzienniku aplikacji (nazwa i początek guid-a).
  final String kto;
  final DateTime started = DateTime.now();
  DateTime lastUsed = DateTime.now();

  /// Numery paczek, które już weszły. Powtórzona paczka nie liczy się drugi
  /// raz do limitu.
  final Set<int> seqs = {};
  int messages = 0;

  /// Pliki zapowiedziane w paczkach: tylko te wolno potem przysłać, i tylko
  /// pod tą nazwą i z tym rozmiarem.
  final Map<String, ({String name, int size})> files = {};
  int fileBytes = 0;

  /// Pliki, które już są u nas. Powtórzona zapowiedź nie liczy się drugi raz.
  final Set<String> doneFiles = {};
  int filesDone = 0;
  int imported = 0;
  int skipped = 0;

  _HistoryGrant({
    required this.peerGuid,
    required this.id,
    required this.token,
    required this.conversationId,
    required this.summary,
    required this.kto,
  });

  bool get expired {
    final teraz = DateTime.now();
    return teraz.difference(lastUsed) > historyIdle ||
        teraz.difference(started) > historyMaxLife;
  }
}

typedef _HistoryAnswer = ({int status, Map<String, Object?> payload});

/// Własne udostępnianie w toku.
class _HistoryShare {
  final Peer peer;
  final String id;
  bool cancelled = false;
  String? token;
  PeerRoute? route;

  _HistoryShare(this.peer, this.id);
}

/// Udostępnianie historii w obie strony. Własność [AppServices], który tylko
/// deleguje.
class _History {
  final AppServices _s;

  _History(this._s);

  late HistoryPolicy _policy = _askUser;

  final ValueNotifier<List<PendingHistory>> pending = ValueNotifier(const []);
  final ValueNotifier<HistoryTransfer?> outgoing = ValueNotifier(null);
  final ValueNotifier<HistoryTransfer?> incoming = ValueNotifier(null);

  /// Bieżąca zgoda na przyjmowanie. Najwyżej jedna naraz: druga historia
  /// w trakcie pierwszej to `busy`.
  _HistoryGrant? _grant;

  /// Karty czekające na decyzję i odpowiedzi już udzielone, po kluczu
  /// `guid|id`. Kopia zapytania, która przyszła drugą drogą, dostaje tę samą
  /// odpowiedź bez drugiej karty.
  final Map<String, Future<_HistoryAnswer>> _asking = {};
  final Map<String, _HistoryAnswer> _answered = {};
  final Map<String, Completer<HistoryDecision>> _decisions = {};

  /// Własne prośby o historię: zapowiedź, która na nią odpowiada, wchodzi
  /// bez karty, bo zgoda już padła po tej stronie.
  final Map<String, ({String peerGuid, DateTime until})> _myRequests = {};

  _HistoryShare? _share;
  bool _closed = false;

  /// Paczki przychodzące idą po kolei: kopia paczki, która przyszła drugą
  /// drogą w trakcie importu pierwszej, nie przejdzie razem z nią kontroli
  /// numeru.
  Future<void> _chunks = Future.value();

  /// Gasi zgodę, która wygasła, choćby nadawca już nic nie przysłał (padł,
  /// zasnął, wyszedł z zasięgu). Bez tego pasek przywracania wisiałby do
  /// następnej historii albo restartu.
  Timer? _grantClock;

  static const int _maxAnswers = 64;

  /// Najwyżej tyle kart historii naraz, od wszystkich. Od jednego nadawcy
  /// jedna: zalew prośbami nie zasypie ekranu kartami.
  static const int _maxAsks = 8;

  /// Zapas na zaokrąglenie czasu (baza trzyma sekundy) przy sprawdzaniu, czy
  /// wiadomość mieści się w zakresie dat z karty.
  static const Duration _zapasDat = Duration(seconds: 1);

  void _set<T>(ValueNotifier<T> notifier, T value) {
    if (!_closed) notifier.value = value;
  }

  /// Tożsamość w paczkach. Odbiorca sprawdza z niej tylko guid.
  DeviceIdentity get _me => DeviceIdentity(
        guid: _s.identity.guid,
        name: '',
        welcomeMessage: '',
        tcpPort: _s.identity.tcpPort,
      );

  // --- Udostępniający -------------------------------------------------------

  /// Rozmiar pliku wiadomości, jeśli jego bajty wciąż są na dysku. Bez
  /// synchronicznych wywołań: rozmowa potrafi mieć setki plików, a to
  /// liczy się na wątku interfejsu.
  static Future<int?> _rozmiarDoOddania(Message m) async {
    final path = m.filePath;
    if (m.kind != MessageKind.file || path == null) return null;
    final file = File(path);
    try {
      return await file.exists() ? await file.length() : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<List<Message>> _doOddania(int conversationId, DateTime? since) async {
    final wszystkie =
        await _s.db.messagesForHistory(conversationId, since: since);
    // Zgoda obejmuje najwyżej tyle wiadomości; przy większej rozmowie idą
    // najnowsze.
    return wszystkie.length > maxHistoryMessages
        ? wszystkie.sublist(wszystkie.length - maxHistoryMessages)
        : wszystkie;
  }

  Future<HistoryPreview> preview(int conversationId,
      {DateTime? since,
      bool withFiles = true,
      int? sourceConversationId}) async {
    final rows =
        await _doOddania(sourceConversationId ?? conversationId, since);
    var files = 0;
    var bytes = 0;
    var missing = 0;
    for (final m in rows) {
      if (m.kind != MessageKind.file) continue;
      final rozmiar = withFiles ? await _rozmiarDoOddania(m) : null;
      if (rozmiar == null) {
        missing++;
        continue;
      }
      files++;
      bytes += rozmiar;
    }
    return HistoryPreview(
      messages: rows.length,
      files: files,
      bytes: bytes,
      missingFiles: withFiles ? missing : 0,
      first: rows.isEmpty ? null : rows.first.createdAt,
      last: rows.isEmpty ? null : rows.last.createdAt,
    );
  }

  /// Oddaje rozmówcy z rozmowy [conversationId] naszą wspólną historię.
  /// [answering] to identyfikator jego prośby, jeśli to odpowiedź na nią.
  ///
  /// [sourceConversationId] to inna rozmowa, z której bierzemy wiadomości:
  /// to samo urządzenie po reinstalacji albo nowy telefon przychodzi pod
  /// nowym wpisem (tożsamość bierze się z klucza), a stara rozmowa zostaje
  /// pod starym. Że to ta sama osoba, rozstrzyga człowiek, więc tylko przy
  /// zielonej tarczy: inaczej każdy, kto poda się za znajomego, dostałby
  /// jego rozmowę z nami.
  Future<HistoryShareResult> share(int conversationId,
      {DateTime? since,
      bool withFiles = true,
      String? answering,
      int? sourceConversationId}) async {
    if (_closed) return HistoryShareResult.failed;
    if (_share != null) return HistoryShareResult.busy;
    final peer = await _s.db.peerForConversation(conversationId);
    if (peer == null) return HistoryShareResult.failed;
    final kto = _s._kto(peer);
    final zrodlo = sourceConversationId ?? conversationId;
    if (zrodlo != conversationId && !peer.verified) {
      _s.log.info(LogArea.history,
          'History share to $kto not started: older conversation needs a verified device');
      return HistoryShareResult.needsVerified;
    }

    final rows = await _doOddania(zrodlo, since);
    if (rows.isEmpty) {
      _s.log.info(LogArea.history, 'History share to $kto: nothing to share');
      return HistoryShareResult.nothingToShare;
    }

    final items = <HistoryItem>[];
    final zPlikami = <Message>[];
    var bytes = 0;
    for (final m in rows) {
      final naDysku = withFiles ? await _rozmiarDoOddania(m) : null;
      final rozmiar = naDysku ?? m.fileSize ?? 0;
      if (naDysku != null) {
        zPlikami.add(m);
        bytes += rozmiar;
      }
      items.add(HistoryItem(
        messageGuid: m.messageGuid,
        mine: m.direction == MessageDirection.outgoing,
        sentAt: m.createdAt,
        body: m.body.length > maxHistoryBodyUnits
            ? m.body.substring(0, maxHistoryBodyUnits)
            : m.body,
        fileName: m.kind == MessageKind.file
            ? _krotkaNazwa(m.fileName ?? m.body)
            : null,
        fileSize: m.kind == MessageKind.file ? rozmiar : null,
        fileFollows: naDysku != null,
      ));
    }
    final summary = HistorySummary(
      count: items.length,
      files: zPlikami.length,
      bytes: bytes,
      first: rows.first.createdAt,
      last: rows.last.createdAt,
    );

    final udzial = _HistoryShare(peer, AppServices._uuid.v4());
    _share = udzial;
    // Do dziennika idą same liczby: ani treści, ani nazw plików.
    _s.log.info(
        LogArea.history,
        'History share to $kto started: ${summary.count} messages, '
        '${summary.files} files, ${summary.bytes} bytes'
        '${answering == null ? '' : ', answering a request'}'
        '${zrodlo == conversationId ? '' : ', from an older conversation'}');
    try {
      final wynik = await _run(udzial, items, zPlikami, summary, answering);
      _zapiszWynikUdostepniania(kto, wynik, summary);
      return wynik;
    } catch (blad, slad) {
      _s.log.error(LogArea.history, 'History share to $kto failed',
          error: blad, stack: slad);
      // Odbiorca ma się dowiedzieć, że nic więcej nie przyjdzie: inaczej jego
      // pasek przywracania wisiałby do wygaśnięcia zgody.
      await _cancel(udzial);
      return HistoryShareResult.failed;
    } finally {
      _share = null;
      _set(outgoing, null);
    }
  }

  /// Wynik własnego udostępniania w dzienniku aplikacji.
  void _zapiszWynikUdostepniania(
      String kto, HistoryShareResult wynik, HistorySummary summary) {
    switch (wynik) {
      case HistoryShareResult.done:
        _s.log.info(
            LogArea.history,
            'History share to $kto finished: ${summary.count} messages and '
            '${summary.files} files sent');
      case HistoryShareResult.cancelled:
        _s.log.info(LogArea.history, 'History share to $kto cancelled');
      case HistoryShareResult.rejected:
      case HistoryShareResult.noAnswer:
      case HistoryShareResult.busy:
        _s.log.info(
            LogArea.history, 'History share to $kto declined: ${wynik.name}');
      case HistoryShareResult.needsVerified:
      case HistoryShareResult.nothingToShare:
      case HistoryShareResult.olderVersion:
      case HistoryShareResult.unreachable:
      case HistoryShareResult.failed:
        _s.log.warning(
            LogArea.history, 'History share to $kto failed: ${wynik.name}');
    }
  }

  static String _krotkaNazwa(String name) => name.length > maxHistoryFileName
      ? name.substring(name.length - maxHistoryFileName)
      : (name.isEmpty ? 'plik' : name);

  Future<HistoryShareResult> _run(
    _HistoryShare udzial,
    List<HistoryItem> items,
    List<Message> zPlikami,
    HistorySummary summary,
    String? answering,
  ) async {
    final peer = udzial.peer;
    final zapowiedz = HistoryOfferMessage(
      from: _me,
      op: historyOpOffer,
      id: udzial.id,
      summary: summary,
      answering: answering,
    ).toJson();
    final odp = await _s._exchangeSealed(
      peer,
      zapowiedz,
      (route, koperta) =>
          _s.client.historyOffer(route: route, payload: koperta),
      alive: () => !udzial.cancelled && !_closed,
    );
    if (udzial.cancelled) return HistoryShareResult.cancelled;
    if (odp.status == 404) return HistoryShareResult.olderVersion;
    final reply = HistoryReply.fromJson(odp.reply, id: udzial.id);
    if (reply == null) return HistoryShareResult.unreachable;
    if (!reply.accepted || reply.token == null) {
      return switch (reply.reason) {
        historyNoAnswer => HistoryShareResult.noAnswer,
        historyBusy => HistoryShareResult.busy,
        _ => HistoryShareResult.rejected,
      };
    }
    udzial.token = reply.token;
    udzial.route = odp.route;

    var postep = HistoryTransfer(
      peerName: peer.displayName,
      conversationId: (await _s.db.ensureConversation(peer.id)),
      messagesTotal: items.length,
      filesTotal: zPlikami.length,
    );
    _set(outgoing, postep);

    // Wiadomości paczkami, po kolei. Paczka trzyma się też limitu bajtów:
    // dwieście długich wiadomości potrafiłoby przekroczyć limit ciała.
    var seq = 0;
    var od = 0;
    while (od < items.length) {
      if (udzial.cancelled || _closed) return _cancel(udzial);
      var do_ = od;
      var rozmiar = 0;
      while (do_ < items.length &&
          do_ - od < maxHistoryChunkItems &&
          (do_ == od || rozmiar < _chunkBytes)) {
        final item = items[do_];
        rozmiar += item.body.length * 3 + (item.fileName?.length ?? 0) * 3 + 160;
        do_++;
      }
      seq++;
      final paczka = HistoryChunk(
        from: _me,
        id: udzial.id,
        token: udzial.token!,
        seq: seq,
        items: items.sublist(od, do_),
      );
      HistoryChunkReply? wynik;
      // Paczka bez odpowiedzi idzie jeszcze raz z tym samym numerem: import
      // i tak pomija to, co już weszło.
      for (var proba = 0; proba < 3 && wynik == null; proba++) {
        if (udzial.cancelled || _closed) return _cancel(udzial);
        final o = await _s._exchangeSealed(
          peer,
          paczka.toJson(),
          (route, koperta) =>
              _s.client.historyChunk(route: route, payload: koperta),
          route: udzial.route,
          alive: () => !udzial.cancelled && !_closed,
        );
        wynik = HistoryChunkReply.fromJson(o.reply, id: udzial.id, seq: seq);
        if (wynik == null && o.status == 403) break;
      }
      if (wynik == null || !wynik.ok) {
        _s.log.warning(
            LogArea.history,
            'History share to ${_s._kto(peer)}: chunk $seq refused '
            '(${logText(wynik?.reason ?? 'no reply')})');
        await _cancel(udzial);
        return HistoryShareResult.failed;
      }
      od = do_;
      postep = postep.copyWith(messagesDone: od);
      _set(outgoing, postep);
    }

    // Pliki zwykłą drogą, z polem historii: odbiorca przyjmuje je bez
    // pytania, bo zgoda objęła ich liczbę i bajty.
    var pliki = 0;
    for (final m in zPlikami) {
      if (udzial.cancelled || _closed) return _cancel(udzial);
      await _s._deliverFile(m.id, peer, historyId: udzial.id);
      pliki++;
      postep = postep.copyWith(filesDone: pliki);
      _set(outgoing, postep);
    }

    await _s._exchangeSealed(
      peer,
      HistoryOfferMessage(
        from: _me,
        op: historyOpDone,
        id: udzial.id,
        token: udzial.token,
      ).toJson(),
      (route, koperta) =>
          _s.client.historyOffer(route: route, payload: koperta),
      route: udzial.route,
    );
    return HistoryShareResult.done;
  }

  /// Około tylu bajtów treści w jednej paczce.
  static const int _chunkBytes = 256 * 1024;

  Future<HistoryShareResult> _cancel(_HistoryShare udzial) async {
    final token = udzial.token;
    if (token != null && !_closed) {
      try {
        await _s._exchangeSealed(
        udzial.peer,
        HistoryOfferMessage(
          from: _me,
          op: historyOpCancel,
          id: udzial.id,
          token: token,
        ).toJson(),
        (route, koperta) =>
            _s.client.historyOffer(route: route, payload: koperta),
        route: udzial.route,
      );
      } catch (_) {
        // Odbiorca i tak zgasi zgodę po pół godzinie ciszy.
      }
    }
    return HistoryShareResult.cancelled;
  }

  /// Przerywa własne udostępnianie. Odbiorca zachowuje to, co już doszło.
  void cancelShare() => _share?.cancelled = true;

  /// Prosi rozmówcę z rozmowy [conversationId] o jego kopię naszej historii.
  Future<HistoryRequestResult> request(int conversationId) async {
    if (_closed) return HistoryRequestResult.unreachable;
    final peer = await _s.db.peerForConversation(conversationId);
    if (peer == null) return HistoryRequestResult.unreachable;
    final kto = _s._kto(peer);
    _s.log.info(LogArea.history, 'History requested from $kto');
    final id = AppServices._uuid.v4();
    // Wpis przed wysłaniem: zapowiedź potrafi przyjść, zanim wróci odpowiedź.
    _myRequests[id] = (
      peerGuid: peer.guid,
      until: DateTime.now().add(historyRequestLife),
    );
    final odp = await _s._exchangeSealed(
      peer,
      HistoryOfferMessage(from: _me, op: historyOpRequest, id: id).toJson(),
      (route, koperta) =>
          _s.client.historyOffer(route: route, payload: koperta),
    );
    final reply = HistoryReply.fromJson(odp.reply, id: id);
    final wynik = odp.status == 404
        ? HistoryRequestResult.olderVersion
        : reply == null
            ? HistoryRequestResult.unreachable
            : reply.accepted
                ? HistoryRequestResult.accepted
                : switch (reply.reason) {
                    historyNoAnswer => HistoryRequestResult.noAnswer,
                    historyBusy => HistoryRequestResult.busy,
                    historyEmpty => HistoryRequestResult.empty,
                    _ => HistoryRequestResult.rejected,
                  };
    if (wynik != HistoryRequestResult.accepted) _myRequests.remove(id);
    _s.log.add(
      switch (wynik) {
        HistoryRequestResult.olderVersion ||
        HistoryRequestResult.unreachable =>
          LogLevel.warning,
        _ => LogLevel.info,
      },
      LogArea.history,
      'History request to $kto: ${wynik.name}',
    );
    return wynik;
  }

  // --- Odbiorca zapowiedzi i proszony ---------------------------------------

  static const SealedReply _noSession = (
    status: 409,
    body: {'ok': false, 'error': errorNoSession},
  );

  Future<SealedReply> _seal(_Session sesja, _HistoryAnswer odpowiedz) async =>
      (
        status: odpowiedz.status,
        body: await ChattCrypto.seal(
            payload: odpowiedz.payload, key: sesja.key, sessionId: sesja.id),
      );

  Future<SealedReply> handleOffer(
      HistoryOfferMessage message, String fromHost, String session) async {
    final sesja = _s._sessionsById[session];
    if (sesja == null || sesja.peerGuid != message.from.guid) return _noSession;
    sesja.touch();
    return _seal(sesja, await _answerOffer(message, fromHost));
  }

  _HistoryAnswer _reply(String id, {required bool accepted, String? token,
          String? reason}) =>
      (
        status: accepted ? 200 : 403,
        payload: HistoryReply(
                id: id, accepted: accepted, token: token, reason: reason)
            .toJson(),
      );

  Future<_HistoryAnswer> _answerOffer(
      HistoryOfferMessage message, String fromHost) async {
    final guid = message.from.guid;
    final klucz = '$guid|${message.id}';

    switch (message.op) {
      case historyOpDone:
      case historyOpCancel:
        final grant = _grant;
        if (grant != null &&
            grant.peerGuid == guid &&
            grant.id == message.id &&
            grant.token == message.token) {
          _endGrant(
            finished: message.op == historyOpDone,
            reason: message.op == historyOpDone
                ? 'finished'
                : 'cancelled by the sender',
          );
        }
        return _reply(message.id, accepted: true);
    }

    final juz = _answered[klucz];
    if (juz != null) return juz;
    final trwa = _asking[klucz];
    if (trwa != null) return trwa;

    // Jedna karta od jednego nadawcy i kilka naraz w ogóle: kolejne pytania
    // w tym czasie słyszą `busy`.
    if (_asking.keys.any((k) => k.startsWith('$guid|')) ||
        _asking.length >= _maxAsks) {
      return _reply(message.id, accepted: false, reason: historyBusy);
    }

    final odpowiedz = message.op == historyOpOffer
        ? _decideOffer(message, fromHost, klucz)
        : _decideRequest(message, fromHost, klucz);
    _asking[klucz] = odpowiedz;
    try {
      final wynik = await odpowiedz;
      if (_answered.length >= _maxAnswers) {
        _answered.remove(_answered.keys.first);
      }
      _answered[klucz] = wynik;
      return wynik;
    } finally {
      _asking.remove(klucz);
    }
  }

  Future<int> _retentionDays() async =>
      (await _s.db.getSettings())?.retentionDays ?? 0;

  Future<_HistoryAnswer> _decideOffer(
      HistoryOfferMessage message, String fromHost, String klucz) async {
    final guid = message.from.guid;
    final summary = message.summary!;
    final peer = await _s.db.peerByGuid(guid);
    if (peer == null) {
      _s.log.warning(LogArea.history,
          'History offer from unknown device ${peerLabel('', guid)} refused');
      return _reply(message.id, accepted: false, reason: historyRejected);
    }
    _s._drogaPrzychodzaca(guid, fromHost);
    final kto = _s._kto(peer);
    final co = '${summary.count} messages, ${summary.files} files, '
        '${summary.bytes} bytes';

    final grant = _grant;
    if (grant != null && !grant.expired && grant.peerGuid != guid) {
      _s.log.info(LogArea.history,
          'History offer from $kto ($co) refused: another history in progress');
      return _reply(message.id, accepted: false, reason: historyBusy);
    }

    // Odpowiedź na naszą własną prośbę: zgoda już padła po tej stronie.
    _myRequests.removeWhere((_, r) => r.until.isBefore(DateTime.now()));
    final prosba =
        message.answering == null ? null : _myRequests[message.answering!];
    HistoryDecision decyzja;
    if (prosba != null && prosba.peerGuid == guid) {
      _myRequests.remove(message.answering);
      decyzja = HistoryDecision.accept;
      _s.log.info(LogArea.history,
          'History offer from $kto ($co) answers our request');
    } else {
      _s.log.info(LogArea.history, 'History offer from $kto ($co)');
      decyzja = await _policy(PendingHistory(
        id: klucz,
        kind: PendingHistoryKind.offer,
        peerGuid: guid,
        peerName: peer.displayName,
        fromVerifiedPeer: peer.verified,
        conversationId: await _s.db.conversationOfPeer(peer.id),
        summary: summary,
        retentionDays: await _retentionDays(),
      ));
    }
    if (_closed) decyzja = HistoryDecision.noAnswer;
    switch (decyzja) {
      case HistoryDecision.reject:
        _s.log.info(LogArea.history, 'History offer from $kto rejected');
        return _reply(message.id, accepted: false, reason: historyRejected);
      case HistoryDecision.noAnswer:
        _s.log.info(LogArea.history, 'History offer from $kto: no answer');
        return _reply(message.id, accepted: false, reason: historyNoAnswer);
      case HistoryDecision.accept:
      case HistoryDecision.acceptWithoutFiles:
        break;
    }
    // Przez dwie minuty karty ktoś inny mógł zacząć oddawać swoją.
    final teraz = _grant;
    if (teraz != null && !teraz.expired && teraz.peerGuid != guid) {
      _s.log.info(LogArea.history,
          'History offer from $kto refused: another history in progress');
      return _reply(message.id, accepted: false, reason: historyBusy);
    }
    if (teraz != null) _endGrant(reason: 'replaced');
    // Rozmowa powstaje dopiero po zgodzie.
    final conversationId = await _s.db.ensureConversation(peer.id);
    final nowa = _HistoryGrant(
      peerGuid: guid,
      id: message.id,
      token: newSessionId(),
      conversationId: conversationId,
      summary: summary,
      kto: kto,
    );
    _grant = nowa;
    _s.log.info(LogArea.history, 'History offer from $kto accepted');
    _grantClock?.cancel();
    _grantClock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_grant?.expired ?? false) _endGrant(reason: 'expired');
    });
    _set(
        incoming,
        HistoryTransfer(
          peerName: peer.displayName,
          conversationId: conversationId,
          messagesTotal: summary.count,
          filesTotal: summary.files,
        ));
    return _reply(message.id, accepted: true, token: nowa.token);
  }

  Future<_HistoryAnswer> _decideRequest(
      HistoryOfferMessage message, String fromHost, String klucz) async {
    final guid = message.from.guid;
    final peer = await _s.db.peerByGuid(guid);
    if (peer == null) {
      _s.log.warning(LogArea.history,
          'History request from unknown device ${peerLabel('', guid)} refused');
      return _reply(message.id, accepted: false, reason: historyRejected);
    }
    _s._drogaPrzychodzaca(guid, fromHost);
    final kto = _s._kto(peer);
    if (_share != null) {
      _s.log.info(LogArea.history,
          'History request from $kto refused: own share in progress');
      return _reply(message.id, accepted: false, reason: historyBusy);
    }
    // Bez rozmowy nie ma czego oddać, a pytanie o nią nie zakłada nowej.
    final conversationId = await _s.db.conversationOfPeer(peer.id);
    if (conversationId == null) {
      _s.log.info(
          LogArea.history, 'History request from $kto: nothing to share');
      return _reply(message.id, accepted: false, reason: historyEmpty);
    }
    final co = await preview(conversationId);
    if (co.messages == 0) {
      _s.log.info(
          LogArea.history, 'History request from $kto: nothing to share');
      return _reply(message.id, accepted: false, reason: historyEmpty);
    }
    _s.log.info(
        LogArea.history,
        'History request from $kto (${co.messages} messages, '
        '${co.files} files, ${co.bytes} bytes)');
    var decyzja = await _policy(PendingHistory(
      id: klucz,
      kind: PendingHistoryKind.request,
      peerGuid: guid,
      peerName: peer.displayName,
      fromVerifiedPeer: peer.verified,
      conversationId: conversationId,
      summary: HistorySummary(
        count: co.messages,
        files: co.files,
        bytes: co.bytes,
        first: co.first!,
        last: co.last!,
      ),
    ));
    if (_closed) decyzja = HistoryDecision.noAnswer;
    switch (decyzja) {
      case HistoryDecision.reject:
        _s.log.info(LogArea.history, 'History request from $kto rejected');
        return _reply(message.id, accepted: false, reason: historyRejected);
      case HistoryDecision.noAnswer:
        _s.log.info(LogArea.history, 'History request from $kto: no answer');
        return _reply(message.id, accepted: false, reason: historyNoAnswer);
      case HistoryDecision.accept:
      case HistoryDecision.acceptWithoutFiles:
        break;
    }
    if (_share != null) {
      _s.log.info(LogArea.history,
          'History request from $kto refused: own share in progress');
      return _reply(message.id, accepted: false, reason: historyBusy);
    }
    // Zapowiedź rusza dopiero po odpowiedzi: proszący najpierw ma się
    // dowiedzieć, że się zgodziliśmy.
    final zPlikami = decyzja == HistoryDecision.accept;
    _s.log.info(
        LogArea.history,
        'History request from $kto accepted '
        '${zPlikami ? 'with files' : 'without files'}');
    Timer.run(() async {
      try {
        await share(conversationId, withFiles: zPlikami, answering: message.id);
      } catch (blad, slad) {
        // `share` sam kończy zgodę po drugiej stronie; zostaje ślad.
        _s.log.error(LogArea.history, 'History share to $kto failed',
            error: blad, stack: slad);
      }
    });
    return _reply(message.id, accepted: true);
  }

  // --- Paczki wiadomości ----------------------------------------------------

  Future<SealedReply> handleChunk(
      HistoryChunk chunk, String fromHost, String session) async {
    final sesja = _s._sessionsById[session];
    if (sesja == null || sesja.peerGuid != chunk.from.guid) return _noSession;
    sesja.touch();
    final wynik = _chunks.then((_) => _answerChunk(chunk));
    _chunks = wynik.then((_) {}, onError: (_) {});
    return _seal(sesja, await wynik);
  }

  _HistoryAnswer _chunkReply(HistoryChunk chunk,
          {required bool ok, int imported = 0, int skipped = 0,
          String? reason}) =>
      (
        status: ok ? 200 : 403,
        payload: HistoryChunkReply(
          id: chunk.id,
          seq: chunk.seq,
          ok: ok,
          imported: imported,
          skipped: skipped,
          reason: reason,
        ).toJson(),
      );

  Future<_HistoryAnswer> _answerChunk(HistoryChunk chunk) async {
    final grant = _grant;
    if (grant != null && grant.expired) _endGrant(reason: 'expired');
    if (grant == null ||
        grant.expired ||
        grant.peerGuid != chunk.from.guid ||
        grant.id != chunk.id ||
        grant.token != chunk.token) {
      _s.log.add(
        LogLevel.warning,
        LogArea.history,
        'History chunk from ${peerLabel('', chunk.from.guid)} refused: no grant',
        // Spóźnione paczki po przerwaniu przychodzą seriami.
        collapseWithin: const Duration(minutes: 1),
      );
      return _chunkReply(chunk, ok: false, reason: historyNoGrant);
    }
    grant.lastUsed = DateTime.now();

    // Paczka, która już weszła (powtórka po zgubionej odpowiedzi), nie
    // importuje niczego drugi raz. Bez tego ten sam numer z nową treścią
    // wpuszczałby wiadomości ponad zapowiedź.
    if (grant.seqs.contains(chunk.seq)) {
      return _chunkReply(chunk, ok: true, skipped: chunk.items.length);
    }

    // Zgoda obowiązuje w granicach zapowiedzi: tyle wiadomości, tyle plików,
    // tyle bajtów i ten zakres dat, ile stało na karcie. Plik zapowiedziany
    // raz zostaje przy tej nazwie i tym rozmiarze.
    final nowePliki = <String, ({String name, int size})>{};
    var bajty = 0;
    final od = grant.summary.first.subtract(_zapasDat);
    final do_ = grant.summary.last.add(_zapasDat);
    _HistoryAnswer ponadZapowiedz(String co) {
      _s.log.warning(LogArea.history,
          'History chunk ${chunk.seq} from ${grant.kto} refused: $co');
      return _chunkReply(chunk, ok: false, reason: historyOverLimit);
    }

    for (final item in chunk.items) {
      if (item.sentAt.isBefore(od) || item.sentAt.isAfter(do_)) {
        return ponadZapowiedz('message outside the announced dates');
      }
      if (!item.fileFollows) continue;
      final opis = (name: item.fileName!, size: item.fileSize ?? 0);
      final znany =
          grant.files[item.messageGuid] ?? nowePliki[item.messageGuid];
      if (znany != null) {
        if (znany != opis) {
          return ponadZapowiedz('file changed between chunks');
        }
        continue;
      }
      nowePliki[item.messageGuid] = opis;
      bajty += opis.size;
    }
    if (grant.messages + chunk.items.length > grant.summary.count ||
        grant.files.length + nowePliki.length > grant.summary.files ||
        grant.fileBytes + bajty > grant.summary.bytes) {
      return ponadZapowiedz('more than announced');
    }

    final teraz = DateTime.now();
    final dni = await _retentionDays();
    final wynik = await _s.db.importHistory(
      conversationId: grant.conversationId,
      items: [for (final item in chunk.items) _restored(item)],
      restoredAt: teraz,
      notAfter: teraz.add(historyFutureSlack),
      notBefore: dni > 0 ? teraz.subtract(Duration(days: dni)) : null,
    );
    // Liczniki dopiero po udanym imporcie: paczka, której import padł,
    // wróci z tym samym numerem i ma wtedy wejść.
    grant.seqs.add(chunk.seq);
    grant.messages += chunk.items.length;
    grant.fileBytes += bajty;
    grant.files.addAll(nowePliki);
    grant.imported += wynik.imported;
    grant.skipped += wynik.skipped;
    final postep = incoming.value;
    if (postep != null && identical(_grant, grant)) {
      _set(
          incoming,
          postep.copyWith(
              messagesDone: grant.messages, skipped: grant.skipped));
    }
    return _chunkReply(chunk,
        ok: true, imported: wynik.imported, skipped: wynik.skipped);
  }

  /// Wiadomość z kopii rozmówcy, odwrócona na nasz punkt widzenia. Plik,
  /// który przetrwał u nas na dysku (odebrane pliki zostają po „Wyczyść
  /// historię"), podpina się od razu i nie musi jechać drugi raz.
  RestoredMessage _restored(HistoryItem item) {
    String? path;
    final name = item.fileName;
    if (name != null) {
      final file = File(_s._receivedPathFor(item.messageGuid, name));
      if (file.existsSync() && file.lengthSync() == item.fileSize) {
        path = file.path;
      }
    }
    return RestoredMessage(
      messageGuid: item.messageGuid,
      direction:
          item.mine ? MessageDirection.incoming : MessageDirection.outgoing,
      sentAt: item.sentAt,
      body: item.body,
      fileName: name,
      fileSize: item.fileSize,
      filePath: path,
    );
  }

  // --- Pliki ----------------------------------------------------------------

  /// Zapowiedź pliku z historii [FileOffer.history]. Nigdy nie spada na
  /// zwykłą drogę z kartą: plik z historii albo mieści się w zgodzie, albo
  /// dostaje odmowę. Wpuszczamy wyłącznie plik zapowiedziany w paczce, pod tą
  /// samą nazwą i z tym samym rozmiarem, i tylko do przywróconego wpisu tej
  /// rozmowy, który ma właśnie tę nazwę i ten rozmiar.
  Future<FileOfferReply> fileOffer(FileOffer offer) async {
    const odmowa = FileOfferReply(accepted: false, reason: historyNoGrant);
    final grant = _grant;
    if (grant == null ||
        grant.peerGuid != offer.from.guid ||
        grant.id != offer.history) {
      return odmowa;
    }
    if (grant.expired) {
      _endGrant(reason: 'expired');
      return odmowa;
    }
    final zapowiedziany = grant.files[offer.messageGuid];
    if (zapowiedziany == null ||
        zapowiedziany.name != offer.fileName ||
        zapowiedziany.size != offer.fileSize) {
      return odmowa;
    }
    final wiersz = await _s.db.messageByGuid(offer.messageGuid);
    if (wiersz == null ||
        wiersz.restoredAt == null ||
        wiersz.kind != MessageKind.file ||
        wiersz.conversationId != grant.conversationId ||
        wiersz.fileName != offer.fileName ||
        wiersz.fileSize != offer.fileSize) {
      return odmowa;
    }
    grant.lastUsed = DateTime.now();
    if (wiersz.filePath != null) {
      // Plik przetrwał na dysku albo dojechał wcześniej.
      _fileDone(grant, offer.messageGuid);
      return const FileOfferReply(accepted: true, alreadyHave: true);
    }
    return FileOfferReply(accepted: true, resumeFrom: _s._resumableBytes(offer));
  }

  /// Bajty pliku z historii płyną: zgoda nie wygasa w trakcie długiego pliku.
  void touch(String peerGuid, String? id) {
    final grant = _grant;
    if (grant != null && grant.peerGuid == peerGuid && grant.id == id) {
      grant.lastUsed = DateTime.now();
    }
  }

  /// Bajty pliku z historii dojechały: podpinamy je pod czekający wpis.
  Future<void> fileReceived(FileOffer offer, String path) async {
    final czeka = await _s.db.restoredFileAwaiting(offer.messageGuid);
    if (czeka != null) await _s.db.attachRestoredFile(czeka.id, path);
    final grant = _grant;
    if (grant != null &&
        grant.peerGuid == offer.from.guid &&
        grant.id == offer.history) {
      grant.lastUsed = DateTime.now();
      _fileDone(grant, offer.messageGuid);
    }
  }

  void _fileDone(_HistoryGrant grant, String messageGuid) {
    if (!grant.doneFiles.add(messageGuid)) return;
    grant.filesDone++;
    final postep = incoming.value;
    if (postep != null && identical(_grant, grant)) {
      _set(incoming, postep.copyWith(filesDone: grant.filesDone));
    }
  }

  // --- Karty, sprzątanie ----------------------------------------------------

  Future<HistoryDecision> _askUser(PendingHistory ask) {
    final decyzja = Completer<HistoryDecision>();
    _decisions[ask.id] = decyzja;
    _set(pending, [...pending.value, ask]);
    return decyzja.future.timeout(historyAnswerTimeout, onTimeout: () {
      respond(ask.id, HistoryDecision.noAnswer);
      return HistoryDecision.noAnswer;
    });
  }

  void respond(String id, HistoryDecision decision) {
    _set(pending,
        pending.value.where((a) => a.id != id).toList(growable: false));
    final decyzja = _decisions.remove(id);
    if (decyzja != null && !decyzja.isCompleted) decyzja.complete(decision);
  }

  /// Koniec zgody. [finished]: udostępniający powiedział, że skończył, więc
  /// pasek pokazuje wynik, zanim zniknie. [reason] trafia do dziennika
  /// aplikacji razem z liczbami.
  void _endGrant({bool finished = false, required String reason}) {
    final grant = _grant;
    _grant = null;
    _grantClock?.cancel();
    _grantClock = null;
    if (grant == null) return;
    _zapiszKoniecZgody(grant, reason);
    final postep = incoming.value;
    if (finished && postep != null) {
      _set(
          incoming,
          postep.copyWith(
            finished: true,
            messagesDone: grant.messages,
            filesDone: grant.filesDone,
            skipped: grant.skipped,
          ));
    } else {
      _set(incoming, null);
    }
  }

  /// Koniec przyjmowania historii w dzienniku aplikacji: same liczby.
  void _zapiszKoniecZgody(_HistoryGrant grant, String reason) => _s.log.info(
      LogArea.history,
      'History from ${grant.kto} ended ($reason): '
      '${grant.imported} messages imported, ${grant.skipped} skipped, '
      '${grant.filesDone} of ${grant.summary.files} files received');

  /// Przerwanie przywracania po stronie odbierającej: zgoda gaśnie, pasek
  /// znika, a następna porcja od udostępniającego dostaje `no_grant`.
  void stopIncoming() {
    if (_grant != null) _endGrant(reason: 'stopped here');
  }

  /// Pasek „Przywrócono" po zakończeniu zamyka użytkownik.
  void dismissIncoming() {
    if (incoming.value?.finished ?? false) _set(incoming, null);
  }

  void forgetPeer(String guid) {
    if (_grant?.peerGuid == guid) _endGrant(reason: 'device removed');
    for (final ask in pending.value.where((a) => a.peerGuid == guid).toList()) {
      respond(ask.id, HistoryDecision.noAnswer);
    }
    _myRequests.removeWhere((_, r) => r.peerGuid == guid);
    if (_share?.peer.guid == guid) cancelShare();
  }

  Future<void> dispose() async {
    for (final id in _decisions.keys.toList()) {
      respond(id, HistoryDecision.noAnswer);
    }
    cancelShare();
    final grant = _grant;
    if (grant != null) _zapiszKoniecZgody(grant, 'app closed');
    _closed = true;
    _grant = null;
    _grantClock?.cancel();
    pending.dispose();
    outgoing.dispose();
    incoming.dispose();
  }
}
