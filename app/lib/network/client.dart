import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/identity.dart';
import 'bt_transport.dart';
import 'http_transport.dart';
import 'protocol.dart';
import 'transport.dart';

/// Klient do rozmowy z drugim urządzeniem.
///
/// Sam nie wie, czym jadą bajty: bierze [PeerRoute] i oddaje ją transportowi,
/// który tę trasę obsługuje. Serializacja, kody odpowiedzi i znaczenie
/// każdej operacji są te same, co były, gdy istniało tylko HTTP.
class PeerClient {
  final HttpTransport _ip;
  BluetoothTransport? _bluetooth;
  bool _wifiOn = true;

  PeerClient([http.Client? client]) : _ip = HttpTransport(client);

  void Function(PeerRoute route, String path, Object error)? _onStreamError;

  /// Błąd w trakcie strumieniowania pliku, którąkolwiek drogą: ślad
  /// z powodem dla dziennika aplikacji. Sam wynik wysyłki się nie zmienia.
  set onStreamError(
      void Function(PeerRoute route, String path, Object error)? hook) {
    _onStreamError = hook;
    _ip.onStreamError = hook;
    _bluetooth?.onStreamError = hook;
  }

  /// Podpina transport Bluetooth. null odpina: tak wygląda wyłączenie go
  /// w ustawieniach.
  void useBluetooth(BluetoothTransport? transport) {
    _bluetooth = transport;
    transport?.onStreamError = _onStreamError;
  }

  /// Włącza i wyłącza drogę przez sieć lokalną. Wyłączona znaczy, że żadna
  /// trasa IP nie zostanie nawet spróbowana.
  void useWifi(bool on) => _wifiOn = on;

  /// Czy droga przez sieć lokalną jest włączona.
  bool get wifiOn => _wifiOn;

  /// Który transport dowiezie tę trasę. null = żaden, czyli nie ma dokąd
  /// pisać (rozmówca znany tylko po Bluetooth przy wyłączonym Bluetoothcie).
  PeerTransport? transportFor(PeerRoute route) {
    if (_wifiOn && _ip.handles(route)) return _ip;
    final bluetooth = _bluetooth;
    if (bluetooth != null && bluetooth.handles(route)) return bluetooth;
    return null;
  }

  /// Pobiera tożsamość urządzenia pod trasą. Zwraca null, gdy nie odpowiada
  /// albo to nie jest Chatt, służy też jako test obecności i jako „ręczne
  /// dodanie po IP".
  Future<DeviceIdentity?> fetchInfo(
    PeerRoute route, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final reply = await _request(route, 'GET', '/info', timeout: timeout);
    if (reply.status != 200) return null;
    final json = tryDecodeJsonMap(reply.body);
    if (json == null || json['app'] != 'chatt') return null;
    return DeviceIdentity.fromJson(json);
  }

