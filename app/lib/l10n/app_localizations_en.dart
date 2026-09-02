// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Chatt';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get confirm => 'Confirm';

  @override
  String get close => 'Close';

  @override
  String get copy => 'Copy';

  @override
  String errorWithDetails(Object details) {
    return 'Error: $details';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get nearbyButton => 'Nearby';

  @override
  String get noConversationsTitle => 'No conversations yet';

  @override
  String get noConversationsBody =>
      'Find devices on the same Wi-Fi network with the “Nearby” button and send your first message.';

  @override
  String deleteConversationTitle(Object name) {
    return 'Delete the conversation with $name?';
  }

  @override
  String get deleteConversationBody =>
      'The messages and the device itself will disappear from your list. Received files stay on disk.';

  @override
  String conversationDeleted(Object name) {
    return 'Deleted the conversation with $name';
  }

  @override
  String get nearbyTitle => 'Nearby devices';

  @override
  String get addByAddress => 'Add by IP address';

  @override
  String scanRunning(int count) {
    return 'Searching… ($count found)';
  }

  @override
  String get scanStart => 'Search the network';

  @override
  String get scanNothingFound =>
      'No devices found. Check that Chatt is running on the other device on the same network, or add it manually by address.';

  @override
  String scanFound(int count) {
    return 'Found: $count';
  }

  @override
  String get noKnownDevices => 'You don\'t know any devices yet.';

  @override
  String get longPressToDelete => 'Press and hold a device to remove it';

  @override
  String lastSeen(Object when) {
    return 'seen $when';
  }

  @override
  String deleteDeviceTitle(Object name) {
    return 'Delete $name?';
  }

  @override
  String get deleteDeviceBody =>
      'The device will disappear from the list along with the conversation and its messages. Received files stay on disk.';

  @override
  String deviceDeleted(Object name) {
    return 'Deleted $name';
  }

  @override
  String get manualAddTitle => 'Add a device by address';

  @override
  String get ipLabel => 'IP address';

  @override
  String get ipHint => 'e.g. 192.168.1.20';

  @override
  String get portLabel => 'Port';

  @override
  String get connect => 'Connect';

  @override
  String noChattAtAddress(Object host, int port) {
    return 'No Chatt is answering at $host:$port.';
  }

  @override
  String get peerOnline => 'available';

  @override
  String get peerOffline => 'unavailable';

  @override
  String get pairTooltipPaired => 'Device paired with a code';

  @override
  String get pairTooltip => 'Pair with a PIN code';

  @override
  String get sendFileTooltip => 'Send a file';

  @override
  String get sendTooltip => 'Send';

  @override
  String get messageHint => 'Write a message…';

  @override
  String get notDeliveredRetry => 'Not delivered — retry';

  @override
  String get fileFallbackName => 'file';

  @override
  String get openFile => 'Open';

  @override
  String get showFolder => 'Show folder';

  @override
  String get shareFile => 'Share';

  @override
  String get copyPath => 'Copy path';

  @override
  String get fileGone => 'That file is no longer on disk.';

  @override
  String get fileOpenFailed => 'Could not open the file.';

  @override
  String receivingFile(Object name) {
    return 'Receiving: $name';
  }

  @override
  String get pairCodeTitle => 'Pairing code';

  @override
  String pairCodeBody(Object name, int minutes) {
    return 'Type this code on $name. Valid for $minutes minutes.';
  }

  @override
  String get pairStartFailed =>
      'Could not start pairing — the device is not answering.';

  @override
  String pairRequest(Object name) {
    return '$name wants to pair';
  }

  @override
  String get pairCodeLabel => 'Code from the other device';

  @override
  String get pairChecking => 'Checking…';

  @override
  String pairedWith(Object name) {
    return 'Paired with $name';
  }

  @override
  String get pairWrongCode => 'The code doesn\'t match';

  @override
  String get pairCodeExpired =>
      'The code expired — ask for a new one on the other device';

  @override
  String get pairPeerUnreachable => 'The other device is not answering';

  @override
  String fileOfferTitle(Object name) {
    return '$name wants to send a file';
  }

  @override
  String fileOfferResume(Object size, Object have) {
    return '$size — resuming, you already have $have';
  }

  @override
  String get unpairedWarning =>
      'Device is not paired — anyone can pick that name';

  @override
  String moreFilesWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more files waiting',
      one: '$count more file waiting',
    );
    return '$_temp0';
  }

  @override
  String get reject => 'Reject';

  @override
  String get accept => 'Accept';

  @override
  String get nicknameLabel => 'Your nickname';

  @override
  String get nicknameRequired => 'Enter a nickname';

  @override
  String get welcomeLabel => 'Welcome message';

  @override
  String get welcomeHelper => 'Visible to others when they search';

  @override
  String get portFieldLabel => 'Preferred listening port';

  @override
  String get portRange => 'Port between 1024 and 65535';

  @override
  String get save => 'Save';

  @override
  String get saved => 'Saved.';

  @override
  String get savedRestartNeeded =>
      'Saved. The new port takes effect after restarting the app.';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languagePolish => 'Polish';

  @override
  String get languageEnglish => 'English';

  @override
  String get backgroundListening => 'Background listening';

  @override
  String get batteryExemptOk =>
      'The system does not doze Chatt. Messages and files arrive with the screen off too.';

  @override
  String get batteryOptimizedWarning =>
      'Android dozes Chatt with the screen off and can cut off its network. Without an exemption, messages may not arrive until you open the app.';

  @override
  String get batteryExemptButton => 'Turn off battery optimisation';

  @override
  String get batteryExemptUnavailable =>
      'This device has no battery optimisation screen. Look for it in the system settings.';

  @override
  String get cleanUpDevices => 'Clean up unused devices';

  @override
  String get cleanUpHelp =>
      'Removes devices you have no messages with and haven\'t seen for an hour. Paired devices and conversations are left alone.';

  @override
  String get nothingToCleanUp => 'Nothing to remove.';

  @override
  String cleanedUp(int count) {
    return 'Removed from the list: $count';
  }

  @override
  String get thisDevice => 'This device';

  @override
  String get listeningOn => 'Listening';

  @override
  String get deviceIdentifier => 'Identifier';

  @override
  String listeningPort(int port) {
    return 'port $port';
  }

  @override
  String get manualPairingHint =>
      'Type this address on the other device under “Add by IP address” when automatic discovery doesn\'t work.';

  @override
  String get backgroundServiceTitle => 'Chatt is listening';

  @override
  String get backgroundServiceBody =>
      'Receiving messages and files from this Wi-Fi network';
}
