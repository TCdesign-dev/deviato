import 'package:flutter/material.dart';

import '../core/deviation_service.dart';
import '../core/models/transit.dart';
import '../core/pipeline/closure_summary.dart';
import '../core/text/display_names.dart';
import 'theme.dart';

/// Il riassunto di una linea: quali fermate non sono servite, fino a
/// quando, e dove salire invece. Per tratti, non per avviso.
///
/// Sta in un file suo perche' lo usano due schermate: il dettaglio della
/// linea, in cima, e la mappa a tutto schermo, nel pannello in basso.
class RiassuntoLinea extends StatelessWidget {
  const RiassuntoLinea({
    required this.status,
    super.key,
    this.soloDirezione,
    this.onTratto,
    this.margin = const EdgeInsets.fromLTRB(12, 12, 12, 12),
  });

  final LineStatus status;

  /// Solo la direzione di questo percorso (shapeId): la mappa a tutto
  /// schermo puo' mostrarne una sola, e il riassunto la segue.
  final String? soloDirezione;

  /// Toccando un tratto: la mappa a tutto schermo ci si sposta sopra.
  final ValueChanged<ClosedRun>? onTratto;

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colori = StatusColors.of(context);
    final testo = Theme.of(context).textTheme;
    final attivi = status.activeReports;

    if (status.reports.isEmpty) {
      return _Riga(
        colore: colori.ok,
        icona: Icons.check_circle_outline,
        titolo: 'Percorso regolare',
        dettaglio: 'Nessun avviso di GTT su questa linea.',
      );
    }
    if (attivi.isEmpty) {
      return _Riga(
        colore: colori.ok,
        icona: Icons.check_circle_outline,
        titolo: 'Percorso regolare',
        dettaglio:
            'C\'è una variazione in programma: trovi i dettagli più '
            'in basso.',
      );
    }

    final direzioni = [
      for (final d in ClosureSummary.of(attivi))
        if (soloDirezione == null || d.shape.shapeId == soloDirezione) d,
    ];
    if (direzioni.isEmpty) {
      final ricostruito = attivi.any((r) => r.impact != null);
      // Senza un avviso letto non si sa nemmeno se sia una deviazione:
      // quello della 7 il 26/09 diceva «sospesa». Si dice la stessa cosa
      // della home, e si rimanda al testo.
      return _Riga(
        colore: colori.warning,
        icona: ricostruito ? Icons.alt_route : Icons.article_outlined,
        titolo: ricostruito ? 'Deviata, fermate servite' : 'Avviso in corso',
        dettaglio: ricostruito
            ? 'Il percorso cambia, ma tutte le fermate restano servite.'
            : 'Non è stato possibile ricavarne le fermate: leggi il testo '
                  'di GTT più in basso.',
      );
    }

    final totale = {
      for (final d in direzioni)
        for (final r in d.runs) ...r.stops.map((s) => s.id),
    }.length;
    final fine = ClosureSummary.commonEnd(attivi);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.do_not_disturb_on_outlined,
                size: 20,
                color: scheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  totale == 1
                      ? '1 fermata non servita'
                      : '$totale fermate non servite',
                  style: testo.titleMedium?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (fine != null)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 2),
              child: Text(
                'fino al ${_data(fine)}',
                style: testo.bodyMedium?.copyWith(color: scheme.error),
              ),
            ),
          for (final d in direzioni)
            _Direzione(d: d, line: status.line, onTratto: onTratto),
        ],
      ),
    );
  }
}

class _Riga extends StatelessWidget {
  const _Riga({
    required this.colore,
    required this.icona,
    required this.titolo,
    this.dettaglio,
  });

  final Color colore;
  final IconData icona;
  final String titolo;
  final String? dettaglio;

