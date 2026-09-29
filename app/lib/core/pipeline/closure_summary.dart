import '../deviation_service.dart';
import '../models/transit.dart';

/// Fermate chiuse una dopo l'altra, con le aperte ai due capi.
class ClosedRun {
  const ClosedRun({required this.stops, this.before, this.after});

  /// In ordine di percorrenza.
  final List<TransitStop> stops;

  /// L'ultima fermata aperta prima del tratto, e la prima dopo. null al
  /// capolinea. Sono le fermate a cui conviene andare: stessa linea,
  /// stessa direzione, e aperte per costruzione.
  final TransitStop? before;
  final TransitStop? after;
}

/// Le chiusure di una direzione, lette sul percorso e non per avviso.
class DirectionClosures {
  const DirectionClosures({
    required this.shape,
    required this.runs,
    required this.window,
  });

  final RouteShape shape;
  final List<ClosedRun> runs;

  /// Le fermate dalla prima aperta prima dei tratti all'ultima aperta
  /// dopo, ognuna col suo stato: e' quello che si disegna a striscia.
  final List<({TransitStop stop, bool closed})> window;

  int get closedCount => runs.fold(0, (n, r) => n + r.stops.length);
}

/// Cosa e' chiuso su una linea, detto per tratti.
///
/// Sulla 10N il 26/09 GTT aveva pubblicato **sedici avvisi, uno per
/// fermata**, e l'app mostrava sedici schede. Per chi aspetta il bus è
/// una cosa sola: in una direzione nove fermate chiuse di fila, da Largo
/// Giachino Sud a Principe Eugenio, e si sale a Vibò o a Statuto Nord.
/// Gli avvisi dicono cosa ha scritto GTT; questo dice cosa succede.
class ClosureSummary {
  const ClosureSummary._();

  static List<DirectionClosures> of(Iterable<DeviationReport> reports) {
    final chiuse = <String, Set<String>>{};
    final percorsi = <String, RouteShape>{};
    for (final r in reports) {
      if (r.skippedStops.isEmpty) continue;
      percorsi[r.shape.shapeId] = r.shape;
      chiuse
          .putIfAbsent(r.shape.shapeId, () => {})
          .addAll(r.skippedStops.map((s) => s.stop.id));
    }

    final out = <DirectionClosures>[];
    // Prima l'andata, poi il ritorno: lo stesso ordine della mappa.
    final ordinati = percorsi.values.toList()
      ..sort((a, b) => a.directionId.compareTo(b.directionId));
    for (final shape in ordinati) {
      final ids = chiuse[shape.shapeId]!;
      final fermate = shape.stops;
      final runs = <ClosedRun>[];
      int? primo, ultimo;
      var i = 0;
      while (i < fermate.length) {
        if (!ids.contains(fermate[i].id)) {
          i++;
          continue;
        }
        final da = i;
        while (i < fermate.length && ids.contains(fermate[i].id)) {
          i++;
        }
        runs.add(ClosedRun(
          stops: fermate.sublist(da, i),
          before: da > 0 ? fermate[da - 1] : null,
          after: i < fermate.length ? fermate[i] : null,
        ));
        primo ??= da;
        ultimo = i - 1;
      }
      // Fermate saltate che il percorso principale non conosce: non c'e'
      // modo di metterle in fila, e non si inventa un ordine.
      if (runs.isEmpty) continue;

      final inizio = primo! > 0 ? primo - 1 : 0;
      final fine = ultimo! + 1 < fermate.length ? ultimo + 1 : ultimo;
      out.add(DirectionClosures(
        shape: shape,
        runs: runs,
        window: [
          for (final s in fermate.sublist(inizio, fine + 1))
            (stop: s, closed: ids.contains(s.id)),
        ],
      ));
    }
    return out;
  }

  /// La data di fine, se e' la stessa per tutti gli avvisi. null se non
  /// c'e' o se sono diverse: in quel caso la dice ogni avviso, e un
  /// «fino al» unico sarebbe falso per qualcuno.
  static DateTime? commonEnd(Iterable<DeviationReport> reports) {
    DateTime? fine;
    for (final r in reports) {
      final u = r.notice.endToShow;
      if (u == null) return null;
      final giorno = DateTime(u.year, u.month, u.day);
      if (fine != null && fine != giorno) return null;
      fine = giorno;
    }
    return fine;
  }
}
