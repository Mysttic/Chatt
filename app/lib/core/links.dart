import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show MethodChannel;

/// Odnośniki w treści wiadomości: znajdowanie ich w napisie, ocena, czy da się
/// im zaufać, i otwieranie w przeglądarce systemowej.
///
/// Wiadomość przychodzi od kogoś z sieci i jest zwykłym tekstem, więc każdy
/// adres w niej to napis od obcego. Dlatego niżej nie ma nic, co wykonywałoby
/// cokolwiek z tego adresu: aplikacja rozpoznaje wyłącznie `http` i `https`,
/// resztę zostawia zwykłym napisem, a otwarcie zawsze przechodzi przez pytanie
/// zadane użytkownikowi (patrz `ui/widgets/link_confirm.dart`).

/// Schematy, które w ogóle stają się odnośnikiem. Wszystko inne —
/// `javascript:`, `data:`, `file:`, `intent:`, `content:` — zostaje napisem,
/// bo kliknięcie w nie znaczy „uruchom coś", a nie „pokaż stronę".
const Set<String> allowedLinkSchemes = {'http', 'https'};

/// Znaki, które w mowie ludzkiej kończą zdanie, a w adresie prawie nigdy nie
/// stoją na końcu. Ucinamy je z ogona, żeby „wejdź na https://example.com."
/// nie prowadziło do adresu z kropką.
const String _trailingPunctuation = '.,;:!?…„”"\'`*_~';

/// Wzorzec adresu w tekście. Nawiasy zostają w środku dopasowania (adresy
/// Wikipedii ich potrzebują) i dopiero [_trimTail] odcina te niedomknięte.
/// Adres kończy się na białym znaku, ostrym nawiasie albo cudzysłowie.
final RegExp _linkPattern = RegExp(
  r'(?:https?://|www\.)[^\s<>"' "'" r'`\\]+',
  caseSensitive: false,
);

/// Znaki, po których adres nie może się zaczynać: to znaczy, że dopasowanie
/// wypadło w środku wyrazu, nazwy pliku albo adresu poczty.
final RegExp _wordChar = RegExp(r'[\w.@%+-]');

/// Czy w napisie siedzi coś, czego nie widać.
///
/// Znaki sterujące, spacje zerowej szerokości i przełączniki kierunku pisma
/// nie mają w adresie czego szukać, a potrafią pokazać co innego, niż
/// zostanie otwarte: „RTL override" odwraca końcówkę nazwy, więc `…exe`
/// czyta się jako `…txt`. Adres z takim znakiem nie zostaje odnośnikiem
/// w ogóle, bo nie da się uczciwie pokazać, dokąd prowadzi.
bool _hasInvisible(String text) => text.runes.any((z) =>
    z < 0x20 || // znaki sterujące
    z == 0x7f || // DEL
    (z >= 0x200b && z <= 0x200f) || // zerowa szerokość, znaczniki kierunku
    (z >= 0x202a && z <= 0x202e) || // osadzenia i przełączniki kierunku
    (z >= 0x2060 && z <= 0x2064) || // łączniki bez szerokości
    (z >= 0x2066 && z <= 0x2069) || // izolaty kierunku
    z == 0xfeff); // znacznik kolejności bajtów

/// Kawałek treści rozpoznany jako adres.
class LinkSpan {
  /// Pozycja w oryginalnym napisie (do podmiany fragmentu na klikalny).
  final int start;
  final int end;

  /// Napis dokładnie taki, jaki widać w wiadomości.
  final String text;

  /// Adres do otwarcia. Dla „www.example.com" dostaje z przodu `https://`.
  final Uri uri;

  const LinkSpan({
    required this.start,
    required this.end,
    required this.text,
    required this.uri,
  });
}

/// Czego użytkownik ma się dowiedzieć, zanim kliknie „Otwórz".
enum LinkWarning {
  /// Adres niesie login przed nazwą serwera: „https://bank.pl@zly.example".
  /// Wygląda jak jeden serwer, prowadzi do drugiego.
  userInfo,

