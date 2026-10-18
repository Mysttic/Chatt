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
  final int conversationId;

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
    required this.conversationId,
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
  int filesDone = 0;
  int imported = 0;
  int skipped = 0;

  _HistoryGrant({
    required this.peerGuid,
    required this.id,
    required this.token,
    required this.conversationId,
    required this.summary,
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

  static const int _maxAnswers = 64;

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

  /// Plik wiadomości, jeśli jego bajty wciąż są na dysku.
  static File? _plikDoOddania(Message m) {
    final path = m.filePath;
    if (m.kind != MessageKind.file || path == null) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
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
      {DateTime? since, bool withFiles = true}) async {
    final rows = await _doOddania(conversationId, since);
    var files = 0;
    var bytes = 0;
    var missing = 0;
    for (final m in rows) {
      if (m.kind != MessageKind.file) continue;
      final plik = _plikDoOddania(m);
      if (plik == null || !withFiles) {
        missing++;
        continue;
      }
      files++;
      bytes += plik.lengthSync();
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
  Future<HistoryShareResult> share(int conversationId,
      {DateTime? since, bool withFiles = true, String? answering}) async {
    if (_closed) return HistoryShareResult.failed;
    if (_share != null) return HistoryShareResult.busy;
    final peer = await _s.db.peerForConversation(conversationId);
    if (peer == null) return HistoryShareResult.failed;

    final rows = await _doOddania(conversationId, since);
    if (rows.isEmpty) return HistoryShareResult.nothingToShare;

    final items = <HistoryItem>[];
    final zPlikami = <Message>[];
    var bytes = 0;
    for (final m in rows) {
      final plik = withFiles ? _plikDoOddania(m) : null;
      final rozmiar = plik?.lengthSync() ?? m.fileSize ?? 0;
      if (plik != null) {
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
        fileFollows: plik != null,
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
    try {
      return await _run(udzial, items, zPlikami, summary, answering);
    } finally {
      _share = null;
      _set(outgoing, null);
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
      if (wynik == null || !wynik.ok) return HistoryShareResult.failed;
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
          _endGrant(finished: message.op == historyOpDone);
        }
        return _reply(message.id, accepted: true);
    }

    final juz = _answered[klucz];
    if (juz != null) return juz;
    final trwa = _asking[klucz];
    if (trwa != null) return trwa;

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
      return _reply(message.id, accepted: false, reason: historyRejected);
    }
    _s._drogaPrzychodzaca(guid, fromHost);

    final grant = _grant;
    if (grant != null && !grant.expired && grant.peerGuid != guid) {
      return _reply(message.id, accepted: false, reason: historyBusy);
    }

    // Odpowiedź na naszą własną prośbę: zgoda już padła po tej stronie.
    _myRequests.removeWhere((_, r) => r.until.isBefore(DateTime.now()));
    final prosba =
        message.answering == null ? null : _myRequests[message.answering!];
    final conversationId = await _s.db.ensureConversation(peer.id);
    HistoryDecision decyzja;
    if (prosba != null && prosba.peerGuid == guid) {
      _myRequests.remove(message.answering);
      decyzja = HistoryDecision.accept;
    } else {
      decyzja = await _policy(PendingHistory(
        id: klucz,
        kind: PendingHistoryKind.offer,
        peerGuid: guid,
        peerName: peer.displayName,
        fromVerifiedPeer: peer.verified,
        conversationId: conversationId,
        summary: summary,
        retentionDays: await _retentionDays(),
      ));
    }
    if (_closed) decyzja = HistoryDecision.noAnswer;
    switch (decyzja) {
      case HistoryDecision.reject:
        return _reply(message.id, accepted: false, reason: historyRejected);
      case HistoryDecision.noAnswer:
        return _reply(message.id, accepted: false, reason: historyNoAnswer);
      case HistoryDecision.accept:
      case HistoryDecision.acceptWithoutFiles:
        break;
    }
    // Przez dwie minuty karty ktoś inny mógł zacząć oddawać swoją.
    final teraz = _grant;
    if (teraz != null && !teraz.expired && teraz.peerGuid != guid) {
      return _reply(message.id, accepted: false, reason: historyBusy);
    }
    if (teraz != null) _endGrant();
    final nowa = _HistoryGrant(
      peerGuid: guid,
      id: message.id,
      token: newSessionId(),
      conversationId: conversationId,
      summary: summary,
    );
    _grant = nowa;
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
      return _reply(message.id, accepted: false, reason: historyRejected);
    }
    _s._drogaPrzychodzaca(guid, fromHost);
    if (_share != null) {
      return _reply(message.id, accepted: false, reason: historyBusy);
    }
    final conversationId = await _s.db.ensureConversation(peer.id);
    final co = await preview(conversationId);
    if (co.messages == 0) {
      return _reply(message.id, accepted: false, reason: historyEmpty);
    }
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
        return _reply(message.id, accepted: false, reason: historyRejected);
      case HistoryDecision.noAnswer:
        return _reply(message.id, accepted: false, reason: historyNoAnswer);
      case HistoryDecision.accept:
      case HistoryDecision.acceptWithoutFiles:
        break;
    }
    if (_share != null) {
      return _reply(message.id, accepted: false, reason: historyBusy);
    }
    // Zapowiedź rusza dopiero po odpowiedzi: proszący najpierw ma się
    // dowiedzieć, że się zgodziliśmy.
    final zPlikami = decyzja == HistoryDecision.accept;
    Timer.run(() => unawaited(share(conversationId,
        withFiles: zPlikami, answering: message.id)));
    return _reply(message.id, accepted: true);
  }

  // --- Paczki wiadomości ----------------------------------------------------

  Future<SealedReply> handleChunk(
      HistoryChunk chunk, String fromHost, String session) async {
    final sesja = _s._sessionsById[session];
    if (sesja == null || sesja.peerGuid != chunk.from.guid) return _noSession;
    sesja.touch();
    return _seal(sesja, await _answerChunk(chunk));
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
    if (grant == null ||
        grant.expired ||
        grant.peerGuid != chunk.from.guid ||
        grant.id != chunk.id ||
        grant.token != chunk.token) {
      return _chunkReply(chunk, ok: false, reason: historyNoGrant);
    }
    grant.lastUsed = DateTime.now();
    final pierwszyRaz = !grant.seqs.contains(chunk.seq);

    // Zgoda obowiązuje w granicach zapowiedzi: tyle wiadomości, tyle plików
    // i tyle bajtów, ile stało na karcie.
    if (pierwszyRaz) {
      var bajty = 0;
      var nowePliki = 0;
      for (final item in chunk.items) {
        if (!item.fileFollows || grant.files.containsKey(item.messageGuid)) {
          continue;
        }
        nowePliki++;
        bajty += item.fileSize ?? 0;
      }
      if (grant.messages + chunk.items.length > grant.summary.count ||
          grant.files.length + nowePliki > grant.summary.files ||
          grant.fileBytes + bajty > grant.summary.bytes) {
        return _chunkReply(chunk, ok: false, reason: historyOverLimit);
      }
      grant.seqs.add(chunk.seq);
      grant.messages += chunk.items.length;
      grant.fileBytes += bajty;
      for (final item in chunk.items) {
        if (item.fileFollows) {
          grant.files[item.messageGuid] =
              (name: item.fileName!, size: item.fileSize ?? 0);
        }
      }
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
    if (pierwszyRaz) {
      grant.imported += wynik.imported;
      grant.skipped += wynik.skipped;
    }
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

  /// Zapowiedź pliku z historii [FileOffer.history]. Zwraca odpowiedź albo
  /// null, gdy zapowiedź do żadnej zgody nie pasuje i ma pójść zwykłą drogą
  /// (z pytaniem). Wpuszczamy wyłącznie plik zapowiedziany w paczce, pod tą
  /// samą nazwą i z tym samym rozmiarem, i tylko do wpisu, który na niego
  /// czeka.
  Future<FileOfferReply?> fileOffer(FileOffer offer) async {
    final grant = _grant;
    if (grant == null ||
        grant.expired ||
        grant.peerGuid != offer.from.guid ||
        grant.id != offer.history) {
      return null;
    }
    final zapowiedziany = grant.files[offer.messageGuid];
    if (zapowiedziany == null ||
        zapowiedziany.name != offer.fileName ||
        zapowiedziany.size != offer.fileSize) {
      return null;
    }
    grant.lastUsed = DateTime.now();
    final czeka = await _s.db.restoredFileAwaiting(offer.messageGuid);
    if (czeka == null) {
      // Wpis ma już plik (przetrwał na dysku albo dojechał wcześniej).
      if (await _s.db.messageByGuid(offer.messageGuid) != null) {
        _fileDone(grant);
        return const FileOfferReply(accepted: true, alreadyHave: true);
      }
      return null;
    }
    return FileOfferReply(accepted: true, resumeFrom: _s._resumableBytes(offer));
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
      _fileDone(grant);
    }
  }

  void _fileDone(_HistoryGrant grant) {
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
  /// pasek pokazuje wynik, zanim zniknie.
  void _endGrant({bool finished = false}) {
    final grant = _grant;
    _grant = null;
    if (grant == null) return;
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

  /// Pasek „Przywrócono" po zakończeniu zamyka użytkownik.
  void dismissIncoming() {
    if (incoming.value?.finished ?? false) _set(incoming, null);
  }

  void forgetPeer(String guid) {
    if (_grant?.peerGuid == guid) _endGrant();
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
    _closed = true;
    _grant = null;
    pending.dispose();
    outgoing.dispose();
    incoming.dispose();
  }
}
