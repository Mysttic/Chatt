import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../l10n_context.dart';
import '../styles.dart';

/// Inicjały do awatara: pierwsze litery dwóch pierwszych słów, a przy
/// jednym słowie jego dwie pierwsze litery („Laptop Ani" to LA,
/// „KOMPUTER" to KO).
String initialsOf(String name) {
  final slowa = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (slowa.isEmpty) return '?';
  final pierwsze = slowa.first.characters;
  final wynik = slowa.length > 1
      ? '${pierwsze.first}${slowa.elementAt(1).characters.first}'
      : pierwsze.take(2).toString();
  return wynik.toUpperCase();
}

/// Awatar z inicjałami rozmówcy: na liście rozmów, na liście urządzeń
/// i w nagłówku rozmowy. Kształt, kolory i rozmiar idą za stylem: koło
/// w Ciszy, zaokrąglony kwadrat w Precyzji i Cieple, kolor stały dla nazwy.
///
/// [online] to obecność w sieci: `true` dokłada zieloną kropkę w rogu.
/// `false` rysuje pusty pierścień tam, gdzie styl go ma (Precyzja); `null`
/// nie rysuje nic, bo nie wiadomo.
class InitialsAvatar extends StatelessWidget {
  final String name;
  final bool? online;

  /// Mniejszy awatar do nagłówka rozmowy.
  final bool header;

  const InitialsAvatar({
    super.key,
    required this.name,
    this.online,
    this.header = false,
  });

  @override
  Widget build(BuildContext context) {
    final k = ChattTokens.of(context);
    final bok = header ? k.avatarHeaderSize : k.avatarSize;
    final kolory = k.avatarFor(name);
    final avatar = Container(
      width: bok,
      height: bok,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kolory.background,
        shape: k.avatarCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius:
            k.avatarCircle ? null : BorderRadius.circular(bok * k.avatarCorner),
      ),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          color: kolory.foreground,
          fontSize: bok * 0.34,
          fontWeight: k.avatarWeight,
          letterSpacing: bok * 0.34 * 0.02,
          height: 1,
        ),
      ),
    );
    if (online == null) return avatar;
    // Czytnik ekranu słyszy obecność w każdym stylu, także tam, gdzie
    // brak połączenia nie ma własnego znaku.
    final opis =
        online! ? context.l10n.peerOnline : context.l10n.peerOffline;
    final kropka = online! ? k.presence : k.presenceOff;
    if (kropka == null) return Semantics(label: opis, child: avatar);

    // Obwódka w kolorze powierzchni odcina kropkę od awatara, więc widać ją
    // tak samo na jasnym i na ciemnym motywie.
    final srednica = k.presenceDot * (header ? 0.85 : 1);
    return Semantics(
      label: opis,
      child: SizedBox(
        width: bok + 2,
        height: bok + 2,
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
                  color: online == true ? kropka : k.surface1,
                  shape: BoxShape.circle,
                  border: online == true
                      ? Border.all(color: k.surface1, width: k.presenceDotBorder)
                      : Border.all(color: kropka, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ramka z ostrzeżeniem bezpieczeństwa w wyglądzie stylu. Domyślnie
/// [ChattTokens.security]; [colors] podmienia na zagrożenie albo
/// potwierdzenie.
class SecurityNote extends StatelessWidget {
  final String text;
  final IconData icon;
  final NoteColors? colors;
  final bool dense;

  const SecurityNote(
    this.text, {
    super.key,
    this.icon = Icons.gpp_maybe_outlined,
    this.colors,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final k = ChattTokens.of(context);
    final c = colors ?? k.security;
    final tekst = dense
        ? Theme.of(context).textTheme.bodySmall
        : Theme.of(context).textTheme.bodyMedium;
    return Container(
      width: double.infinity,
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(k.radiusWarning),
        border: c.border == null || c.borderWidth == 0
            ? null
            : Border.all(color: c.border!, width: c.borderWidth),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: dense ? 16 : 20, color: c.icon),
          SizedBox(width: dense ? 6 : 10),
          Expanded(
            child: Text(text, style: tekst?.copyWith(color: c.foreground)),
          ),
        ],
      ),
    );
  }
}

/// Licznik nieprzeczytanych: pigułka w Ciszy, kwadrat w Precyzji,
/// zaokrąglony kafelek w Cieple.
class UnreadCount extends StatelessWidget {
  final int count;

  const UnreadCount({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final k = ChattTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final wysokosc = switch (k.style) {
      AppStyle.cisza => 22.0,
      AppStyle.precyzja => 20.0,
      AppStyle.cieplo => 24.0,
    };
    // Align z mnożnikami 1: licznik ma rozmiar swojej liczby. Samo
    // `alignment` rozciągnęłoby go na całą szerokość wiersza listy.
    return Container(
      constraints: BoxConstraints(minWidth: wysokosc, minHeight: wysokosc),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(
            k.radiusBadge == 999 ? wysokosc / 2 : k.radiusBadge),
      ),
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          count > 99 ? '99+' : '$count',
          style: (k.style == AppStyle.precyzja
                  ? k.caption.copyWith(fontWeight: FontWeight.w600)
                  : Theme.of(context).textTheme.labelSmall)
              ?.copyWith(color: scheme.onPrimary, height: 1),
        ),
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
              child: Icon(Icons.verified_user,
                  size: 16, color: ChattTokens.of(context).verified),
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

/// Godzina z sekundami: 15:30:12. Do historii pisania i dziennika, gdzie
/// kolejność zdarzeń w obrębie minuty ma znaczenie.
String formatClockSeconds(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

/// Pełna data z godziną, bez skracania do „dziś": 18.10.2026 15:30,
/// z [seconds] 18.10.2026 15:30:12. Historia i dziennik czyta się po
/// czasie, więc data stoi zawsze, także dla dzisiejszych wpisów.
String formatDateTime(DateTime time, {bool seconds = false}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final godzina = seconds ? formatClockSeconds(time) : formatClock(time);
  return '${time.day}.${two(time.month)}.${time.year} $godzina';
}

/// Czas trwania po ludzku: 45 s, 3 min 05 s, 2 h 05 min. Jednostki
/// wyglądają tak samo po polsku i po angielsku.
String formatDuration(Duration duration) {
  String two(int v) => v.toString().padLeft(2, '0');
  final sekundy = duration.isNegative ? 0 : duration.inSeconds;
  if (sekundy < 60) return '$sekundy s';
  final minuty = sekundy ~/ 60;
  if (minuty < 60) return '$minuty min ${two(sekundy % 60)} s';
  return '${minuty ~/ 60} h ${two(minuty % 60)} min';
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
