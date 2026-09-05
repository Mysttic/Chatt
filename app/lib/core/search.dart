import '../data/db.dart';

/// Szukanie w rozmowach. Filtrowanie leci po tym, co użytkownik ma przed
/// oczami: treści wiadomości i nazwie pliku w dymku, a na liście rozmów po
/// nazwie rozmówcy i ostatniej wiadomości. Szukanie po czymś niewidocznym
/// dawałoby wyniki, których nie da się wytłumaczyć.

/// Czy wiadomość pasuje do [query]. Wielkość liter nie ma znaczenia.
/// Pusty napis pasuje do wszystkiego: to stan „nikt nie szuka".
bool messageMatches(Message message, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return message.body.toLowerCase().contains(needle) ||
      (message.fileName?.toLowerCase().contains(needle) ?? false);
}

/// Czy wiersz listy rozmów pasuje do [query].
bool conversationMatches(ConversationSummary item, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return item.peer.name.toLowerCase().contains(needle) ||
      (item.lastBody?.toLowerCase().contains(needle) ?? false);
}
