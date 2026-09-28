import '../geo/geometry.dart';
import '../models/transit.dart';
import 'vehicle_heading.dart';

/// Il verso di marcia a ciascuna fermata di una direzione, preso dal
/// percorso: la direzione va dal primo capolinea all'ultimo, e la freccia
/// segue la linea nel punto in cui passa dalla fermata.
///
/// Sulla mappa due pallini sui lati opposti della stessa via sembrano la
/// stessa fermata, e invece da uno si va verso un capolinea e dall'altro
/// verso l'altro. La freccia dentro il pallino lo dice senza doverla
/// toccare.
class VersoFermate {
  const VersoFermate._();

  /// Oltre questa distanza dal percorso la fermata non si orienta: il palo
  /// e' fuori posto nel GTFS, o il percorso passa altrove.
  static const distanzaMassima = 60.0;

  /// Quanto percorso si guarda prima e dopo la fermata. Col segmento solo,
  /// una fermata vicino a un incrocio prendeva il verso della via
  /// trasversale.
  static const finestra = 25.0;

  static final _giaCalcolati = Expando<Map<String, double>>();

  /// Il verso del percorso a ogni fermata di [shape], in gradi (0 nord,
  /// 90 est, in senso orario), per id della fermata. Le fermate che non
  /// si riescono a orientare mancano.
  static Map<String, double> di(RouteShape shape) =>
      _giaCalcolati[shape] ??= _calcola(shape);

  static Map<String, double> _calcola(RouteShape shape) {
    final linea = shape.meters;
    if (linea.length < 2) return const {};
    final versi = <String, double>{};
    // Le fermate sono in ordine di percorrenza: ciascuna si cerca a valle
    // della precedente. Una linea che passa due volte vicino allo stesso
    // posto (un anello, un capolinea a racchetta) prenderebbe se no il
    // verso del passaggio sbagliato. Un po' di tolleranza all'indietro:
    // due pali vicini possono proiettarsi in ordine inverso di qualche metro.
    var da = 0.0;
    for (final s in shape.stops) {
      final p = Geometry.projectOnPolyline(
        s.position.meters,
        linea,
        fromAlong: da - 20,
      );
      if (p.distance > distanzaMassima) continue;
      da = p.alongMeters;
      final prima = Geometry.pointAtAlong(linea, p.alongMeters - finestra);
      final dopo = Geometry.pointAtAlong(linea, p.alongMeters + finestra);
      if (prima == null || dopo == null) continue;
      final gradi = VehicleHeading.rotta(prima, dopo);
      if (gradi != null) versi[s.id] = gradi;
    }
    return versi;
  }
}
