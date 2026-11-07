// Wspólne narzędzia scenariuszy na urządzeniu z Androidem: adb, drzewo
// widoków z `uiautomator dump` i stukanie po etykietach.
//
// Używają ich `tool/android_e2e_test.dart` i `tool/klawiatura_android_e2e_test.dart`.
// Zmienne: ADB (ścieżka do adb), CHATT_DEVICE (id urządzenia z `adb devices`,
// domyślnie emulator-5554).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

String get adbPath => Platform.environment['ADB'] ?? 'adb';
String get deviceId => Platform.environment['CHATT_DEVICE'] ?? 'emulator-5554';

/// Wyjście adb czytamy jako UTF-8. Przy kodowaniu systemowym Windows
/// „Odrzuć" ze zrzutu drzewa widoków wracało jako „OdrzuÄ‡" i żadne
/// wyszukiwanie po polskiej etykiecie nie trafiało.
///
/// Każde wywołanie ma limit czasu. `uiautomator dump` potrafi zawisnąć na
/// telefonie (czeka na „spokojne" okno, którego nie ma), a wtedy razem z nim
/// wisiał cały scenariusz, a zawieszone klienty adb zatykały serwer adb.
/// Po limicie proces adb jest zabijany, a wynik ma kod -1.
Future<ProcessResult> adb(List<String> args,
    {Duration limit = const Duration(seconds: 30)}) async {
  final proces = await Process.start(adbPath, ['-s', deviceId, ...args]);
  final wyjscie = proces.stdout.transform(utf8.decoder).join();
  final bledy = proces.stderr.transform(utf8.decoder).join();
  final kod = await proces.exitCode.timeout(limit, onTimeout: () {
    proces.kill();
    return -1;
  });
  return ProcessResult(
    proces.pid,
    kod,
    await wyjscie.timeout(const Duration(seconds: 2), onTimeout: () => ''),
    await bledy.timeout(const Duration(seconds: 2), onTimeout: () => ''),
  );
}

/// Jeden węzeł drzewa widoków: to, po czym go szukamy, i jego środek.
class UiNode {
  final String text;
  final String desc;
  final String cls;
  final String package;
  final bool focused;
  final bool checked;
  final int x;
  final int y;

  const UiNode({
    required this.text,
    required this.desc,
    required this.cls,
    required this.package,
    required this.focused,
    required this.checked,
    required this.x,
    required this.y,
  });

  bool get isEditText => cls.endsWith('EditText');
}

String _attr(String node, String name) {
  final m = RegExp('$name="([^"]*)"').firstMatch(node);
  return m == null ? '' : _unescape(m.group(1)!);
}

String _unescape(String s) => s
    .replaceAll('&#10;', '\n')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Zrzut drzewa widoków. Bierzemy go w pętli, bo `uiautomator dump` czeka na
