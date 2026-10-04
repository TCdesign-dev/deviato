import '../deviation_service.dart';
import '../models/saved_stop.dart';
import '../models/transit.dart';
import 'closure_summary.dart';

/// Cosa si puo' dire di una fermata salvata.
enum StopState {
  /// La linea non e' ancora stata controllata: non si sa.
  unknown,

  /// Servita, adesso.
  served,

  /// C'e' un avviso in corso sulla sua direzione che non si e' potuto
  /// leggere fino in fondo: non si sa se la riguardi.
  uncertain,

  /// Non servita, adesso.
  closed,

  /// Servita oggi, ma un avviso in programma la chiude.
  closesLater,

  /// Il percorso di oggi non passa piu' da quel palo: gli orari di GTT
  /// sono cambiati da quando la si e' salvata.
  notOnRoute,
}

/// La risposta alla domanda per cui esiste l'app: **la mia fermata e'
/// ancora servita?**
///
/// La home diceva «16 fermate non servite» sulla 10N, che e' vero ma non
/// risponde: chi prende il bus a Vibò non sa se fra quelle sedici c'e' la
/// sua. Qui si guarda UNA fermata, in UNA direzione.
class StopAnswer {
  const StopAnswer({
    required this.state,
    required this.saved,
    this.stop,
    this.shape,
    this.until,
    this.from,
    this.walkTo = const [],
  });

  final StopState state;
  final SavedStop saved;

  /// La fermata e la direzione, ritrovate negli orari di oggi. null se non
  /// ci sono piu'.
  final TransitStop? stop;
  final RouteShape? shape;

  /// Fin quando resta chiusa, se tutti gli avvisi che la chiudono dicono
  /// la stessa data.
  final DateTime? until;

  /// Da quando chiudera', per [StopState.closesLater].
  final DateTime? from;

  /// Dove salire invece, la piu' vicina prima: le fermate aperte ai due
  /// capi del tratto chiuso, sulla stessa linea e nella stessa direzione.
  final List<({TransitStop stop, double meters})> walkTo;

  static StopAnswer of(SavedStop saved, LineStatus? status, GtfsIndex index) {
    final shape = index.mainShape(saved.routeId, saved.directionId);
    final stop = shape == null ? null : _find(shape, saved);
    if (shape == null || stop == null) {
      return StopAnswer(state: StopState.notOnRoute, saved: saved);
    }
    if (status == null) {
      return StopAnswer(
        state: StopState.unknown,
        saved: saved,
        stop: stop,
        shape: shape,
      );
    }

    bool chiude(DeviationReport r) =>
        r.shape.directionId == saved.directionId &&
        r.skippedStops.any((s) => s.stop.id == stop.id);

    final adesso = status.activeReports.where(chiude).toList();
    if (adesso.isNotEmpty) {
      return StopAnswer(
        state: StopState.closed,
        saved: saved,
        stop: stop,
        shape: shape,
        until: ClosureSummary.commonEnd(adesso),
        walkTo: _doveSalire(stop, shape, status.activeReports),
      );
    }

    final poi = status.scheduledReports.where(chiude).toList();
    if (poi.isNotEmpty) {
      DateTime? primo;
      for (final r in poi) {
        final f = r.notice.inizioDaDire(status.checkedAt);
        if (f != null && (primo == null || f.isBefore(primo))) primo = f;
      }
      return StopAnswer(
        state: StopState.closesLater,
        saved: saved,
        stop: stop,
        shape: shape,
        from: primo,
      );
    }

    // «Servita» si dice solo se ogni avviso in corso su questa direzione
    // e' stato letto. Uno non letto — quota esaurita, testo che non
    // descrive un percorso — puo' riguardare proprio questa fermata.
    final nonLetti = status.activeReports.where(
      (r) => r.shape.directionId == saved.directionId && r.impact == null,
    );
    if (nonLetti.isNotEmpty) {
      return StopAnswer(
        state: StopState.uncertain,
        saved: saved,
        stop: stop,
        shape: shape,
      );
    }

    return StopAnswer(
      state: StopState.served,
      saved: saved,
      stop: stop,
      shape: shape,
    );
  }

  /// Il palo nel percorso di oggi: per id, e se non c'e' per codice.
  static TransitStop? _find(RouteShape shape, SavedStop saved) {
    for (final s in shape.stops) {
      if (s.id == saved.stopId) return s;
    }
    if (saved.stopCode == null) return null;
    for (final s in shape.stops) {
      if (s.code == saved.stopCode) return s;
    }
    return null;
  }

  /// Le fermate aperte ai capi del tratto che contiene [stop].
  static List<({TransitStop stop, double meters})> _doveSalire(
    TransitStop stop,
    RouteShape shape,
    List<DeviationReport> attivi,
  ) {
    final direzione = ClosureSummary.of(
      attivi,
    ).where((d) => d.shape.shapeId == shape.shapeId).firstOrNull;
    final tratto = direzione?.runs
        .where((r) => r.stops.any((s) => s.id == stop.id))
        .firstOrNull;
    if (tratto == null) return const [];
    final da = stop.position.meters;
    return [
      for (final s in [?tratto.before, ?tratto.after])
        (stop: s, meters: da.distanceTo(s.position.meters)),
    ]..sort((a, b) => a.meters.compareTo(b.meters));
  }
}
