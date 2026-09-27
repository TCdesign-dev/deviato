import 'dart:math' as math;

import '../geo/geometry.dart';
import '../geo/projection.dart';
import '../models/transit.dart';
import 'vehicle_watch.dart';

/// Dove sta andando un mezzo: la rotta, e verso quale capolinea.
///
/// Sulla mappa un pallino fermo non dice se il 15 che vedi sta venendo
/// verso la tua fermata o se ne sta andando, e su una via percorsa nei due
/// sensi le due cose si confondono. La freccia risponde alla prima domanda,
/// il colore della direzione alla seconda.
class VehicleHeading {
  const VehicleHeading({this.degrees, this.directionIndex});

  /// Nessuna informazione.
  static const sconosciuta = VehicleHeading();

  /// Rotta in gradi: 0 nord, 90 est, in senso orario. null se non si sa.
  final double? degrees;

  /// Indice, nella lista delle direzioni passata a [of], di quella che il
  /// mezzo sta percorrendo. null se non si capisce: fermo, fuori
  /// percorso, o su un tratto in cui nessuna direzione va da quella parte.
  final int? directionIndex;

  /// Quanto deve essersi spostato un mezzo perche' lo spostamento dica
  /// una direzione.
  ///
  /// MISURATO: la distanza del GPS dal percorso ha mediana 3,6 m e 99°
  /// percentile 28 m. Sotto una quindicina di metri lo spostamento fra
  /// due campioni e' spesso solo rumore, e la freccia girerebbe a caso su
  /// un mezzo fermo al semaforo.
  static const spostamentoMinimo = 15.0;

  /// Oltre questa distanza dal percorso di una direzione non si prova ad
  /// assegnarla: il mezzo e' in deviazione, o su un'altra variante.
  static const distanzaMassima = 60.0;

  /// Quanto la rotta del mezzo puo' scostarsi da quella del percorso.
  static const scartoAngolare = 60.0;

  static VehicleHeading of(VehicleTrack track, List<RouteShape> directions) {
    if (track.points.isEmpty) return sconosciuta;
    final ultimo = track.points.last;
    final gradi = _dalMovimento(track) ?? ultimo.bearing;
    if (gradi == null) return sconosciuta;

    final qui = ultimo.position.meters;
    int? scelta;
    var migliore = double.infinity;
    for (var i = 0; i < directions.length; i++) {
      final linea = directions[i].meters;
      if (linea.length < 2) continue;
      final p = Geometry.projectOnPolyline(qui, linea);
      if (p.distance > distanzaMassima) continue;
      final s = p.segmentIndex.clamp(0, linea.length - 2);
      final tangente = _rotta(linea[s], linea[s + 1]);
      if (tangente == null) continue;
      if (_scarto(gradi, tangente) > scartoAngolare) continue;
      // Andata e ritorno spesso passano per la stessa via: la rotta le
      // separa, e fra quelle rimaste vince la piu' vicina.
      if (p.distance < migliore) {
        migliore = p.distance;
        scelta = i;
      }
    }
    return VehicleHeading(degrees: gradi, directionIndex: scelta);
  }

  /// La rotta dall'ultimo spostamento abbastanza lungo da non essere
  /// rumore. Viene prima di quella dichiarata nel feed: questa e'
  /// misurata, quella non si sa come GTT la calcoli.
  static double? _dalMovimento(VehicleTrack track) {
    final ultimo = track.points.last.position.meters;
    for (var i = track.points.length - 2; i >= 0; i--) {
      final prima = track.points[i].position.meters;
      if (prima.distanceTo(ultimo) >= spostamentoMinimo) {
        return _rotta(prima, ultimo);
      }
    }
    return null;
  }

  /// Attenzione agli assi: in [Projection.toMeters] `x` e' la latitudine
  /// (nord) e `y` la longitudine (est), al contrario del solito.
  static double? _rotta(Point da, Point a) {
    final nord = a.x - da.x;
    final est = a.y - da.y;
    if (nord == 0 && est == 0) return null;
    final g = math.atan2(est, nord) * 180 / math.pi;
    return g < 0 ? g + 360 : g;
  }

  static double _scarto(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }
}
