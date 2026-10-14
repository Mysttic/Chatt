import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/background_service.dart';
import '../core/remote_input.dart';
import '../l10n/app_localizations.dart';
import '../services/app_services.dart';

/// Dodatek klawiatury na Androidzie poza ekranami aplikacji.
///
/// Przez całą zgodę pasek klawiatury Chatt i stałe powiadomienie mówią, kto
/// pisze i dokąd. Zgoda kliknięta na karcie pokazuje okno wyboru klawiatury
/// (gdy Chatt nie jest bieżącą) i chowa aplikację, żeby było widać pole, do
/// którego pójdzie pisanie. Zgoda bez karty („nie pytaj więcej") zostawia
/// powiadomienie „Przełącz klawiaturę na Chatt". Karta, która przyszła przy
/// zamkniętym oknie, daje znać powiadomieniem.
///
/// Przy wyłączonym dodatku nic z tego się nie dzieje, bo nie ma ani zgody,
/// ani kart.
class RemoteInputMobile {
  final AppServices services;
  final AppLocalizations? Function() texts;

  /// Czy aplikacja jest na wierzchu.
  final bool Function() appInFront;
  final Future<bool> Function({required String text, required String stop})
      showIndicator;
  final Future<bool> Function() hideIndicator;
  final Future<bool> Function() afterAccept;
  final Future<bool> Function({required String title, required String body})
      notifySwitchKeyboard;
  final Future<void> Function(
      {required String title, required String body, required int id}) notify;

  RemoteInputMobile(
    this.services, {
    required this.texts,
    bool Function()? appInFront,
    Future<bool> Function({required String text, required String stop})?
        showIndicator,
    Future<bool> Function()? hideIndicator,
    Future<bool> Function()? afterAccept,
    Future<bool> Function({required String title, required String body})?
        notifySwitchKeyboard,
    Future<void> Function(
            {required String title, required String body, required int id})?
        notify,
  })  : appInFront = appInFront ??
            (() =>
                WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed),
        showIndicator = showIndicator ?? RemoteInputChannel.showIndicator,
        hideIndicator = hideIndicator ?? RemoteInputChannel.hideIndicator,
        afterAccept = afterAccept ?? RemoteInputChannel.afterAccept,
        notifySwitchKeyboard =
            notifySwitchKeyboard ?? RemoteInputChannel.notifySwitchKeyboard,
        notify = notify ?? BackgroundService.notifyMessage;

  /// Powiadomienie o karcie ma stały numer: kolejna prośba je podmienia.
  static const int requestNotificationId = 7300;

  String? _shown;
  String? _grantOf;
  final Set<String> _announced = {};
  Future<void> _queue = Future.value();

  void attach() {
    services.incomingRemoteInput.addListener(_onIncoming);
    services.pendingRemoteInput.addListener(_onPending);
    RemoteInputChannel.listen(onStop: services.stopIncomingRemoteInput);
  }

  void detach() {
    services.incomingRemoteInput.removeListener(_onIncoming);
    services.pendingRemoteInput.removeListener(_onPending);
  }

  /// Zmiana języka: pasek i powiadomienie dostają nowe napisy.
  void refreshTexts() {
    _shown = null;
    _onIncoming();
  }

  /// Ostatnie zmiany doszły do strony natywnej (dla testów).
  Future<void> get settled => _queue;

  void _run(Future<void> Function() krok) {
    _queue = _queue.then((_) => krok()).catchError((Object _) {});
  }

  void _onIncoming() {
    final grant = services.incomingRemoteInput.value;
    final l = texts();
    if (grant == null) {
      _grantOf = null;
      if (_shown == null) return;
      _shown = null;
      _run(hideIndicator);
      return;
    }
    // Początek zgody, nie kolejna paczka tej samej.
    final nowa = _grantOf != '${grant.peerGuid}|${grant.started}';
    _grantOf = '${grant.peerGuid}|${grant.started}';
    if (l == null) return;
    final app = grant.target.appLabel.isNotEmpty
        ? grant.target.appLabel
        : grant.target.app;
    final text = (grant.target.active && app.isNotEmpty)
        ? l.remoteInputBarTarget(grant.peerName, app)
        : l.remoteInputActive(grant.peerName);
    final stop = l.remoteInputStop;
    if (text != _shown) {
      _shown = text;
      _run(() => showIndicator(text: text, stop: stop));
    }
    if (!nowa) return;
    if (appInFront()) {
      // Zgoda kliknięta przed chwilą na karcie: wybór klawiatury (gdy
      // trzeba) i zejście aplikacji na dół.
      _run(afterAccept);
    } else {
      final title = l.remoteInputSwitchTitle;
      final body = l.remoteInputSwitchBody(grant.peerName);
      _run(() => notifySwitchKeyboard(title: title, body: body));
    }
  }

  void _onPending() {
    final prosby = services.pendingRemoteInput.value;
    _announced.removeWhere((id) => !prosby.any((p) => p.id == id));
    final l = texts();
    if (l == null || appInFront()) return;
    for (final prosba in prosby) {
      if (!_announced.add(prosba.id)) continue;
      final title = l.remoteInputRequestTitle(prosba.peerName);
      final body = l.remoteInputRequestBody;
      _run(() => notify(title: title, body: body, id: requestNotificationId));
    }
  }
}
