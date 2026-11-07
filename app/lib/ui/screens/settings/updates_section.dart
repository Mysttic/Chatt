import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/tray.dart';
import '../../../core/update_install.dart';
import '../../../core/updates.dart';
import '../../../core/version.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/providers.dart';
import '../../l10n_context.dart';
import '../../styles.dart';
import '../../widgets/common.dart';
import '../../widgets/toasts.dart';
import '../../widgets/update_card.dart';
import 'settings_widgets.dart';

/// Kategoria Aktualizacje: numer tej wersji i karta sprawdzania.
class UpdatesSection extends StatelessWidget {
  const UpdatesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsPage(
      children: [
        // Numer wersji mieszka tutaj: na górze aplikacji stoi nazwa
        // urządzenia.
        Text(
          '${context.l10n.version} $appVersion',
          style: ChattTokens.of(context).mono
              .copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        const _UpdatesCard(),
      ],
    );
  }
}

/// Pobieranie nowego wydania: ile procent pliku już jest (`null`: nic się
/// nie pobiera) i ostatni błąd. Żyje dłużej niż karta: przejście do innej
/// kategorii zdejmuje kartę z drzewa, a pobieranie i przekazanie instalatora
/// mają dojść do końca. Karta po powrocie pokazuje stan stąd.
final _pobieranie = ValueNotifier<({int? postep, String? blad})>((
  postep: null,
  blad: null,
));

/// Pobiera wydanie i uruchamia instalator, niezależnie od tego, czy karta
/// jeszcze stoi. Teksty przychodzą z chwili kliknięcia.
Future<void> _pobierzIZainstaluj(
  Release wydanie,
  AppLocalizations teksty,
) async {
  if (_pobieranie.value.postep != null) return;
  _pobieranie.value = (postep: 0, blad: null);
  try {
    final plik = await downloadRelease(
      wydanie,
      onProgress: (odebrane, razem) {
        if (razem == null || razem == 0) return;
        _pobieranie.value = (postep: odebrane * 100 ~/ razem, blad: null);
      },
    );
    final ruszyl = await launchInstaller(plik);
    if (!ruszyl) {
      _pobieranie.value = (postep: null, blad: teksty.updateInstallFailed);
      return;
    }
    _pobieranie.value = (postep: null, blad: null);
    // Windows: instalator wgrywa się w miejsce działającej aplikacji, więc
    // ta musi zejść mu z drogi, także gdy Ustawienia stoją już gdzie indziej.
    // Android zostaje otwarty, bo tam podmianą zajmuje się osobny ekran
    // systemu.
    if (Platform.isWindows) {
      showToast(teksty.updateClosingForInstall);
      await Future<void>.delayed(const Duration(seconds: 2));
      await TrayIcon.instance.quit();
    }
  } catch (_) {
    _pobieranie.value = (postep: null, blad: teksty.updateDownloadFailed);
  }
}

/// Karta „Aktualizacje": przełącznik, sprawdzenie na żądanie i karta
/// z nowym wydaniem, gdy jakieś jest.
///
/// Pobieranie i uruchomienie instalatora rusza stąd, bo to jedyne miejsce,
/// w którym użytkownik o to prosi i w którym widzi postęp.
class _UpdatesCard extends ConsumerStatefulWidget {
  const _UpdatesCard();

  @override
  ConsumerState<_UpdatesCard> createState() => _UpdatesCardState();
}

class _UpdatesCardState extends ConsumerState<_UpdatesCard> {
  /// Wynik ostatniego sprawdzenia zrobionego z tego ekranu. `null`, dopóki
  /// nikt nie nacisnął przycisku: sam brak nowego wydania nie jest jeszcze
  /// powodem, żeby cokolwiek pisać.
  UpdateCheck? _ostatniWynik;

  Future<void> _sprawdz() async {
    setState(() => _ostatniWynik = null);
    final biezace = _pobieranie.value;
    if (biezace.postep == null && biezace.blad != null) {
      _pobieranie.value = (postep: null, blad: null);
    }
    final wynik = await ref.read(appServicesProvider).checkForUpdate();
    if (mounted) setState(() => _ostatniWynik = wynik.outcome);
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.read(appServicesProvider);
    final ustawienia = ref.watch(settingsProvider).value;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: ustawienia?.updateChecks ?? false,
              title: Text(context.l10n.updateChecksLabel),
              subtitle: Text(context.l10n.updateChecksHelp),
              isThreeLine: true,
              onChanged: ustawienia == null
                  ? null
                  : (wlaczone) async {
                      await services.db.saveUpdateChecks(wlaczone);
                      // Włączenie ma dać odpowiedź od razu, zamiast kazać
                      // czekać do jutra na pierwsze pytanie.
                      if (wlaczone) await _sprawdz();
                    },
            ),
            const Divider(height: 24),
            ListenableBuilder(
              listenable: Listenable.merge([
                services.checkingForUpdate,
                _pobieranie,
              ]),
              builder: (context, _) {
                final sprawdza = services.checkingForUpdate.value;
                final pobiera = _pobieranie.value.postep != null;
                return Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: sprawdza || pobiera ? null : _sprawdz,
                      icon: sprawdza
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(
                        sprawdza
                            ? context.l10n.updateChecking
                            : context.l10n.updateCheckNow,
                      ),
                    ),
                    if (ustawienia?.lastUpdateCheck != null) ...[
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          context.l10n.updateLastChecked(
                            formatWhen(ustawienia!.lastUpdateCheck),
                          ),
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            if (_ostatniWynik == UpdateCheck.upToDate) ...[
              const SizedBox(height: 12),
              Text(context.l10n.updateUpToDate),
            ],
            if (_ostatniWynik == UpdateCheck.failed) ...[
              const SizedBox(height: 12),
              Text(
                context.l10n.updateDownloadFailed,
                style: TextStyle(color: scheme.error),
              ),
            ],
            ListenableBuilder(
              listenable: Listenable.merge([
                services.availableRelease,
                _pobieranie,
              ]),
              builder: (context, _) {
                final wydanie = services.availableRelease.value;
                final pobieranie = _pobieranie.value;
                return wydanie == null
                    ? const SizedBox.shrink()
                    : UpdateCard(
                        release: wydanie,
                        canInstall: canInstallUpdate(),
                        progress: pobieranie.postep,
                        error: pobieranie.blad,
                        onInstall: () =>
                            _pobierzIZainstaluj(wydanie, context.l10n),
                      );
              },
            ),
          ],
        ),
      ),
    );
  }
}
