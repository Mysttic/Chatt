import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/autostart.dart';
import '../../core/background_service.dart';
import '../../data/db.dart';
import '../../services/app_services.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';
import '../styles.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/toasts.dart';
import 'settings/appearance_section.dart';
import 'settings/background_section.dart';
import 'settings/connection_section.dart';
import 'settings/data_section.dart';
import 'settings/keyboard_section.dart';
import 'settings/privacy_section.dart';
import 'settings/profile_section.dart';
import 'settings/settings_category_row.dart';
import 'settings/settings_section.dart';
import 'settings/settings_summary.dart';
import 'settings/settings_widgets.dart';
import 'settings/updates_section.dart';

export 'settings/settings_section.dart' show SettingsSection;

/// Ustawienia (issue #71): krótka lista kategorii, a przy każdej jedno
/// zdanie o tym, co jest ustawione. Kategoria otwiera się w tym samym
/// ekranie, a na szerokim oknie ([czyDwupanel]) stoi obok listy.
///
/// Wstecz, strzałka i Esc wracają z kategorii do listy. W dwóch panelach
/// nie ma listy, do której można wrócić, więc zamykają Ustawienia. Pola
/// tekstowe zapisują się przy wyjściu z kategorii; błędna wartość
/// zatrzymuje w niej ([SettingsCommit]).
class SettingsScreen extends ConsumerStatefulWidget {
  /// Kategoria otwarta od razu, np. z odsyłacza na innym ekranie.
  final SettingsSection? initialSection;

  /// System, od którego zależy lista kategorii. W aplikacji to ten, na
  /// którym Chatt działa ([biezacaPlatforma]).
  @visibleForTesting
  final TargetPlatform? platform;

  const SettingsScreen({super.key, this.initialSection, this.platform});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final TargetPlatform _platforma = widget.platform ?? biezacaPlatforma();
  late final AppServices _services = ref.read(appServicesProvider);

  /// Kategoria wybrana przez użytkownika. `null`: lista (na wąskim ekranie)
  /// albo pierwsza kategoria w prawym panelu (na szerokim).
  SettingsSection? _wybrana;

  /// Wąski ekran: kategoria, która po „Wstecz” jeszcze odjeżdża.
  SettingsSection? _schodzi;

  /// Wąski ekran: przejście między listą a kategorią (0: lista, 1:
  /// kategoria), ten sam ruch co między ekranami.
  late final AnimationController _ruch;

  /// Szeroki ekran: wejście kategorii w prawym panelu po zmianie wyboru.
  late final AnimationController _panel = motionController(
    vsync: this,
    value: 1,
  );

  /// Treść każdej kategorii pod własnym kluczem, w obu układach. Przejście
  /// przez 900 px przenosi więc jej stan (pobieranie aktualizacji, zgodę
  /// Bluetooth, pola tekstowe) w nowe miejsce. Klucze żyją w tym stanie:
  /// dwa ekrany Ustawień naraz (jeden schodzi, drugi wchodzi) nie dzielą
  /// kluczy.
  late final Map<SettingsSection, GlobalKey> _klucze = {
    for (final kategoria in SettingsSection.values)
      kategoria: GlobalKey(debugLabel: 'ustawienia ${kategoria.name}'),
  };

  /// Szeroki ekran: zamykanie trwa (zapis pól przed zejściem). Drugie
  /// „Wstecz” w tym czasie nie zdejmuje ekranu pod Ustawieniami.
  bool _zamyka = false;

  /// Szeroki ekran: wybór kategorii pokazanej bez wyboru czeka na koniec
  /// klatki.
  bool _wyborZaplanowany = false;

  bool _batteryOptimized = false;
  bool _autostart = false;

  /// Liczba sesji w historii pisania, na żywo. Jeden strumień na życie
  /// ekranu: przebudowa nie zakłada nowego zapytania w bazie.
  late final Stream<int> _sesjePisania = _services.db.watchTypingSessionCount();

  /// Wszystko z serwisów, z czego powstają streszczenia.
  late final Listenable _zrodla = Listenable.merge([
    _services.bluetoothAddon,
    _services.bluetoothRunning,
    _services.bluetoothStatus,
    _services.internetAddon,
    _services.internetRunning,
    _services.keyboardAddon,
    _services.typingHistory,
    _services.availableRelease,
  ]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBattery();
    if (Autostart.supported) {
      Autostart.enabled().then((wlaczony) {
        if (mounted) setState(() => _autostart = wlaczony);
      });
    }
    final start = widget.initialSection;
    if (start != null && start.dostepnaNa(_platforma)) _wybrana = start;
    // Kategoria z odsyłacza stoi od razu, bez wjazdu. Każda zmiana stanu
    // przejścia przebudowuje ekran: po wjeździe lista chowa się pod
    // kategorią, przy powrocie wychodzi spod niej.
    _ruch = motionController(vsync: this, value: _wybrana == null ? 0 : 1)
      ..addStatusListener((_) {
        if (mounted) setState(() {});
      });
    // Stan radia i zgody bywa sprzed chwili, a od niego zależy linia pod
    // Połączeniem. Przy wyłączonym dodatku serwis nie pyta systemu o nic.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_services.refreshBluetoothStatus());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ruch.dispose();
    _panel.dispose();
    super.dispose();
  }

