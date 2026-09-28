import '../geo/geometry.dart';
import '../geo/projection.dart';
import '../models/transit.dart';

/// Dove due vie si toccano, e dove una via incontra la linea.
///
/// Un avviso e' una sequenza di svolte: «devia per corso Vinzaglio, via
/// Cernaia, …» vuol dire che il bus gira da corso Vinzaglio in via
/// Cernaia. Il punto giusto da dare al calcolo del percorso e' l'incrocio
/// fra una via e la successiva, non un punto qualunque di ciascuna.
class Incroci {
  const Incroci._();

  /// Due vie si toccano se passano a meno di cosi': le carreggiate di un
  /// corso e il bordo di una piazza non coincidono con l'asse dell'altra.
  static const tolleranza = 40.0;

  /// Una via tocca la linea se ci passa a meno di cosi'.
  static const sullaLinea = 30.0;

  static const _passo = 10.0;

  /// Il punto in cui [a] e [b] si toccano. Se si toccano in piu' punti —
  /// due corsi paralleli uniti da piu' traverse, una via ad anello — vince
  /// quello piu' vicino a [vicino], cioe' a dove il bus sta arrivando;
  /// senza, quello in cui passano piu' vicine. null se non si toccano.
  static GeoPoint? incrocio(
    List<List<GeoPoint>> a,
    List<List<GeoPoint>> b, {
    GeoPoint? vicino,
  }) {
    final candidati = <({Point punto, double distanza})>[];
    for (final ta in a) {
      for (final tb in b) {
        final pa = [for (final p in ta) p.meters];
        final pb = [for (final p in tb) p.meters];
        for (var i = 0; i < pa.length - 1; i++) {
          for (var j = 0; j < pb.length - 1; j++) {
            final c = _vicinissimi(pa[i], pa[i + 1], pb[j], pb[j + 1]);
            if (c.distanza <= tolleranza) candidati.add(c);
          }
        }
      }
    }
    if (candidati.isEmpty) return null;
    final v = vicino?.meters;
    candidati.sort(
      (x, y) => v == null
          ? x.distanza.compareTo(y.distanza)
          : x.punto.distanceTo(v).compareTo(y.punto.distanceTo(v)),
    );
    return _gradi(candidati.first.punto);
  }

  /// Il punto di [via] piu' vicino a [p]: dove si entra in una via che non
  /// tocca la precedente (una piazza disegnata come area, una via che in
  /// OpenStreetMap si interrompe).
  static GeoPoint? piuVicino(List<List<GeoPoint>> via, GeoPoint p) {
    final q = p.meters;
    Point? migliore;
    var minimo = double.infinity;
    for (final t in via) {
      final m = [for (final x in t) x.meters];
      final pr = Geometry.projectOnPolyline(q, m);
      if (pr.distance < minimo) {
        minimo = pr.distance;
        migliore = Geometry.pointAtAlong(m, pr.alongMeters);
      }
    }
    return migliore == null ? null : _gradi(migliore);
  }

  /// Un punto in cui [via] tocca [linea], da [daMetri] in avanti: dove il
  /// bus lascia la linea o ci torna. Il punto sta sulla linea.
  ///
  /// Senza [vicino] e' il primo lungo la linea. Con [vicino] e' quello piu'
  /// vicino a dove il bus entra nella via: via XX Settembre per la S4 e'
  /// la linea stessa per un lungo tratto, e il bus ci torna all'angolo con
  /// corso Matteotti, non dove la via comincia.
  static ({GeoPoint punto, double metri})? contatto(
    List<List<GeoPoint>> via,
    RouteShape linea, {
    double daMetri = 0,
    GeoPoint? vicino,
  }) {
    final l = linea.meters;
    if (l.length < 2) return null;
    final v = vicino?.meters;
    double? scelto;
    var migliore = double.infinity;
    for (final t in via) {
      final fitto = Geometry.densify([for (final p in t) p.meters], _passo);
      for (final q in fitto) {
        final pr = Geometry.projectOnPolyline(q, l, fromAlong: daMetri);
        if (pr.distance > sullaLinea) continue;
        final punteggio = v == null ? pr.alongMeters : q.distanceTo(v);
        if (punteggio < migliore) {
          migliore = punteggio;
          scelto = pr.alongMeters;
        }
      }
    }
    if (scelto == null) return null;
    return (punto: _gradi(Geometry.pointAtAlong(l, scelto)!), metri: scelto);
  }

  /// I due punti piu' vicini fra due segmenti, e la loro distanza. Se si
  /// incrociano, il punto d'incrocio.
  static ({Point punto, double distanza}) _vicinissimi(
    Point a1,
    Point a2,
    Point b1,
    Point b2,
  ) {
    final x = _intersezione(a1, a2, b1, b2);
    if (x != null) return (punto: x, distanza: 0);
    ({Point punto, double distanza}) su(Point p, Point s1, Point s2) {
      final q = _proietta(p, s1, s2);
      return (
        punto: Point((p.x + q.x) / 2, (p.y + q.y) / 2),
        distanza: p.distanceTo(q),
      );
    }

    final prove = [
      su(a1, b1, b2),
      su(a2, b1, b2),
      su(b1, a1, a2),
      su(b2, a1, a2),
    ]..sort((p, q) => p.distanza.compareTo(q.distanza));
    return prove.first;
  }

  static Point _proietta(Point p, Point a, Point b) {
    final dx = b.x - a.x, dy = b.y - a.y;
    final l2 = dx * dx + dy * dy;
    if (l2 == 0) return a;
    final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0);
    return Point(a.x + t * dx, a.y + t * dy);
  }

  static Point? _intersezione(Point p1, Point p2, Point p3, Point p4) {
    final d = (p2.x - p1.x) * (p4.y - p3.y) - (p2.y - p1.y) * (p4.x - p3.x);
    if (d == 0) return null;
    final t =
        ((p3.x - p1.x) * (p4.y - p3.y) - (p3.y - p1.y) * (p4.x - p3.x)) / d;
    final u =
        ((p3.x - p1.x) * (p2.y - p1.y) - (p3.y - p1.y) * (p2.x - p1.x)) / d;
    if (t < 0 || t > 1 || u < 0 || u > 1) return null;
    return Point(p1.x + t * (p2.x - p1.x), p1.y + t * (p2.y - p1.y));
  }

  static GeoPoint _gradi(Point p) {
    final (lat, lon) = Projection.toDegrees(p);
    return GeoPoint(lat, lon);
  }
}
