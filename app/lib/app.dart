import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/languages.dart';
import 'data/db.dart';
import 'l10n/app_localizations.dart';
import 'services/providers.dart';
import 'ui/backgrounds.dart';
import 'ui/screens/conversations_screen.dart';
import 'ui/widgets/prompt_overlay.dart';
import 'ui/widgets/toasts.dart';

/// Fiolet odziedziczony po pierwotnej wersji projektu (ikona MAUI #512BD4).
const chattSeedColor = Color(0xFF512BD4);

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
    // Wybrane tło leży pod całą aplikacją, więc powierzchnie, które je
    // zasłaniały (tło ekranu i pasek u góry), muszą zrobić się przezroczyste.
    // Karty i dymki zostają nieprzezroczyste, na nich stoi czytelność.
    final tlo = backgroundAt(settings?.background ?? 0);

    ThemeData theme(Brightness brightness) => ThemeData(
          colorScheme:
              ColorScheme.fromSeed(seedColor: chattSeedColor, brightness: brightness),
          fontFamily: 'Roboto',
          useMaterial3: true,
          scaffoldBackgroundColor: tlo.plain ? null : Colors.transparent,
          appBarTheme: tlo.plain
              ? null
              : AppBarTheme(
                  backgroundColor: Colors.transparent,
                  scrolledUnderElevation: 0,
                  // Jasność ikon paska systemowego trzeba podać wprost:
                  // Flutter liczy ją z koloru paska aplikacji, a ten jest
                  // teraz przezroczysty i wychodziło z tego białe na jasnym.
                  systemOverlayStyle: brightness == Brightness.dark
                      ? SystemUiOverlayStyle.light
                      : SystemUiOverlayStyle.dark,
                ),
          // Na pulpicie steruje się myszą, a nie palcem: listy i przyciski
          // dostają ciaśniejsze odstępy, przez co na monitorze mieści się
          // więcej niż trzy wiersze. Na telefonie bez zmian.
          visualDensity: VisualDensity.adaptivePlatformDensity,
        );

    return MaterialApp(
      // Tytuł okna/zadania: przed pierwszą klatką nie ma jeszcze skąd wziąć
      // tłumaczenia, a nazwa aplikacji i tak jest ta sama w obu językach.
      title: 'Chatt',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ConversationsScreen(),
      // Prośby o zgodę na odbiór pliku muszą być widoczne na każdym ekranie,
      // tak samo krótkie komunikaty w rogu.
      builder: (context, child) => AppBackground(
        background: tlo,
        child: PromptOverlay(
          child: ToastHost(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
