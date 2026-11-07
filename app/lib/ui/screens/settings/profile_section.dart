import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/app_services.dart';
import '../../../services/providers.dart';
import '../../l10n_context.dart';
import 'settings_widgets.dart';

/// Kategoria Profil: nick i wiadomość powitalna. Pole zapisuje się przy
/// wyjściu z niego (Enter, utrata fokusu) i przy wyjściu z kategorii
/// ([commit]); pusty nick zatrzymuje w kategorii z komunikatem pola.
class ProfileSection extends ConsumerStatefulWidget {
  const ProfileSection({super.key});

  @override
  ConsumerState<ProfileSection> createState() => ProfileSectionState();
}

class ProfileSectionState extends ConsumerState<ProfileSection>
    with SettingsCommit {
  /// Serwis z chwili wejścia: zapis przy zamknięciu ekranu dzieje się już
  /// po odpięciu widgetu.
  late final AppServices _services = ref.read(appServicesProvider);
  final _nickPole = GlobalKey<FormFieldState<String>>();
  late final TextEditingController _nickname = TextEditingController(
    text: _services.identity.name,
  );
  late final TextEditingController _welcome = TextEditingController(
    text: _services.identity.welcomeMessage,
  );
  final _nickFokus = FocusNode();
  final _welcomeFokus = FocusNode();

  @override
  void initState() {
    super.initState();
    _nickFokus.addListener(() => _poWyjsciu(_nickFokus));
    _welcomeFokus.addListener(() => _poWyjsciu(_welcomeFokus));
  }

  @override
  void dispose() {
    // Ekran zamknięty bez „Wstecz” (np. udostępnienie z innej aplikacji
    // zdejmuje wszystko nad listą rozmów): poprawne zmiany i tak zostają.
    if (_nickname.text.trim().isNotEmpty) unawaited(_zapisz());
    _nickFokus.dispose();
    _welcomeFokus.dispose();
    _nickname.dispose();
    _welcome.dispose();
    super.dispose();
  }

  /// Wyjście z pola zapisuje je od razu, także przejście do drugiego pola.
  void _poWyjsciu(FocusNode pole) {
    if (!pole.hasFocus) unawaited(commit());
  }

  @override
  Future<bool> commit() async {
    if (!(_nickPole.currentState?.validate() ?? true)) return false;
    await _zapisz();
    return true;
  }

  Future<void> _zapisz() => _services.saveProfile(
    nickname: _nickname.text.trim(),
    welcomeMessage: _welcome.text.trim(),
  );

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      children: [
        TextFormField(
          key: _nickPole,
          controller: _nickname,
          focusNode: _nickFokus,
          textInputAction: TextInputAction.next,
          autovalidateMode: AutovalidateMode.onUserInteractionIfError,
          decoration: InputDecoration(labelText: context.l10n.nicknameLabel),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? context.l10n.nicknameRequired
              : null,
          onFieldSubmitted: (_) => unawaited(commit()),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _welcome,
          focusNode: _welcomeFokus,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: context.l10n.welcomeLabel,
            helperText: context.l10n.welcomeHelper,
          ),
          onFieldSubmitted: (_) => unawaited(commit()),
        ),
      ],
    );
  }
}