  /// Nazwa serwera spoza ASCII. Litery z innych alfabetów potrafią wyglądać
  /// identycznie jak łacińskie (cyrylickie „а" w „аpple.com").
  nonAsciiHost,

  /// Połączenie bez szyfrowania.
  insecure,

  /// Adres w sieci lokalnej albo na tym urządzeniu. Sam w sobie bywa
  /// w porządku (drukarka, router), ale wiadomość od obcego prosząca
  /// o wejście na router to coś, o czym trzeba powiedzieć.
  localAddress,
}

/// Znajduje adresy w treści wiadomości, w kolejności występowania.
///
/// Zwraca wyłącznie to, co da się otworzyć: `http` i `https` z sensowną nazwą
/// serwera. Napis, który tylko wygląda jak adres, zostaje zwykłym tekstem.
List<LinkSpan> findLinks(String text) {
  final wynik = <LinkSpan>[];
  for (final dopasowanie in _linkPattern.allMatches(text)) {
    // Adres zaczyna się na granicy wyrazu. Bez tego „jan@www.example.com"
    // pokazywałoby odnośnik do „www.example.com", którego w tekście nikt nie
    // napisał, a użytkownik miałby przed sobą coś, czego nie widać.
    if (dopasowanie.start > 0 &&
        _wordChar.hasMatch(text[dopasowanie.start - 1])) {
      continue;
    }
    final surowy = _trimTail(dopasowanie.group(0)!);
    if (surowy.isEmpty) continue;
    final uri = parseLink(surowy);
    if (uri == null) continue;
    wynik.add(LinkSpan(
      start: dopasowanie.start,
      end: dopasowanie.start + surowy.length,
      text: surowy,
      uri: uri,
    ));
  }
  return wynik;
}

/// Zamienia napis na adres do otwarcia albo oddaje `null`, gdy to nie jest
/// adres, któremu wolno zrobić z siebie odnośnik.
Uri? parseLink(String text) {
  var napis = text.trim();
  if (napis.isEmpty || _hasInvisible(napis)) return null;
  if (napis.toLowerCase().startsWith('www.')) napis = 'https://$napis';

  final uri = Uri.tryParse(napis);
  if (uri == null) return null;
  if (!allowedLinkSchemes.contains(uri.scheme.toLowerCase())) return null;
  if (uri.host.isEmpty) return null;
  // Nazwa serwera bez kropki („http://localhost", „http://wewnetrzny") nie
  // jest adresem w internecie. Adres IP wpisany wprost przechodzi, bo w sieci
  // lokalnej to codzienność.
  if (!uri.host.contains('.') && InternetAddress.tryParse(uri.host) == null) {
    return null;
  }
  return uri;
}

/// Co pokazać w pytaniu przed otwarciem.
Set<LinkWarning> warningsFor(Uri uri) => {
      if (uri.userInfo.isNotEmpty) LinkWarning.userInfo,
      if (hasNonAsciiHost(uri)) LinkWarning.nonAsciiHost,
      if (uri.scheme.toLowerCase() == 'http') LinkWarning.insecure,
      if (isLocalHost(uri.host)) LinkWarning.localAddress,
    };

/// Czy w nazwie serwera siedzą litery spoza ASCII, w którejkolwiek z trzech
/// postaci, w jakich potrafią przyjść.
///
/// [Uri.host] zapisuje je procentowo („%D0%B0pple.com"), zapis `xn--` to ta
/// sama nazwa po stronie DNS-u, a same znaki zostają, gdy adres powstał
/// inaczej niż z rozbioru napisu. Wszystkie trzy znaczą to samo: nazwa nie
/// jest tym, na co wygląda, i użytkownik ma o tym wiedzieć przed kliknięciem.
bool hasNonAsciiHost(Uri uri) {
  final nazwa = uri.host.toLowerCase();
  if (!_isAscii(nazwa)) return true;
  if (nazwa.contains('%')) return true;
  return nazwa.split('.').any((czlon) => czlon.startsWith('xn--'));
}

