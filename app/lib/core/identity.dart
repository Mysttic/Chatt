import 'dart:convert';

/// Tożsamość urządzenia w sieci Chatt.
///
/// Od protokołu 5 urządzeniem jest **klucz**, a nie losowy napis: [guid] jest
/// liczony ze skrótu [publicKey] (patrz `ChattCrypto.guidFromPublicKey`), więc
/// nie da się podać cudzego identyfikatora bez jego klucza prywatnego. Adres IP
/// może się zmieniać (DHCP), tożsamość nie.
///
/// [tcpPort] to FAKTYCZNY port, na którym nasłuchuje serwer tej instancji (może
/// różnić się od preferowanego z ustawień, gdy tamten był zajęty, np. dwie
/// instancje na jednym komputerze).
class DeviceIdentity {
  final String guid;
  final String name;
  final String welcomeMessage;
  final int tcpPort;

  /// Klucz publiczny X25519. Rozgłaszamy go w discovery i w `GET /info`, żeby
  /// druga strona mogła zaszyfrować już pierwszą wiadomość, bez rundy
  /// „przywitajmy się jawnie". Pusty tylko wtedy, gdy po drugiej stronie stoi
  /// wersja sprzed protokołu 5.
  final List<int> publicKey;

  const DeviceIdentity({
    required this.guid,
    required this.name,
    required this.welcomeMessage,
    required this.tcpPort,
    this.publicKey = const [],
  });

  bool get hasKey => publicKey.isNotEmpty;

  DeviceIdentity copyWith({
    String? name,
    String? welcomeMessage,
    int? tcpPort,
    List<int>? publicKey,
  }) {
    return DeviceIdentity(
      guid: guid,
      name: name ?? this.name,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
      tcpPort: tcpPort ?? this.tcpPort,
      publicKey: publicKey ?? this.publicKey,
    );
  }

  Map<String, Object?> toJson() => {
        'guid': guid,
        'name': name,
        'welcome': welcomeMessage,
        'tcpPort': tcpPort,
        if (hasKey) 'key': base64.encode(publicKey),
      };

  static DeviceIdentity? fromJson(Object? json) {
    if (json is! Map) return null;
    final guid = json['guid'];
    final name = json['name'];
    final tcpPort = json['tcpPort'];
    if (guid is! String || guid.isEmpty || name is! String || tcpPort is! int) {
      return null;
    }
    return DeviceIdentity(
      guid: guid,
      name: name,
      welcomeMessage: json['welcome'] is String ? json['welcome'] as String : '',
      tcpPort: tcpPort,
      publicKey: decodeKey(json['key']),
    );
  }

  /// Klucz publiczny z pola JSON. Pusta lista = brak klucza albo śmieci;
  /// X25519 ma zawsze 32 bajty, więc wszystko inne odrzucamy tutaj, a nie
  /// dopiero przy uzgodnieniu.
  static List<int> decodeKey(Object? value) {
    if (value is! String || value.isEmpty) return const [];
    try {
      final bytes = base64.decode(value);
      return bytes.length == 32 ? bytes : const [];
    } catch (_) {
      return const [];
    }
  }

  @override
  String toString() => 'DeviceIdentity($name, $guid, :$tcpPort)';
}
