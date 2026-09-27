import 'package:flutter/material.dart';

import '../data/app_repository.dart';

/// Da dove vengono i dati, cosa sono, e cosa non sono.
///
/// Era la schermata delle impostazioni, con la chiave del modello e il
/// pulsante per riscaricare gli orari. Da quando il calcolo lo fa il job su
/// GitHub non c'e' piu' niente da impostare: restano le cose che chi usa
/// l'app deve poter sapere, e che la licenza di GTT chiede di dire.
class InfoScreen extends StatelessWidget {
  const InfoScreen({required this.repo, super.key});

  final AppRepository repo;

  @override
  Widget build(BuildContext context) {
    final testo = Theme.of(context).textTheme;
    final secondario = Theme.of(context).colorScheme.onSurfaceVariant;
    final generato = repo.generato;
    final feed = repo.feed;

    return Scaffold(
      appBar: AppBar(title: const Text('Informazioni')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _Sezione('Da sapere'),
          const _Paragrafo(
            'DeviaTo non è un\'app di GTT e non è collegata a GTT. Le '
            'fermate non servite e i percorsi deviati sono ricavati in '
            'automatico dagli avvisi e possono contenere errori: in caso di '
            'dubbio fa fede l\'avviso originale, che trovi sempre nel '
            'dettaglio della linea.',
          ),
          const _Sezione('Da dove vengono i dati'),
          const _Paragrafo(
            'Avvisi, percorsi, fermate e posizioni dei mezzi sono dati '
            'aperti di GTT. Gli avvisi vengono letti ogni mezz\'ora durante '
            'il giorno per ricavarne i percorsi deviati e le fermate non '
            'servite.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Data source: GTT S.p.A. – Gruppo Torinese Trasporti\n'
              'www.gtt.to.it',
              style: testo.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (generato != null || feed != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                [
                  if (generato != null) 'Dati aggiornati alle ${_ora(generato)}',
                  if (feed != null) 'Orari GTT del ${_feed(feed)}',
                ].join(' · '),
                style: testo.bodySmall?.copyWith(color: secondario),
              ),
            ),
          const _Sezione('Privacy'),
          const _Paragrafo(
            'L\'app non raccoglie dati personali e non ha un account. La tua '
            'posizione, se la attivi sulla mappa, resta sul telefono.',
          ),
          const _Sezione('Crediti'),
          const _Paragrafo(
            'Mappe © contributori di OpenStreetMap. Percorsi calcolati con '
            'Valhalla (FOSSGIS), indirizzi con Photon.',
          ),
        ],
      ),
    );
  }

  static String _ora(DateTime t) {
    final h = '${t.hour.toString().padLeft(2, "0")}:'
        '${t.minute.toString().padLeft(2, "0")}';
    final oggi = DateTime.now();
    final stessoGiorno =
        t.year == oggi.year && t.month == oggi.month && t.day == oggi.day;
    return stessoGiorno ? h : '$h del ${t.day}/${t.month}';
  }

  /// «20260922» → «22/09/2026».
  static String _feed(String f) => f.length == 8
      ? '${f.substring(6)}/${f.substring(4, 6)}/${f.substring(0, 4)}'
      : f;
}

class _Sezione extends StatelessWidget {
  const _Sezione(this.testo);

  final String testo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(testo,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class _Paragrafo extends StatelessWidget {
  const _Paragrafo(this.testo);

  final String testo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(testo, style: Theme.of(context).textTheme.bodyMedium),
      );
}
