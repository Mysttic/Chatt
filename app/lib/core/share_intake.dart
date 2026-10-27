import 'dart:async';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, MissingPluginException, PlatformException;

/// Prośba spoza aplikacji: treść z systemowego okna „Udostępnij" albo skrót
/// rozmowy z ekranu głównego (issue #60).
sealed class OutsideRequest {
  const OutsideRequest();
}

/// Treść udostępniona Chattowi przez inną aplikację.
///
/// Pliki kopiują się w tle od chwili udostępnienia (`ChattShare.kt`). Tu jest
/// tylko ich liczba, kopie oddaje [ShareIntake.files].
class IncomingShare extends OutsideRequest {
  final String id;
  final String? text;
  final int fileCount;

  /// Pliki, których Chatt nie przyjął: zwykła ścieżka zamiast `content://`.
  final int skipped;

  /// Rozmówca stuknięty wprost w oknie systemu (guid). Bez niego rozmowę
  /// wybiera się w Chatcie.
  final String? peerGuid;

  const IncomingShare({
    required this.id,
    this.text,
    this.fileCount = 0,
    this.skipped = 0,
    this.peerGuid,
  });

  bool get hasText => text != null && text!.trim().isNotEmpty;

  /// Nic do wysłania: ani tekstu, ani pliku, który dało się przyjąć.
  bool get isEmpty => !hasText && fileCount == 0;
}

/// Skrót rozmowy stuknięty po przytrzymaniu ikony Chatt.
class OpenConversationRequest extends OutsideRequest {
  final String peerGuid;

  const OpenConversationRequest(this.peerGuid);
}

/// Kopia udostępnionego pliku w katalogu aplikacji, gotowa do wysłania.
class SharedFile {
  final String path;
  final String name;
  final int size;

  const SharedFile({required this.path, required this.name, required this.size});
}

/// Rozmowa pokazywana w oknie „Udostępnij" i po przytrzymaniu ikony Chatt.
class ShareTarget {
  final String peerGuid;
  final String label;

  /// Awatar jako PNG. Bez niego system pokaże ikonę Chatta.
  final Uint8List? icon;

  const ShareTarget({required this.peerGuid, required this.label, this.icon});
}

/// Udostępnianie do Chatta (issue #60), strona Darta kanału `chatt/share`.
///
/// Kanał jest tylko na Androidzie. Gdzie indziej (Windows, testy) każde
/// wywołanie odpowiada „nic": brak prośby, brak plików, żadnego wyjątku.
class ShareIntake {
  ShareIntake({MethodChannel? channel})
      : _kanal = channel ?? const MethodChannel('chatt/share');

  /// Wspólny dla aplikacji, bo kanał ma jednego słuchacza.
  static final instance = ShareIntake();

  final MethodChannel _kanal;

  /// Ostatnia prośba spoza aplikacji, dopóki ekran rozmów jej nie odbierze.
  final pending = ValueNotifier<OutsideRequest?>(null);

  /// Treść czekająca na „Wyślij" w rozmowie, po identyfikatorze rozmowy.
  final staged = ValueNotifier<Map<int, IncomingShare>>(const {});

  /// Podpina się pod kanał i odbiera to, co przyszło przed startem Darta,
  /// na przykład udostępnienie, które uruchomiło aplikację.
  Future<void> attach() async {
    _kanal.setMethodCallHandler(_odKanalu);
    await _odbierz();
  }

  Future<Object?> _odKanalu(MethodCall call) async {
    if (call.method == 'incoming') await _odbierz();
    return null;
  }

  Future<void> _odbierz() async {
    final Map<String, Object?>? surowa;
    try {
      surowa = await _kanal.invokeMapMethod<String, Object?>('take');
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
    final prosba = surowa == null ? null : requestFrom(surowa);
    if (prosba == null) return;
    // Nieodebrana starsza treść przepada: ekran pokazuje tylko najnowszą.
    final starsza = pending.value;
    if (starsza is IncomingShare) unawaited(discard(starsza.id));
    pending.value = prosba;
  }

  /// Zapowiedź z kanału. `null`, gdy nie wiadomo, o co chodzi.
  @visibleForTesting
  static OutsideRequest? requestFrom(Map<String, Object?> raw) {
    switch (raw['kind']) {
      case 'share':
        final id = raw['id'];
        if (id is! String) return null;
        final peer = raw['peer'];
        return IncomingShare(
          id: id,
          text: raw['text'] as String?,
          fileCount: (raw['count'] as int?) ?? 0,
          skipped: (raw['skipped'] as int?) ?? 0,
          peerGuid: peer is String && peer.isNotEmpty ? peer : null,
        );
      case 'open':
        final peer = raw['peer'];
        return peer is String && peer.isNotEmpty
            ? OpenConversationRequest(peer)
            : null;
    }
    return null;
  }

  /// Kopie plików treści [id]. Czeka, aż kopiowanie się skończy. Plik,
  /// którego aplikacja źródłowa nie oddała, w liście się nie pojawia.
  Future<List<SharedFile>> files(String id) async {
    try {
      final lista = await _kanal
          .invokeListMethod<Map<Object?, Object?>>('files', {'id': id});
      return [
        for (final plik in lista ?? const <Map<Object?, Object?>>[])
          if (plik['path'] is String)
            SharedFile(
              path: plik['path'] as String,
              name: (plik['name'] as String?) ?? '',
              size: (plik['size'] as int?) ?? 0,
            ),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Rezygnacja z treści [id]: kopie plików idą do kosza.
  Future<void> discard(String id) => _wywolaj('discard', {'id': id});

  /// Pliki treści [id] poszły do rozmowy: kopie zostają przy wiadomościach.
  Future<void> keep(String id) => _wywolaj('keep', {'id': id});

  /// Rozmowy do okna „Udostępnij", od pierwszej. Lista zastępuje poprzednią.
  Future<bool> setTargets(List<ShareTarget> targets) async {
    try {
      return await _kanal.invokeMethod<bool>('setTargets', {
            'targets': [
              for (final cel in targets)
                {'id': cel.peerGuid, 'label': cel.label, 'icon': cel.icon},
            ],
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Wysłana wiadomość: rozmowa idzie w górę w podpowiedziach systemu.
  Future<void> reportUsed(String peerGuid) =>
      _wywolaj('reportUsed', {'id': peerGuid});

  /// Treść czeka w rozmowie [conversationId] na „Wyślij". Inna treść, która
  /// czekała tam wcześniej, przepada.
  void stage(int conversationId, IncomingShare share) {
    final wczesniejsza = staged.value[conversationId];
    if (wczesniejsza != null && wczesniejsza.id != share.id) {
      unawaited(discard(wczesniejsza.id));
    }
    staged.value = {...staged.value, conversationId: share};
  }

  /// Zabiera treść czekającą w rozmowie, jeśli jest.
  IncomingShare? takeStaged(int conversationId) {
    final share = staged.value[conversationId];
    if (share == null) return null;
    staged.value = {...staged.value}..remove(conversationId);
    return share;
  }

  Future<void> _wywolaj(String metoda, Map<String, Object?> argumenty) async {
    try {
      await _kanal.invokeMethod<void>(metoda, argumenty);
    } on PlatformException {
      // Kopia, której nie ma, i skrót, którego system nie przyjął, niczego
      // nie psują: najwyżej plik w cache poczeka na sprzątanie systemu.
    } on MissingPluginException {
      // Brak kanału poza Androidem.
    }
  }
}
