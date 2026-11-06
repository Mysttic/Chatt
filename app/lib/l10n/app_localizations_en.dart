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
  String get pickConversation => 'Pick a conversation from the list';

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
  String get nearbyBeforeScan =>
      'Search the network to see which devices answer right now.';

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
  String get copied => 'Copied';

  @override
  String get securityNoEncryptionTitle => 'No encryption';

  @override
  String get securityNoEncryptionBody =>
      'The other side runs an older version of Chatt that cannot encrypt. This conversation will not work until you update it.';

  @override
  String get securityEncryptedTitle => 'Encrypted, identity unconfirmed';

  @override
  String get securityEncryptedBody =>
      'Nobody on the network can read this conversation. You have no confirmation yet that the other side is who you think: anyone can pick a device name.';

  @override
  String get securityVerifiedTitle => 'Encrypted and confirmed';

  @override
  String get securityVerifiedBody =>
      'You compared a code, so it is known who the key on the other side belongs to.';

  @override
  String get fingerprintMine => 'This device\'s fingerprint';

  @override
  String fingerprintOf(Object name) {
    return '$name\'s fingerprint';
  }

  @override
  String get fingerprintHelp =>
      'The fingerprint comes from the device key and never changes. Read it out loud and check the other side sees the same. If it does, nobody is in the middle.';

  @override
  String get peerOnline => 'available';

  @override
  String get peerOffline => 'unavailable';

  @override
  String get shieldNoEncryption =>
      'No encryption: the other side runs an older version';

  @override
  String get shieldEncrypted =>
      'Encrypted, identity unconfirmed. Tap to compare a code';

  @override
  String get shieldVerified => 'Encrypted and confirmed';

  @override
  String get pairTooltip => 'Pair by comparing a code';

  @override
  String get sendFileTooltip => 'Send a file';

  @override
  String get sendTooltip => 'Send';

  @override
  String get messageHint => 'Write a message…';

  @override
  String get notDeliveredRetry => 'Not delivered, retry';

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
  String get saveFile => 'Save to device';

  @override
  String get saveFileHint =>
      'A copy in Pictures or Downloads, outside the app folder';

  @override
  String savedTo(Object where) {
    return 'Saved to $where';
  }

  @override
  String get saveFailed => 'Could not save the file.';

  @override
  String get saveUnsupported =>
      'This system has nowhere to save the file without extra permissions. Use “Share”.';

  @override
  String get fileGone => 'That file is no longer on disk.';

  @override
  String get fileOpenFailed => 'Could not open the file.';

  @override
  String get imageLoadFailed => 'Could not load the image.';

  @override
  String get rotate => 'Rotate';

  @override
  String receivingFile(Object name) {
    return 'Receiving: $name';
  }

  @override
  String get pairStartFailed =>
      'Could not start pairing: the device is not answering.';

  @override
  String get pairAgainWarning =>
      'This device\'s identity is already confirmed. Anyone can send this request under the same name, so only confirm if you asked for it yourself.';

  @override
  String pairRequest(Object name) {
    return '$name wants to pair';
  }

  @override
  String get qrShowTitle => 'Show QR code';

  @override
  String get qrShowBody =>
      'Scan this code with the other device. The code holds no secret. What counts is that the other device saw it on this screen.';

  @override
  String get qrOtherAddress => 'Another address';

  @override
  String get qrScanTitle => 'Scan QR code';

  @override
  String get qrScanHint => 'Point at the code shown on the other device';

  @override
  String get qrScanFailed =>
      'No device with that key answers at the address from the code. It may be out of date, so show it again.';

  @override
  String pairScannedTitle(Object name) {
    return '$name scanned the code from this screen';
  }

  @override
  String get pairScannedBody =>
      'Confirm only if it was you scanning just now. Someone else could have seen the code on screen, and the app cannot tell the difference.';

  @override
  String get pairScannedConfirm => 'That was me';

  @override
  String get pairCompareHint =>
      'Check that the other device shows the same code:';

  @override
  String get pairCodesMatch => 'They match';

  @override
  String get pairCodesDiffer => 'They differ';

  @override
  String get pairChecking => 'Waiting…';

  @override
  String pairedWith(Object name) {
    return 'Paired with $name';
  }

  @override
  String get pairRejected => 'The other device cancelled pairing';

  @override
  String get pairCodeExpired => 'Pairing expired, start again';

  @override
  String get pairPeerUnreachable => 'The other device is not answering';

  @override
  String get dropFilesHint => 'Drop the files to send them';

  @override
  String get attachFromDevice => 'A file from this device';

  @override
  String get attachFromClipboard => 'Paste from the clipboard';

  @override
  String get pasteNothing => 'Nothing could be taken from the clipboard';

  @override
  String get pastedImageName => 'image.png';

  @override
  String get copyText => 'Copy text';

  @override
  String get deleteMessage => 'Delete message';

  @override
  String get deleteMessageHint => 'It disappears from this device only';

  @override
  String get messageDeleted => 'Message deleted from this device';

  @override
  String get searchTooltip => 'Search this conversation';

  @override
  String get searchHint => 'Search this conversation…';

  @override
  String get searchConversationsTooltip => 'Search conversations';

  @override
  String get searchConversationsHint => 'Search conversations…';

  @override
  String searchNothingFound(Object query) {
    return 'Nothing matches “$query”';
  }

  @override
  String fileOfferTitle(Object name) {
    return '$name wants to send a file';
  }

  @override
  String fileOfferResume(Object size, Object have) {
    return '$size, resuming: you already have $have';
  }

  @override
  String get unpairedWarning =>
      'Identity unconfirmed: anyone can pick that name';

  @override
  String fileOfferBatchTitle(Object name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'wants to send $count files',
      one: 'wants to send $count file',
    );
    return '$name $_temp0';
  }

  @override
  String get acceptAll => 'Accept all';

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
  String get background => 'Background';

  @override
  String get backgroundNone => 'No background';

  @override
  String get backgroundDusk => 'Dusk';

  @override
  String get backgroundOcean => 'Ocean';

  @override
  String get backgroundForest => 'Forest';

  @override
  String get backgroundSand => 'Sand';

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
  String get privacy => 'Privacy';

  @override
  String get dbKeyProtected =>
      'The history on disk is encrypted and the key is held by the system keystore. Copying the database file alone gets you nothing.';

  @override
  String get dbKeyUnprotected =>
      'The history is encrypted, but the system keystore refused to hold the key, so it sits next to the database. That protects the database file alone; a copy of the whole app directory carries the key with it.';

  @override
  String get retentionLabel => 'Delete messages older than';

  @override
  String get retentionNever => 'Never delete';

  @override
  String retentionDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
    );
    return '$_temp0';
  }

  @override
  String get retentionHelp =>
      'This deletes entries in conversations and the typing history. Received files stay on disk.';

  @override
  String get clearHistory => 'Clear history';

  @override
  String get clearHistoryTitle => 'Clear the entire history?';

  @override
  String get clearHistoryBody =>
      'All messages, conversations and the typing history disappear. Devices keep their confirmed identity, and received files stay on disk.';

  @override
  String historyCleared(int count) {
    return 'Messages deleted: $count';
  }

  @override
  String get links => 'Links';

  @override
  String get linkPreviewsLabel => 'Show link previews';

  @override
  String get linkPreviewsHelp =>
      'A card with the page\'s title, description and image appears under a link in the conversation. To fetch it the app connects to that page, so its server sees this device\'s IP address and the moment the message arrived. Off by default.';

  @override
  String get linkPreviewsSafety =>
      'A preview is text and one image, nothing more. The app does not open the page, runs no scripts from it, and fetches no previews from addresses on your local network. Tapping a link always asks first.';

  @override
  String linkPreviewOf(Object site) {
    return 'Page preview: $site';
  }

  @override
  String get linkConfirmTitle => 'Are you sure you want to go to this page?';

  @override
  String get linkConfirmHost => 'This link goes to';

  @override
  String get linkConfirmFull => 'Full address';

  @override
  String get linkOpen => 'Open';

  @override
  String get linkOpenTitle => 'Open link';

  @override
  String get linkCopy => 'Copy address';

  @override
  String get linkCopied => 'Address copied.';

  @override
  String get linkOpenFailed => 'Could not open the browser.';

  @override
  String get linkWarnUserInfo =>
      'There is an @ in the address: what you see before it is not the server name. The name shown above is the one that counts.';

  @override
  String get linkWarnNonAscii =>
      'The server name contains letters from outside the Latin alphabet. They can be indistinguishable from ordinary ones and lead somewhere else.';

  @override
  String get linkWarnInsecure =>
      'Unencrypted connection (http). Anyone on the same network can read the page and alter it.';

  @override
  String get linkWarnLocal =>
      'The address points to a device on your local network, a router for instance.';

  @override
  String get updates => 'Updates';

  @override
  String get updateChecksLabel => 'Check for updates automatically';

  @override
  String get updateChecksHelp =>
      'Once a day Chatt asks GitHub whether a newer release is out. It is the only thing the app sends outside your own network, and it stays off until you turn it on.';

  @override
  String get updateCheckNow => 'Check now';

  @override
  String get updateChecking => 'Checking…';

  @override
  String get updateUpToDate => 'This is the newest release.';

  @override
  String updateAvailable(Object version) {
    return 'Version $version is out';
  }

  @override
  String get updateDownload => 'Download and install';

  @override
  String updateDownloading(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get updatePortableHint =>
      'This copy runs from the zip, so a new one has to be unpacked by hand. The release page:';

  @override
  String get updateNoAsset =>
      'This release has no file for this platform. The release page:';

  @override
  String get updateInstallFailed => 'Could not start the installer.';

  @override
  String get updateDownloadFailed => 'Could not download the file.';

  @override
  String get updateClosingForInstall =>
      'Chatt closes now and the installer takes over.';

  @override
  String updateLastChecked(Object when) {
    return 'Last checked $when';
  }

  @override
  String get thisDevice => 'This device';

  @override
  String get version => 'Version';

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
  String get windowsSection => 'Windows';

  @override
  String get startWithWindows => 'Start with Windows';

  @override
  String get startWithWindowsHelp =>
      'Chatt starts after you log in and goes straight to the tray, so messages arrive without opening the window.';

  @override
  String get startWithWindowsFailed =>
      'Could not change the autostart setting.';

  @override
  String get trayHint =>
      'Closing the window hides Chatt in the tray and does not stop it listening. Quitting is in the tray icon menu.';

  @override
  String get trayTooltip => 'Chatt: listening on the local network';

  @override
  String get trayShow => 'Show Chatt';

  @override
  String get trayQuit => 'Quit Chatt';

  @override
  String get backgroundServiceTitle => 'Chatt is listening';

  @override
  String get backgroundServiceBody =>
      'Receiving messages and files from this Wi-Fi network';

  @override
  String get copyImage => 'Copy image';

  @override
  String get imageCopied => 'Image copied to the clipboard';

  @override
  String get imageCopyFailed => 'Could not copy the image';

  @override
  String get renamePeer => 'Rename';

  @override
  String get renamePeerTitle => 'Your name for this device';

  @override
  String get renamePeerHelp =>
      'The name stays on this device and is never sent anywhere. Leave the field empty to go back to the name the device broadcasts.';

  @override
  String peerRenamed(String name) {
    return 'Now called $name';
  }

  @override
  String get peerRenameCleared => 'Back to the broadcast name';

  @override
  String broadcastName(String name) {
    return 'Broadcast name: $name';
  }

  @override
  String get autoAcceptTitle => 'Accept files without asking';

  @override
  String get autoAcceptBody =>
      'Files from this device land in the conversation straight away, with no consent card. It works only with a confirmed identity, and the switch goes off by itself if the confirmation ever goes away.';

  @override
  String get autoAcceptNeedsVerified => 'Confirm the identity first';

  @override
  String get selectText => 'Select text';

  @override
  String get selectTextHint => 'Press and hold to select part of it';

  @override
  String get discoveryDeaf =>
      'This device does not answer scans. Others will find it only by adding its address by hand. The usual cause is another program holding port 47777.';

  @override
  String get addons => 'Add-ons';

  @override
  String get transportWifi => 'Local network';

  @override
  String get transportInternet => 'Internet';

  @override
  String get transportBluetooth => 'Bluetooth';

  @override
  String get transportBluetoothUnsupported =>
      'Chatt has no Bluetooth on this system.';

  @override
  String get transportBluetoothRadioOff =>
      'Turn Bluetooth on in the system settings.';

  @override
  String get transportBluetoothNoPermission =>
      'Chatt has no permission for nearby devices.';

  @override
  String get transportBluetoothGrant => 'Open settings';

  @override
  String get transportBluetoothFailed => 'Bluetooth would not start.';

  @override
  String get transportBothOff =>
      'The network is off and Bluetooth is not running: this device will reach nobody.';

  @override
  String get transportBluetoothDiscoverable =>
      'While the add-on is on, this PC is visible to nearby devices. It goes away with the switch.';

  @override
  String get keyboardAddon => 'Keyboard from a PC';

  @override
  String get remoteInputReceive => 'Allow typing on this device';

  @override
  String get remoteInputSafety =>
      'The other device types here like an ordinary keyboard: it can send a message, submit a form, enter a password. A session lasts until Stop or half an hour without typing.';

  @override
  String get remoteInputUnsupported =>
      'Typing from another device works on Android and Windows.';

  @override
  String remoteInputRequestTitle(Object name) {
    return '$name wants to type on this device';
  }

  @override
  String get remoteInputRequestBody =>
      'Text goes into the field that has focus, in any app, until Stop.';

  @override
  String remoteInputActive(Object name) {
    return 'Typing: $name';
  }

  @override
  String get remoteInputStop => 'Stop';

  @override
  String remoteInputBarTarget(Object name, Object app) {
    return 'Typing: $name → $app';
  }

  @override
  String get trayRemoteInputStop => 'Stop remote keyboard';

  @override
  String get remoteInputSwitchTitle => 'Switch the keyboard to Chatt';

  @override
  String remoteInputSwitchBody(Object name) {
    return '$name is typing on this device. Tap and pick the Chatt keyboard.';
  }

  @override
  String get remoteInputImeOff =>
      'Typing from another device goes through the Chatt keyboard. Turn it on once in the system settings.';

  @override
  String get remoteInputImeWarning =>
      'Android will warn that a keyboard can collect what you type. The Chatt keyboard sends nothing from your fields: it types what comes from the device you allow to type.';

  @override
  String get remoteInputImeEnable => 'Turn on the Chatt keyboard';

  @override
  String get remoteInputImeNotSelected =>
      'Pick the Chatt keyboard for the time of typing. The previous one comes back after the session.';

  @override
  String get remoteInputImePick => 'Pick keyboard';

  @override
  String get remoteInputImeReady => 'The Chatt keyboard is on.';

  @override
  String get remoteInputDontAskAgain => 'Don\'t ask again for this device';

  @override
  String remoteInputBannerTarget(Object name, Object app) {
    return '$name is typing into $app';
  }

  @override
  String get remoteInputAllowTitle => 'Typing without asking';

  @override
  String get remoteInputAllowBody =>
      'This device starts typing here without the consent card. The Typing bar with Stop shows as always. It works only with a confirmed identity and with typing allowed in the Keyboard from a PC add-on.';

  @override
  String get remoteKeyboardOpen => 'Type on that device';

  @override
  String get remoteKeyboardNeedsVerified =>
      'Typing on that device needs a confirmed identity';

  @override
  String remoteKeyboardTitle(Object name) {
    return 'Typing on $name';
  }

  @override
  String remoteKeyboardWaiting(Object name) {
    return 'Waiting for consent on $name. Open Chatt there.';
  }

  @override
  String get remoteKeyboardWaitingHint =>
      'An Android phone shows a notification if Chatt may post notifications.';

  @override
  String remoteKeyboardTarget(Object app) {
    return 'Typing into: $app';
  }

  @override
  String remoteKeyboardTargetPassword(Object app) {
    return 'Typing into: $app · password field';
  }

  @override
  String get remoteKeyboardNoField =>
      'No field to type into. Tap a field on that device; on Android, with the Chatt keyboard picked.';

  @override
  String get remoteKeyboardElevated =>
      'A window running as administrator. Nothing is typed there.';

  @override
  String get remoteKeyboardLocked =>
      'That device is locked or its screen is off.';

  @override
  String get remoteKeyboardPaused =>
      'Paused: a question is waiting on that device. Typing resumes once it is answered.';

  @override
  String get remoteKeyboardLocalCard =>
      'Answer the question at the top, then go on typing.';

  @override
  String remoteKeyboardEnded(Object name) {
    return 'The session was ended on $name.';
  }

  @override
  String get remoteKeyboardLost => 'The connection dropped.';

  @override
  String get remoteKeyboardReconnect => 'Reconnect';

  @override
  String get remoteKeyboardModeLive => 'Live';

  @override
  String get remoteKeyboardModeCompose => 'Compose';

  @override
  String get remoteKeyboardLiveHint =>
      'Type here. Every character goes to that device at once.';

  @override
  String get remoteKeyboardKeysHint =>
      'Enter submits the field, Shift+Enter is a new line, Backspace and Delete delete on that device.';

  @override
  String get remoteKeyboardComposeHint =>
      'Write the text and send it in one go.';

  @override
  String get remoteKeyboardSend => 'Send';

  @override
  String get remoteKeyboardThenEnter => 'Then Enter';

  @override
  String get remoteKeyboardPaste => 'Paste from clipboard';

  @override
  String get remoteKeyboardClipboardEmpty =>
      'There is no text on the clipboard.';

  @override
  String get remoteKeyboardTooLong =>
      'Too much text at once. Send it in parts.';

  @override
  String remoteKeyboardRejected(Object name) {
    return '$name declined.';
  }

  @override
  String remoteKeyboardNotEnabled(Object name) {
    return 'Typing is off on $name. It is turned on in Settings, in the Keyboard from a PC add-on.';
  }

  @override
  String remoteKeyboardNoAnswer(Object name) {
    return '$name did not answer the request.';
  }

  @override
  String remoteKeyboardBusy(Object name) {
    return 'Someone else is already typing on $name.';
  }

  @override
  String remoteKeyboardOlderPeer(Object name) {
    return '$name has an older Chatt, without the remote keyboard.';
  }

  @override
  String remoteKeyboardUnreachable(Object name) {
    return 'Could not reach $name.';
  }

  @override
  String get remoteKeyboardNotVerified =>
      'Confirm this device\'s identity first.';

  @override
  String get remoteKeyboardAddonOff => 'The Keyboard from a PC add-on is off.';

  @override
  String get viaWifi => 'over the network';

  @override
  String get viaBluetooth => 'over Bluetooth';

  @override
  String get viaInternet => 'over the internet';

  @override
  String get protocolWifi => 'Network';

  @override
  String get protocolBluetooth => 'Bluetooth';

  @override
  String get protocolInternet => 'Internet';

  @override
  String get searchWhere => 'Where to look';

  @override
  String get searchBluetoothHint =>
      'Looking over the radio takes up to a minute and a half and slows open conversations down while it runs.';

  @override
  String get searchBluetoothOff =>
      'Bluetooth is not running. Check the radio and the permission in Settings, under Add-ons.';

  @override
  String get searchingBluetooth => 'Looking over Bluetooth…';

  @override
  String get scanStartBluetooth => 'Search over Bluetooth';

  @override
  String get nearbyBeforeScanBluetooth =>
      'Search over Bluetooth to see which devices next to you answer.';

  @override
  String get nearbyScanningBluetooth =>
      'Nothing has answered yet. Devices show up here one by one, as soon as they answer.';

  @override
  String get scanNothingFoundBluetooth =>
      'No devices found over Bluetooth. Check that Chatt is running on the other device with the Bluetooth add-on on, and that it is a few metres away at most. An Android phone has to be shown first: on it, in “Nearby” with Bluetooth picked, tap “Show this phone nearby”. You can also add the device by radio address.';

  @override
  String get searchBluetoothNoLocation =>
      'Android hands out no search results while location services are off. The connection itself does not need them, and Chatt never asks where you are.';

  @override
  String get turnOnLocation => 'Turn location on';

  @override
  String get showThisPhone => 'Show this phone nearby';

  @override
  String get showThisPhoneHint =>
      'Android shows a phone to other devices only when asked. When another device has to find this phone, tap the button, confirm in the system prompt and start the search over there.';

  @override
  String get thisPhoneVisible =>
      'This phone is visible to devices nearby now, for about two minutes. Start the search on the other device.';

  @override
  String get showThisPhoneFailed =>
      'Android did not show the visibility prompt. An open pairing screen in the phone\'s Bluetooth settings does the same.';

  @override
  String get addByBtAddress => 'Add by radio address';

  @override
  String get manualAddBtTitle => 'Add by Bluetooth address';

  @override
  String get manualAddBtHelp =>
      'The other device shows its address in its Bluetooth settings. A PC also shows its own in Chatt\'s Settings, under Add-ons.';

  @override
  String get btAddressLabel => 'Bluetooth address';

  @override
  String get btAddressHint => 'AA:BB:CC:DD:EE:FF';

  @override
  String noChattAtBtAddress(String address) {
    return 'No Chatt answers at $address';
  }

  @override
  String myBtAddress(String address) {
    return 'This radio\'s address: $address';
  }

  @override
  String get historyMenu => 'More';

  @override
  String get historyShare => 'Share history';

  @override
  String get historyRequest => 'Ask for history';

  @override
  String get historyShareTitle => 'Share the conversation\'s history';

  @override
  String historyShareBody(Object name) {
    return '$name gets a copy of your conversation, marked as restored. A card asks them first.';
  }

  @override
  String get historyRangeAll => 'Everything';

  @override
  String historyRangeSince(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Since $dateString';
  }

  @override
  String get historyPickDate => 'Pick a date';

  @override
  String get historyWithFiles => 'With files';

  @override
  String get historyWithoutFiles => 'Without files';

  @override
  String historyCountMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '$count message',
    );
    return '$_temp0';
  }

  @override
  String historyCountFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '$count file',
      zero: 'no files',
    );
    return '$_temp0';
  }

  @override
  String historyRange(DateTime from, DateTime to) {
    final intl.DateFormat fromDateFormat = intl.DateFormat.yMMMd(localeName);
    final String fromString = fromDateFormat.format(from);
    final intl.DateFormat toDateFormat = intl.DateFormat.yMMMd(localeName);
    final String toString = toDateFormat.format(to);

    return 'from $fromString to $toString';
  }

  @override
  String historyMissingFiles(int count) {
    return 'Files no longer here go without content: $count';
  }

  @override
  String get historyNothing =>
      'There is nothing to share in this conversation.';

  @override
  String get historyShareAction => 'Share';

  @override
  String get historyShareDone => 'History shared.';

  @override
  String historyShareRejected(Object name) {
    return '$name declined the history.';
  }

  @override
  String get historyNoAnswer => 'Nobody answered the card on the other side.';

  @override
  String get historyBusy => 'Another history transfer is running. Try later.';

  @override
  String get historyOlderVersion =>
      'That device runs an older Chatt, without history sharing.';

  @override
  String get historyUnreachable => 'That device is not answering.';

  @override
  String get historyCancelled =>
      'Sharing stopped. What arrived stays on the other side.';

  @override
  String get historyFailed =>
      'Sharing failed. Try again: what arrived will not be duplicated.';

  @override
  String get historyRequestSent => 'Request sent, waiting for an answer.';

  @override
  String historyRequestAccepted(Object name) {
    return '$name agreed. The history is on its way.';
  }

  @override
  String historyRequestRejected(Object name) {
    return '$name declined.';
  }

  @override
  String historyRequestEmpty(Object name) {
    return '$name does not have this conversation.';
  }

  @override
  String historyOfferTitle(Object name) {
    return '$name wants to restore your conversation\'s history';
  }

  @override
  String get historyOfferDeleted =>
      'What was deleted here before comes back too.';

  @override
  String get historyOfferMarked =>
      'Restored messages are marked: this is the other side\'s copy, and nothing signs it.';

  @override
  String get historyOfferUnverified =>
      'Identity not confirmed: the history may come from someone posing as this person.';

  @override
  String historyOfferRetention(int days) {
    return 'Messages older than $days days do not come in: that is how long the retention setting keeps them.';
  }

  @override
  String historyRequestTitle(Object name) {
    return '$name asks for your conversation\'s history';
  }

  @override
  String get historyRequestBody =>
      'They get a copy of what this conversation holds here, marked as restored.';

  @override
  String historySharing(Object name) {
    return 'Sharing history: $name';
  }

  @override
  String historyRestoring(Object name) {
    return 'Restoring history from: $name';
  }

  @override
  String historyRestored(Object name) {
    return 'History from $name restored';
  }

  @override
  String historyProgressMessages(int done, int total) {
    return 'Messages: $done of $total';
  }

  @override
  String historyProgressFiles(int done, int total) {
    return 'Files: $done of $total';
  }

  @override
  String historySkipped(int count) {
    return 'Skipped, already here or too old: $count';
  }

  @override
  String get historyStop => 'Stop';

  @override
  String messageRestored(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Restored on $dateString from the other side\'s copy';
  }

  @override
  String get fileUnavailable => 'File not available';

  @override
  String get fileAwaiting => 'Waiting for the file';

  @override
  String get dateToday => 'Today';

  @override
  String get dateYesterday => 'Yesterday';

  @override
  String dateSeparator(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMEEEEd(
      localeName,
    );
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String get historySource => 'From';

  @override
  String get historySourceThis => 'This conversation';

  @override
  String historySourceOther(Object name, int count) {
    return 'Older conversation with: $name ($count)';
  }

  @override
  String get historySourceHint =>
      'After a reinstall or on a new phone the same device comes under a new entry. You can hand over the older conversation with the old entry here.';

  @override
  String get historySourceNeedsShield =>
      'An older conversation with another entry goes only to a device with a green shield. Confirm its identity first.';

  @override
  String get historyMergeLocally =>
      'Merge that conversation into this one here';

  @override
  String get historyNeedsVerified =>
      'Confirm this device\'s identity first (green shield).';

  @override
  String get historyMerged => 'Conversations merged.';

  @override
  String get profileSection => 'Profile';

  @override
  String get styleLabel => 'Style';

  @override
  String get styleCisza => 'Calm';

  @override
  String get stylePrecyzja => 'Precise';

  @override
  String get styleCieplo => 'Warm';

  @override
  String get themeLabel => 'Theme';

  @override
  String get addonBluetoothShort => 'Conversations with no shared Wi-Fi';

  @override
  String get addonInternetShort => 'Conversations across different networks';

  @override
  String get addonInternetBody =>
      'Reach a confirmed device on another network, with no server in between. The connection is found through public STUN servers and the BitTorrent DHT, which see your IP address and when you connect. None of them sees the content. It does not get through every network: a symmetric NAT (Check reachability shows it) or a network that blocks UDP stops it. Off by default.';

  @override
  String get internetAddonExperimental =>
      'Experimental. Works device-to-device by punching through NAT; about seven connections in ten get through.';

  @override
  String get internetBatteryWarning =>
      'To stay reachable, this device keeps listening in the background, checks every minute whether a confirmed device is calling, and refreshes its address every ten minutes. That uses more battery than Wi-Fi alone.';

  @override
  String internetPublicAddressLabel(String address) {
    return 'This device is seen at: $address';
  }

  @override
  String get internetPublicAddressUnknown => 'Public address not known yet.';

  @override
  String get internetCheckNat => 'Check reachability';

  @override
  String get internetNatOpen =>
      'Endpoint-independent NAT: hole punching should work.';

  @override
  String get internetNatSymmetric =>
      'Symmetric NAT: hole punching will usually fail here.';

  @override
  String get internetNatNone => 'No NAT: this device is directly reachable.';

  @override
  String get internetNatUnknown => 'Could not reach the STUN servers.';

  @override
  String get addonKeyboardShort => 'Typing from a computer\'s keyboard';

  @override
  String historyClearedWithTyping(int messages, int sessions) {
    return 'Messages deleted: $messages, typing sessions: $sessions';
  }

  @override
  String get typingHistorySwitch => 'Save typing history';

  @override
  String get typingHistoryHelp =>
      'Saves sessions in both directions on this device: typing from here and typing here. The other device keeps its own history under its own switch. Text typed into password fields and unknown fields stays hidden: only the character count is saved. The history is stored encrypted.';

  @override
  String get typingHistory => 'Typing history';

  @override
  String typingHistoryEntryHelp(int count) {
    return 'Remote keyboard sessions saved on this device: $count. The history screen can clear them.';
  }

  @override
  String get typingHistoryOff =>
      'Saving typing history is turned off. Turn it on in Settings, in the Keyboard from a PC add-on.';

  @override
  String get typingHistoryEmptyTitle => 'No typing history';

  @override
  String get typingHistoryEmptyBody =>
      'Remote keyboard sessions show up here in both directions: this device typing on others, and others typing here.';

  @override
  String get typingHistoryClear => 'Clear typing history';

  @override
  String get typingHistoryClearTitle => 'Clear the typing history?';

  @override
  String get typingHistoryClearBody =>
      'Every saved typing session disappears. Conversations and the app log stay.';

  @override
  String typingHistoryCleared(int count) {
    return 'Typing sessions deleted: $count';
  }

  @override
  String typingHistoryOutgoing(Object name) {
    return 'This device typed on $name';
  }

  @override
  String typingHistoryIncoming(Object name) {
    return '$name typed on this device';
  }

  @override
  String typingHistorySessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions',
      one: '$count session',
    );
    return '$_temp0';
  }

  @override
  String typingHistoryChars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count characters',
      one: '$count character',
    );
    return '$_temp0';
  }

  @override
  String get typingHistoryStarted => 'Started';

  @override
  String get typingHistoryEnded => 'Ended';

  @override
  String get typingHistoryDuration => 'Duration';

  @override
  String get typingHistoryCharsLabel => 'Characters';

  @override
  String get typingHistoryApps => 'Apps';

  @override
  String get typingHistoryRequest => 'Request';

  @override
  String get typingHistoryEndReason => 'End reason';

  @override
  String get typingHistorySessionId => 'Session ID';

  @override
  String get typingHistoryNotEnded => 'End not recorded yet';

  @override
  String get typingHistoryText => 'Rebuilt text';

  @override
  String get typingHistoryTextNote =>
      'Rebuilt from the keys. Hidden fields show as dots.';

  @override
  String get typingHistoryNoText => 'The rebuilt text is empty.';

  @override
  String get typingHistoryTimeline => 'Timeline';

  @override
  String get typingHistoryNoEntries => 'Nothing was typed in this session.';

  @override
  String get typingHistoryHidden => 'Hidden text';

  @override
  String get typingFieldPassword => 'password field';

  @override
  String get typingFieldUnknown => 'unknown field';

  @override
  String get typingKeyEnter => 'Enter';

  @override
  String get typingKeyBackspace => 'Backspace';

  @override
  String get typingKeyDelete => 'Delete';

  @override
  String get typingResultAccepted => 'Accepted on the card';

  @override
  String get typingResultAcceptedAlways =>
      'Accepted on the card, don\'t ask again';

  @override
  String get typingResultAutomatic => 'No card: remembered permission';

  @override
  String get typingResultRejected => 'Rejected';

  @override
  String get typingResultNoAnswer => 'No answer on the card';

  @override
  String get typingResultBusy => 'Busy with another session';

  @override
  String get typingResultNotEnabled =>
      'Typing turned off on the receiving device';

  @override
  String get typingResultCancelled => 'Request withdrawn';

  @override
  String get typingResultUnreachable => 'Could not reach the device';

  @override
  String get typingResultOlderPeer => 'Older Chatt version on the other side';

  @override
  String get typingEndStoppedHere => 'Stopped on this device';

  @override
  String get typingEndStoppedByPeer => 'Stopped by the other side';

  @override
  String get typingEndExpired => 'Permission expired';

  @override
  String get typingEndReceiveOff => 'Typing on this device turned off';

  @override
  String get typingEndAddonOff => 'Keyboard add-on turned off';

  @override
  String get typingEndReplaced => 'Replaced by a new session';

  @override
  String get typingEndPeerRemoved => 'Device removed from the list';

  @override
  String get typingEndNotAllowed => 'Permission withdrawn during the session';

  @override
  String get typingEndLinkLost => 'Connection lost';

  @override
  String get typingEndAppClosed => 'App closed';

  @override
  String get typingStatusTyped => 'Typed';

  @override
  String get typingStatusNotTyped => 'Typed in part or not at all';

  @override
  String get typingStatusPaused => 'Paused: a card was waiting for an answer';

  @override
  String get typingStatusRefused => 'Refused: the permission had already ended';

  @override
  String get typingStatusUnconfirmed => 'Delivery not confirmed';

  @override
  String get typingStatusUnsent => 'Not sent';

  @override
  String get dataSection => 'Data and diagnostics';

  @override
  String get exportData => 'Export data';

  @override
  String get exportDataHelp =>
      'One ZIP file with the data you choose: conversations, devices, settings, typing history, the app log and received files. For keeping or for analysis in another program.';

  @override
  String get exportDataConversations => 'Conversations, devices and settings';

  @override
  String exportDataCountConversations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations',
      one: '$count conversation',
    );
    return '$_temp0';
  }

  @override
  String exportDataCountDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count devices',
      one: '$count device',
    );
    return '$_temp0';
  }

  @override
  String get exportDataFiles => 'Received files';

  @override
  String exportDataWarning(String parts) {
    String _temp0 = intl.Intl.selectLogic(parts, {
      'both': 'The export file is not encrypted and holds message text and typed text.',
      'messages': 'The export file is not encrypted and holds message text.',
      'typing': 'The export file is not encrypted and holds typed text.',
      'other': 'The export file is not encrypted.',
    });
    return '$_temp0 Keep it somewhere safe. This device\'s keys stay out of the export.';
  }

  @override
  String get exportDataReplaceTitle => 'Replace the file?';

  @override
  String exportDataReplaceBody(Object name) {
    return '$name already exists. The export will replace it.';
  }

  @override
  String get exportDataReplace => 'Replace';

  @override
  String get exportDataAction => 'Export';

  @override
  String get exportDataBusy => 'Exporting…';

  @override
  String get exportDataEstimateFailed => 'Could not count the data to export.';

  @override
  String exportDataSaved(Object where) {
    return 'Export saved to $where';
  }

  @override
  String get exportDataDone => 'Export ready.';

  @override
  String get exportDataFailed => 'Could not export the data.';

  @override
  String get exportDataUnsupported =>
      'This system has nowhere to save the export file.';

  @override
  String exportDataSkipped(int count) {
    return 'Files left out: $count';
  }

  @override
  String get appLog => 'App log';

  @override
  String get appLogHelp =>
      'Network, pairing and file events and errors from the last 30 days, for diagnostics. No message text, typed text or keys.';

  @override
  String appLogEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '$count entry',
    );
    return '$_temp0';
  }

  @override
  String get appLogFilterAll => 'All';

  @override
  String get appLogFilterProblems => 'Warnings and errors';

  @override
  String get appLogEmpty => 'The log is empty.';

  @override
  String get appLogEmptyProblems => 'No warnings or errors.';

  @override
  String appLogLimit(int count) {
    return 'Showing the newest entries: $count. The export holds the full log.';
  }

  @override
  String get appLogCopy => 'Copy the entries shown';

  @override
  String get appLogExport => 'Export the log';

  @override
  String get appLogClear => 'Clear the log';

  @override
  String get appLogClearTitle => 'Clear the app log?';

  @override
  String get appLogClearBody =>
      'Every log entry disappears. Conversations and the typing history stay.';

  @override
  String appLogCleared(int count) {
    return 'Log entries deleted: $count';
  }

  @override
  String get appLogDetails => 'Details';

  @override
  String get appLogLevelInfo => 'Info';

  @override
  String get appLogLevelWarning => 'Warning';

  @override
  String get appLogLevelError => 'Error';

  @override
  String get shareSendToTitle => 'Send to';

  @override
  String shareFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '$count file',
    );
    return '$_temp0';
  }

  @override
  String get shareNoConversations =>
      'No conversations yet. Find a device with the “Nearby” button to send this to it.';

  @override
  String sharePreparing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Preparing $count files…',
      one: 'Preparing the file…',
    );
    return '$_temp0';
  }

  @override
  String get shareDontSend => 'Don\'t send';

  @override
  String get shareNothing =>
      'Chatt got nothing it can send: no text and no file it can read.';

  @override
  String shareSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count files left out: Chatt doesn\'t accept files handed over as a plain path.',
      one:
          '$count file left out: Chatt doesn\'t accept files handed over as a plain path.',
    );
    return '$_temp0';
  }

  @override
  String shareFilesMissing(int missing, int total) {
    return 'Couldn\'t read $missing of $total shared files.';
  }

  @override
  String get conversationGone => 'That conversation is gone.';
}
