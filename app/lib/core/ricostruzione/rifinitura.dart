import '../geo/geometry.dart';
import '../geo/projection.dart';
import '../models/transit.dart';

/// Il percorso deviato, rifinito e controllato: il rosso deve cominciare e
/// finire sulla linea normale e coprire solo il tratto in cui il bus passa
/// davvero altrove.
///
/// MISURATO il 28/09/2026 sulle 66 deviazioni disegnate dal primo
/// algoritmo: in 15 il rosso correva sopra la linea normale per almeno
/// 300 m all'inizio, in 17 alla fine (la 99: 1,2 km su corso Roma), in 22
/// cominciava a piu' di 50 m dalla linea, e in 25 andava e tornava sulla
/// stessa via per almeno 100 m. Nessuna di queste cose la vedevano le
/// cinque prove di [RouteBuilder]: la 9, col suo giro enorme, era
/// «Verificato».
class Rifinitura {
  const Rifinitura._();

  /// Entro questa distanza dalla linea normale il rosso le «corre sopra».
  static const sopraLaLinea = 25.0;

  /// Oltre questa distanza un inizio o una fine non stanno sulla linea.
  static const lontanoDallaLinea = 50.0;

  /// Metri percorsi due volte in versi opposti oltre i quali il percorso
  /// e' sospetto: il bus non va in fondo a una via per tornare indietro,
  /// lo fa il calcolo quando una via lunga e' finita in un punto lontano.
  static const ripercorsoMassimo = 100.0;

  /// Un rientro puo' stare poco prima dello stacco (un anello che torna
  /// dove e' partito), non un chilometro prima.
  static const indietroMassimo = 50.0;

  static const _passo = 10.0;

  /// Il punto della linea normale piu' vicino a [p], cercato a valle di
  /// [daMetri]. E' li' che il bus lascia la linea o ci torna.
  static ({GeoPoint punto, double metri, double distanza}) aggancia(
    GeoPoint p,
    RouteShape normale, {
    double daMetri = 0,
  }) {
    final linea = normale.meters;
    final proiezione = Geometry.projectOnPolyline(
      p.meters,
      linea,
      fromAlong: daMetri,
    );
    final q = Geometry.pointAtAlong(linea, proiezione.alongMeters)!;
    final (lat, lon) = Projection.toDegrees(q);
    return (
      punto: GeoPoint(lat, lon),
      metri: proiezione.alongMeters,
      distanza: proiezione.distance,
    );
  }

  /// [deviata] senza i pezzi, in testa e in coda, che corrono sopra
  /// [normale]. Resta un punto sulla linea a ogni capo, cosi' il rosso
  /// parte dal blu. Vuota se tutto il percorso sta sopra la linea normale.
  static List<GeoPoint> taglia(List<GeoPoint> deviata, RouteShape normale) {
    if (deviata.length < 2) return deviata;
    final linea = normale.meters;
    final fitto = Geometry.densify([for (final p in deviata) p.meters], _passo);
    bool sopra(Point q) => Geometry.pointToPolyline(q, linea) <= sopraLaLinea;
    var a = 0;
    while (a < fitto.length - 1 && sopra(fitto[a + 1])) {
      a++;
    }
    var b = fitto.length - 1;
    while (b > a && sopra(fitto[b - 1])) {
      b--;
    }
    if (b - a < 2) return const [];
    return [
      for (final q in fitto.sublist(a, b + 1))
        () {
          final (lat, lon) = Projection.toDegrees(q);
          return GeoPoint(lat, lon);
        }(),
    ];
  }

  /// Quanti metri di [deviata] si ripercorrono in verso opposto: andare in
  /// fondo a una via e tornare indietro.
  ///
  /// Si confrontano punti ogni 10 m: due punti vicini (le due carreggiate
  /// di un corso stanno a una ventina di metri) con versi opposti sono lo
  /// stesso pezzo di strada fatto due volte.
  static double ripercorso(List<GeoPoint> deviata, {double vicino = 20}) {
    if (deviata.length < 2) return 0;
    final p = Geometry.densify([for (final q in deviata) q.meters], _passo);
    if (p.length < 3) return 0;
    final dx = <double>[], dy = <double>[];
    for (var i = 0; i < p.length - 1; i++) {
      final l = p[i].distanceTo(p[i + 1]);
      dx.add(l == 0 ? 0 : (p[i + 1].x - p[i].x) / l);
      dy.add(l == 0 ? 0 : (p[i + 1].y - p[i].y) / l);
    }
    var ripetuti = 0;
    for (var i = 0; i < dx.length; i++) {
      for (var j = 0; j < dx.length; j++) {
        if ((i - j).abs() < 4) continue;
        if (dx[i] * dx[j] + dy[i] * dy[j] < -0.85 &&
            p[i].distanceTo(p[j]) < vicino) {
          ripetuti++;
          break;
        }
      }
    }
    // Ogni pezzo ripercorso conta due volte, all'andata e al ritorno.
    return ripetuti * _passo / 2;
  }

  /// Cosa non torna in un percorso gia' rifinito, detto a chi legge. Vuota
  /// se va tutto bene.
  static List<String> controlla(List<GeoPoint> rifinita, RouteShape normale) {
    if (rifinita.length < 2) return const [];
    final problemi = <String>[];
    final linea = normale.meters;
    final inizio = Geometry.projectOnPolyline(rifinita.first.meters, linea);
    final fine = Geometry.projectOnPolyline(rifinita.last.meters, linea);
    if (inizio.distance > lontanoDallaLinea ||
        fine.distance > lontanoDallaLinea) {
      problemi.add('inizio o fine lontani dalla linea');
    }
    if (fine.alongMeters < inizio.alongMeters - indietroMassimo) {
      problemi.add('verso contrario alla direzione');
    }
    if (ripercorso(rifinita) > ripercorsoMassimo) {
      problemi.add('va e torna sulla stessa via');
    }
    return problemi;
  }
}
