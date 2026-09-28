import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/deviation_service.dart';
import 'package:gtt_deviazioni/core/geo/geometry.dart';
import 'package:gtt_deviazioni/core/geo/projection.dart';
import 'package:gtt_deviazioni/core/models/notice.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/net/gtt_http.dart';
import 'package:gtt_deviazioni/core/pipeline/extractor.dart';
import 'package:gtt_deviazioni/core/pipeline/geocoder.dart';
import 'package:gtt_deviazioni/core/pipeline/route_builder.dart';
import 'package:gtt_deviazioni/core/pipeline/stop_impact.dart';
import 'package:gtt_deviazioni/core/pipeline/vie_osm.dart';
import 'package:gtt_deviazioni/core/ricostruzione/incroci.dart';
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

/// Overpass finto: le vie intere che gli si danno, nessuna se vuoto.
class _Vie extends ViePerNome {
  _Vie([this.vie = const {}]);
  final Map<String, List<List<GeoPoint>>> vie;

  @override
  Future<Map<String, List<List<GeoPoint>>>> cerca(
    List<String> nomi,
    RouteShape vicino, {
    List<GeoPoint> attorno = const [],
  }) async => {for (final n in nomi) n: vie[n] ?? const []};
}

/// Overpass giu': ogni chiamata risponde 504.
class _OverpassGiu extends GttHttp {
  int chiamate = 0;

  @override
  Future<String> getTextPolite(String url, {Duration? timeout}) async {
    chiamate++;
    throw GttHttpException(url, 504, 'tempo scaduto');
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
    shapes: {
      'TU': [andata, ritorno],
    },
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

  Ricostruzione2 algoritmo(_Router router, [_Vie? intere]) => Ricostruzione2(
    geocoder: vie,
    router: router,
    impact: StopImpactAnalyzer(index: index),
    vie: intere ?? _Vie(),
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
      final a = await algoritmo(
        _Router(),
      ).analizza(avviso, andata, letto(const [est, ovest]));
      final r = await algoritmo(
        _Router(),
      ).analizza(avviso, ritorno, letto(const [est, ovest]));
      expect(a.parsed!.directionDesc, 'direzione piazza Oriente');
      expect(r.parsed!.directionDesc, 'direzione piazza Ponente');
      // Anche nell'ordine opposto della lettura.
      final r2 = await algoritmo(
        _Router(),
      ).analizza(avviso, ritorno, letto(const [ovest, est]));
      expect(r2.parsed!.directionDesc, 'direzione piazza Ponente');
    });

    test('lo stacco sta sulla linea, non dove Photon mette la via', () async {
      final router = _Router();
      await algoritmo(
        router,
      ).analizza(avviso, andata, letto(const [est, ovest]));
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
      final a = await algoritmo(
        _Router(),
      ).analizza(avviso, andata, letto(const [unica]));
      expect(a.confidence, Confidence.confermata);
      expect(a.whyIncomplete, isNull);
    });

    test('per l\'altra direzione si gira, e si dice', () async {
      final router = _Router();
      final r = await algoritmo(
        router,
      ).analizza(avviso, ritorno, letto(const [unica]));
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
      final r = await algoritmo(
        _Router(
          (_) => const [
            GeoPoint(lat, 7.6600),
            GeoPoint(lat, 7.6700),
            GeoPoint(nord, 7.6700),
            GeoPoint(nord, 7.6800),
            GeoPoint(lat, 7.6800),
            GeoPoint(lat, 7.6900),
          ],
        ),
      ).analizza(avviso, andata, letto(const [giro]));
      final g = r.deviatedGeometry!;
      expect(g.first.lon, closeTo(7.6700, 0.0004));
      expect(g.last.lon, closeTo(7.6800, 0.0004));
      expect(distanzaDallaLinea(g.first, andata), lessThanOrEqualTo(25));
      expect(r.confidence, Confidence.confermata);
    });