/// Czy nazwa serwera wskazuje na to urządzenie albo na sieć lokalną.
///
/// Decyduje o tym, czy wolno pobrać podgląd: podgląd leci bez pytania, więc
/// adres w sieci lokalnej zamieniłby wiadomość od obcego w skaner tej sieci
/// i w „kliknięcie" w panel routera.
bool isLocalHost(String host) {
  var nazwa = host.toLowerCase();
  if (nazwa.startsWith('[') && nazwa.endsWith(']')) {
    nazwa = nazwa.substring(1, nazwa.length - 1);
  }
  // IPv6 potrafi nieść na końcu identyfikator interfejsu („fe80::1%eth0").
  // Ucinamy go tylko wtedy, gdy przed procentem naprawdę stoi adres: w nazwie
  // serwera procent znaczy co innego, bo tak [Uri] zapisuje znaki spoza ASCII,
  // a ślepe ucięcie zrobiłoby z „%D0%B0pple.com" pustą nazwę, czyli — po
  // regule „nazwa bez kropki" — adres lokalny.
  final procent = nazwa.indexOf('%');
  if (procent > 0) {
    final bezStrefy = nazwa.substring(0, procent);
    if (InternetAddress.tryParse(bezStrefy) != null) nazwa = bezStrefy;
  }

  final adres = InternetAddress.tryParse(nazwa);
  if (adres != null) return isLocalAddress(adres);

  if (nazwa == 'localhost' || !nazwa.contains('.')) return true;
  return _localSuffixes.any(nazwa.endsWith);
}

const List<String> _localSuffixes = [
  '.local',
  '.localhost',
  '.localdomain',
  '.internal',
  '.intranet',
  '.lan',
  '.home',
  '.home.arpa',
  '.corp',
  '.private',
  '.in-addr.arpa',
  '.ip6.arpa',
];

/// Czy adres IP wskazuje na to urządzenie, na sieć lokalną albo na coś, czego
/// w publicznym internecie nie ma.
bool isLocalAddress(InternetAddress adres) {
  if (adres.isLoopback || adres.isLinkLocal || adres.isMulticast) return true;
  final bajty = adres.rawAddress;
  if (adres.type == InternetAddressType.IPv4) {
    if (bajty.length != 4) return true;
    final a = bajty[0];
    final b = bajty[1];
    // 0.0.0.0/8 („ten host"), 10/8, 100.64/10 (CGNAT), 127/8, 169.254/16,
    // 172.16/12, 192.0.0/24, 192.168/16, 198.18/15 (testy wydajności),
    // 224/4 (rozgłoszeniowe) i 240/4 (zarezerwowane, w tym 255.255.255.255).
    if (a == 0 || a == 10 || a == 127) return true;
    if (a == 100 && b >= 64 && b <= 127) return true;
    if (a == 169 && b == 254) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 0 && bajty[2] == 0) return true;
    if (a == 192 && b == 168) return true;
    if (a == 198 && (b == 18 || b == 19)) return true;
    if (a >= 224) return true;
    return false;
  }
  if (bajty.length != 16) return true;
  // :: i wszystko, co jest samymi zerami.
  if (bajty.every((b) => b == 0)) return true;
  // ::ffff:0:0/96 — adres IPv4 w przebraniu IPv6, oceniamy go jak IPv4.
  final czyMapowany = bajty.take(10).every((b) => b == 0) &&
      bajty[10] == 0xff &&
      bajty[11] == 0xff;
  if (czyMapowany) {
    return isLocalAddress(
        InternetAddress('${bajty[12]}.${bajty[13]}.${bajty[14]}.${bajty[15]}'));
  }
  // fc00::/7 (unikatowe lokalne), fe80::/10 (łącze lokalne), ff00::/8
  // (rozgłoszeniowe).
  if (bajty[0] & 0xfe == 0xfc) return true;
  if (bajty[0] == 0xfe && bajty[1] & 0xc0 == 0x80) return true;
  if (bajty[0] == 0xff) return true;
  return false;
}

