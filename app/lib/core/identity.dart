/// Tożsamość urządzenia w sieci Chatt.
///
/// [guid] jest generowany raz, przy pierwszym uruchomieniu, i nigdy się nie
/// zmienia — to on identyfikuje rozmówcę, bo adres IP może się zmieniać
/// (DHCP). [tcpPort] to FAKTYCZNY port, na którym nasłuchuje serwer tej
/// instancji (może różnić się od preferowanego z ustawień, gdy tamten był
/// zajęty — np. dwie instancje na jednym komputerze).
class DeviceIdentity {
  final String guid;
  final String name;
  final String welcomeMessage;
  final int tcpPort;

  const DeviceIdentity({
    required this.guid,
    required this.name,
    required this.welcomeMessage,
    required this.tcpPort,
  });

  DeviceIdentity copyWith({String? name, String? welcomeMessage, int? tcpPort}) {
    return DeviceIdentity(
      guid: guid,
      name: name ?? this.name,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
      tcpPort: tcpPort ?? this.tcpPort,
    );
  }

  Map<String, Object?> toJson() => {
        'guid': guid,
        'name': name,
        'welcome': welcomeMessage,
        'tcpPort': tcpPort,
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
    );
  }

  @override
  String toString() => 'DeviceIdentity($name, $guid, :$tcpPort)';
}