    test(
      'se va in fondo a una via e torna indietro, e\' da confermare',
      () async {
        // Una via lunga finita in un punto lontano: il calcolo ci va e torna.
        final r = await algoritmo(
          _Router(
            (_) => const [
              GeoPoint(lat, 7.6700),
              GeoPoint(nord, 7.6700),
              GeoPoint(nord, 7.6900),
              GeoPoint(nord, 7.6800),
              GeoPoint(lat, 7.6800),
            ],
          ),
        ).analizza(avviso, andata, letto(const [giro]));
        expect(r.confidence, Confidence.probabile);
        expect(r.whyIncomplete, contains('non corrisponde'));
      },
    );

    test('se sta tutto sopra la linea normale non si disegna', () async {
      final r = await algoritmo(
        _Router((_) => const [GeoPoint(lat, 7.6600), GeoPoint(lat, 7.6900)]),
      ).analizza(avviso, andata, letto(const [giro]));
      expect(r.deviatedGeometry, isNull);
      expect(r.confidence, Confidence.soloTesto);
    });
  });

  group('SceltaDirezione', () {
    test('riconosce il capolinea anche con l\'apostrofo e abbreviato', () {
      expect(SceltaDirezione.parole("C.SO M. D'AZEGLIO"), contains('azeglio'));
      expect(
        SceltaDirezione.parole('Direzione corso Massimo D\u2019Azeglio'),
        contains('azeglio'),
      );
    });

    test('«in entrambe le direzioni» non nomina nessun capolinea', () {
      expect(SceltaDirezione.parole('in entrambe le direzioni'), isEmpty);
      expect(SceltaDirezione.luogo('in entrambe le direzioni'), isNull);
    });

    test('il luogo di una direzione, da cercare sulla mappa', () {
      expect(
        SceltaDirezione.luogo('Nella sola direzione via Biscaretti'),
        'via Biscaretti',
      );
      expect(
        SceltaDirezione.luogo('Direzione via Goito (Moncalieri)'),
        'via Goito, Moncalieri',
      );
      expect(
        SceltaDirezione.luogo('in direzione XX Settembre'),
        'XX Settembre',
      );
    });
  });

  group('una direzione sola, col capolinea chiamato in un altro modo', () {
    // La 94 il 28/09: «nella sola direzione via Biscaretti», e negli orari
    // il capolinea si chiama «MIRAFIORI, VIA FACCIOLI (FCA)». Qui via
    // Lontana sta vicino alla fine dell'andata.
    final conLontana = _Geocoder({
      ...vie.punti,
      'via Lontana': const GeoPoint(lat + 0.0030, 7.7010),
    });
    const soloAndata = ParsedDeviation(
      type: DeviationType.deviazione,
      directionDesc: 'nella sola direzione via Lontana',
      detachStreet: 'corso Linea',
      viaSequence: ['via Nord', 'via Alta', 'via Rientro'],
    );
    Ricostruzione2 algoritmoLontana() => Ricostruzione2(
      geocoder: conLontana,
      router: _Router(),
      impact: StopImpactAnalyzer(index: index),
      vie: _Vie(),
    );

    test('l\'avviso non si applica all\'altra direzione', () async {
      final d = await algoritmoLontana().direzioniDi(avviso, [
        andata,
        ritorno,
      ], letto(const [soloAndata]));
      expect(d.map((s) => s.shapeId), ['T:0']);
    });

    test(
      'e sulla sua il percorso e\' quello dell\'avviso, non girato',
      () async {
        final a = await algoritmoLontana().analizza(
          avviso,
          andata,
          letto(const [soloAndata]),
        );
        expect(a.parsed, same(soloAndata));
        expect(a.whyIncomplete ?? '', isNot(contains('al contrario')));
      },
    );

    test(
      'se ci si arriva lo stesso, l\'altra direzione non ha fermate',
      () async {
        final r = await algoritmoLontana().analizza(
          avviso,
          ritorno,
          letto(const [soloAndata]),
        );
        expect(r.deviatedGeometry, isNull);
        expect(r.impact!.skipped, isEmpty);
        expect(r.whyIncomplete, contains('altra direzione'));
      },
    );

    test('senza nome ne\' luogo riconoscibile valgono tutte e due', () async {
      const qualunque = ParsedDeviation(
        type: DeviationType.deviazione,
        viaSequence: ['via Nord'],
      );
      final d = await algoritmoLontana().direzioniDi(avviso, [
        andata,
        ritorno,
      ], letto(const [qualunque]));
      expect(d.length, 2);
    });
  });

  group('gli incroci', () {
    // Le vie intere del giro a nord: via Nord sale da 7,670, via Alta va
    // verso est a 222 m dalla linea, via Rientro scende a 7,680. Photon
    // invece mette via Alta in un punto lontano, a 7,695: con quel punto
    // il calcolo andrebbe fin laggiu' e tornerebbe indietro.
    const nord = lat + 0.0020;
    final intere = _Vie({
      'corso Linea': [
        const [GeoPoint(lat, 7.6550), GeoPoint(lat, 7.7050)],
      ],
      'via Nord': [
        const [GeoPoint(lat - 0.0005, 7.6700), GeoPoint(nord + 0.0005, 7.6700)],
      ],
      'via Alta': [
        const [GeoPoint(nord, 7.6650), GeoPoint(nord, 7.7000)],
      ],
      'via Rientro': [
        const [GeoPoint(nord + 0.0005, 7.6800), GeoPoint(lat - 0.0005, 7.6800)],
      ],
    });
    final lontano = _Geocoder({
      ...vie.punti,
      'via Alta': const GeoPoint(nord, 7.6950),
    });
    const giro = ParsedDeviation(
      type: DeviationType.deviazione,
      detachStreet: 'corso Linea',
      detachCrossStreet: 'via Nord',
      viaSequence: ['via Nord', 'via Alta', 'via Rientro'],
    );

    test('le tappe sono le svolte, non i punti di Photon', () async {
      final router = _Router();
      await Ricostruzione2(
        geocoder: lontano,
        router: router,
        impact: StopImpactAnalyzer(index: index),
        vie: intere,
      ).analizza(avviso, andata, letto(const [giro]));
      final t = router.tappe;
      expect(t.length, 4);
      // corso Linea angolo via Nord, via Nord in via Alta, via Alta in via
      // Rientro, via Rientro sulla linea.
      expect(t[0].lon, closeTo(7.6700, 0.0001));
      expect(t[0].lat, closeTo(lat, 0.0001));
      expect(t[1].lon, closeTo(7.6700, 0.0001));
      expect(t[1].lat, closeTo(nord, 0.0001));
      expect(t[2].lon, closeTo(7.6800, 0.0001));
      expect(t[3].lon, closeTo(7.6800, 0.0001));
      expect(t[3].lat, closeTo(lat, 0.0001));
    });

    test('col giro vero niente andare e tornare: e\' verificato', () async {
      final r = await Ricostruzione2(
        geocoder: lontano,
        router: _Router(),
        impact: StopImpactAnalyzer(index: index),
        vie: intere,
      ).analizza(avviso, andata, letto(const [giro]));
      expect(Rifinitura.ripercorso(r.deviatedGeometry!), lessThan(50));
      expect(r.confidence, Confidence.confermata);
    });

    test('se una via manca in OpenStreetMap si usano i punti', () async {
      final router = _Router();
      await Ricostruzione2(
        geocoder: lontano,
        router: router,
        impact: StopImpactAnalyzer(index: index),
        vie: _Vie({...intere.vie}..remove('via Alta')),
      ).analizza(avviso, andata, letto(const [giro]));
      // C'e' il punto lontano di Photon fra le tappe.
      expect(router.tappe.any((p) => (p.lon - 7.6950).abs() < 0.0001), isTrue);
    });

    test(
      'Incroci: dove due vie si incrociano, anche fra un vertice e l\'altro',
      () {
        final x = Incroci.incrocio(
          [
            const [GeoPoint(lat, 7.66), GeoPoint(lat, 7.70)],
          ],
          [
            const [GeoPoint(lat - 0.001, 7.68), GeoPoint(lat + 0.001, 7.68)],
          ],
        )!;
        expect(x.lat, closeTo(lat, 0.00001));
        expect(x.lon, closeTo(7.68, 0.00001));
      },
    );

    test('Incroci: fra due incroci vince quello vicino a dove si arriva', () {
      final orizzontale = [
        const [GeoPoint(lat, 7.66), GeoPoint(lat, 7.70)],
      ];
      final anello = [
        const [
          GeoPoint(lat - 0.001, 7.67),
          GeoPoint(lat + 0.001, 7.67),
          GeoPoint(lat + 0.001, 7.69),
          GeoPoint(lat - 0.001, 7.69),
        ],
      ];
      final x = Incroci.incrocio(
        orizzontale,
        anello,
        vicino: const GeoPoint(lat, 7.692),
      )!;
      expect(x.lon, closeTo(7.69, 0.0001));
    });

    test('Incroci: il contatto con la linea si cerca a valle', () {
      final traversa = [
        const [GeoPoint(lat - 0.001, 7.675), GeoPoint(lat + 0.001, 7.675)],
      ];
      final prima = Incroci.contatto(traversa, andata)!;
      expect(prima.punto.lon, closeTo(7.675, 0.0002));
      expect(
        Incroci.contatto(traversa, andata, daMetri: prima.metri + 50),
        isNull,
      );
    });
  });

  group('ViePerNome', () {
    test(
      'se Overpass non risponde, per il resto del giro non si richiama',
      () async {
        final http = _OverpassGiu();
        final v = ViePerNome(http: http, pausa: Duration.zero);
        await expectLater(
          v.cerca(['via Nord'], andata),
          throwsA(isA<GttHttpException>()),
        );
        expect(http.chiamate, 2, reason: 'il server principale e la riserva');
        await expectLater(
          v.cerca(['via Alta'], andata),
          throwsA(isA<GttHttpException>()),
        );
        expect(http.chiamate, 2, reason: 'niente altre attese in questo giro');
      },
    );

    ({String nome, List<GeoPoint> punti}) via(String nome) =>
        (nome: nome, punti: const [GeoPoint(lat, 7.66), GeoPoint(lat, 7.67)]);

    test('stesso nome scritto in modi diversi', () {
      final a = ViePerNome.abbina(
        [
          'corso Massimo D\u2019Azeglio',
          'Rondò Rivella',
          'via Buttigliera Alta (SP 186)',
        ],
        [
          via("Corso Massimo D'Azeglio"),
          via('Rondò Rivella'),
          via('Via Buttigliera Alta'),
        ],
      );
      expect(a.values.every((t) => t.length == 1), isTrue);
    });

    test('corso Roma non e\' via Roma, ma senza tipo va bene lo stesso', () {
      final a = ViePerNome.abbina(
        ['corso Roma', 'piazza XVIII Dicembre'],
        [via('Via Roma'), via('Corso Roma'), via('XVIII Dicembre')],
      );
      expect(a['corso Roma']!.length, 1);
      expect(a['piazza XVIII Dicembre']!.length, 1);
    });

    test('via Cibrario e\' Via Luigi Cibrario, se non c\'e\' di meglio', () {
      final a = ViePerNome.abbina(
        ['via Cibrario', 'via Roma'],
        [via('Via Luigi Cibrario'), via('Via Roma'), via('Via Roma Nuova')],
      );
      expect(a['via Cibrario']!.length, 1);
      // Il nome identico vince: via Roma Nuova resta fuori.
      expect(a['via Roma']!.length, 1);
    });

    test(
      'i numeri: XX Settembre e\' Venti Settembre, I Maggio Primo Maggio',
      () {
        final a = ViePerNome.abbina(
          [
            'via XX Settembre',
            'piazza I Maggio',
            'corso Vittorio Emanuele II',
            'via di Nanni',
          ],
          [
            via('Via Venti Settembre'),
            via('Piazza Primo Maggio'),
            via('Corso Vittorio Emanuele II'),
            via('Via di Nanni'),
          ],
        );
        expect(a.values.every((t) => t.length == 1), isTrue);
        expect(ViePerNome.scomponi('via di Nanni').resto, 'di nanni');
        expect(
          ViePerNome.scomponi('piazza XVIII Dicembre').resto,
          '18 dicembre',
        );
      },
    );

    test('una via che non c\'e\' resta vuota', () {
      final a = ViePerNome.abbina(['via Inesistente'], [via('Via Roma')]);
      expect(a['via Inesistente'], isEmpty);
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
