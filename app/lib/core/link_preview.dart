import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'links.dart';

/// Podgląd strony pod odnośnikiem: tytuł, opis i obrazek, tak jak w zwykłych
/// komunikatorach.
///
/// Cała rzecz sprowadza się do jednego pytania GET i wyjęcia z odpowiedzi
/// kilku znaczników `<meta>`. Nic z pobranej strony **nie jest uruchamiane**:
/// nie ma tu przeglądarki, nie ma WebView, nie ma wykonywania skryptów, nie ma
/// nawet składania HTML-a w drzewo. Aplikacja bierze z odpowiedzi wyłącznie
/// zwykły tekst (który potem rysuje jako tekst) i bajty obrazka (które oddaje
/// dekoderowi Fluttera, temu samemu, co miniatury odebranych plików).
///
/// Pobranie podglądu jest jedynym momentem, w którym adres z cudzej wiadomości
/// zamienia się w połączenie, dlatego stoi wyłączone, dopóki użytkownik go nie
/// włączy (patrz `Settings.linkPreviews`), i nigdy nie idzie w sieć lokalną
/// ani na to urządzenie (patrz [hostAllowsPreview]).

/// Ile czekamy na odpowiedź. Podgląd jest ozdobą, więc lepiej odpuścić niż
/// trzymać rozmowę.
const Duration previewTimeout = Duration(seconds: 8);

/// Ile bajtów strony wolno przeczytać. Znaczniki `<meta>` siedzą w nagłówku
/// dokumentu, więc więcej nie jest do niczego potrzebne, a bez granicy
/// „strona" o nieskończonej długości zjadłaby pamięć.
const int previewHtmlLimit = 512 * 1024;

/// Ile bajtów obrazka wolno przeczytać.
const int previewImageLimit = 2 * 1024 * 1024;

/// Ile razy wolno pójść za przekierowaniem. Każdy skok jest sprawdzany od nowa
/// (schemat i nazwa serwera), bo przekierowanie to najprostszy sposób, żeby
/// z adresu w internecie zrobić adres w cudzej sieci lokalnej.
const int previewMaxRedirects = 3;

/// Typy treści, z których da się wyjąć podgląd.
const Set<String> _htmlTypes = {'text/html', 'application/xhtml+xml'};

/// Formaty obrazków, które Flutter dekoduje sam. `image/svg+xml` **nie** jest
/// na liście świadomie: SVG to dokument, który potrafi nieść skrypty.
const Set<String> _imageTypes = {
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/bmp',
};

/// Nagłówek przedstawiający aplikację. Jest stały dla wszystkich instalacji,
/// więc nie wyróżnia użytkownika: serwer po drugiej stronie widzi „Chatt",
/// a nie „Chatt tego a tego".
const String previewUserAgent =
    'Mozilla/5.0 (compatible; ChattLinkPreview; +https://github.com/Mysttic/Chatt)';

/// Ile podglądów trzymamy w pamięci. Rozmowa przewijana w tę i we w tę ma nie
/// odpytywać cudzych serwerów po raz drugi.
const int previewCacheSize = 64;

/// Tytuł dłuższy niż to nie mieści się w karcie i nie wnosi nic poza szumem.
const int _titleLimit = 140;
const int _descriptionLimit = 300;
const int _siteNameLimit = 60;

/// To, co pokazuje karta pod dymkiem.
class LinkPreview {
  final Uri url;
  final String? title;
  final String? description;

  /// Nazwa serwisu z `og:site_name`. Gdy jej nie ma, karta pokazuje serwer.
  final String? siteName;

  /// Bajty obrazka. Zawsze przechodzą przez dekoder Fluttera, nigdy przez
  /// nic, co potrafiłoby cokolwiek wykonać.
  final Uint8List? imageBytes;

  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.siteName,
    this.imageBytes,
  });

  /// Podgląd bez tytułu i bez opisu nie jest wart osobnej karty: zostaje sam
  /// odnośnik w tekście.
  bool get isEmpty =>
      (title == null || title!.isEmpty) &&
      (description == null || description!.isEmpty);

  /// Co pokazać w nagłówku karty.
  String get label => siteName?.isNotEmpty == true ? siteName! : url.host;
}

/// Rozwiązywanie nazw. Testy podstawiają własne, żeby sprawdzić zaporę bez
/// pytania prawdziwego DNS-u.
typedef HostResolver = Future<List<InternetAddress>> Function(String host);

