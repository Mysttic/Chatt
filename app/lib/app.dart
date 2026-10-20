import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/languages.dart';
import 'data/db.dart';
import 'l10n/app_localizations.dart';
import 'services/providers.dart';
import 'ui/backgrounds.dart';
import 'ui/screens/conversations_screen.dart';
import 'ui/styles.dart';
import 'ui/widgets/prompt_overlay.dart';
import 'ui/widgets/remote_input_banner.dart';
import 'ui/widgets/toasts.dart';

class ChattApp extends ConsumerWidget {
  const ChattApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Wybór motywu siedzi w ustawieniach, więc przeżywa restart aplikacji.
    // Zanim baza odpowie, idziemy za systemem.
    final settings = ref.watch(settingsProvider).value;
    final themeMode = switch (settings?.theme) {
      AppTheme.light => ThemeMode.light,
      AppTheme.dark => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    // null = idziemy za językiem systemu (Flutter wybierze z obsługiwanych).
    final locale = settings?.language.locale;
    // Tło leży pod całą aplikacją przy każdym wyborze, także przy „Bez tła”
    // (kolor tła stylu), więc tło ekranu i pasek u góry są zawsze
    // przezroczyste. Dzięki temu zmiana tła nie rusza motywu: przenika tylko
    // AppBackground. Karty i dymki zostają nieprzezroczyste, na nich stoi
    // czytelność.
    final tlo = backgroundAt(settings?.background ?? 0);

    // Styl (Cisza, Precyzja, Ciepło) zmienia wyłącznie wygląd: kolory,
    // fonty, zaokrąglenia i gęstość siedzą w ui/styles.dart.
    final styl = settings?.style ?? AppStyle.cisza;

    // „Ogranicz animacje” w systemie: ruch stylu ustawia każde przejście na
    // przenikanie 100 ms. Flutter przy tej fladze skraca dodatkowo każdy
    // kontroler do 5% czasu. MediaQuery daje tu View, który runApp stawia
    // nad aplikacją.
    final ograniczRuch = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final ruch =
        ograniczRuch ? chattMotion(styl).reduced : chattMotion(styl);

    ThemeData theme(Brightness brightness) => chattTheme(styl, brightness,
        gradient: true, reduceMotion: ograniczRuch);

    return MaterialApp(
      // Tytuł okna/zadania: przed pierwszą klatką nie ma jeszcze skąd wziąć
      // tłumaczenia, a nazwa aplikacji i tak jest ta sama w obu językach.
      title: 'Chatt',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: themeMode,
      // Zmiana stylu i motywu przenika w czasie i krzywej stylu.
      themeAnimationStyle:
          AnimationStyle(duration: ruch.themeChange, curve: ruch.enter),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ConversationsScreen(),
      // Prośby o zgodę na odbiór pliku muszą być widoczne na każdym ekranie,
      // tak samo krótkie komunikaty w rogu i pasek „Pisze" dodatku
      // klawiatury (komunikaty pod nim, żeby nie zasłaniały jego Stopu).
      builder: (context, child) => AppBackground(
        background: tlo,
        child: PromptOverlay(
          child: RemoteInputBanner(
            child: ToastHost(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}