  /// Uścisk dłoni: wysyłamy swoją tożsamość i klucz efemeryczny, dostajemy
  /// numer sesji i klucz drugiej strony. null = nie doszło do skutku.
  Future<HandshakeResult?> handshake({
    required PeerRoute route,
    required Map<String, Object?> payload,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final reply = await _json(route, '/handshake', payload, timeout);
    if (reply.status != 200) return null;
    return HandshakeResult.fromJson(tryDecodeJsonMap(reply.body));
  }

  /// Dostarcza wiadomość. [Delivery.ok] = odbiorca potwierdził zapis (ACK),
  /// [Delivery.noSession] = trzeba powtórzyć uścisk dłoni i spróbować raz
  /// jeszcze (odbiorca się zrestartował albo sesja wygasła).
  Future<Delivery> sendMessage({
    required PeerRoute route,
    required Map<String, Object?> payload,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final reply = await _json(route, '/message', payload, timeout);
    if (reply.status == 409) return Delivery.noSession;
    if (reply.status != 200) return Delivery.failed;
    return tryDecodeJsonMap(reply.body)?['ok'] == true
        ? Delivery.ok
        : Delivery.failed;
  }

  /// Wysyła krok parowania (prośbę albo potwierdzenie kodem).
  Future<PairReply> pair({
    required PeerRoute route,
    required Map<String, Object?> payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final reply = await _json(route, '/pair', payload, timeout);
    if (!reply.reachable) return const PairReply(PairOutcome.unreachable);
    return PairReply.fromJson(tryDecodeJsonMap(reply.body));
  }

  /// Zapowiada plik i czeka na decyzję odbiorcy. Zwraca null, gdy odbiorca
  /// nie odpowiada albo nie zna `/file-offer` (protokół 1), wtedy nadawca
  /// wysyła plik po staremu, bez pytania o zgodę.
  Future<FileOfferReply?> offerFile({
    required PeerRoute route,
    required Map<String, Object?> payload,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final reply = await _json(route, '/file-offer', payload, timeout);
    if (!reply.reachable) return null;
    if (reply.status == 409) return null; // sesja do odnowienia
    final json = tryDecodeJsonMap(reply.body);
    if (json == null) return null; // 404 z routera = starszy odbiorca
    return FileOfferReply.fromJson(json);
  }

  /// Wysyła plik strumieniowo (bez ładowania do pamięci), od bajtu [offset]
  /// (wznowienie przerwanego transferu). [onProgress] dostaje liczbę bajtów
  /// już zapisanych u odbiorcy, licząc te z poprzedniej próby.
  Future<Delivery> sendFile({
    required PeerRoute route,
    required Map<String, String> headers,
    required File file,
    int offset = 0,
    void Function(int sentBytes, int totalBytes)? onProgress,

    /// Przepuszczenie treści przez szyfrowanie. Dostaje strumień z pliku
    /// i bajt, od którego się zaczyna (żeby wznowienie trafiło w to samo
    /// miejsce strumienia klucza). Musi zachować długość.
    Stream<List<int>> Function(Stream<List<int>> data, int startOffset)?
        transform,
  }) async {
    final transport = transportFor(route);
    if (transport == null) return Delivery.failed;
    final reply = await transport.stream(
      route,
      '/file',
      headers: headers,
      file: file,
      offset: offset,
      onProgress: onProgress,
      transform: transform,
    );
    if (reply.status == 409) return Delivery.noSession;
    if (reply.status != 200) return Delivery.failed;
    return tryDecodeJsonMap(reply.body)?['ok'] == true
        ? Delivery.ok
        : Delivery.failed;
  }

  /// Prośba o sesję zdalnej klawiatury (albo jej wycofanie). Odpowiedź jest
  /// zapieczętowana, więc wraca surowa: otwiera ją ten, kto ma klucz sesji.
  /// Limit czasu obejmuje kartę zgody u odbiorcy.
  Future<TransportReply> requestInputSession({
    required PeerRoute route,
    required Map<String, Object?> payload,
    Duration timeout = remoteInputRequestTimeout,
  }) =>
      _json(route, '/input-session', payload, timeout);

  /// Paczka operacji zdalnej klawiatury. Odpowiedź jak przy
  /// [requestInputSession].
  Future<TransportReply> sendInput({
    required PeerRoute route,
    required Map<String, Object?> payload,
    Duration timeout = remoteInputPacketTimeout,
  }) =>
      _json(route, '/input', payload, timeout);

  /// Zapowiedź historii, prośba o nią, jej koniec albo przerwanie. Odpowiedź
  /// jest zapieczętowana i wraca surowa, jak przy [requestInputSession].
  /// Limit czasu obejmuje kartę zgody u drugiej strony.
  Future<TransportReply> historyOffer({
    required PeerRoute route,
    required Map<String, Object?> payload,
    Duration timeout = historyRequestTimeout,
  }) =>
      _json(route, '/history-offer', payload, timeout);

  /// Paczka wiadomości udostępnianej historii.
  Future<TransportReply> historyChunk({
    required PeerRoute route,
    required Map<String, Object?> payload,
    Duration timeout = historyChunkTimeout,
  }) =>
      _json(route, '/history-chunk', payload, timeout);

  Future<TransportReply> _json(
    PeerRoute route,
    String path,
    Map<String, Object?> payload,
    Duration timeout,
  ) =>
      _request(
        route,
        'POST',
        path,
        headers: {'content-type': 'application/json'},
        body: utf8.encode(jsonEncode(payload)),
        timeout: timeout,
      );

  Future<TransportReply> _request(
    PeerRoute route,
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int> body = const [],
    required Duration timeout,
  }) async {
    final transport = transportFor(route);
    if (transport == null) return const TransportReply.unreachable();
    return transport.request(
      route,
      method,
      path,
      headers: headers,
      body: body,
      timeout: timeout,
    );
  }

  void dispose() {
    unawaited(_ip.dispose());
  }
}
