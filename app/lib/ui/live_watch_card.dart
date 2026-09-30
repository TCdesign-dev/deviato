import 'package:flutter/material.dart';

import '../core/models/transit.dart';
import '../core/text/display_names.dart';
import '../core/pipeline/route_excursion.dart';
import '../core/pipeline/vehicle_watch.dart';
import 'theme.dart';

/// "Dove sono i mezzi adesso": comandi ed esito.
///
/// Non tiene lo stato dell'osservazione: quello sta nella schermata, che
/// deve passarlo anche alla mappa per disegnarci sopra i mezzi. Qui c'e'
/// solo la presentazione.
class LiveWatchCard extends StatelessWidget {
  const LiveWatchCard({
    required this.running,
    required this.samples,
    required this.liveTracks,
    required this.result,
    required this.shape,
    required this.altraLinea,
    required this.onStart,
    required this.onStop,
    super.key,
    this.error,
    this.inCard = true,
  });

  /// false dentro il pannello che si apre dal fondo: la scheda sarebbe un
  /// riquadro dentro un riquadro.
  final bool inCard;

  final bool running;
  final int samples;
  final List<VehicleTrack> liveTracks;
  final WatchResult? result;
  final String? error;

  /// Il percorso principale: serve a dire "escono dopo Sabotino" invece
  /// di "escono al metro 1420".
  final RouteShape shape;

  /// Il nome della linea che si sta gia' osservando, se e' un'altra.
  /// Partire da qui la fermerebbe, e va detto prima.
  final String? altraLinea;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final contenuto = _contenuto(context);
    if (!inCard) return contenuto;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: contenuto,
    );
  }

  Widget _contenuto(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                'Mezzi in tempo reale',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Vedi dove sono i mezzi, in tempo reale, finché non '
            'interrompi: capisci se la deviazione è ancora in corso.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),

          if (running) ...[
            _Progress(samples: samples, tracks: liveTracks),
            const SizedBox(height: 10),
            // Si puo' sempre smettere: in continuo e' l'unico modo, e
            // sugli altri e' scortese obbligare ad aspettare.
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop_outlined, size: 18),
                label: const Text('Interrompi'),
              ),
            ),
          ] else if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (result != null)
            _Outcome(result: result!, shape: shape)
          else ...[
            FilledButton.tonalIcon(
              onPressed: onStart,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Segui i mezzi'),
            ),
            // Una linea alla volta: due osservazioni in parallelo
            // raddoppierebbero le richieste al feed di GTT, e nessuno
            // guarda due linee insieme. Ma dirlo dopo sarebbe una
            // sorpresa sgradevole.
            if (altraLinea != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Stai seguendo la $altraLinea: se inizi qui, quella si '
                  'interrompe.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],

          if (!running && (result != null || error != null))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onStart,
                child: const Text('Segui di nuovo'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.samples, required this.tracks});

  final int samples;
  final List<VehicleTrack> tracks;

  @override
  Widget build(BuildContext context) {
    final off = tracks.where((t) => t.isOffRoute).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(
          tracks.isEmpty
              ? 'Ricerca dei mezzi…'
              : '${tracks.length} ${tracks.length == 1 ? "mezzo" : "mezzi"} '
                    'sulla mappa'
                    '${off > 0 ? ", di cui $off fuori percorso" : ""}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// "9 min 40 s" invece di "580 s": da quando si puo' guardare per dieci
/// minuti, i secondi da soli non si leggono piu'.
String _durata(Duration d) {
  if (d.inSeconds < 90) return '${d.inSeconds} s';
  final m = d.inMinutes;
  final s = d.inSeconds - m * 60;
  return s == 0 ? '$m min' : '$m min $s s';
}

class _Outcome extends StatelessWidget {
  const _Outcome({required this.result, required this.shape});

  final WatchResult result;
  final RouteShape shape;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color colour, IconData icon) = switch (result.outcome) {
      WatchOutcome.tuttiSulPercorso => (
        StatusColors.of(context).ok,
        Icons.check_circle_outline,
      ),
      WatchOutcome.fuoriPercorso => (scheme.error, Icons.alt_route),
      WatchOutcome.unMezzoFuori => (
        StatusColors.of(context).warning,
        Icons.alt_route,
      ),
      WatchOutcome.nessunMezzo => (
        scheme.onSurfaceVariant,
        Icons.bedtime_outlined,
      ),
      WatchOutcome.feedSpento => (
        scheme.onSurfaceVariant,
        Icons.cloud_off_outlined,
      ),
      WatchOutcome.inconcludente => (
        scheme.onSurfaceVariant,
        Icons.hourglass_empty,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: colour),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.summary,
                style: TextStyle(color: colour, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        // Dove escono e dove rientrano, misurato sui mezzi veri. E' la
        // sola cosa in tutta l'app che non viene da un testo di GTT.
        if (result.consensus != null)
          _Osservato(consenso: result.consensus!, shape: shape),
        // Si dice solo cosa fanno i mezzi. Che la deviazione sia finita non
        // lo si suggerisce: un'osservazione di qualche minuto non basta, e
        // una deviazione gia' negli orari lascia i mezzi sul percorso
        // (Tommaso, 30/09/2026).
        // Un mezzo solo, visto due volte, non e' una prova: puo' essere
        // fermo al capolinea. Non cambia l'esito, ma va detto.
        if (!result.enoughVehicles && result.tracks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              result.vehiclesSeen == 1
                  ? 'Un solo mezzo osservato: risultato indicativo.'
                  : 'Pochi mezzi osservati: risultato indicativo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Seguiti per ${_durata(result.observed)}'
            '${result.tracks.isEmpty ? "" : " · fino a ${result.maxDistance.round()} m dal percorso"}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// "Escono dopo Sabotino e rientrano a San Paolo."
///
/// E' l'informazione piu' solida che il sistema possa dare su una
/// deviazione: non e' dedotta da come GTT ha scritto l'avviso, e' quello
/// che i mezzi hanno fatto mentre li guardavamo.
class _Osservato extends StatelessWidget {
  const _Osservato({required this.consenso, required this.shape});

  final ExcursionConsensus consenso;
  final RouteShape shape;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viola = StatusColors.of(context).observed;
    final esce = shape.stopNearestAlong(consenso.detachAlongMeters);
    final rientra = consenso.rejoinAlongMeters == null
        ? null
        : shape.stopNearestAlong(consenso.rejoinAlongMeters!);

    final frase = StringBuffer('Lasciano il percorso normale');
    if (esce != null) {
      frase.write(' all\'altezza di ${DisplayNames.stop(esce)}');
    }
    if (rientra != null) {
      frase.write(' e rientrano a ${DisplayNames.stop(rientra)}');
    } else {
      frase.write('. Rientro non ancora osservato');
    }
    frase.write('.');

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: viola.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_outlined, size: 17, color: viola),
              const SizedBox(width: 7),
              Text(
                'Visto sui mezzi',
                style: TextStyle(fontWeight: FontWeight.w600, color: viola),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(frase.toString()),
          const SizedBox(height: 4),
          Text(
            consenso.isSolid
                ? 'Confermato da ${consenso.vehicles} mezzi.'
                // Un mezzo solo puo' essere un guasto o un rientro in
                // deposito: va detto, non nascosto.
                : 'Visto su un solo mezzo: potrebbe essere un caso isolato.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: consenso.isSolid ? null : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