Future<List<InternetAddress>> _systemLookup(String host) =>
    InternetAddress.lookup(host);

/// Czy wolno pobrać podgląd spod tej nazwy serwera.
///
/// Odmowa dotyczy wszystkiego, co wskazuje na to urządzenie albo na sieć
/// lokalną. Bez tego wystarczyłoby przysłać „http://192.168.0.1/reboot", żeby
/// aplikacja sama weszła na cudzy router, albo przysłać serię adresów i po
/// czasach odpowiedzi wyczytać, co stoi w sieci.
///
/// Sprawdzana jest **każda** odpowiedź DNS-u, nie tylko pierwsza: nazwa
/// wskazująca naraz na adres publiczny i na lokalny zostaje odrzucona
/// w całości. Pytanie idzie jeszcze raz przed każdym przekierowaniem, bo
/// przekierowanie zmienia serwer.
///
/// Zostaje wąskie okno: między naszym pytaniem do DNS-u a pytaniem, które
/// zada sobie sam klient HTTP, wpis może się zmienić („DNS rebinding").
/// Zamknięcie go do końca wymagałoby własnego łączenia gniazdem z pominięciem
/// [http.Client], czego nie da się rzetelnie przetestować bez sieci. Skutkiem
/// takiego wyścigu byłoby jedno puste pytanie GET pod adres w sieci lokalnej;
/// odpowiedź i tak nie ma jak nic uruchomić, bo aplikacja bierze z niej
/// wyłącznie tekst i bajty obrazka.
Future<bool> hostAllowsPreview(String host, {HostResolver? resolve}) async {
  if (host.isEmpty || isLocalHost(host)) return false;
  // Adres wpisany wprost nie idzie do DNS-u, [isLocalHost] ocenił go już sam.
  if (InternetAddress.tryParse(host) != null) return true;
  try {
    final adresy = await (resolve ?? _systemLookup)(host).timeout(previewTimeout);
    if (adresy.isEmpty) return false;
    return !adresy.any(isLocalAddress);
  } catch (_) {
    return false;
  }
}

/// Wyciąga tytuł, opis i adres obrazka z HTML-a.
///
/// Nie jest to parser HTML-a i nie ma nim być: czyta wyłącznie znaczniki
/// `<meta>` i `<title>` z nagłówka dokumentu, a wszystko poza nimi (skrypty,
/// ramki, style, treść strony) ignoruje, bo nic z tego nie jest tu do niczego
/// potrzebne.
({String? title, String? description, String? siteName, String? image})
    parsePreviewMeta(String html) {
  // Znaczniki opisujące dokument siedzą w `<head>`. Ucięcie reszty to i mniej
  // pracy, i mniejsza szansa, że „opis" przyjdzie z treści strony.
  final koniec = html.toLowerCase().indexOf('</head');
  final glowa = koniec > 0 ? html.substring(0, koniec) : html;

  final meta = <String, String>{};
  for (final znacznik in _metaTag.allMatches(glowa)) {
    final atrybuty = _attributes(znacznik.group(1) ?? '');
    final klucz = (atrybuty['property'] ?? atrybuty['name'])?.toLowerCase();
    final wartosc = atrybuty['content'];
    if (klucz == null || wartosc == null) continue;
    // Pierwszy wpis wygrywa: strony potrafią powtarzać `og:title` i ten
    // z początku dokumentu jest zwykle tym właściwym.
    meta.putIfAbsent(klucz, () => wartosc);
  }

  final tytulZnacznika = _titleTag.firstMatch(glowa)?.group(1);

  String? wybierz(List<String> klucze, int limit) {
    for (final klucz in klucze) {
      final tekst = _clean(meta[klucz], limit);
      if (tekst != null) return tekst;
    }
    return null;
  }

  return (
    title: wybierz(['og:title', 'twitter:title'], _titleLimit) ??
        _clean(tytulZnacznika, _titleLimit),
    description: wybierz(
      ['og:description', 'twitter:description', 'description'],
      _descriptionLimit,
    ),
    siteName: wybierz(['og:site_name', 'application-name'], _siteNameLimit),
    // Adres obrazka zostaje surowy: ocenia go dopiero [LinkPreviewService].
    image: meta['og:image:secure_url'] ??
        meta['og:image:url'] ??
        meta['og:image'] ??
        meta['twitter:image'],
  );
}

