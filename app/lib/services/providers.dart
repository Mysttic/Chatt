import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/share_intake.dart';
import '../data/db.dart';
import 'app_services.dart';

/// Uruchomiony stos aplikacji. Wartość jest wstrzykiwana w main() przez
/// override: dzięki temu testy mogą podstawić własną instancję.
final appServicesProvider = Provider<AppServices>(
  (ref) => throw UnimplementedError('appServicesProvider nadpisywany w main()'),
);

/// Udostępnianie z innych aplikacji (issue #60). Testy podstawiają własną
/// instancję z kanałem na niby.
final shareIntakeProvider = Provider<ShareIntake>((ref) => ShareIntake.instance);

final settingsProvider = StreamProvider<Setting>(
  (ref) => ref.watch(appServicesProvider).db.watchSettings(),
);

final conversationSummariesProvider = StreamProvider<List<ConversationSummary>>(
  (ref) => ref.watch(appServicesProvider).db.watchConversationSummaries(),
);

final messagesProvider = StreamProvider.family<List<Message>, int>(
  (ref, conversationId) =>
      ref.watch(appServicesProvider).db.watchMessages(conversationId),
);

final knownPeersProvider = StreamProvider<List<Peer>>(
  (ref) => ref.watch(appServicesProvider).db.watchPeers(),
);
