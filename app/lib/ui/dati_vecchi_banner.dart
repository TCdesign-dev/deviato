import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/pipeline/dati_vecchi.dart';
import 'theme.dart';

/// In cima alla home quando i dati sono troppo vecchi per fidarsi.
///
/// Dal 20 al 28/10/2026 gli avvisi di GTT non hanno risposto e l'app
/// mostrava le deviazioni di sei giorni prima come fossero di adesso: lo
/// diceva solo «Aggiornate il 20/10 alle 23:20», in piccolo sopra le linee.
/// Che sia colpa di GTT si dice solo se il job l'ha visto; se no si dice
/// che i dati non sono aggiornati, e basta.
class DatiVecchiBanner extends StatelessWidget {
  const DatiVecchiBanner({required this.stato, required this.ora, super.key});

  /// Da `AppRepository.datiVecchi`: null se i dati sono freschi.
  final ({DateTime da, bool gttGiu})? stato;
  final DateTime ora;

  @override
  Widget build(BuildContext context) {
    final s = stato;
    if (s == null) return const SizedBox.shrink();
    final colore = StatusColors.of(context).warning;
    final quando = DatiVecchi.daQuando(s.da, ora);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: colore.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.update_disabled, color: colore),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.gttGiu
                          ? 'Gli avvisi di GTT non arrivano $quando'
                          : 'Dati non aggiornati $quando',
                      style: TextStyle(
                        color: colore,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Deviazioni e fermate non servite sono quelle di '
                      'allora: nel frattempo potrebbero essere cambiate.',
                    ),
                    if (s.gttGiu)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: colore,
                          ),
                          onPressed: () => launchUrl(
                            Uri.parse(GttConfig.variazioniUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Variazioni sul sito di GTT'),
                        ),
                      )
                    else
                      const SizedBox(height: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
