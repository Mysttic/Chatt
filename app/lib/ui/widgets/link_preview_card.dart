import 'package:flutter/material.dart';

import '../../core/link_preview.dart';
import '../l10n_context.dart';
import 'link_confirm.dart';

/// Karta z podglądem strony pod odnośnikiem: obrazek, nazwa serwisu, tytuł
/// i opis, tak jak w zwykłych komunikatorach.
///
/// Wszystko, co karta rysuje, jest zwykłym tekstem i zwykłymi bajtami obrazka
/// (patrz `core/link_preview.dart`). Nie ma tu przeglądarki, nie ma ramki
/// z cudzą stroną i nie ma niczego, co mogłoby uruchomić skrypt z tej strony.
/// Kliknięcie w kartę robi to samo co kliknięcie w odnośnik w tekście: pyta,
/// czy na pewno przejść.
class LinkPreviewCard extends StatefulWidget {
  final Uri url;
  final LinkPreviewService service;

  /// Karta wisi we własnym dymku (tło z koloru głównego) czy w cudzym.
  /// Od tego zależą kolory, bo tła są zupełnie różne.
  final bool mine;

  const LinkPreviewCard({
    super.key,
    required this.url,
    required this.service,
    required this.mine,
  });

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  LinkPreview? _podglad;

  @override
  void initState() {
    super.initState();
    _pobierz();
  }

  @override
  void didUpdateWidget(LinkPreviewCard stary) {
    super.didUpdateWidget(stary);
    // Ten sam widget potrafi dostać inny adres, gdy lista dymków się przesunie.
    if (stary.url != widget.url) {
      _podglad = null;
      _pobierz();
    }
  }

  void _pobierz() {
    final gotowy = widget.service.cached(widget.url);
    if (gotowy != null) {
      _podglad = gotowy;
      return;
    }
    widget.service.previewOf(widget.url).then((podglad) {
      // Ekran mógł w tym czasie zniknąć, a lista przesunąć widget na inny
      // adres. Bez tego sprawdzenia karta pokazałaby cudzy podgląd.
      if (!mounted || podglad == null || podglad.url != widget.url) return;
      setState(() => _podglad = podglad);
    });
  }

  @override
  Widget build(BuildContext context) {
    final podglad = _podglad;
    // Dopóki nic nie przyszło, nie ma czego pokazywać: puste miejsce pod
    // dymkiem, które za chwilę zniknie, wygląda jak usterka.
    if (podglad == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final tekst = widget.mine ? scheme.onPrimary : scheme.onSurface;
    final drugorzedny = tekst.withValues(alpha: 0.75);
    final tlo = widget.mine
        ? scheme.onPrimary.withValues(alpha: 0.12)
        : scheme.surface.withValues(alpha: 0.75);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: tlo,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => confirmAndOpenLink(context, podglad.url),
          child: Semantics(
            link: true,
            label: context.l10n.linkPreviewOf(podglad.label),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (podglad.imageBytes != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 170),
                    child: SizedBox(
                      width: double.infinity,
                      child: Image.memory(
                        podglad.imageBytes!,
                        fit: BoxFit.cover,
                        // Obrazek przyszedł z obcego serwera, więc dekoder ma
                        // prawo się na nim wyłożyć. Wtedy zostaje sam tekst,
                        // a nie wywrócona lista.
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        podglad.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: drugorzedny,
                          fontSize: 11,
                          letterSpacing: 0.4,
                        ),
                      ),
                      if (podglad.title != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          podglad.title!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tekst,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ],
                      if (podglad.description != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          podglad.description!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: drugorzedny,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
