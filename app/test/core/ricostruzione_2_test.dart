import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/deviation_service.dart';
import 'package:gtt_deviazioni/core/geo/geometry.dart';
import 'package:gtt_deviazioni/core/geo/projection.dart';
import 'package:gtt_deviazioni/core/models/notice.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/pipeline/extractor.dart';
import 'package:gtt_deviazioni/core/pipeline/geocoder.dart';
import 'package:gtt_deviazioni/core/pipeline/route_builder.dart';
import 'package:gtt_deviazioni/core/pipeline/stop_impact.dart';
import 'package:gtt_deviazioni/core/ricostruzione/rifinitura.dart';
import 'package:gtt_deviazioni/core/ricostruzione/ricostruzione_2.dart';
import 'package:gtt_deviazioni/core/ricostruzione/scelta_direzione.dart';

/// Photon finto: ogni via e' un punto fisso.
class _Geocoder extends Geocoder {
  _Geocoder(this.punti);
  final Map<String, GeoPoint> punti;

  @override
  Future<GeocodeResult> locate(
    String toponym, {
    required RouteShape near,
    String? municipality,
  }) async {
    final p = punti[toponym];
    return p == null
        ? GeocodeResult.notFound(toponym)
        : GeocodeResult(
            status: GeocodeStatus.ok,
            query: toponym,
            point: p,
            metersFromRoute: 0,
          );
  }
}

/// Valhalla finto: unisce le tappe con segmenti dritti, o disegna quello
/// che gli si dice. Ricorda le tappe ricevute.
class _Router extends RouteBuilder {
  _Router([this.disegna]);
  final List<GeoPoint> Function(List<GeoPoint> tappe)? disegna;
  List<GeoPoint> tappe = const [];

  @override
  Future<RouteBuildResult> build({
    required List<GeoPoint> waypoints,
    required RouteShape officialRoute,
    List<GeoPoint> requiredVias = const [],
  }) async {
    tappe = waypoints;
    return RouteBuildResult(
      status: RouteBuildStatus.ok,
      geometry: disegna?.call(waypoints) ?? waypoints,
      lengthMeters: 0,
    );
  }
}

