import 'package:flutter/material.dart';

import '../core/models/transit.dart';
import '../core/pipeline/stop_answer.dart';
import '../core/text/display_names.dart';
import 'line_badge.dart';
import 'theme.dart';

/// Le fermate salvate di una linea, in una scheda sola.
///
/// Una scheda per fermata, col numero della linea ripetuto in ognuna,
/// con sei fermate spingeva le linee fuori dallo schermo (29/09). Qui la
/// linea si dice una volta, in testa, e ogni fermata e' una riga: resta
/// visibile, con la sua risposta, e si toglie scorrendola.
class SavedStopsGroup extends StatelessWidget {
  const SavedStopsGroup({
    required this.line,
    required this.onOpenLine,
    required this.children,
    super.key,
  });

  final TransitLine line;
  final VoidCallback onOpenLine;

  /// Le righe, di solito [SavedStopRow].
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nome = line.longName;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpenLine,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Row(
                children: [
                  LineBadge(line: line, height: 24),
                  if (nome != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        nome.replaceAll(' - ', ' – '),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              // A tutta larghezza: rientrato, fra due righe rosse lasciava
              // un gradino chiaro a sinistra.
              Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Una fermata salvata, con la risposta: servita o no, e dove salire.
///
/// E' la domanda per cui esiste l'app, detta per la fermata di chi guarda.
/// «16 fermate non servite» sulla 10N e' vero ma non risponde: chi aspetta
/// a Largo Giachino Sud vuole sapere di Largo Giachino Sud.
class SavedStopRow extends StatelessWidget {
  const SavedStopRow({
    required this.answer,
    required this.line,
    required this.checking,
    required this.onTap,
    super.key,
  });

  final StopAnswer answer;
  final TransitLine line;
  final bool checking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colori = StatusColors.of(context);
    final testo = Theme.of(context).textTheme;
    final secondario = scheme.onSurfaceVariant;
    final stop = answer.stop;
    final chiusa = answer.state == StopState.closed && !checking;

    final (Color colore, IconData icona, String stato) = checking
        ? (secondario, Icons.sync, 'Aggiornamento…')
        : switch (answer.state) {
            StopState.unknown => (
              secondario,
              Icons.help_outline,
              'Tocca per aggiornare',
            ),
            StopState.served => (
              colori.ok,
              Icons.check_circle_outline,
              'Servita',
            ),
            StopState.uncertain => (
                colori.warning,
                Icons.article_outlined,
                'Avviso in corso: controlla i dettagli',
              ),
            StopState.closed => (
              scheme.error,
              Icons.do_not_disturb_on_outlined,
              answer.until == null
                  ? 'Non servita'
                  : 'Non servita fino al ${_data(answer.until!)}',
            ),
            StopState.closesLater => (
              colori.warning,
              Icons.event_outlined,
              answer.from == null
                  ? 'Servita, chiuderà a breve'
                  : 'Servita, chiude dal ${_data(answer.from!)}',
            ),
            StopState.notOnRoute => (
              secondario,
              Icons.wrong_location_outlined,
              'Non è più su questa linea',
            ),
          };

    final verso = answer.shape == null
        ? null
        : DisplayNames.direction(
            answer.shape!.headsign,
            longName: line.longName,
          );

    return Material(
      color: chiusa
          ? scheme.errorContainer.withValues(alpha: 0.45)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icona, size: 20, color: colore),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: stop == null
                                ? 'Fermata ${answer.saved.stopCode ?? ""}'
                                : DisplayNames.stop(stop),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (stop?.code != null)
                            TextSpan(
                              text: '  ${stop!.code}',
                              style: testo.bodySmall?.copyWith(
                                color: secondario,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // Lo stato e il verso sulla stessa riga: e' la riga che
                    // si legge, e va a capo solo se serve.
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: stato,
                            style: TextStyle(
                              color: colore,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (verso != null)
                            TextSpan(
                              text: ' · verso $verso',
                              style: TextStyle(color: secondario),
                            ),
                        ],
                      ),
                      style: testo.bodySmall?.copyWith(fontSize: 13),
                    ),
                    if (chiusa && answer.walkTo.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.directions_walk, size: 16),
                            const SizedBox(width: 4),
                            Expanded(
                              child: DefaultTextStyle.merge(
                                style: const TextStyle(fontSize: 13),
                                child: _SaliA(walkTo: answer.walkTo),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _data(DateTime d) =>
      '${d.day.toString().padLeft(2, "0")}/'
      '${d.month.toString().padLeft(2, "0")}';
}

/// «Sali a Vibò, 180 m in linea d'aria», o le due fermate ai capi.
///
/// La seconda si dice solo se e' vicina quasi quanto la prima. Su Mortara,
/// in mezzo a sette fermate chiuse, i capi erano a 680 e a 1430 m: il
/// secondo numero non aiuta nessuno, e allunga la riga.
class _SaliA extends StatelessWidget {
  const _SaliA({required this.walkTo});

  final List<({TransitStop stop, double meters})> walkTo;

  @override
  Widget build(BuildContext context) {
    const forte = TextStyle(fontWeight: FontWeight.w600);
    String m(double x) => '${(x / 10).round() * 10} m';
    final primo = walkTo.first;
    final secondo = walkTo.length > 1 && walkTo[1].meters <= primo.meters * 1.5
        ? walkTo[1]
        : null;
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Sali a '),
          TextSpan(text: DisplayNames.stop(primo.stop), style: forte),
          TextSpan(text: ', ${m(primo.meters)}'),
          if (secondo != null) ...[
            const TextSpan(text: ' o a '),
            TextSpan(text: DisplayNames.stop(secondo.stop), style: forte),
            TextSpan(text: ', ${m(secondo.meters)}'),
          ],
          // Si dice una volta, in fondo: e' la distanza fra le due fermate,
          // non il percorso a piedi, e un fiume o una ferrovia cambiano tutto.
          TextSpan(
            text: ' in linea d\'aria',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
