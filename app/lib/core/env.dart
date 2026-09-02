import 'dart:io';

/// Nadpisania konfiguracji przez zmienne środowiskowe — wyłącznie do
/// developmentu i testów na desktopie (uruchamianie kilku instancji na
/// jednej maszynie, testy E2E w kontenerze). Android je ignoruje.
///
///   CHATT_DATA_DIR      — katalog na bazę danych tej instancji
///   CHATT_TCP_PORT      — preferowany port serwera wiadomości
///   CHATT_INSTANCE_NAME — początkowy nick (tylko przy pierwszym starcie)
class ChattEnv {
  static String? get dataDir => _nonEmpty('CHATT_DATA_DIR');

  static int? get tcpPort => int.tryParse(_nonEmpty('CHATT_TCP_PORT') ?? '');

  static String? get instanceName => _nonEmpty('CHATT_INSTANCE_NAME');

  static String? _nonEmpty(String key) {
    final value = Platform.environment[key];
    return (value == null || value.isEmpty) ? null : value;
  }
}
