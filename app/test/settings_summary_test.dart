import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/version.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/network/protocol.dart' show defaultTcpPort;
import 'package:chatt/ui/backgrounds.dart';
import 'package:chatt/ui/screens/settings/settings_section.dart';
import 'package:chatt/ui/screens/settings/settings_summary.dart';

/// Streszczenia pod nazwami kategorii Ustawień, ich trzecie linie i karty
/// listy kategorii (issue #71). Funkcje są czyste, więc test bez widgetów
/// sprawdza dokładne napisy po polsku i po angielsku. Oczekiwane napisy
/// stoją dosłownie: wartości z plików arb złożone według reguł streszczeń.
void main() {
  final pl = lookupAppLocalizations(const Locale('pl'));
  final en = lookupAppLocalizations(const Locale('en'));

  const android = TargetPlatform.android;
  const windows = TargetPlatform.windows;

  const profil = SettingsSection.profile;
  const polaczenie = SettingsSection.connection;
  const nasluch = SettingsSection.backgroundListening;
  const klawiatura = SettingsSection.keyboard;
  const wyglad = SettingsSection.appearance;
  const prywatnosc = SettingsSection.privacy;
  const dane = SettingsSection.data;
  const aktualizacje = SettingsSection.updates;

  /// Streszczenie kategorii w obu językach.
  void streszczenia(
    SettingsSection kategoria,
    StanUstawien stan,
    String poPolsku,
    String poAngielsku,
  ) {
    expect(streszczenie(kategoria, stan, pl), poPolsku);
    expect(streszczenie(kategoria, stan, en), poAngielsku);
  }

  /// Trzecia linia w kolorze ostrzeżenia, w obu językach.
  void problemy(
    SettingsSection kategoria,
    StanUstawien stan,
    String poPolsku,
    String poAngielsku,
  ) {
    expect(linia(kategoria, stan, pl), (tekst: poPolsku, problem: true));
    expect(linia(kategoria, stan, en), (tekst: poAngielsku, problem: true));
  }

  /// Wiersz kategorii bez trzeciej linii, w obu językach.
  void bezLinii(SettingsSection kategoria, StanUstawien stan) {
    expect(linia(kategoria, stan, pl), isNull, reason: '$kategoria');
    expect(linia(kategoria, stan, en), isNull, reason: '$kategoria');
  }

  /// Każdy kłopot i nowość naraz.
  const wszystkieKlopoty = StanUstawien(
    platforma: android,
    wifiEnabled: false,
    bluetoothAddon: true,
    discoveryListening: false,
    keyProtected: false,
    batteryOptimized: true,
    availableVersion: '10.0.0',
    typingSessions: 3,
  );

  /// Wszystko włączone i działające.
  const wszystkoDziala = StanUstawien(
    platforma: windows,
    nickname: 'Komputer',
    welcomeMessage: 'Cześć',
    tcpPort: 50123,
    style: AppStyle.cieplo,
    theme: AppTheme.dark,
    background: 2,
    language: AppLanguage.polish,
    retentionDays: 30,
    linkPreviews: true,
    updateChecks: true,
    bluetoothAddon: true,
    bluetoothRunning: true,
    bluetoothRadioOn: true,
    bluetoothGranted: true,
    internetAddon: true,
    keyboardAddon: true,
    remoteInputReceive: true,
    typingSessions: 12,
    autostart: true,
  );

  /// Stany od świeżej instalacji przez wszystkie kłopoty naraz po wszystko
  /// działające.
  const rozneStany = <StanUstawien>[
    StanUstawien(platforma: android),
    StanUstawien(platforma: windows),
    StanUstawien(platforma: TargetPlatform.linux),
    wszystkieKlopoty,
    wszystkoDziala,
  ];

  group('Profil', () {
    test('bez wiadomości powitalnej stoi sam nick', () {
      streszczenia(
        profil,
        const StanUstawien(platforma: android, nickname: 'Telefon'),
        'Telefon',
        'Telefon',
      );
    });

    test('wiadomość powitalna stoi za nickiem w cudzysłowie języka', () {
      streszczenia(
        profil,
        const StanUstawien(
          platforma: android,
          nickname: 'Telefon',
          welcomeMessage: 'Cześć, tu Ola',
        ),
        'Telefon · „Cześć, tu Ola”',
        'Telefon · “Cześć, tu Ola”',
      );
    });
  });

  group('Połączenie', () {
    test('świeża instalacja: sieć lokalna i domyślny port', () {
      streszczenia(
        polaczenie,
        const StanUstawien(platforma: android),
        'Sieć lokalna · port 47780',
        'Local network · port 47780',
      );
    });

    test('bez dodatku Bluetooth sieć lokalna stoi zawsze, także przy '
        'wifiEnabled false', () {
      streszczenia(
        polaczenie,
        const StanUstawien(platforma: android, wifiEnabled: false),
        'Sieć lokalna · port 47780',
        'Local network · port 47780',
      );
    });

    test('dodatek Bluetooth przy włączonej sieci lokalnej', () {
      streszczenia(
        polaczenie,
        const StanUstawien(platforma: android, bluetoothAddon: true),
        'Sieć lokalna i Bluetooth · port 47780',
        'Local network and Bluetooth · port 47780',
      );
    });

    test('sam Bluetooth przy wyłączonej sieci lokalnej', () {
      streszczenia(
        polaczenie,
        const StanUstawien(
          platforma: android,
          bluetoothAddon: true,
          wifiEnabled: false,
        ),
        'Bluetooth · port 47780',
        'Bluetooth · port 47780',
      );
    });

    test('trzy drogi: przecinek po pierwszej i spójnik przed ostatnią', () {
      streszczenia(
        polaczenie,
        const StanUstawien(
          platforma: windows,
          bluetoothAddon: true,
          internetAddon: true,
        ),
        'Sieć lokalna, Bluetooth i Internet · port 47780',
        'Local network, Bluetooth and Internet · port 47780',
      );
    });

    test('Internet obok sieci lokalnej', () {
      streszczenia(
        polaczenie,
        const StanUstawien(platforma: windows, internetAddon: true),
        'Sieć lokalna i Internet · port 47780',
        'Local network and Internet · port 47780',
      );
    });

    test('Bluetooth i Internet przy wyłączonej sieci lokalnej', () {
      streszczenia(
        polaczenie,
        const StanUstawien(
          platforma: android,
          bluetoothAddon: true,
          wifiEnabled: false,
          internetAddon: true,
        ),
        'Bluetooth i Internet · port 47780',
        'Bluetooth and Internet · port 47780',
      );
    });

    test('port w streszczeniu to preferowany port z bazy', () {
      streszczenia(
        polaczenie,
        const StanUstawien(platforma: windows, tcpPort: 50123),
        'Sieć lokalna · port 50123',
        'Local network · port 50123',
      );
    });

    test('zdrowe połączenie nie ma trzeciej linii', () {
      bezLinii(polaczenie, const StanUstawien(platforma: android));
      bezLinii(
        polaczenie,
        const StanUstawien(
          platforma: android,
          bluetoothAddon: true,
          bluetoothRunning: true,
          bluetoothRadioOn: true,
          bluetoothGranted: true,
          internetAddon: true,
        ),
      );
    });

    test('sieć lokalna wyłączona i Bluetooth stoi: z nikim się nie '
        'skontaktuje, przed każdym innym kłopotem', () {
      // Radio zgaszone i bez zgody: to wartości domyślne.
      problemy(
        polaczenie,
        const StanUstawien(
          platforma: android,
          bluetoothAddon: true,
          wifiEnabled: false,
        ),
        'To urządzenie z nikim się nie skontaktuje',
        'This device will reach nobody',
      );
      problemy(
        polaczenie,
        const StanUstawien(
          platforma: android,
          bluetoothAddon: true,
          wifiEnabled: false,
          discoveryListening: false,
        ),
        'To urządzenie z nikim się nie skontaktuje',
        'This device will reach nobody',
      );
    });

    test('działająca droga internetowa: bez „z nikim się nie '
        'skontaktuje”, zostaje kłopot z radiem', () {
      // Internet łączy z potwierdzonymi urządzeniami także bez sieci
      // lokalnej i radia.
      problemy(
        polaczenie,
        const StanUstawien(
          platforma: android,
          bluetoothAddon: true,
          wifiEnabled: false,
          internetAddon: true,
          internetRunning: true,
        ),
        'Włącz Bluetooth w ustawieniach systemu.',
        'Turn Bluetooth on in the system settings.',
      );
    });

    test('głuche wykrywanie: inni nie znajdą urządzenia, przed kłopotami '
        'radia', () {
      const gluche = StanUstawien(
        platforma: windows,
        discoveryListening: false,
      );
      problemy(
        polaczenie,
        gluche,
        'Inni nie znajdą tego urządzenia',
        'Others will not find this device',
      );
      // Kłopot stoi w trzeciej linii, streszczenie się nie zmienia.
      streszczenia(
        polaczenie,
        gluche,
        'Sieć lokalna · port 47780',
        'Local network · port 47780',
      );
      problemy(
        polaczenie,
        const StanUstawien(
          platforma: android,
          bluetoothAddon: true,
          discoveryListening: false,
        ),
        'Inni nie znajdą tego urządzenia',
        'Others will not find this device',
      );
      // Bluetooth działa przy wyłączonej sieci lokalnej.
      problemy(
        polaczenie,
        const StanUstawien(
          platforma: android,
          bluetoothAddon: true,
          bluetoothRunning: true,
          wifiEnabled: false,
          discoveryListening: false,
        ),
        'Inni nie znajdą tego urządzenia',
        'Others will not find this device',
      );
    });

    test('zgaszone radio, przed brakiem zgody', () {
      problemy(
        polaczenie,
        const StanUstawien(platforma: android, bluetoothAddon: true),
        'Włącz Bluetooth w ustawieniach systemu.',
        'Turn Bluetooth on in the system settings.',
      );
    });

    test('brak zgody na urządzenia w pobliżu przy włączonym radiu', () {
      problemy(
        polaczenie,
        const StanUstawien(
          platforma: android,
          bluetoothAddon: true,
          bluetoothRadioOn: true,
        ),
        'Chatt nie ma zgody na urządzenia w pobliżu.',
        'Chatt has no permission for nearby devices.',
      );
    });

    test('działający Bluetooth bez kłopotu, nawet przy zgaszonym radiu '
        'i braku zgody w stanie z systemu', () {
      bezLinii(
        polaczenie,
        const StanUstawien(
          platforma: android,
          bluetoothAddon: true,
          bluetoothRunning: true,
        ),
      );
      bezLinii(
        polaczenie,
        const StanUstawien(
          platforma: android,
          bluetoothAddon: true,
          bluetoothRunning: true,
          wifiEnabled: false,
        ),
      );
    });

    test('wyłączony dodatek Bluetooth bez kłopotów radia i zgody', () {
      bezLinii(polaczenie, const StanUstawien(platforma: android));
      bezLinii(
        polaczenie,
        const StanUstawien(platforma: android, wifiEnabled: false),
      );
    });

    test('radio i zgoda są, Bluetooth jeszcze wstaje: bez trzeciej linii', () {
      bezLinii(
        polaczenie,
        const StanUstawien(
          platforma: android,
          bluetoothAddon: true,
          bluetoothRadioOn: true,
          bluetoothGranted: true,
        ),
      );
    });
  });

  group('Nasłuch w tle', () {
    test('Android bez usypiania: bez trzeciej linii', () {
      const stan = StanUstawien(platforma: android);
      streszczenia(
        nasluch,
        stan,
        'System nie usypia Chatta',
        'The system does not doze Chatt',
      );
      bezLinii(nasluch, stan);
      // Autostart to sprawa Windows.
      streszczenia(
        nasluch,
        const StanUstawien(platforma: android, autostart: true),
        'System nie usypia Chatta',
        'The system does not doze Chatt',
      );
    });

    test('Android usypia Chatta: streszczenie i ostrzeżenie', () {
      const stan = StanUstawien(platforma: android, batteryOptimized: true);
      streszczenia(
        nasluch,
        stan,
        'Android usypia Chatta',
        'Android dozes Chatt',
      );
      problemy(
        nasluch,
        stan,
        'Wiadomości mogą nie dochodzić przy zgaszonym ekranie',
        'Messages may not arrive with the screen off',
      );
    });

    test('Windows: start razem z systemem albo ręczny, bez trzeciej linii', () {
      const zSystemem = StanUstawien(platforma: windows, autostart: true);
      streszczenia(
        nasluch,
        zSystemem,
        'Start razem z Windowsem',
        'Starts with Windows',
      );
      bezLinii(nasluch, zSystemem);
      const reczny = StanUstawien(platforma: windows);
      streszczenia(nasluch, reczny, 'Start ręczny', 'Manual start');
      bezLinii(nasluch, reczny);
      // Bateria to sprawa Androida.
      const zBateria = StanUstawien(platforma: windows, batteryOptimized: true);
      streszczenia(nasluch, zBateria, 'Start ręczny', 'Manual start');
      bezLinii(nasluch, zBateria);
    });

    test('Linux: puste streszczenie i bez trzeciej linii', () {
      const stan = StanUstawien(
        platforma: TargetPlatform.linux,
        batteryOptimized: true,
        autostart: true,
      );
      streszczenia(nasluch, stan, '', '');
      bezLinii(nasluch, stan);
    });
  });

  group('Klawiatura z PC', () {
    test('wyłączona bez sesji', () {
      streszczenia(
        klawiatura,
        const StanUstawien(platforma: windows),
        'Wyłączona',
        'Off',
      );
    });

    test('wyłączona z sesjami w historii: liczba z odmianą', () {
      const przypadki = [
        (
          1,
          'Wyłączona · 1 sesja w historii pisania',
          'Off · 1 session in typing history',
        ),
        (
          2,
          'Wyłączona · 2 sesje w historii pisania',
          'Off · 2 sessions in typing history',
        ),
        (
          5,
          'Wyłączona · 5 sesji w historii pisania',
          'Off · 5 sessions in typing history',
        ),
        (
          12,
          'Wyłączona · 12 sesji w historii pisania',
          'Off · 12 sessions in typing history',
        ),
        (
          22,
          'Wyłączona · 22 sesje w historii pisania',
          'Off · 22 sessions in typing history',
        ),
      ];
      for (final (sesje, poPolsku, poAngielsku) in przypadki) {
        streszczenia(
          klawiatura,
          StanUstawien(platforma: windows, typingSessions: sesje),
          poPolsku,
          poAngielsku,
        );
      }
    });

    test('wyłączona: odbiór i historia pisania nie trafiają do linii', () {
      streszczenia(
        klawiatura,
        const StanUstawien(
          platforma: android,
          remoteInputReceive: true,
          typingHistory: false,
        ),
        'Wyłączona',
        'Off',
      );
    });

    test('włączona z pisaniem na tym urządzeniu albo bez', () {
      streszczenia(
        klawiatura,
        const StanUstawien(
          platforma: android,
          keyboardAddon: true,
          remoteInputReceive: true,
        ),
        'Włączona · pisanie na tym urządzeniu · z historią pisania',
        'On · typing on this device · with typing history',
      );
      streszczenia(
        klawiatura,
        const StanUstawien(platforma: android, keyboardAddon: true),
        'Włączona · bez pisania na tym urządzeniu · z historią pisania',
        'On · no typing on this device · with typing history',
      );
    });

    test('włączona bez ujścia do pisania: fakt o pisaniu wypada', () {
      streszczenia(
        klawiatura,
        const StanUstawien(
          platforma: windows,
          keyboardAddon: true,
          remoteInputReceiveSupported: false,
          remoteInputReceive: true,
        ),
        'Włączona · z historią pisania',
        'On · with typing history',
      );
      streszczenia(
        klawiatura,
        const StanUstawien(
          platforma: windows,
          keyboardAddon: true,
          remoteInputReceiveSupported: false,
          typingHistory: false,
        ),
        'Włączona · bez historii pisania',
        'On · no typing history',
      );
    });

    test('włączona bez historii pisania', () {
      streszczenia(
        klawiatura,
        const StanUstawien(
          platforma: android,
          keyboardAddon: true,
          typingHistory: false,
        ),
        'Włączona · bez pisania na tym urządzeniu · bez historii pisania',
        'On · no typing on this device · no typing history',
      );
      streszczenia(
        klawiatura,
        const StanUstawien(
          platforma: android,
          keyboardAddon: true,
          remoteInputReceive: true,
          typingHistory: false,
        ),
        'Włączona · pisanie na tym urządzeniu · bez historii pisania',
        'On · typing on this device · no typing history',
      );
    });

    test('liczba sesji stoi tylko przy wyłączonym dodatku', () {
      streszczenia(
        klawiatura,
        const StanUstawien(
          platforma: android,
          keyboardAddon: true,
          typingSessions: 5,
        ),
        'Włączona · bez pisania na tym urządzeniu · z historią pisania',
        'On · no typing on this device · with typing history',
      );
    });
  });

  group('Wygląd', () {
    test('świeża instalacja: Cisza, motyw systemowy, angielski', () {
      streszczenia(
        wyglad,
        const StanUstawien(platforma: android),
        'Cisza · motyw systemowy · angielski',
        'Calm · system theme · English',
      );
    });

    test('nazwa każdego stylu', () {
      const przypadki = [
        (
          AppStyle.cisza,
          'Cisza · motyw systemowy · angielski',
          'Calm · system theme · English',
        ),
        (
          AppStyle.precyzja,
          'Precyzja · motyw systemowy · angielski',
          'Precise · system theme · English',
        ),
        (
          AppStyle.cieplo,
          'Ciepło · motyw systemowy · angielski',
          'Warm · system theme · English',
        ),
      ];
      expect([for (final p in przypadki) p.$1], AppStyle.values);
      for (final (styl, poPolsku, poAngielsku) in przypadki) {
        streszczenia(
          wyglad,
          StanUstawien(platforma: android, style: styl),
          poPolsku,
          poAngielsku,
        );
      }
    });

    test('motyw systemowy, jasny i ciemny', () {
      const przypadki = [
        (
          AppTheme.system,
          'Cisza · motyw systemowy · angielski',
          'Calm · system theme · English',
        ),
        (AppTheme.light, 'Cisza · jasny · angielski', 'Calm · light · English'),
        (AppTheme.dark, 'Cisza · ciemny · angielski', 'Calm · dark · English'),
      ];
      expect([for (final p in przypadki) p.$1], AppTheme.values);
      for (final (motyw, poPolsku, poAngielsku) in przypadki) {
        streszczenia(
          wyglad,
          StanUstawien(platforma: android, theme: motyw),
          poPolsku,
          poAngielsku,
        );
      }
    });

    test('tło: „Bez tła” wypada z linii, pozostałe stoją po motywie', () {
      const przypadki = [
        (
          0,
          'Cisza · motyw systemowy · angielski',
          'Calm · system theme · English',
        ),
        (
          1,
          'Cisza · motyw systemowy · Zmierzch · angielski',
          'Calm · system theme · Dusk · English',
        ),
        (
          2,
          'Cisza · motyw systemowy · Ocean · angielski',
          'Calm · system theme · Ocean · English',
        ),
        (
          3,
          'Cisza · motyw systemowy · Las · angielski',
          'Calm · system theme · Forest · English',
        ),
        (
          4,
          'Cisza · motyw systemowy · Piasek · angielski',
          'Calm · system theme · Sand · English',
        ),
      ];
      expect(
        przypadki,
        hasLength(chattBackgrounds.length),
        reason: 'każde tło ma tu swój przypadek',
      );
      for (final (tlo, poPolsku, poAngielsku) in przypadki) {
        streszczenia(
          wyglad,
          StanUstawien(platforma: android, background: tlo),
          poPolsku,
          poAngielsku,
        );
      }
    });

    test('tło spoza listy, np. z nowszego Chatta, wypada jak „Bez tła”', () {
      // Aplikacja pokazuje wtedy kolor tła stylu (backgroundAt w app.dart).
      streszczenia(
        wyglad,
        StanUstawien(platforma: android, background: chattBackgrounds.length),
        'Cisza · motyw systemowy · angielski',
        'Calm · system theme · English',
      );
    });

    test('język: systemowy wypada z linii, polski i angielski stoją na '
        'końcu', () {
      const przypadki = [
        (AppLanguage.system, 'Cisza · motyw systemowy', 'Calm · system theme'),
        (
          AppLanguage.polish,
          'Cisza · motyw systemowy · polski',
          'Calm · system theme · Polish',
        ),
        (
          AppLanguage.english,
          'Cisza · motyw systemowy · angielski',
          'Calm · system theme · English',
        ),
      ];
      expect([for (final p in przypadki) p.$1], AppLanguage.values);
      for (final (jezyk, poPolsku, poAngielsku) in przypadki) {
        streszczenia(
          wyglad,
          StanUstawien(platforma: android, language: jezyk),
          poPolsku,
          poAngielsku,
        );
      }
    });

    test('przykłady z issue i wszystko naraz', () {
      streszczenia(
        wyglad,
        const StanUstawien(
          platforma: android,
          theme: AppTheme.light,
          language: AppLanguage.polish,
        ),
        'Cisza · jasny · polski',
        'Calm · light · Polish',
      );
      streszczenia(
        wyglad,
        const StanUstawien(
          platforma: android,
          theme: AppTheme.dark,
          background: 2,
          language: AppLanguage.polish,
        ),
        'Cisza · ciemny · Ocean · polski',
        'Calm · dark · Ocean · Polish',
      );
      streszczenia(
        wyglad,
        const StanUstawien(
          platforma: windows,
          style: AppStyle.cieplo,
          theme: AppTheme.dark,
          background: 4,
          language: AppLanguage.system,
        ),
        'Ciepło · ciemny · Piasek',
        'Warm · dark · Sand',
      );
    });
  });

  group('Prywatność', () {
    test('świeża instalacja: nie kasuj, bez podglądów stron', () {
      streszczenia(
        prywatnosc,
        const StanUstawien(platforma: android),
        'Nie kasuj · bez podglądów stron',
        'Never delete · no link previews',
      );
    });

    test('kasowanie po dniach: liczba z odmianą', () {
      const przypadki = [
        (
          1,
          'Kasowanie po 1 dniu · bez podglądów stron',
          'Deleting after 1 day · no link previews',
        ),
        (
          7,
          'Kasowanie po 7 dniach · bez podglądów stron',
          'Deleting after 7 days · no link previews',
        ),
        (
          30,
          'Kasowanie po 30 dniach · bez podglądów stron',
          'Deleting after 30 days · no link previews',
        ),
        (
          90,
          'Kasowanie po 90 dniach · bez podglądów stron',
          'Deleting after 90 days · no link previews',
        ),
        (
          365,
          'Kasowanie po 365 dniach · bez podglądów stron',
          'Deleting after 365 days · no link previews',
        ),
      ];
      for (final (dni, poPolsku, poAngielsku) in przypadki) {
        streszczenia(
          prywatnosc,
          StanUstawien(platforma: android, retentionDays: dni),
          poPolsku,
          poAngielsku,
        );
      }
    });

    test('podglądy stron włączone', () {
      streszczenia(
        prywatnosc,
        const StanUstawien(platforma: android, linkPreviews: true),
        'Nie kasuj · z podglądami stron',
        'Never delete · with link previews',
      );
      streszczenia(
        prywatnosc,
        const StanUstawien(
          platforma: android,
          retentionDays: 30,
          linkPreviews: true,
        ),
        'Kasowanie po 30 dniach · z podglądami stron',
        'Deleting after 30 days · with link previews',
      );
    });

    test('klucz obok bazy: ostrzeżenie w trzeciej linii', () {
      const stan = StanUstawien(platforma: windows, keyProtected: false);
      problemy(
        prywatnosc,
        stan,
        'Klucz do historii leży obok bazy',
        'The history key sits next to the database',
      );
      streszczenia(
        prywatnosc,
        stan,
        'Nie kasuj · bez podglądów stron',
        'Never delete · no link previews',
      );
      bezLinii(prywatnosc, const StanUstawien(platforma: windows));
    });
  });

  test('Dane i diagnostyka: stała linia z tym, co jest w kategorii', () {
    for (final stan in rozneStany) {
      streszczenia(
        dane,
        stan,
        'Eksport danych · dziennik aplikacji',
        'Data export · app log',
      );
    }
  });

  group('Aktualizacje', () {
    test('wersja i sprawdzanie ręczne albo automatyczne', () {
      streszczenia(
        aktualizacje,
        const StanUstawien(platforma: windows, appVersion: '9.9.9'),
        'Wersja 9.9.9 · sprawdzanie ręczne',
        'Version 9.9.9 · checked by hand',
      );
      streszczenia(
        aktualizacje,
        const StanUstawien(
          platforma: windows,
          appVersion: '9.9.9',
          updateChecks: true,
        ),
        'Wersja 9.9.9 · sprawdzane automatycznie',
        'Version 9.9.9 · checked automatically',
      );
    });

    test('domyślna wersja to appVersion z core/version.dart', () {
      const stan = StanUstawien(platforma: android);
      expect(stan.appVersion, appVersion);
      streszczenia(
        aktualizacje,
        stan,
        'Wersja $appVersion · sprawdzanie ręczne',
        'Version $appVersion · checked by hand',
      );
    });

    test('nowe wydanie: nowość w trzeciej linii bez koloru ostrzeżenia', () {
      const stan = StanUstawien(
        platforma: android,
        appVersion: '9.9.9',
        availableVersion: '10.0.0',
      );
      expect(linia(aktualizacje, stan, pl), (
        tekst: 'Wyszła wersja 10.0.0',
        problem: false,
      ));
      expect(linia(aktualizacje, stan, en), (
        tekst: 'Version 10.0.0 is out',
        problem: false,
      ));
      streszczenia(
        aktualizacje,
        stan,
        'Wersja 9.9.9 · sprawdzanie ręczne',
        'Version 9.9.9 · checked by hand',
      );
      bezLinii(
        aktualizacje,
        const StanUstawien(platforma: android, appVersion: '9.9.9'),
      );
    });
  });

  group('Trzecia linia', () {
    test('Profil, Klawiatura z PC, Wygląd i Dane i diagnostyka nigdy jej '
        'nie mają', () {
      for (final stan in rozneStany) {
        for (final kategoria in const [profil, klawiatura, wyglad, dane]) {
          bezLinii(kategoria, stan);
        }
      }
    });

    test('świeża instalacja i wszystko działające: żadna kategoria jej nie '
        'ma', () {
      for (final kategoria in SettingsSection.values) {
        for (final platforma in TargetPlatform.values) {
          bezLinii(kategoria, StanUstawien(platforma: platforma));
        }
        bezLinii(kategoria, wszystkoDziala);
      }
    });
  });

  test('wartości domyślne StanUstawien to wiersz ustawień świeżej '
      'instalacji', () async {
    final db = ChattDb(NativeDatabase.memory());
    addTearDown(db.close);
    final wiersz = await db.ensureSettings(
      identityFactory: () async => ('klucz', 'guid'),
      defaultNickname: 'Telefon',
      defaultPort: defaultTcpPort,
    );
    const stan = StanUstawien(platforma: android);
    expect(stan.welcomeMessage, wiersz.welcomeMessage);
    expect(stan.style, wiersz.style);
    expect(stan.theme, wiersz.theme);
    expect(stan.background, wiersz.background);
    expect(stan.language, wiersz.language);
    expect(stan.retentionDays, wiersz.retentionDays);
    expect(stan.linkPreviews, wiersz.linkPreviews);
    expect(stan.updateChecks, wiersz.updateChecks);
    expect(stan.wifiEnabled, wiersz.wifiEnabled);
    expect(stan.bluetoothAddon, wiersz.bluetoothEnabled);
    expect(stan.internetAddon, wiersz.internetEnabled);
    expect(stan.keyboardAddon, wiersz.keyboardEnabled);
    expect(stan.remoteInputReceive, wiersz.remoteInputReceive);
    expect(stan.typingHistory, wiersz.typingHistory);
  });

  group('Kategorie i karty', () {
    const karty = [
      [profil],
      [polaczenie, nasluch, klawiatura],
      [wyglad, prywatnosc, dane, aktualizacje],
    ];
    const kartyBezNasluchu = [
      [profil],
      [polaczenie, klawiatura],
      [wyglad, prywatnosc, dane, aktualizacje],
    ];

    test('kolejność, numery kart i ikony z issue', () {
      expect(SettingsSection.values, [
        profil,
        polaczenie,
        nasluch,
        klawiatura,
        wyglad,
        prywatnosc,
        dane,
        aktualizacje,
      ]);
      expect(
        [for (final k in SettingsSection.values) k.group],
        [1, 2, 2, 2, 3, 3, 3, 3],
      );
      expect(
        [for (final k in SettingsSection.values) k.icon],
        [
          Icons.person_outline,
          Icons.lan_outlined,
          Icons.notifications_active_outlined,
          Icons.keyboard_outlined,
          Icons.palette_outlined,
          Icons.shield_outlined,
          Icons.storage_outlined,
          Icons.system_update_outlined,
        ],
      );
    });

    test('Android i Windows: trzy karty z Nasłuchem w tle', () {
      for (final platforma in const [android, windows]) {
        expect(SettingsSection.grupy(platforma), karty, reason: '$platforma');
      }
    });

    test('Linux, macOS i iOS: druga karta bez Nasłuchu w tle', () {
      for (final platforma in const [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.iOS,
      ]) {
        expect(
          SettingsSection.grupy(platforma),
          kartyBezNasluchu,
          reason: '$platforma',
        );
      }
    });

    test('każda dostępna kategoria stoi dokładnie raz, Profil pierwszy', () {
      for (final platforma in TargetPlatform.values) {
        final grupy = SettingsSection.grupy(platforma);
        final naLiscie = [for (final karta in grupy) ...karta];
        for (final kategoria in SettingsSection.values) {
          expect(
            naLiscie.where((k) => k == kategoria),
            hasLength(kategoria.dostepnaNa(platforma) ? 1 : 0),
            reason: '$kategoria na $platforma',
          );
        }
        expect(grupy.first.first, profil, reason: '$platforma');
        expect(SettingsSection.pierwszaNa(platforma), profil);
        // Karta trzyma kategorie jednej grupy, a grupy idą po kolei.
        for (final karta in grupy) {
          expect(karta.map((k) => k.group).toSet(), hasLength(1));
        }
        expect([for (final karta in grupy) karta.first.group], [1, 2, 3]);
      }
    });

    test('dostepnaNa ukrywa tylko Nasłuch w tle poza Androidem i '
        'Windows', () {
      for (final platforma in TargetPlatform.values) {
        for (final kategoria in SettingsSection.values) {
          final dostepna =
              kategoria != nasluch ||
              platforma == android ||
              platforma == windows;
          expect(
            kategoria.dostepnaNa(platforma),
            dostepna,
            reason: '$kategoria na $platforma',
          );
        }
      }
    });

    test('nazwy kategorii w obu językach: dokładne, niepuste i różne', () {
      expect(
        [for (final k in SettingsSection.values) k.title(pl)],
        [
          'Profil',
          'Połączenie',
          'Nasłuch w tle',
          'Klawiatura z PC',
          'Wygląd',
          'Prywatność',
          'Dane i diagnostyka',
          'Aktualizacje',
        ],
      );
      expect(
        [for (final k in SettingsSection.values) k.title(en)],
        [
          'Profile',
          'Connection',
          'Background listening',
          'Keyboard from a PC',
          'Appearance',
          'Privacy',
          'Data and diagnostics',
          'Updates',
        ],
      );
      for (final teksty in [pl, en]) {
        final nazwy = [for (final k in SettingsSection.values) k.title(teksty)];
        expect(nazwy.where((n) => n.trim().isEmpty), isEmpty);
        expect(nazwy.toSet(), hasLength(nazwy.length));
      }
    });
  });
}
