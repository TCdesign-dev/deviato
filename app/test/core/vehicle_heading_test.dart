import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/geo/projection.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/pipeline/vehicle_heading.dart';
import 'package:gtt_deviazioni/core/pipeline/vehicle_watch.dart';
import 'package:gtt_deviazioni/core/sources/vehicles_source.dart';

/// La freccia sul mezzo deve dire dove va, e il colore verso quale
/// capolinea. Il caso difficile e' la via percorsa nei due sensi: li'
/// solo la rotta separa l'andata dal ritorno.
void main() {
  // Andata verso est e ritorno verso ovest, sulla stessa via.
  final andata = RouteShape(
    shapeId: 'T:0',
    routeId: 'TESTU',
    directionId: 0,
    headsign: 'EST',
    points: const [GeoPoint(45.0700, 7.6600), GeoPoint(45.0700, 7.6900)],
  );
  final ritorno = RouteShape(
    shapeId: 'T:1',
    routeId: 'TESTU',
    directionId: 1,
    headsign: 'OVEST',
    points: const [GeoPoint(45.0700, 7.6900), GeoPoint(45.0700, 7.6600)],
  );

  VehicleTrack traccia(List<(double lat, double lon)> punti,
      {double? bearing}) {
    final t = VehicleTrack('V1');
    for (var i = 0; i < punti.length; i++) {
      t.points.add(VehicleObservation(
        vehicleId: 'V1',
        routeId: 'TESTU',
        position: GeoPoint(punti[i].$1, punti[i].$2),
        seenAt: DateTime(2026, 9, 27, 18, 0, i * 20),
        bearing: bearing,
      ));
    }
    return t;
  }

  test('verso est: rotta 90 gradi, e la direzione e\' l\'andata', () {
    final h = VehicleHeading.of(
        traccia([(45.0700, 7.6700), (45.0700, 7.6710)]), [andata, ritorno]);
    expect(h.degrees, closeTo(90, 1));
    expect(h.directionIndex, 0);
  });

  test('stessa via verso ovest: e\' il ritorno', () {
    final h = VehicleHeading.of(
        traccia([(45.0700, 7.6710), (45.0700, 7.6700)]), [andata, ritorno]);
    expect(h.degrees, closeTo(270, 1));
    expect(h.directionIndex, 1);
  });

  test('uno spostamento di pochi metri e\' rumore, non una direzione', () {
    // 0,00005 gradi di longitudine sono circa 4 m.
    final ferma = traccia([(45.0700, 7.67000), (45.0700, 7.67005)]);
    expect(VehicleHeading.of(ferma, [andata, ritorno]).degrees, isNull);
  });

  test('fermo: si usa la rotta dichiarata da GTT, se c\'e\'', () {
    final ferma = traccia([(45.0700, 7.6700)], bearing: 270);
    final h = VehicleHeading.of(ferma, [andata, ritorno]);
    expect(h.degrees, 270);
    expect(h.directionIndex, 1);
  });

  test('lo spostamento misurato vince sulla rotta dichiarata', () {
    final h = VehicleHeading.of(
        traccia([(45.0700, 7.6700), (45.0700, 7.6710)], bearing: 270),
        [andata, ritorno]);
    expect(h.degrees, closeTo(90, 1));
    expect(h.directionIndex, 0);
  });

  test('lontano dal percorso: la rotta si sa, la direzione no', () {
    // 45.0720 e' circa 220 m a nord della via: il mezzo e' in deviazione.
    final h = VehicleHeading.of(
        traccia([(45.0720, 7.6700), (45.0720, 7.6710)]), [andata, ritorno]);
    expect(h.degrees, closeTo(90, 1));
    expect(h.directionIndex, isNull);
  });

  test('di traverso rispetto al percorso: nessuna direzione', () {
    // Verso nord su una linea che va est-ovest: non e' ne' l'una ne'
    // l'altra, e dirne una sarebbe inventare.
    final h = VehicleHeading.of(
        traccia([(45.0698, 7.6700), (45.0701, 7.6700)]), [andata, ritorno]);
    expect(h.degrees, closeTo(0, 1));
    expect(h.directionIndex, isNull);
  });
}
