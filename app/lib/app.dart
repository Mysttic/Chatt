import 'package:flutter/material.dart';

import 'ui/screens/conversations_screen.dart';

/// Fiolet odziedziczony po pierwotnej wersji projektu (ikona MAUI #512BD4).
const chattSeedColor = Color(0xFF512BD4);

class ChattApp extends StatelessWidget {
  const ChattApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
          colorScheme:
              ColorScheme.fromSeed(seedColor: chattSeedColor, brightness: brightness),
          fontFamily: 'Roboto',
          useMaterial3: true,
        );

    return MaterialApp(
      title: 'Chatt',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const ConversationsScreen(),
    );
  }
}
