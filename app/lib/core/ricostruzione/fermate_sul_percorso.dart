import '../geo/geometry.dart';
import '../geo/projection.dart';
import '../models/transit.dart';
import '../pipeline/vehicle_heading.dart';
import '../pipeline/verso_fermate.dart';

/// Le fermate lungo il percorso deviato: dove si puo' prendere il bus
/// mentre e' deviato.
///
/// Le fermate saltate dicono dove il bus non passa; a chi aspetta serve
/// anche sapere dove passa. Durante una deviazione i bus GTT si fermano
/// alle fermate delle altre linee che trovano sulla strada: sono quelle
/// del GTFS vicine al rosso, lontane dalla linea normale, e dal lato
/// giusto della via.
class FermateSulPercorso {
  FermateSulPercorso(this._index);

  final GtfsIndex _index;

  /// Una fermata sta sul percorso deviato se ci passa a meno di cosi'.
  static const vicinoAlRosso = 25.0;

  /// Una fermata piu' vicina di cosi' alla linea normale e' gia' fra le
  /// sue: non e' una fermata della deviazione.
  static const lontanoDallaLinea = 40.0;

  /// Il verso del rosso e quello di un'altra linea alla stessa fermata
  /// possono differire al massimo di tanto: dall'altro lato della via si
  /// va nel verso opposto.
  static const scartoVerso = 60.0;

  /// Quanto rosso si guarda prima e dopo la fermata per il suo verso.
  static const _finestra = 25.0;

  late final Map<String, List<RouteShape>> _percorsiDi = () {
    final out = <String, List<RouteShape>>{};
    for (final percorsi in _index.shapes.values) {
      for (final s in percorsi) {
        for (final f in s.stops) {
          (out[f.id] ??= []).add(s);
        }
      }
    }
    return out;
  }();

  /// Le fermate lungo [rosso], nell'ordine in cui il bus le incontra.
  List<TransitStop> lungo(List<GeoPoint> rosso, RouteShape normale) {
    if (rosso.length < 2) return const [];
    final r = [for (final p in rosso) p.meters];
    final linea = normale.meters;
    final zona = Geometry.boundsOf(rosso, paddingMeters: vicinoAlRosso);
    final trovate = <({TransitStop fermata, double metri})>[];
    for (final f in _index.stops.values) {
      if (!zona.contains(f.position)) continue;
      final q = f.position.meters;
      final p = Geometry.projectOnPolyline(q, r);
      if (p.distance > vicinoAlRosso) continue;
      if (Geometry.pointToPolyline(q, linea) <= lontanoDallaLinea) continue;
      final verso = VehicleHeading.rotta(
        Geometry.pointAtAlong(r, p.alongMeters - _finestra)!,
        Geometry.pointAtAlong(r, p.alongMeters + _finestra)!,
      );
      if (verso == null) continue;
      // Il verso della fermata lo danno le linee che la servono. Una
      // fermata di cui non si sa il verso non si propone: meglio tacerla
      // che mandare qualcuno sul lato sbagliato.
      final giusto = (_percorsiDi[f.id] ?? const <RouteShape>[]).any((s) {
        final v = VersoFermate.di(s)[f.id];
        return v != null && _scarto(v, verso) <= scartoVerso;
      });
      if (giusto) trovate.add((fermata: f, metri: p.alongMeters));
    }
    trovate.sort((a, b) => a.metri.compareTo(b.metri));
    return [for (final t in trovate) t.fermata];
  }

  static double _scarto(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }
}
