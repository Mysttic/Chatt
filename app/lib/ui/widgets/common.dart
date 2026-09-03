import 'package:flutter/material.dart';

/// Kółko z inicjałem rozmówcy — odpowiednik makiety z Prototype/.
class InitialsAvatar extends StatelessWidget {
  final String name;
  final double radius;

  const InitialsAvatar({super.key, required this.name, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        initial,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Zwięzły czas dla list: dziś -> HH:mm, ten rok -> d.MM, starsze -> d.MM.rrrr.
String formatWhen(DateTime? time) {
  if (time == null) return '';
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  if (time.year == now.year && time.month == now.month && time.day == now.day) {
    return '${two(time.hour)}:${two(time.minute)}';
  }
  if (time.year == now.year) {
    return '${time.day}.${two(time.month)}';
  }
  return '${time.day}.${two(time.month)}.${time.year}';
}

String formatClock(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}';
}

/// Od tej szerokości okna pokazujemy listę rozmów i rozmowę obok siebie.
/// Poniżej jeden ekran naraz, bo dwa panele na telefonie to dwa paski.
const double dwupanelOd = 900;

bool czyDwupanel(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= dwupanelOd;

/// Ogranicza szerokość treści na dużym oknie i przykleja ją do góry.
///
/// Formularz rozciągnięty na cały monitor czyta się fatalnie: oko wraca
/// z końca linii w nieznane miejsce. Na wąskim ekranie nic nie zmienia.
class ContentColumn extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ContentColumn({super.key, required this.child, this.maxWidth = 760});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// Wysokość paska nawigacji, którą trzeba dołożyć na dole przewijanej treści.
///
/// Od Androida 15 (API 35) system rysuje swoje paski **na** aplikacji i nie
/// zwęża jej okna, więc ostatni element listy chowa się pod paskiem gestów.
/// Bierzemy `padding`, a nie `viewPadding`: przy otwartej klawiaturze pasek
/// leży nad nią i dokładanie tej przerwy drugi raz odsuwałoby treść w próżnię.
double bottomSystemInset(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom;

/// Rozmiar pliku po ludzku: 512 B, 12,3 KB, 3,4 MB, 1,20 GB.
String formatFileSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