/// „spokojne" okno i przy animacjach Fluttera potrafi się poddać. Bez
/// sprawdzenia, czy zrzut faktycznie powstał, czytalibyśmy poprzedni plik
/// i szukali przycisku na nieaktualnym ekranie. `null` = nie udało się.
Future<List<UiNode>?> uiNodes() async {
  const dump = '/sdcard/chatt_ui.xml';
  for (var proba = 0; proba < 4; proba++) {
    // `--windows` bierze wszystkie okna naraz, także pasek klawiatury, który
    // jest osobnym oknem; starszy uiautomator go nie zna, wtedy samo
    // aktywne okno.
    final dumped = await adb([
      'shell', 'uiautomator', 'dump',
      if (proba.isEven) '--windows',
      dump,
    ], limit: const Duration(seconds: 15));
    if (dumped.exitCode == -1) {
      // Zawieszony zrzut na urządzeniu blokuje następne: zabić go tam.
      await adb(['shell', 'pkill', '-f', 'uiautomator']);
      continue;
    }
    if (!'${dumped.stdout}'.contains(dump)) continue;
    final xml = (await adb(['shell', 'cat', dump])).stdout as String;
    final wezly = <UiNode>[];
    for (final node in xml.split('<node ').skip(1)) {
      final bounds =
          RegExp(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"').firstMatch(node);
      if (bounds == null) continue;
      wezly.add(UiNode(
        text: _attr(node, 'text'),
        desc: _attr(node, 'content-desc'),
        cls: _attr(node, 'class'),
        package: _attr(node, 'package'),
        focused: _attr(node, 'focused') == 'true',
        checked: _attr(node, 'checked') == 'true',
        x: (int.parse(bounds.group(1)!) + int.parse(bounds.group(3)!)) ~/ 2,
        y: (int.parse(bounds.group(2)!) + int.parse(bounds.group(4)!)) ~/ 2,
      ));
    }
    return wezly;
  }
  return null;
}

/// Środek widgetu o danej etykiecie. Flutter wystawia teksty jako
/// `content-desc`, systemowe widoki jako `text`. Zwraca null, gdy przez
/// [timeout] nic takiego się nie pojawiło. [fragment] dopasowuje po kawałku
/// opisu, bo Flutter potrafi scalić całą kartę czy wiersz listy w jeden węzeł.
/// Ta sama etykieta bywa na ekranie kilka razy; [ostatni] bierze najniższą.
/// [pakiet] zawęża szukanie do jednej aplikacji: na telefonie, którego ktoś
/// używa, „Ustawienia" stoją też w menu klawiatury.
Future<(int, int)?> findWidget(
  String label, {
  Duration timeout = const Duration(seconds: 15),
  bool fragment = false,
  bool ostatni = false,
  String? pakiet,
}) async =>
    (await findAnyWidget([label],
            timeout: timeout,
            fragment: fragment,
            ostatni: ostatni,
            pakiet: pakiet))
        ?.$2;

/// Jak [findWidget], dla kilku etykiet naraz (wersje językowe): każdy zrzut
/// drzewa sprawdza wszystkie, więc każda ma cały [timeout]. Zwraca etykietę,
/// która się znalazła, i środek widgetu.
Future<(String, (int, int))?> findAnyWidget(
  List<String> etykiety, {
  Duration timeout = const Duration(seconds: 15),
  bool fragment = false,
  bool ostatni = false,
  String? pakiet,
}) async {
  final koniec = DateTime.now().add(timeout);
  do {
    final wezly = await uiNodes() ?? const <UiNode>[];
    for (final label in etykiety) {
      (int, int)? znaleziony;
      for (final w in wezly) {
        if (pakiet != null && w.package != pakiet) continue;
        final pasuje = fragment
            ? (w.desc.contains(label) || w.text.contains(label))
            : (w.desc == label || w.text == label);
        if (!pasuje) continue;
        znaleziony = (w.x, w.y);
        if (!ostatni) break;
      }
      if (znaleziony != null) return (label, znaleziony);
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  } while (DateTime.now().isBefore(koniec));
  return null;
}

/// Na telefonie, którego ktoś używa na co dzień, ekran niesie cudze
/// rozmowy: wtedy komunikaty błędów mówią tylko, ile węzłów widać.
bool ukryjTrescEkranu = false;

/// Etykiety widoczne na ekranie, do komunikatu błędu, żeby nie trzeba było
/// zgadywać, na czym test się potknął.
Future<String> widocznaTresc() async {
  final wezly = await uiNodes();
  if (ukryjTrescEkranu) {
    return wezly == null
        ? 'nie udało się zrzucić drzewa'
        : '${wezly.length} węzłów (treść ukryta)';
  }
  if (wezly == null) return 'nie udało się zrzucić drzewa';
  return wezly
      .map((w) => w.desc.isNotEmpty ? w.desc : w.text)
      .where((s) => s.isNotEmpty)
      .map((s) => s.replaceAll('\n', ' / '))
      .take(14)
      .join(' | ');
}

/// Klik w cokolwiek podpisanego jedną z [etykiety]. Kilka, bo aplikacja na
/// urządzeniu może być po polsku albo po angielsku, a test nie ma powodu tego
/// wymuszać.
///
/// [azZniknie] stuka ponownie, dopóki etykieta nie zniknie z ekranu (najwyżej
/// trzy razy): stuknięcie w kartę, która jeszcze się układa, potrafi przepaść.
Future<void> stuknijEtykiete(
  List<String> etykiety, {
  bool fragment = false,
  bool ostatni = false,
  bool azZniknie = false,
  Duration timeout = const Duration(seconds: 15),
  String? pakiet,
}) async {
  final trafienie = await findAnyWidget(etykiety,
      fragment: fragment, ostatni: ostatni, timeout: timeout, pakiet: pakiet);
  if (trafienie == null) {
    throw StateError('Nie znalazłem na ekranie: ${etykiety.first}. '
        'Co widać: ${await widocznaTresc()}');
  }
  final etykieta = trafienie.$1;
  (int, int)? gdzie = trafienie.$2;
  for (var proba = 0; proba < 3 && gdzie != null; proba++) {
    await adb(['shell', 'input', 'tap', '${gdzie.$1}', '${gdzie.$2}']);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!azZniknie) return;
    gdzie = await findWidget(etykieta,
        fragment: fragment,
        ostatni: ostatni,
        pakiet: pakiet,
        timeout: const Duration(seconds: 2));
  }
}

/// Pole tekstowe z fokusem i jego treść (`text=` z drzewa widoków). Puste
/// pole Android pokazuje tam podpowiedź, więc treść porównuje się
/// z oczekiwanym tekstem.
Future<UiNode?> poleZFokusem() async {
  final wezly = await uiNodes() ?? const <UiNode>[];
  for (final w in wezly) {
    if (w.focused && w.isEditText) return w;
  }
  return null;
}

/// Czy na ekranie jest pole tekstowe z taką treścią. Część aplikacji
/// (Kontakty) dokleja w `text=` podpowiedź po przecinku: „Chatt, Name".
Future<bool> jestPoleZTekstem(String tekst) async {
  for (final w in await uiNodes() ?? const <UiNode>[]) {
    if (w.isEditText && (w.text == tekst || w.text.startsWith('$tekst, '))) {
      return true;
    }
  }
  return false;
}

/// Stuknięcie w [ktore] z kolei pole tekstowe na ekranie (licząc od góry).
/// Etykiety pól zależą od języka i wersji aplikacji, klasa nie.
Future<void> stuknijPole({int ktore = 0}) async {
  final koniec = DateTime.now().add(const Duration(seconds: 15));
  do {
    final pola = [
      for (final w in await uiNodes() ?? const <UiNode>[])
        if (w.isEditText) w,
    ];
    if (pola.length > ktore) {
      final pole = pola[ktore];
      await adb(['shell', 'input', 'tap', '${pole.x}', '${pole.y}']);
      await Future<void>.delayed(const Duration(seconds: 1));
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  } while (DateTime.now().isBefore(koniec));
  throw StateError('Nie ma na ekranie pola tekstowego nr $ktore. '
      'Co widać: ${await widocznaTresc()}');
}

/// Czeka, aż prośba [prosba] się rozstrzygnie albo w aplikacji [pakiet]
/// pojawi się jedna z [etykiety]. Zwraca wynik prośby, gdy przyszedł, a `null`,
/// gdy pojawiła się etykieta. Zrzuty idą po kolei: dwa `uiautomator dump`
/// naraz wywracają się na urządzeniu („UiAutomationService already
/// registered").
Future<T?> czekajNaKarteAlbo<T>(Future<T> prosba, List<String> etykiety,
    {required String pakiet,
    Duration timeout = const Duration(seconds: 30)}) async {
  T? wynik;
  var gotowe = false;
  unawaited(prosba.then((w) {
    wynik = w;
    gotowe = true;
  }));
  final koniec = DateTime.now().add(timeout);
  while (!gotowe && DateTime.now().isBefore(koniec)) {
    if (await findAnyWidget(etykiety,
            pakiet: pakiet, timeout: const Duration(seconds: 1)) !=
        null) {
      return null;
    }
  }
  return wynik;
}

/// Kategoria Ustawień „Klawiatura z PC". Ta sama nazwa stoi też w tytule
/// otwartej kategorii i w tytule przełącznika dodatku.
const kategoriaKlawiatury = ['Keyboard from a PC', 'Klawiatura z PC'];

/// Przełącznik dodatku „Klawiatura z PC" po podpisie, jedynym napisie
/// w kategorii, który ma tylko on. Angielski bez apostrofu z „computer's".
const przelacznikKlawiatury = [
  'Typing from a computer',
  'Pisanie z klawiatury komputera',
];

/// Przełącznik odbioru w karcie dodatku „Klawiatura z PC".
const odbiorKlawiatury = [
  'Allow typing on this device',
  'Pozwól pisać na tym urządzeniu',
];

/// Wraca w aplikacji [pakiet] na listę rozmów: stuka strzałkę wstecz
/// w pasku, dopóki jakaś jest, najwyżej [ile] razy. Aplikacja wraca na
/// ekranie, na którym ją zostawiono, a z kategorii Ustawień strzałka
/// prowadzi najpierw na listę kategorii. Etykieta dokładnie: „Background
/// listening" na liście kategorii też zawiera „Back".
Future<void> wrocDoListyRozmow(String pakiet, {int ile = 4}) async {
  for (var i = 0; i < ile; i++) {
    final wstecz = await findAnyWidget(['Back', 'Wstecz'],
        pakiet: pakiet, timeout: const Duration(seconds: 2));
    if (wstecz == null) return;
    await adb(['shell', 'input', 'tap', '${wstecz.$2.$1}', '${wstecz.$2.$2}']);
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}

/// Otwiera w aplikacji [pakiet] kategorię Ustawień o nazwie z [nazwy]
/// (wersje językowe): z listy rozmów koło zębate, potem wiersz kategorii.
/// Wiersz to jeden węzeł z nazwą i streszczeniem („Nazwa\nStreszczenie"),
/// więc szukamy go po fragmencie.
Future<void> otworzKategorieUstawien(String pakiet, List<String> nazwy) async {
  await wrocDoListyRozmow(pakiet);
  await stuknijEtykiete(['Settings', 'Ustawienia'], pakiet: pakiet);
  await stuknijEtykiete(nazwy, fragment: true, pakiet: pakiet);
}

/// Dodatek „Klawiatura z PC" i „Pozwól pisać na tym urządzeniu" w aplikacji
/// [pakiet], gdy prośba o sesję dostała `not_enabled`. Stuka wyłącznie
/// w elementy tej aplikacji. Wyłączony dodatek gasi też odbiór, więc gdy
/// przełącznika odbioru nie widać, najpierw idzie sam dodatek. Na koniec
/// aplikacja wraca na listę rozmów.
Future<void> wlaczDodatekKlawiatury(String pakiet) async {
  await adb([
    'shell', 'monkey', '-p', pakiet, '-c',
    'android.intent.category.LAUNCHER', '1',
  ]);
  await Future<void>.delayed(const Duration(seconds: 2));
  await otworzKategorieUstawien(pakiet, kategoriaKlawiatury);
  // Kategoria jest krótka: oba przełączniki stoją pod paskiem, bez
  // przewijania.
  final odbiorWidac = await findAnyWidget(odbiorKlawiatury,
          fragment: true, pakiet: pakiet, timeout: const Duration(seconds: 2)) !=
      null;
  if (!odbiorWidac) {
    await stuknijEtykiete(przelacznikKlawiatury,
        fragment: true, pakiet: pakiet);
  }
  await stuknijEtykiete(odbiorKlawiatury, fragment: true, pakiet: pakiet);
  await Future<void>.delayed(const Duration(seconds: 2));
  await wrocDoListyRozmow(pakiet);
}

/// Zrzut ekranu urządzenia do pliku (do dokumentacji i podglądu, co się stało).
Future<void> screenshot(String path) async {
  final result = await Process.run(
      adbPath, ['-s', deviceId, 'exec-out', 'screencap', '-p'],
      stdoutEncoding: null);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(result.stdout as List<int>);
}
