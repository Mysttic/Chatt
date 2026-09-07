import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'version.dart';

/// Sprawdzanie, czy wyszło nowsze wydanie Chatta.
///
/// To jedyne miejsce, w którym aplikacja odzywa się poza sieć lokalną, i
/// dzieje się to wyłącznie wtedy, gdy użytkownik włączy przełącznik albo sam
/// naciśnie przycisk w ustawieniach. Pytanie idzie do publicznego API GitHuba
/// i nie niesie ze sobą niczego poza tym, co widzi każdy serwer HTTPS.
///
/// Pliki do pobrania leżą w repozytorium, z którego korzysta strona
/// https://mysttic.github.io/Mysttic/chatt/. Kod aplikacji jest prywatny,
/// a wydania publiczne, więc pytanie ma dokąd trafić.
const String releasesApi =
    'https://api.github.com/repos/Mysttic/Mysttic/releases?per_page=30';

/// Przedrostek tagów Chatta. W tamtym repozytorium leżą wydania wszystkich
/// projektów naraz, więc samo „najnowsze" pokazałoby cudzy numer.
const String releaseTagPrefix = 'chatt-v';

/// Lista wydań w przeglądarce, dla wersji przenośnej i jako zapasowy adres.
const String releasesPage = 'https://github.com/Mysttic/Mysttic/releases';

/// Ile czekamy na odpowiedź. Sprawdzenie aktualizacji jest czynnością
/// poboczną, więc lepiej odpuścić niż wisieć.
const Duration updateTimeout = Duration(seconds: 10);

/// Co ile aplikacja sama pyta o wydanie, gdy przełącznik jest włączony.
const Duration updateCheckInterval = Duration(hours: 24);

/// Wydanie sprowadzone do tego, co aplikacja pokazuje i pobiera.
class Release {
  /// Numer bez „v" z przodu, tak jak [appVersion].
  final String version;

  /// Opis wydania z GitHuba, pokazywany pod numerem.
  final String notes;

  final DateTime? publishedAt;

  /// Strona wydania, do otwarcia w przeglądarce.
  final String pageUrl;

  /// Plik dla tej platformy: instalator na Windowsie, APK na Androidzie.
  /// `null`, gdy wydanie go nie ma.
  final String? assetUrl;
  final String? assetName;
  final int? assetSize;

  const Release({
    required this.version,
    required this.notes,
    required this.publishedAt,
    required this.pageUrl,
    required this.assetUrl,
    required this.assetName,
    required this.assetSize,
  });
}

/// Czym skończyło się pytanie o wydanie.
///
/// „Nie udało się zapytać" musi być czymś innym niż „nic nowego", bo na ekranie
/// to dwie różne wiadomości: pierwsza mówi o sieci, druga o wersji.
enum UpdateCheck { newer, upToDate, failed }

class UpdateResult {
  final UpdateCheck outcome;

  /// Wypełnione tylko przy [UpdateCheck.newer].
  final Release? release;

  const UpdateResult(this.outcome, [this.release]);

  bool get isNewer => outcome == UpdateCheck.newer;
}

/// Porównuje numery wersji. Ujemne, gdy [a] jest starsze niż [b].
///
/// Bierze pod uwagę trzy człony i nic więcej: numer builda z pubspeca („+10")
/// ani przyrostki wydań kandydujących („-rc1") nie decydują o tym, czy warto
/// się aktualizować.
int compareVersions(String a, String b) {
  final pa = _czlony(a);
  final pb = _czlony(b);
  for (var i = 0; i < 3; i++) {
    final roznica = pa[i].compareTo(pb[i]);
    if (roznica != 0) return roznica;
  }
  return 0;
}

List<int> _czlony(String wersja) {
  var tekst = wersja.trim();
  if (tekst.startsWith('v') || tekst.startsWith('V')) {
    tekst = tekst.substring(1);
  }
  tekst = tekst.split(RegExp(r'[-+]')).first;
  final liczby = tekst
      .split('.')
      .map((c) => int.tryParse(c.trim()) ?? 0)
      .toList();
  while (liczby.length < 3) {
    liczby.add(0);
  }
  return liczby.take(3).toList();
}

/// Nazwa pliku wydania dla tej platformy. Wzorce pochodzą z kroku „Nazwy
/// z numerem wersji" w `.github/workflows/wydanie.yml`.
String? assetNameFor(String wersja, {String? platforma}) {
  final cel = platforma ?? Platform.operatingSystem;
  return switch (cel) {
    'windows' => 'chatt-$wersja-windows-instalator.exe',
    'android' => 'chatt-$wersja-android.apk',
    _ => null,
  };
}

/// Pyta GitHuba o najnowsze wydanie.
///
/// Nie rzuca niczym: sprawdzanie aktualizacji jest czynnością poboczną i nie
/// ma prawa zepsuć niczego w aplikacji, więc awaria kończy się
/// [UpdateCheck.failed].
Future<UpdateResult> fetchLatestRelease({
  String biezaca = appVersion,
  http.Client? client,
  String? platforma,
}) async {
  final http.Client polaczenie = client ?? http.Client();
  try {
    final odpowiedz = await polaczenie
        .get(
          Uri.parse(releasesApi),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(updateTimeout);
    if (odpowiedz.statusCode != 200) {
      return const UpdateResult(UpdateCheck.failed);
    }

    final json = jsonDecode(odpowiedz.body);
    if (json is! List) {
      return const UpdateResult(UpdateCheck.failed);
    }

    // Lista przychodzi od najnowszych. Bierzemy pierwsze wydanie Chatta:
    // szkic i wydanie kandydujące to nie jest coś, co ktoś ma dostać
    // automatycznie, a wydania pozostałych projektów zdradza przedrostek tagu.
    Map<String, dynamic>? wydanie;
    for (final w in json) {
      if (w is! Map<String, dynamic>) continue;
      if (w['draft'] == true || w['prerelease'] == true) continue;
      final tag = w['tag_name'];
      if (tag is! String || !tag.startsWith(releaseTagPrefix)) continue;
      wydanie = w;
      break;
    }
    // Wydania Chatta nie ma na liście, więc nie ma o czym mówić.
    if (wydanie == null) {
      return const UpdateResult(UpdateCheck.upToDate);
    }

    final wersja = (wydanie['tag_name'] as String)
        .substring(releaseTagPrefix.length);
    if (wersja.isEmpty || compareVersions(biezaca, wersja) >= 0) {
      return const UpdateResult(UpdateCheck.upToDate);
    }

    final szukana = assetNameFor(wersja, platforma: platforma);
    Map<String, dynamic>? plik;
    for (final a in (wydanie['assets'] as List? ?? const [])) {
      if (a is Map<String, dynamic> && a['name'] == szukana) {
        plik = a;
        break;
      }
    }

    return UpdateResult(
      UpdateCheck.newer,
      Release(
        version: wersja,
        notes: (wydanie['body'] as String? ?? '').trim(),
        publishedAt: DateTime.tryParse(
          wydanie['published_at'] as String? ?? '',
        ),
        pageUrl: wydanie['html_url'] as String? ?? releasesPage,
        assetUrl: plik?['browser_download_url'] as String?,
        assetName: plik?['name'] as String?,
        assetSize: plik?['size'] as int?,
      ),
    );
  } catch (_) {
    // Brak sieci, timeout, zmieniony kształt odpowiedzi. Wszystko jedno:
    // aplikacja ma działać dalej, jakby nikt o nic nie pytał.
    return const UpdateResult(UpdateCheck.failed);
  } finally {
    if (client == null) polaczenie.close();
  }
}