final RegExp _metaTag =
    RegExp(r'<meta\s+([^>]*)>', caseSensitive: false, dotAll: true);
final RegExp _titleTag =
    RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true);
final RegExp _attribute = RegExp(
  r'''([A-Za-z_:][-\w:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))''',
  dotAll: true,
);

Map<String, String> _attributes(String tekst) {
  final wynik = <String, String>{};
  for (final dopasowanie in _attribute.allMatches(tekst)) {
    final nazwa = dopasowanie.group(1)!.toLowerCase();
    final wartosc =
        dopasowanie.group(2) ?? dopasowanie.group(3) ?? dopasowanie.group(4);
    if (wartosc != null) wynik.putIfAbsent(nazwa, () => wartosc);
  }
  return wynik;
}

/// Sprowadza napis ze strony do tego, co wolno narysować: rozwija encje,
/// zbija białe znaki, wyrzuca znaki sterujące i te zmieniające kierunek pisma
/// (inaczej cudzy tytuł potrafiłby przestawić resztę karty), i przycina.
String? _clean(String? tekst, int limit) {
  if (tekst == null) return null;
  var wynik = _decodeEntities(tekst);
  wynik = String.fromCharCodes(wynik.runes.where((z) =>
      !(z < 0x20 ||
          z == 0x7f ||
          (z >= 0x200b && z <= 0x200f) ||
          (z >= 0x202a && z <= 0x202e) ||
          (z >= 0x2060 && z <= 0x2064) ||
          (z >= 0x2066 && z <= 0x2069) ||
          z == 0xfeff)));
  wynik = wynik.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (wynik.isEmpty) return null;
  if (wynik.length <= limit) return wynik;
  return '${wynik.substring(0, limit).trimRight()}…';
}

const Map<String, String> _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'hellip': '…',
  'mdash': '—',
  'ndash': '–',
  'laquo': '«',
  'raquo': '»',
  'ldquo': '“',
  'rdquo': '”',
  'lsquo': '‘',
  'rsquo': '’',
  'eacute': 'é',
  'egrave': 'è',
  'uuml': 'ü',
  'ouml': 'ö',
  'auml': 'ä',
  'szlig': 'ß',
};

final RegExp _entity = RegExp(r'&(#[xX]?[0-9a-fA-F]+|\w+);');

String _decodeEntities(String tekst) =>
    tekst.replaceAllMapped(_entity, (dopasowanie) {
      final tresc = dopasowanie.group(1)!;
      if (tresc.startsWith('#')) {
        final szesnastkowo = tresc.length > 1 && (tresc[1] == 'x' || tresc[1] == 'X');
        final numer = int.tryParse(
          szesnastkowo ? tresc.substring(2) : tresc.substring(1),
          radix: szesnastkowo ? 16 : 10,
        );
        // Poza zakresem Unicode albo w połowie pary zastępczej: zostawiamy
        // napis, jak przyszedł, zamiast wywracać dekodowanie.
        if (numer == null || numer < 0x20 || numer > 0x10ffff) {
          return dopasowanie.group(0)!;
        }
        if (numer >= 0xd800 && numer <= 0xdfff) return dopasowanie.group(0)!;
        return String.fromCharCode(numer);
      }
      return _namedEntities[tresc.toLowerCase()] ?? dopasowanie.group(0)!;
    });

/// Odpowiedź sprowadzona do tego, co jest tu potrzebne.
class _Body {
  final Uint8List bytes;

  /// Kodowanie zadeklarowane w nagłówku, o ile było.
  final String? charset;

  const _Body(this.bytes, this.charset);
}

/// Pobieranie podglądów z pamięcią na to, o co już pytaliśmy.
class LinkPreviewService {
  final http.Client _client;
  final bool _ownsClient;

  /// Rozwiązywanie nazw. Testy podstawiają własne, produkcja bierze systemowe.
  final HostResolver? resolve;

  /// Czy w ogóle wolno pytać. Warstwa wyżej trzyma tu przełącznik
  /// z ustawień; przy `false` [previewOf] nie rusza sieci.
  bool enabled;

  /// Gotowe podglądy, w kolejności pytania (najstarszy wypada pierwszy).
  /// `null` w środku znaczy „pytaliśmy i nic z tego nie wyszło" — dzięki temu
  /// strona bez znaczników nie jest odpytywana przy każdym przewinięciu.
  final Map<String, LinkPreview?> _cache = {};

