import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/sources/scioperi_mit.dart';
import 'theme.dart';

/// In cima alla home: uno sciopero che puo' fermare bus e tram nei
/// prossimi giorni. Toccandolo si vedono tutti, con il calendario del
/// Ministero.
///
/// Solo entro una settimana: uno sciopero fra un mese, in cima alla home,
/// si leggerebbe ogni giorno per niente.
class ScioperoBanner extends StatelessWidget {
  const ScioperoBanner({required this.scioperi, required this.oggi, super.key});

  final List<Sciopero> scioperi;
  final DateTime oggi;

  static const giorniAvanti = 7;

  @override
  Widget build(BuildContext context) {
    final giorno = DateTime(oggi.year, oggi.month, oggi.day);
    final vicini = [
      for (final s in scioperi)
        if (s.nonFinitoIl(giorno) &&
            !s.giorniTpl.inizio.isAfter(
              giorno.add(const Duration(days: giorniAvanti)),
            ))
          s,
    ]..sort((a, b) => a.giorniTpl.inizio.compareTo(b.giorniTpl.inizio));
    if (vicini.isEmpty) return const SizedBox.shrink();
    final primo = vicini.first;
    final colore = StatusColors.of(context).warning;
    final altri = vicini.length - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: colore.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => mostraScioperi(context, scioperi, oggi),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.campaign_outlined, color: colore),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sciopero ${quandoSciopero(primo, giorno)}',
                        style: TextStyle(
                          color: colore,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          descriviSciopero(primo),
                          if (altri > 0)
                            altri == 1
                                ? 'E un altro nei prossimi giorni.'
                                : 'E altri $altri nei prossimi giorni.',
                        ].join(' '),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colore),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «oggi», «domani», «venerdì 30/10», «dal 20/11 al 21/11».
String quandoSciopero(Sciopero s, DateTime oggi) {
  final g = s.giorniTpl;
  String d(DateTime x) =>
      '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}';
  if (g.fine.isAfter(g.inizio)) return 'dal ${d(g.inizio)} al ${d(g.fine)}';
  final giorni = g.inizio.difference(oggi).inDays;
  if (giorni <= 0) return 'oggi';
  if (giorni == 1) return 'domani';
  return '${_giorniSettimana[g.inizio.weekday - 1]} ${d(g.inizio)}';
}

/// «Generale, USB. Bus e tram: durata e modalità stabilite a livello
/// territoriale.»
String descriviSciopero(Sciopero s) {
  final tipo = s.settore.toLowerCase().contains('trasporto pubblico locale')
      ? 'Trasporto locale'
      : s.settore;
  return '$tipo, ${s.sindacati}. Bus e tram: '
      '${_frase(s.modalitaTpl, maiuscola: false)}.';
}

/// Il calendario del Ministero lo scrive in maiuscolo: «DURATA E
/// MODALITA' STABILITE A LIVELLO TERRITORIALE».
String _frase(String maiuscolo, {bool maiuscola = true}) {
  var t = maiuscolo.trim().toLowerCase();
  t = t.replaceAllMapped(
    RegExp(r"([aeiou])'(?=\s|$|[.,;:])"),
    (m) => const {'a': 'à', 'e': 'è', 'i': 'ì', 'o': 'ò', 'u': 'ù'}[m[1]]!,
  );
  t = t.replaceAll(RegExp(r'\btpl\b'), 'trasporto locale');
  t = t.replaceAll(RegExp(r'[.\s]+$'), '');
  if (!maiuscola || t.isEmpty) return t;
  return t[0].toUpperCase() + t.substring(1);
}

const _giorniSettimana = [
  'lunedì',
  'martedì',
  'mercoledì',
  'giovedì',
  'venerdì',
  'sabato',
  'domenica',
];

/// Tutti gli scioperi in calendario, in un foglio dal basso.
Future<void> mostraScioperi(
  BuildContext context,
  List<Sciopero> scioperi,
  DateTime oggi,
) {
  final giorno = DateTime(oggi.year, oggi.month, oggi.day);
  final prossimi = [
    for (final s in scioperi)
      if (s.nonFinitoIl(giorno)) s,
  ]..sort((a, b) => a.giorniTpl.inizio.compareTo(b.giorniTpl.inizio));
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final testo = Theme.of(context).textTheme;
      final tenue = Theme.of(context).colorScheme.onSurfaceVariant;
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Scioperi', style: testo.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Quelli in calendario che possono fermare bus e tram di GTT. '
            'Durante uno sciopero alcune fasce orarie sono garantite: '
            'le indica GTT sul suo sito.',
            style: testo.bodyMedium?.copyWith(color: tenue),
          ),
          for (final s in prossimi) ...[
            const Divider(height: 32),
            Text(
              'Sciopero ${quandoSciopero(s, giorno)}',
              style: testo.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(descriviSciopero(s)),
            if (s.note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${_frase(s.note)}.',
                style: testo.bodySmall?.copyWith(color: tenue),
              ),
            ],
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(ScioperiMit.url),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Calendario del Ministero dei Trasporti'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse('https://www.gtt.to.it'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Sito di GTT'),
          ),
        ],
      );
    },
  );
}
