import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/geo/projection.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/pipeline/verso_fermate.dart';

/// La freccia dentro la fermata viene dal percorso: la direzione va da un
/// capolinea all'altro, e la freccia segue la linea dove passa dal palo.
void main() {
  TransitStop fermata(String id, double lat, double lon) =>
      TransitStop(id: id, name: id, position: GeoPoint(lat, lon));

  RouteShape percorso(List<GeoPoint> punti, List<TransitStop> fermate) =>
      RouteShape(
        shapeId: 'T:0',
        routeId: 'TESTU',
        directionId: 0,
        headsign: 'EST',
        points: punti,
        stops: fermate,
      );

  test('su una via verso est la freccia punta a est', () {
    final s = percorso(
      const [GeoPoint(45.0700, 7.6600), GeoPoint(45.0700, 7.6900)],
      [fermata('A', 45.07003, 7.6700)],
    );
    expect(VersoFermate.di(s)['A'], closeTo(90, 1));
  });

  test('il ritorno sulla stessa via punta a ovest', () {
    final s = percorso(
      const [GeoPoint(45.0700, 7.6900), GeoPoint(45.0700, 7.6600)],
      [fermata('B', 45.06997, 7.6700)],
    );
    expect(VersoFermate.di(s)['B'], closeTo(270, 1));
  });

  test('a ridosso di una svolta la freccia la segue, non salta', () {
    // Verso est per 300 m, poi a nord. La fermata sta 5 m prima
    // dell'angolo: col solo segmento piu' vicino la freccia passerebbe da
    // est a nord spostando il palo di pochi metri. Conta il tratto intorno.
    final s = percorso(
      const [
        GeoPoint(45.0700, 7.6600),
        GeoPoint(45.0700, 7.6638),
        GeoPoint(45.0730, 7.6638),
      ],
      [fermata('C', 45.07002, 7.66374)],
    );
    final gradi = VersoFermate.di(s)['C']!;
    expect(gradi, greaterThan(20));
    expect(gradi, lessThan(90));
  });

  test('su un anello ogni fermata prende il suo passaggio', () {
    // Va a est, torna a ovest sulla stessa via (un capolinea a racchetta):
    // le due fermate stanno quasi nello stesso punto, ma la seconda viene
    // dopo il giro e va verso ovest.
    final s = percorso(
      const [
        GeoPoint(45.0700, 7.6600),
        GeoPoint(45.0700, 7.6800),
        GeoPoint(45.07005, 7.6800),
        GeoPoint(45.07005, 7.6600),
      ],
      [
        fermata('andando', 45.07000, 7.6650),
        fermata('tornando', 45.07005, 7.6650),
      ],
    );
    final versi = VersoFermate.di(s);
    expect(versi['andando'], closeTo(90, 1));
    expect(versi['tornando'], closeTo(270, 1));
  });

  test('una fermata lontana dal percorso resta senza freccia', () {
    final s = percorso(
      const [GeoPoint(45.0700, 7.6600), GeoPoint(45.0700, 7.6900)],
      [fermata('lontana', 45.0720, 7.6700)],
    );
    expect(VersoFermate.di(s).containsKey('lontana'), isFalse);
  });
}