  /// Pytania w locie, żeby ten sam adres w kilku dymkach poszedł raz.
  final Map<String, Future<LinkPreview?>> _inFlight = {};

  LinkPreviewService({
    http.Client? client,
    this.resolve,
    this.enabled = false,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// Podgląd, jeśli już go mamy. Rysowanie zaczyna się od tego, żeby karta
  /// pojawiła się od razu przy powrocie do rozmowy.
  LinkPreview? cached(Uri url) => _cache[url.toString()];

  /// Czy o ten adres już pytaliśmy (choćby bez skutku).
  bool asked(Uri url) => _cache.containsKey(url.toString());

  /// Pyta o podgląd albo oddaje ten, który już jest.
  ///
  /// Nie rzuca niczym: podgląd, który się nie udał, to po prostu brak karty.
  Future<LinkPreview?> previewOf(Uri url) {
    final klucz = url.toString();
    if (_cache.containsKey(klucz)) return Future.value(_cache[klucz]);
    final wLocie = _inFlight[klucz];
    if (wLocie != null) return wLocie;

    final pytanie = _load(url).then((podglad) {
      _remember(klucz, podglad);
      return podglad;
    }).whenComplete(() {
      // Nawias klamrowy, a nie strzałka: `Map.remove` oddaje usuniętą wartość,
      // czyli **to samo** pytanie, a `whenComplete` czeka na future zwrócony
      // z wywołania zwrotnego. Skrót `=> _inFlight.remove(klucz)` kazałby mu
      // więc czekać na samego siebie i pytanie nie kończyłoby się nigdy.
      _inFlight.remove(klucz);
    });
    _inFlight[klucz] = pytanie;
    return pytanie;
  }

  void _remember(String klucz, LinkPreview? podglad) {
    _cache[klucz] = podglad;
    while (_cache.length > previewCacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Czyści pamięć podglądów. Wołane po wyłączeniu przełącznika, żeby to, co
  /// zdążyło przyjść, zniknęło razem ze zgodą.
  void clear() {
    _cache.clear();
    _inFlight.clear();
  }

  Future<LinkPreview?> _load(Uri url) async {
    if (!enabled) return null;
    if (!allowedLinkSchemes.contains(url.scheme.toLowerCase())) return null;
    try {
      final strona = await _fetch(url, _htmlTypes, previewHtmlLimit);
      if (strona == null) return null;

      final html = _decodeBody(strona);
      final meta = parsePreviewMeta(html);
      final podglad = LinkPreview(
        url: url,
        title: meta.title,
        description: meta.description,
        siteName: meta.siteName,
        imageBytes: await _image(url, meta.image),
      );
      return podglad.isEmpty && podglad.imageBytes == null ? null : podglad;
    } catch (_) {
      // Brak sieci, timeout, dziwna odpowiedź. Wszystko jedno: nie ma karty.
      return null;
    }
  }

  Future<Uint8List?> _image(Uri strona, String? adres) async {
    if (adres == null || adres.isEmpty) return null;
    final oczyszczony = _decodeEntities(adres).trim();
    final cel = strona.resolve(oczyszczony);
    if (!allowedLinkSchemes.contains(cel.scheme.toLowerCase())) return null;
    try {
      final odpowiedz = await _fetch(cel, _imageTypes, previewImageLimit);
      return odpowiedz?.bytes;
    } catch (_) {
      return null;
    }
  }

  /// Jedno pobranie: sprawdzenie adresu, pytanie, przekierowania po kolei
  /// i czytanie odpowiedzi z twardą granicą długości.
  Future<_Body?> _fetch(Uri url, Set<String> typy, int limit) async {
    var cel = url;
    for (var skok = 0; skok <= previewMaxRedirects; skok++) {
      if (!allowedLinkSchemes.contains(cel.scheme.toLowerCase())) return null;
      if (!await hostAllowsPreview(cel.host, resolve: resolve)) return null;

      final zadanie = http.Request('GET', cel)
        // Przekierowania obsługujemy sami, bo każdy skok trzeba sprawdzić
        // od nowa: bez tego adres publiczny prowadziłby do sieci lokalnej.
        ..followRedirects = false
        ..headers.addAll({
          'User-Agent': previewUserAgent,
          'Accept': '${typy.join(', ')}, */*;q=0.1',
          // Bez kompresji: rozpakowywanie odpowiedzi od obcego to zbędna
          // powierzchnia, a granica długości ma dotyczyć tego, co naprawdę
          // przyjdzie, nie tego, co się z tego rozwinie.
          'Accept-Encoding': 'identity',
        });

      final odpowiedz = await _client.send(zadanie).timeout(previewTimeout);

      if (odpowiedz.statusCode >= 300 && odpowiedz.statusCode < 400) {
        await odpowiedz.stream.drain<void>();
        final dokad = odpowiedz.headers['location'];
        if (dokad == null || dokad.isEmpty) return null;
        final nastepny = cel.resolve(dokad);
        // Pętla przekierowań kończy się tu, a nie po `previewMaxRedirects`
        // identycznych pytaniach.
        if (nastepny == cel) return null;
        cel = nastepny;
        continue;
      }

      if (odpowiedz.statusCode != 200) {
        await odpowiedz.stream.drain<void>();
        return null;
      }

      final naglowek = odpowiedz.headers['content-type'] ?? '';
      final typ = naglowek.split(';').first.trim().toLowerCase();
      if (!typy.contains(typ)) {
        await odpowiedz.stream.drain<void>();
        return null;
      }
      // Deklarowana długość ponad granicę: nie ma po co zaczynać czytać.
      final zapowiadana = odpowiedz.contentLength;
      if (zapowiadana != null && zapowiadana > limit) {
        await odpowiedz.stream.drain<void>();
        return null;
      }

      final bajty = await _readCapped(odpowiedz.stream, limit);
      if (bajty == null) return null;
      return _Body(bajty, _charsetOf(naglowek));
    }
    return null;
  }

  /// Czyta strumień, dopóki mieści się w granicy. Wyjście z pętli zrywa
  /// połączenie, więc reszta „strony" bez końca nigdy nie zostaje pobrana.
  Future<Uint8List?> _readCapped(Stream<List<int>> stream, int limit) async {
    final kawalki = <List<int>>[];
    var razem = 0;
    var zaDuze = false;
    await for (final kawalek in stream) {
      razem += kawalek.length;
      if (razem > limit) {
        zaDuze = true;
        break;
      }
      kawalki.add(kawalek);
    }
    if (zaDuze) return null;

    final wynik = Uint8List(razem);
    var gdzie = 0;
    for (final kawalek in kawalki) {
      wynik.setRange(gdzie, gdzie + kawalek.length, kawalek);
      gdzie += kawalek.length;
    }
    return wynik;
  }

  /// Rozkodowuje treść strony. Domyślnie UTF-8 z przymrużeniem oka
  /// (`allowMalformed`), bo połamany bajt w cudzym tytule nie ma prawa
  /// wywrócić podglądu.
  String _decodeBody(_Body body) {
    final kodowanie = (body.charset ?? _charsetFromHtml(body.bytes))?.toLowerCase();
    if (kodowanie == 'iso-8859-1' ||
        kodowanie == 'latin1' ||
        kodowanie == 'windows-1252') {
      return latin1.decode(body.bytes, allowInvalid: true);
    }
    return utf8.decode(body.bytes, allowMalformed: true);
  }

  /// Kodowanie zadeklarowane w samym dokumencie (`<meta charset=...>`).
  /// Czytamy je z początku pliku, bo tam stoi i tam wolno je czytać bajtami.
  String? _charsetFromHtml(Uint8List bajty) {
    final poczatek =
        latin1.decode(bajty.take(2048).toList(), allowInvalid: true);
    for (final znacznik in _metaTag.allMatches(poczatek)) {
      final atrybuty = _attributes(znacznik.group(1) ?? '');
      final wprost = atrybuty['charset'];
      if (wprost != null) return wprost.trim();
      if (atrybuty['http-equiv']?.toLowerCase() == 'content-type') {
        final z = _charsetOf(atrybuty['content'] ?? '');
        if (z != null) return z;
      }
    }
    return null;
  }

  static String? _charsetOf(String contentType) {
    for (final czesc in contentType.split(';').skip(1)) {
      final kawalek = czesc.trim();
      if (kawalek.toLowerCase().startsWith('charset=')) {
        return kawalek.substring(8).replaceAll('"', '').trim();
      }
    }
    return null;
  }

  void dispose() {
    _cache.clear();
    _inFlight.clear();
    if (_ownsClient) _client.close();
  }
}
