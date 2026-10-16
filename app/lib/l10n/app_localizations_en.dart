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
      'This deletes entries in conversations. Received files stay on disk.';

  @override
  String get clearHistory => 'Clear history';

  @override
  String get clearHistoryTitle => 'Clear the entire history?';

  @override
  String get clearHistoryBody =>
      'Every message and conversation disappears. Devices keep their confirmed identity, and received files stay on disk.';

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
  String get addonsHelp =>
      'Features most people never need. An add-on that is off stays inside this section: it shows on no other screen and starts nothing.';

  @override
  String get transportsHelp =>
      'Two roads, and both can be on at once. The network is tens of times faster; Bluetooth works with no network at all, as long as the devices are next to each other.';

  @override
  String get transportWifi => 'Local network';

  @override
  String get transportWifiHelp =>
      'Messages and files over Wi-Fi or a cable. Both devices have to be on the same network.';

  @override
  String get transportBluetooth => 'Bluetooth';

  @override
  String get transportBluetoothHelp =>
      'Messages and files over the radio, with no router, no address and no shared network. Tens of times slower than Wi-Fi, so a big file will take a while. Turning it on adds searching over Bluetooth to Nearby and shows which road each conversation takes.';

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
  String get keyboardAddonHelp =>
      'Type on a computer\'s keyboard into the field that has focus on another device, in any app. Only between devices with a confirmed identity, over the same encrypted channel as conversations.';

  @override
  String get remoteInputReceive => 'Allow typing on this device';

  @override
  String get remoteInputReceiveHelp =>
      'A confirmed device can ask to type here. Every session starts with a question on this screen.';

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
  String get viaWifi => 'over the network';

  @override
  String get viaBluetooth => 'over Bluetooth';

  @override
  String get protocolWifi => 'Network';

  @override
  String get protocolBluetooth => 'Bluetooth';

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
      'No devices found over Bluetooth. Check that Chatt is running on the other device with the Bluetooth add-on on, and that it is a few metres away at most. You can also add it by radio address.';

  @override
  String get searchBluetoothNoLocation =>
      'Android hands out no search results while location services are off. The connection itself does not need them, and Chatt never asks where you are.';

  @override
  String get turnOnLocation => 'Turn location on';

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
}
