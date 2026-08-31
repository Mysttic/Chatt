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
