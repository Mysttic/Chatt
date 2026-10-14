import 'dart:async';
import 'dart:io';

/// Przedrostek adresu radia w polu „skąd przyszło".
///
/// Ta sama zmienna niesie raz adres IP nadawcy, a raz adres jego radia, bo
/// przechodzi przez wszystkie obsługujące zapytania bez zmiany kształtu.
/// Przedrostek jest po to, żeby jedno nie weszło tam, gdzie spodziewane jest
/// drugie: adres radia nie ma prawa trafić do kolumny `Peers.host`.
const String btHostPrefix = 'bt:';

/// Klucz w kontekście żądania shelf, pod którym leży adres radia.
const String contextPeerAddress = 'chatt.bluetooth.peer';

/// Adres radia z pola „skąd", albo null, gdy to zwykłe IP.
String? btAddressOf(String fromHost) =>
    fromHost.startsWith(btHostPrefix) ? fromHost.substring(btHostPrefix.length) : null;

/// Adres radia w jedynej postaci, którą przyjmują obie platformy:
/// `AA:BB:CC:DD:EE:FF`, wielkimi literami.
///
/// Android odrzuca wszystko inne wyjątkiem z `getRemoteDevice`, a użytkownik
/// przepisujący adres z ekranu potrafi pominąć dwukropki albo napisać go
/// małymi literami. Pusty napis znaczy „to nie jest adres".
String normalizeBtAddress(String raw) {
  final hex = raw.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
  if (hex.length != 12) return '';
  return [for (var at = 0; at < 12; at += 2) hex.substring(at, at + 2)].join(':');
}

/// Adres IP z pola „skąd", albo pusty napis, gdy to był Bluetooth.
String ipAddressOf(String fromHost) =>
    fromHost.startsWith(btHostPrefix) ? '' : fromHost;

/// Którą drogą jadą bajty do rozmówcy.
///
/// Chatt ma dwa transporty i oba mogą działać naraz. Wybór nie jest wyborem
/// aplikacji: IP wymaga wspólnej sieci, Bluetooth wymaga bycia obok siebie,
/// więc w danej chwili zwykle działa dokładnie jeden z nich.
enum PeerProtocol { wifi, bluetooth }

/// Gdzie to urządzenie teraz jest.
///
/// Trasa to **tylko podpowiedź**: adres IP zmienia DHCP, a adres
/// Bluetooth bywa inny w zależności od tego, czy urządzenia są sparowane
/// (patrz docs/spike-rfcomm.md). Tożsamością jest i zostaje guid wyprowadzony
/// z klucza publicznego.
sealed class PeerRoute {
  const PeerRoute();

  PeerProtocol get protocol;

  /// Postać do pokazania użytkownikowi i do logów.
  String get label;
}

class IpRoute extends PeerRoute {
  final String host;
  final int port;

  const IpRoute(this.host, this.port);

  @override
  PeerProtocol get protocol => PeerProtocol.wifi;

  @override
  String get label => '$host:$port';

  /// Czy w ogóle jest dokąd pisać. Rozmówca poznany wyłącznie przez Bluetooth
  /// ma tu pusty adres i zerowy port.
  bool get isUsable => host.isNotEmpty && port > 0;

  @override
  bool operator ==(Object other) =>
      other is IpRoute && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => 'IpRoute($label)';
}

class BluetoothRoute extends PeerRoute {
  /// Adres radia w postaci `AA:BB:CC:DD:EE:FF`.
  final String address;

  const BluetoothRoute(this.address);

  @override
  PeerProtocol get protocol => PeerProtocol.bluetooth;

  @override
  String get label => address;

  bool get isUsable => address.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is BluetoothRoute && other.address == address;

  @override
  int get hashCode => address.hashCode;

  @override
  String toString() => 'BluetoothRoute($address)';
}

/// Odpowiedź z drugiej strony, w kształcie, który i tak miała: kod jak
/// w HTTP plus ciało. Transport Bluetooth powtarza te same kody, żeby warstwa
/// wyżej nie musiała wiedzieć, którędy przyszła odpowiedź.
class TransportReply {
  /// -1 znaczy „nie doszło w ogóle": brak trasy, zerwane łącze, upłynął czas.
  final int status;
  final List<int> body;

  const TransportReply(this.status, this.body);

  const TransportReply.unreachable() : status = -1, body = const [];

  bool get reachable => status >= 0;
}

/// Jedna z dróg, którymi bajty docierają do rozmówcy.
///
/// Semantyka jest ta sama, którą Chatt miał od początku: żądanie i odpowiedź
/// dla sześciu operacji plus jeden strumień na plik. Nad tym interfejsem nic
/// nie wie, czym jedzie: uścisk dłoni, koperty, szyfrowanie plików
/// i potwierdzanie tożsamości działają bez zmiany.
abstract class PeerTransport {
  PeerProtocol get protocol;

  /// Czy ten transport umie obsłużyć tę trasę i czy jest teraz włączony.
  bool handles(PeerRoute route);

  /// Zwykłe żądanie z ciałem w pamięci. Metadane wiadomości i zapowiedzi
  /// plików nigdy nie są duże, więc nie ma po co ich strumieniować.
  Future<TransportReply> request(
    PeerRoute route,
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int> body = const [],
    Duration timeout = const Duration(seconds: 5),
  });

  /// Treść pliku: leci strumieniem, bez wczytywania do pamięci.
  /// [onProgress] dostaje liczbę bajtów wypchniętych do tej pory.
  Future<TransportReply> stream(
    PeerRoute route,
    String path, {
    required Map<String, String> headers,
    required File file,
    int offset = 0,
    void Function(int sentBytes, int totalBytes)? onProgress,
    Stream<List<int>> Function(Stream<List<int>> data, int startOffset)?
        transform,
  });

  Future<void> dispose();
}