void main() {
  // Una via dritta verso est lunga 3 km, e il ritorno sulla stessa via.
  // 0,001 gradi di longitudine sono ~79 m, di latitudine ~111 m.
  const lat = 45.0700;
  TransitStop palo(String id, double lon, double dLat) =>
      TransitStop(id: id, name: id, position: GeoPoint(lat + dLat, lon));
  final andata = RouteShape(
    shapeId: 'T:0',
    routeId: 'TU',
    directionId: 0,
    headsign: 'PIAZZA ORIENTE',
    points: const [GeoPoint(lat, 7.6600), GeoPoint(lat, 7.7000)],
    stops: [
      for (var i = 0; i < 8; i++) palo('A$i', 7.6625 + i * 0.005, 0.00002),
    ],
  );
  final ritorno = RouteShape(
    shapeId: 'T:1',
    routeId: 'TU',
    directionId: 1,
    headsign: 'PIAZZA PONENTE',
    points: const [GeoPoint(lat, 7.7000), GeoPoint(lat, 7.6600)],
    stops: [
      for (var i = 0; i < 8; i++) palo('R$i', 7.6975 - i * 0.005, -0.00002),
    ],
  );
  final index = GtfsIndex(
    feedVersion: 't',
    builtAt: DateTime(2026),
    lines: {'TU': const TransitLine(routeId: 'TU', shortName: 'T')},
    shapes: {'TU': [andata, ritorno]},
    stops: {
      for (final s in [...andata.stops, ...ritorno.stops]) s.id: s,
    },
  );
  const avviso = RawNotice(
    id: 'n1',
    source: NoticeSource.gtfsRtAlert,
    text: 'Linea T deviata.',
    routeIds: ['TU'],
    sourceUrl: '',
  );

  // Le vie: «corso Linea» e' la via della linea, e Photon la mette dove
  // capita (400 m prima dello stacco vero, a 7,670). A nord il giro
  // dell'andata, a sud quello del ritorno.
  final vie = _Geocoder({
    'corso Linea': const GeoPoint(lat, 7.6650),
    'via Nord': const GeoPoint(lat + 0.0010, 7.6700),
    'via Alta': const GeoPoint(lat + 0.0020, 7.6750),
    'via Rientro': const GeoPoint(lat + 0.0010, 7.6800),
    'via Sud': const GeoPoint(lat - 0.0010, 7.6800),
    'via Bassa': const GeoPoint(lat - 0.0020, 7.6750),
  });

  Ricostruzione2 algoritmo(_Router router) => Ricostruzione2(
        geocoder: vie,
        router: router,
        impact: StopImpactAnalyzer(index: index),
      );

  ExtractionResult letto(List<ParsedDeviation> d) =>
      ExtractionResult(status: ExtractionStatus.ok, deviations: d);

  double distanzaDallaLinea(GeoPoint p, RouteShape s) =>
      Geometry.pointToPolyline(p.meters, s.meters);

  group('un elenco per direzione', () {
    const est = ParsedDeviation(
      type: DeviationType.deviazione,
      directionDesc: 'direzione piazza Oriente',
      detachStreet: 'corso Linea',
      viaSequence: ['via Nord', 'via Alta', 'via Rientro'],
    );
    const ovest = ParsedDeviation(
      type: DeviationType.deviazione,
      directionDesc: 'direzione piazza Ponente',
      detachStreet: 'corso Linea',
      viaSequence: ['via Sud', 'via Bassa'],
    );

    test('ogni direzione prende il suo, non il primo', () async {
      // Il difetto della 9 il 28/09: l'avviso descriveva le due direzioni
      // e il ritorno veniva disegnato col percorso dell'andata.
      final a = await algoritmo(_Router())
          .analizza(avviso, andata, letto(const [est, ovest]));
      final r = await algoritmo(_Router())
          .analizza(avviso, ritorno, letto(const [est, ovest]));
      expect(a.parsed!.directionDesc, 'direzione piazza Oriente');
      expect(r.parsed!.directionDesc, 'direzione piazza Ponente');
      // Anche nell'ordine opposto della lettura.
      final r2 = await algoritmo(_Router())
          .analizza(avviso, ritorno, letto(const [ovest, est]));
      expect(r2.parsed!.directionDesc, 'direzione piazza Ponente');
    });

    test('lo stacco sta sulla linea, non dove Photon mette la via', () async {
      final router = _Router();
      await algoritmo(router)
          .analizza(avviso, andata, letto(const [est, ovest]));
      expect(distanzaDallaLinea(router.tappe.first, andata), lessThan(1));
      expect(distanzaDallaLinea(router.tappe.last, andata), lessThan(1));
    });
  });

  group('un elenco solo, per tutte e due le direzioni', () {
    const unica = ParsedDeviation(
      type: DeviationType.deviazione,
      detachStreet: 'corso Linea',
      viaSequence: ['via Nord', 'via Alta', 'via Rientro'],
    );

    test('nel verso in cui e\' scritto resta com\'e\'', () async {
      final a = await algoritmo(_Router())
          .analizza(avviso, andata, letto(const [unica]));
      expect(a.confidence, Confidence.confermata);
      expect(a.whyIncomplete, isNull);
    });

    test('per l\'altra direzione si gira, e si dice', () async {
      final router = _Router();
      final r = await algoritmo(router)
          .analizza(avviso, ritorno, letto(const [unica]));
      // Le tappe vanno verso ovest, nel verso del ritorno.
      expect(router.tappe.first.lon, greaterThan(router.tappe.last.lon));
      expect(r.confidence, Confidence.probabile);
      expect(r.whyIncomplete, contains('al contrario'));
    });
  });

  group('il rosso', () {
    const giro = ParsedDeviation(
      type: DeviationType.deviazione,
      detachStreet: 'corso Linea',
      viaSequence: ['via Nord', 'via Alta', 'via Rientro'],
    );
    const nord = lat + 0.0020;

    test('perde i pezzi che corrono sopra la linea normale', () async {
      // Valhalla fa 800 m sulla linea prima di uscire, e 800 dopo.
      final r = await algoritmo(_Router((_) => const [
            GeoPoint(lat, 7.6600),
            GeoPoint(lat, 7.6700),
            GeoPoint(nord, 7.6700),
            GeoPoint(nord, 7.6800),
            GeoPoint(lat, 7.6800),
            GeoPoint(lat, 7.6900),
          ])).analizza(avviso, andata, letto(const [giro]));
      final g = r.deviatedGeometry!;
      expect(g.first.lon, closeTo(7.6700, 0.0004));
      expect(g.last.lon, closeTo(7.6800, 0.0004));
      expect(distanzaDallaLinea(g.first, andata), lessThanOrEqualTo(25));
      expect(r.confidence, Confidence.confermata);
    });

    test('se va in fondo a una via e torna indietro, e\' da confermare',
        () async {
      // Una via lunga finita in un punto lontano: il calcolo ci va e torna.
      final r = await algoritmo(_Router((_) => const [
            GeoPoint(lat, 7.6700),
            GeoPoint(nord, 7.6700),
            GeoPoint(nord, 7.6900),
            GeoPoint(nord, 7.6800),
            GeoPoint(lat, 7.6800),
          ])).analizza(avviso, andata, letto(const [giro]));
      expect(r.confidence, Confidence.probabile);
      expect(r.whyIncomplete, contains('non corrisponde'));
    });

    test('se sta tutto sopra la linea normale non si disegna', () async {
      final r = await algoritmo(_Router((_) => const [
            GeoPoint(lat, 7.6600),
            GeoPoint(lat, 7.6900),
          ])).analizza(avviso, andata, letto(const [giro]));
      expect(r.deviatedGeometry, isNull);
      expect(r.confidence, Confidence.soloTesto);
    });
  });

  group('SceltaDirezione', () {
    test('riconosce il capolinea anche con l\'apostrofo e abbreviato', () {
      final s = RouteShape(
        shapeId: 'X',
        routeId: 'X',
        directionId: 1,
        headsign: "C.SO M. D'AZEGLIO",
        points: const [],
      );
      const giusta = ParsedDeviation(
        type: DeviationType.deviazione,
        directionDesc: "Direzione corso Massimo D’Azeglio",
      );
      const altra = ParsedDeviation(
        type: DeviationType.deviazione,
        directionDesc: 'Direzione piazza Stampalia',
      );
      final scelta = SceltaDirezione.per(const [altra, giusta], s);
      expect(scelta.deviazione, same(giusta));
      expect(scelta.esplicita, isTrue);
    });

    test('«in entrambe le direzioni» non nomina nessun capolinea', () {
      expect(SceltaDirezione.parole('in entrambe le direzioni'), isEmpty);
    });
  });

  group('Rifinitura', () {
    test('un percorso dritto non si ripercorre', () {
      expect(
        Rifinitura.ripercorso(const [
          GeoPoint(lat, 7.6600),
          GeoPoint(lat, 7.6700),
        ]),
        0,
      );
    });

    test('andare e tornare si misura, anche su due carreggiate', () {
      // 790 m verso est e ritorno a 15 m di distanza.
      final m = Rifinitura.ripercorso(const [
        GeoPoint(lat, 7.6600),
        GeoPoint(lat, 7.6700),
        GeoPoint(lat + 0.000135, 7.6700),
        GeoPoint(lat + 0.000135, 7.6600),
      ]);
      expect(m, greaterThan(600));
    });

    test('un rosso che va all\'indietro lungo la linea e\' segnalato', () {
      final problemi = Rifinitura.controlla(const [
        GeoPoint(lat, 7.6900),
        GeoPoint(lat + 0.0020, 7.6900),
        GeoPoint(lat + 0.0020, 7.6700),
        GeoPoint(lat, 7.6700),
      ], andata);
      expect(problemi, contains('verso contrario alla direzione'));
    });
  });
}