  /// Odpowiedź na systemowe okienko przychodzi dopiero przy powrocie do
  /// aplikacji, innego sygnału Android nie daje.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkBattery();
  }

  Future<void> _checkBattery() async {
    final optimized = await BackgroundService.batteryOptimized();
    if (mounted && optimized != _batteryOptimized) {
      setState(() => _batteryOptimized = optimized);
    }
  }

  Future<void> _askBatteryExemption() async {
    final pokazane = await BackgroundService.requestBatteryExemption();
    if (!mounted || pokazane) return;
    showToast(context.l10n.batteryExemptUnavailable);
  }

  /// Zapis do rejestru może odmówić (polityka, zablokowany klucz), wtedy
  /// przełącznik wraca na swoje miejsce i mówi o tym komunikat.
  Future<void> _setAutostart(bool value) async {
    final udalo = await Autostart.setEnabled(value);
    if (!mounted) return;
    setState(() => _autostart = udalo ? value : !value);
    if (!udalo) showToast(context.l10n.startWithWindowsFailed);
  }

  /// Kategoria, którą widać: na szerokim ekranie zawsze jakaś.
  SettingsSection? _pokazana(bool dwupanel) => dwupanel
      ? (_wybrana ?? SettingsSection.pierwszaNa(_platforma))
      : _wybrana;

  /// Zapis pól kategorii przed wyjściem z niej. `false`: błędna wartość,
  /// zostajemy.
  Future<bool> _zatwierdz(SettingsSection kategoria) async {
    final stan = _klucze[kategoria]!.currentState;
    if (stan is! SettingsCommit) return true;
    try {
      return await stan.commit();
    } catch (blad, slad) {
      // Zapis do bazy padł (np. pełny dysk): zostajemy w kategorii, żeby dało
      // się spróbować jeszcze raz, a błąd idzie tam, gdzie wszystkie inne.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: blad,
          stack: slad,
          library: 'ustawienia',
        ),
      );
      return false;
    }
  }

  Future<void> _otworz(SettingsSection kategoria) async {
    if (_zamyka) return;
    final dwupanel = czyDwupanel(context);
    final obecna = _pokazana(dwupanel);
    if (kategoria == obecna) {
      if (_wybrana == null) _wybierz(kategoria);
      return;
    }
    if (obecna != null && !await _zatwierdz(obecna)) return;
    if (!mounted) return;
    final m = ChattMotion.of(context);
    setState(() {
      _wybrana = kategoria;
      _schodzi = null;
    });
    if (dwupanel) {
      // Bez ruchu listy: po zwężeniu okna kategoria stoi na miejscu.
      _ruch.value = 1;
      _panel
        ..duration = m.paneSwitch
        ..forward(from: 0);
    } else {
      _ruch
        ..duration = m.screenIn
        ..reverseDuration = m.screenOut
        ..forward();
    }
  }

  /// Kategoria pokazana w prawym panelu bez wyboru staje się wybraną, bez
  /// ruchu: podświetlony wiersz to wtedy naprawdę wybór, a po zwężeniu okna
  /// kategoria zostaje na ekranie razem ze stanem swoich pól.
  void _wybierz(SettingsSection kategoria) {
    setState(() => _wybrana = kategoria);
    _ruch.value = 1;
  }

  /// [_wybierz] po bieżącej klatce: w trakcie budowy stan się nie zmienia.
  void _wybierzPoKlatce(SettingsSection kategoria) {
    if (_wyborZaplanowany) return;
    _wyborZaplanowany = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wyborZaplanowany = false;
      if (mounted && _wybrana == null) _wybierz(kategoria);
    });
  }

  /// Wąski ekran: z kategorii z powrotem do listy.
  Future<void> _doListy() async {
    final obecna = _wybrana;
    if (obecna == null || !await _zatwierdz(obecna)) return;
    if (!mounted || _wybrana != obecna) return;
    final m = ChattMotion.of(context);
    setState(() {
      _wybrana = null;
      _schodzi = obecna;
    });
    _ruch
      ..duration = m.screenIn
      ..reverseDuration = m.screenOut;
    _ruch.reverse().whenCompleteOrCancel(() {
      if (mounted && _wybrana == null) setState(() => _schodzi = null);
    });
  }

  /// Wstecz systemu, strzałka w pasku i Esc.
  Future<void> _wstecz() async {
    if (!czyDwupanel(context)) return _doListy();
    if (_zamyka) return;
    _zamyka = true;
    var mozna = false;
    try {
      mozna = await _zatwierdz(_pokazana(true)!);
    } finally {
      if (!mozna) _zamyka = false;
    }
    if (!mounted || !mozna) return;
    Navigator.of(context).pop();
  }

  /// Esc idzie przez trasę do [PopScope], tak jak strzałka i Wstecz systemu.
  void _naEsc() => unawaited(Navigator.maybePop(context));

  /// Pasek z Esc: fokus na strzałce też wychodzi przez [_Esc].
  PreferredSizeWidget _zEsc(PreferredSizeWidget pasek) => PreferredSize(
    preferredSize: pasek.preferredSize,
    child: _Esc(onEsc: _naEsc, child: pasek),
  );

  StanUstawien _stan(Setting? u, int sesje) {
    final s = _services;
    final radio = s.bluetoothStatus.value;
    return StanUstawien(
      platforma: _platforma,
      nickname: u?.nickname ?? s.identity.name,
      welcomeMessage: u?.welcomeMessage ?? s.identity.welcomeMessage,
      tcpPort: u?.tcpPort ?? s.identity.tcpPort,
      style: u?.style ?? AppStyle.cisza,
      theme: u?.theme ?? AppTheme.system,
      background: u?.background ?? 0,
      language: u?.language ?? AppLanguage.english,
      retentionDays: u?.retentionDays ?? 0,
      linkPreviews: u?.linkPreviews ?? false,
      updateChecks: u?.updateChecks ?? false,
      wifiEnabled: u?.wifiEnabled ?? true,
      remoteInputReceive: u?.remoteInputReceive ?? false,
      bluetoothAddon: s.bluetoothAddon.value,
      bluetoothRunning: s.bluetoothRunning.value,
      bluetoothRadioOn: radio.enabled,
      bluetoothGranted: radio.granted,
      internetAddon: s.internetAddon.value,
      internetRunning: s.internetRunning.value,
      keyboardAddon: s.keyboardAddon.value,
      remoteInputReceiveSupported: s.remoteInputReceiveSupported,
      typingHistory: s.typingHistory.value,
      typingSessions: sesje,
      availableVersion: s.availableRelease.value?.version,
      keyProtected: s.keyProtected,
      discoveryListening: s.discoveryListening,
      batteryOptimized: _batteryOptimized,
      autostart: _autostart,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ustawienia = ref.watch(settingsProvider).value;
    final dwupanel = czyDwupanel(context);
    return PopScope(
      // Z listy na wąskim ekranie wychodzi się od razu. W każdym innym
      // miejscu najpierw zapis pól, potem powrót albo zamknięcie.
      canPop: !dwupanel && _wybrana == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_wstecz());
      },
      // Na pulpicie wyjście z kategorii i z Ustawień to Esc (patrz [_Esc]).
      child: _Esc(
        onEsc: _naEsc,
        // Własny zakres fokusu: pole, które oddaje fokus (Enter, przejście
        // do innej kategorii), oddaje go temu zakresowi, więc Esc działa
        // dalej.
        child: FocusScope(
          autofocus: true,
          child: ListenableBuilder(
            listenable: _zrodla,
            builder: (context, _) => StreamBuilder<int>(
              stream: _sesjePisania,
              builder: (context, sesje) {
                final stan = _stan(ustawienia, sesje.data ?? 0);
                return dwupanel
                    ? _dwaPanele(context, stan)
                    : _jedenPanel(context, stan);
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Wąski ekran: lista albo kategoria, między nimi wspólna oś stylu.
  /// Lista zostaje w drzewie pod kategorią, więc po powrocie stoi tam,
  /// gdzie była przewinięta.
  Widget _jedenPanel(BuildContext context, StanUstawien stan) {
    final m = ChattMotion.of(context);
    final kategoria = _wybrana ?? _schodzi;
    final zakryta = kategoria != null && _ruch.isCompleted;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: zakryta,
          child: IgnorePointer(
            ignoring: kategoria != null,
            child: ExcludeFocus(
              excluding: kategoria != null,
              child: ChattSharedAxisTransition(
                motion: m,
                animation: kAlwaysCompleteAnimation,
                secondaryAnimation: _ruch,
                child: _lista(context, stan, dwupanel: false),
              ),
            ),
          ),
        ),
        if (kategoria != null)
          IgnorePointer(
            // Kategoria, która odjeżdża, nie przyjmuje już dotyku.
            ignoring: _wybrana == null,
            child: ChattSharedAxisTransition(
              motion: m,
              animation: _ruch,
              secondaryAnimation: kAlwaysDismissedAnimation,
              child: _kategoria(context, kategoria, stan, dwupanel: false),
            ),
          ),
      ],
    );
  }

  /// Szeroki ekran: lista 360 px, kreska i kategoria w kolumnie do 640 px.
  /// Prawy panel nigdy nie stoi pusty.
  Widget _dwaPanele(BuildContext context, StanUstawien stan) {
    final m = ChattMotion.of(context);
    final pokazana = _pokazana(true)!;
    if (_wybrana == null) _wybierzPoKlatce(pokazana);
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 360,
            child: FocusTraversalGroup(
              child: _lista(context, stan, dwupanel: true, wybrana: pokazana),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: FocusTraversalGroup(
              child: FadeTransition(
                opacity: _panel.drive(CurveTween(curve: m.enter)),
                child: _kategoria(context, pokazana, stan, dwupanel: true),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lista(
    BuildContext context,
    StanUstawien stan, {
    required bool dwupanel,
    SettingsSection? wybrana,
  }) {
    final teksty = context.l10n;
    final karty = SettingsSection.grupy(_platforma);
    return Scaffold(
      appBar: _zEsc(AppBar(title: Text(teksty.settingsTitle))),
      body: _Esc(
        onEsc: _naEsc,
        child: ContentColumn(
          maxWidth: SettingsPage.szerokosc,
          child: ListView(
            // Główny przewijacz trasy należy do treści kategorii: dwa
            // podpięte naraz psują PageUp i PageDown z klawiatury. Lista
            // mieści się na ekranie bez przewijania klawiszami.
            primary: false,
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + bottomSystemInset(context),
            ),
            children: [
              for (final (i, karta) in karty.indexed) ...[
                if (i > 0) const SizedBox(height: 12),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (j, kategoria) in karta.indexed) ...[
                        if (j > 0)
                          const Divider(
                            height: 1,
                            indent: SettingsCategoryRow.wciecie,
                          ),
                        SettingsCategoryRow(
                          key: ValueKey(kategoria),
                          icon: kategoria.icon,
                          title: kategoria.title(teksty),
                          summary: streszczenie(kategoria, stan, teksty),
                          line: linia(kategoria, stan, teksty),
                          selected: dwupanel ? kategoria == wybrana : null,
                          chevron: !dwupanel,
                          onTap: () => unawaited(_otworz(kategoria)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _kategoria(
    BuildContext context,
    SettingsSection kategoria,
    StanUstawien stan, {
    required bool dwupanel,
  }) {
    final klucz = _klucze[kategoria]!;
    final tresc = switch (kategoria) {
      SettingsSection.profile => ProfileSection(key: klucz),
      SettingsSection.connection => ConnectionSection(key: klucz),
      SettingsSection.backgroundListening => BackgroundSection(
        key: klucz,
        platforma: _platforma,
        batteryOptimized: _batteryOptimized,
        autostart: _autostart,
        onBatteryExemption: _askBatteryExemption,
        onAutostart: _setAutostart,
      ),
      SettingsSection.keyboard => KeyboardSection(
        key: klucz,
        typingSessions: stan.typingSessions,
      ),
      SettingsSection.appearance => AppearanceSection(key: klucz),
      SettingsSection.privacy => PrivacySection(key: klucz),
      SettingsSection.data => DataSection(key: klucz),
      SettingsSection.updates => UpdatesSection(key: klucz),
    };
    return Scaffold(
      appBar: _zEsc(
        AppBar(
          // Na wąskim ekranie strzałka wraca do listy, także gdy pod
          // Ustawieniami nie ma innego ekranu. W dwóch panelach stoi nad
          // listą i zamyka Ustawienia.
          leading: dwupanel ? null : const BackButton(),
          automaticallyImplyLeading: !dwupanel,
          title: Text(kategoria.title(context.l10n)),
        ),
      ),
      body: _Esc(onEsc: _naEsc, child: tresc),
    );
  }
}

/// Esc w Ustawieniach. Aplikacja zamienia Esc na [DismissIntent], a ten
/// idzie od widgetu z fokusem w górę do najbliższej akcji tej intencji.
/// Pole tekstowe chowa najpierw swoje menu (Wytnij, Kopiuj, Wklej) i bez
/// menu oddaje intencję dalej. [Scaffold] ma własną akcję (zamyka
/// szufladę), która bez szuflady zatrzymuje intencję po drodze, więc ta
/// akcja stoi pod paskiem i treścią każdego Scaffoldu, a jedna nad całym
/// ekranem łapie Esc, gdy fokus stoi na samym ekranie.
class _Esc extends StatelessWidget {
  final VoidCallback onEsc;
  final Widget child;

  const _Esc({required this.onEsc, required this.child});

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      DismissIntent: CallbackAction<DismissIntent>(
        onInvoke: (_) {
          onEsc();
          return null;
        },
      ),
    },
    child: child,
  );
}