/// Adres skrócony do pokazania: serwer i tyle ścieżki, ile się mieści.
/// Nazwa serwera zostaje w całości, bo to ona mówi, dokąd się idzie.
String shortenLink(Uri uri, {int limit = 64}) {
  final serwer = uri.host + (uri.hasPort ? ':${uri.port}' : '');
  final reszta = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
  if (reszta.isEmpty || reszta == '/') return serwer;
  final calosc = serwer + reszta;
  if (calosc.length <= limit) return calosc;
  final zostaje = limit - serwer.length;
  if (zostaje < 4) return serwer;
  return '$serwer${reszta.substring(0, zostaje - 1)}…';
}

bool _isAscii(String text) => text.codeUnits.every((c) => c < 128);

/// Ucina ogon dopasowania: znaki przestankowe i niedomknięte nawiasy.
String _trimTail(String text) {
  const pary = {')': '(', ']': '[', '}': '{'};
  var koniec = text.length;
  while (koniec > 0) {
    final znak = text[koniec - 1];
    if (_trailingPunctuation.contains(znak)) {
      koniec--;
      continue;
    }
    // Nawias zamykający zostaje tylko wtedy, gdy w adresie jest jego para.
    // Bez tego „(zobacz https://pl.wikipedia.org/wiki/Dart)" brałoby cudzy
    // nawias, a artykuł „Dart_(język)" gubiłby własny.
    final otwierajacy = pary[znak];
    if (otwierajacy != null) {
      final fragment = text.substring(0, koniec);
      final otwarte = otwierajacy.allMatches(fragment).length;
      final zamkniete = znak.allMatches(fragment).length;
      if (zamkniete > otwarte) {
        koniec--;
        continue;
      }
    }
    break;
  }
  return text.substring(0, koniec);
}

/// Czym skończyła się próba otwarcia adresu w przeglądarce.
enum LinkOpenResult {
  ok,

  /// Platforma nie ma jak otworzyć przeglądarki.
  unsupported,

  /// Nie udało się uruchomić przeglądarki (brak `xdg-open`, odmowa systemu).
  failed,
}

/// System, dla którego otwieramy odnośnik. Podmiana dla testów: CI stoi na
/// Linuksie, a droga przez kanał natywny ma się dać sprawdzić także tam.
@visibleForTesting
String? debugLinkPlatform;

/// Otwiera adres w przeglądarce systemowej.
///
/// Schemat jest sprawdzany jeszcze raz, tuż przed uruchomieniem: to ostatnie
/// miejsce, w którym da się nie oddać systemowi czegoś w rodzaju `file:`
/// albo `intent:`. Argument idzie listą, nie przez powłokę, więc nie ma jak
/// dokleić do niego drugiego polecenia.
Future<LinkOpenResult> openExternalLink(Uri uri) async {
  if (!allowedLinkSchemes.contains(uri.scheme.toLowerCase())) {
    return LinkOpenResult.failed;
  }
  final adres = uri.toString();
  final system = debugLinkPlatform ?? Platform.operatingSystem;
  // Android i Windows oddają adres systemowi własnym kodem, jako jeden napis.
  // Na Windowsie szedł kiedyś jako argument `explorer.exe`, a explorer dzieli
  // swój wiersz poleceń na przecinkach i znakach równości: odnośnik
  // z `?client=...` otwierał folder Dokumenty zamiast przeglądarki (#31).
  final kanal = switch (system) {
    'android' => const MethodChannel('chatt/files'),
    'windows' => const MethodChannel('chatt/links'),
    _ => null,
  };
  if (kanal != null) {
    try {
      final ok = await kanal.invokeMethod<bool>('openUrl', {'url': adres});
      return ok == true ? LinkOpenResult.ok : LinkOpenResult.failed;
    } catch (_) {
      // Brak kanału (test widżetowy) albo wyjątek po stronie natywnej.
      return LinkOpenResult.unsupported;
    }
  }
  final (program, argumenty) = switch (system) {
    'macos' => ('open', [adres]),
    'linux' => ('xdg-open', [adres]),
    _ => (null, const <String>[]),
  };
  if (program == null) return LinkOpenResult.unsupported;
  try {
    await Process.start(program, argumenty, mode: ProcessStartMode.detached);
    return LinkOpenResult.ok;
  } catch (_) {
    return LinkOpenResult.failed;
  }
}
