import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../l10n_context.dart';

/// Kółko z inicjałem rozmówcy: awatar na liście rozmów i w nagłówku.
///
/// [online] to obecność w sieci: `true` dokłada zieloną kropkę w rogu.
/// `false` i `null` nie rysują nic: kropka mówi „urządzenie odpowiada",
/// a jej brak zostawia sprawę otwartą.
class InitialsAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final bool? online;

  const InitialsAvatar({
    super.key,
    required this.name,
    this.radius = 22,
    this.online,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final avatar = CircleAvatar(
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
    if (online != true) return avatar;

    // Obwódka w kolorze tła listy odcina kropkę od awatara, więc widać ją
    // tak samo na jasnym i na ciemnym motywie.
    final srednica = radius * 0.5;
    return Semantics(
      label: context.l10n.peerOnline,
      child: Stack(
        children: [
          avatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: srednica,
              height: srednica,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: radius * 0.09),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nazwa rozmówcy z zieloną tarczą, gdy jego tożsamość jest potwierdzona.
///
/// Ta sama para na liście rozmów i na liście urządzeń: tarcza ma wszędzie
/// znaczyć to samo co zielona tarcza w nagłówku rozmowy.
class PeerName extends StatelessWidget {
  final String name;
  final bool verified;

  const PeerName({super.key, required this.name, required this.verified});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Flexible(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (verified) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: context.l10n.shieldVerified,
              child: const Icon(Icons.verified_user,
                  size: 16, color: Colors.green),
            ),
          ],
        ],
      );
}

/// Adres, pod którym rozmówca jest osiągalny. Poznany wyłącznie przez radio
/// nie ma żadnego w sieci, więc pokazujemy adres radia, o ile [radio] mówi,
/// że dodatek Bluetooth jest włączony. Bez dodatku zostaje pusty napis.
String peerAddressLabel(Peer peer, {required bool radio}) {
  if (peer.host.isNotEmpty && peer.port > 0) return '${peer.host}:${peer.port}';
  final adres = peer.btAddress;
  return (!radio || adres == null || adres.isEmpty) ? '' : adres;
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