  @override
  Widget build(BuildContext context) {
    final testo = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icona, size: 22, color: colore),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titolo,
                  style: testo.titleMedium?.copyWith(
                    color: colore,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (dettaglio != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(dettaglio!, style: testo.bodyMedium),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una direzione: quali fermate, in fila, e dove salire.
///
/// Con un tratto solo si disegna la striscia e si dice dove salire. Con
/// piu' tratti sparsi — la 68 il 26/09 ne aveva quattro verso Frejus, fra
/// Cimitero Monumentale e Palagiustizia — la striscia diventava una fila
/// di ventisette pallini, e «Sali a» elencava sette fermate senza dire a
/// quale tratto appartenessero. Li' si va per righe: un tratto, le sue due
/// fermate aperte.
class _Direzione extends StatelessWidget {
  const _Direzione({required this.d, required this.line, this.onTratto});

  final DirectionClosures d;
  final TransitLine line;
  final ValueChanged<ClosedRun>? onTratto;

  /// Un tratto si tocca solo se qualcuno ascolta: nel dettaglio no.
  Widget _toccabile(ClosedRun r, Widget figlio) => onTratto == null
      ? figlio
      : InkWell(
          onTap: () => onTratto!(r),
          borderRadius: BorderRadius.circular(8),
          child: figlio,
        );

  @override
  Widget build(BuildContext context) {
    final testo = Theme.of(context).textTheme;
    final unTratto = d.runs.length == 1;
    final verso = DisplayNames.direction(
      d.shape.headsign,
      longName: line.longName,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Verso $verso', style: testo.titleSmall),
          const SizedBox(height: 2),
          if (unTratto)
            _toccabile(
              d.runs.single,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _descrivi(d.runs.single, conteggio: true),
                    style: testo.bodyMedium,
                  ),
                  // Oltre una quindicina di pallini non si distinguono
                  // piu' su un telefono: il testo sopra basta.
                  if (d.window.length <= 15) ...[
                    const SizedBox(height: 10),
                    _Striscia(d: d),
                  ],
                  _SaliA(run: d.runs.single),
                ],
              ),
            )
          else
            for (final r in d.runs)
              _toccabile(
                r,
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.do_not_disturb_on_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _descrivi(r, conteggio: false),
                              style: testo.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            _SaliA(run: r, compatto: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  /// «3 di fila, da Verona a Cimitero Monumentale», o solo il nome.
  static String _descrivi(ClosedRun r, {required bool conteggio}) {
    final nome = DisplayNames.stop;
    if (r.stops.length == 1) return nome(r.stops.single);
    final tratto = 'da ${nome(r.stops.first)} a ${nome(r.stops.last)}';
    return conteggio
        ? '${r.stops.length} di fila, $tratto'
        : '${_maiuscola(tratto)} (${r.stops.length})';
  }

  static String _maiuscola(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// «Sali a Vibò o a Statuto Nord»: le fermate aperte ai capi del tratto.
/// Stessa linea, stessa direzione, aperte per costruzione.
class _SaliA extends StatelessWidget {
  const _SaliA({required this.run, this.compatto = false});

  final ClosedRun run;
  final bool compatto;

  @override
  Widget build(BuildContext context) {
    final aperte = [?run.before, ?run.after];
    if (aperte.isEmpty) return const SizedBox.shrink();
    final stile = compatto
        ? Theme.of(context).textTheme.bodySmall
        : Theme.of(context).textTheme.bodyMedium;
    final testo = Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Sali a '),
          TextSpan(
            text: DisplayNames.stop(aperte.first),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (aperte.length > 1) ...[
            const TextSpan(text: ' o a '),
            TextSpan(
              text: DisplayNames.stop(aperte.last),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
      style: stile,
    );
    if (compatto) {
      return Padding(padding: const EdgeInsets.only(top: 2), child: testo);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.directions_walk, size: 18),
          const SizedBox(width: 6),
          Expanded(child: testo),
        ],
      ),
    );
  }
}

/// Le fermate in fila: aperte vuote, chiuse piene. Il testo sopra dice
/// gia' tutto; questa serve a vedere a colpo d'occhio dov'e' il buco.
class _Striscia extends StatelessWidget {
  const _Striscia({required this.d});

  final DirectionClosures d;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final linea = scheme.onSurfaceVariant.withValues(alpha: 0.5);
    final w = d.window;
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 16,
            child: Row(
              children: [
                for (var i = 0; i < w.length; i++) ...[
                  if (i > 0)
                    Expanded(child: Container(height: 2, color: linea)),
                  w[i].closed
                      ? Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: scheme.error,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            size: 10,
                            color: scheme.onError,
                          ),
                        )
                      : Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: scheme.onSurfaceVariant,
                              width: 2,
                            ),
                          ),
                        ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  DisplayNames.stop(w.first.stop),
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  DisplayNames.stop(w.last.stop),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _data(DateTime d) =>
    '${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}';
