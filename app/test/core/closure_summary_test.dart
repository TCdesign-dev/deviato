import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/deviation_service.dart';
import 'package:gtt_deviazioni/core/geo/projection.dart';
import 'package:gtt_deviazioni/core/models/notice.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/pipeline/closure_summary.dart';
import 'package:gtt_deviazioni/core/pipeline/stop_impact.dart';

/// La 10N verso via Massari, com'era il 26/09: un avviso per fermata.
void main() {
  final nomi = {
    '372': 'RONDÒ FORCA',
    '194': 'INDUSTRIA',
    '192': 'LIVORNO',
    '1947': 'UMBRIA',
    '1765': 'TREVISO',
    '1763': 'MORTARA',
    '1761': 'BRIN',
    '1759': 'VEROLENGO',
    '1757': 'LARGO MASSAIA',
    '1755': 'COPPINO',
  };
  var lon = 7.6600;
  final fermate = [
    for (final e in nomi.entries)
      TransitStop(
        id: 'S${e.key}',
        code: e.key,
        name: 'Fermata ${e.key} - ${e.value}',
        position: GeoPoint(45.0700, lon += 0.0030),
      ),
  ];
  final percorso = RouteShape(
    shapeId: '10NUDi10NRD6',
    routeId: '10NU',
    directionId: 1,
    headsign: 'NAVETTA, VIA MASSARI',
    points: const [GeoPoint(45.0700, 7.6600), GeoPoint(45.0700, 7.6950)],
    stops: fermate,
  );
  final analyzer = StopImpactAnalyzer(
    index: GtfsIndex(
      feedVersion: 't',
      builtAt: DateTime(2026),
      lines: const {},
      shapes: {'10NU': [percorso]},
      stops: {for (final s in fermate) s.id: s},
    ),
  );

  DeviationReport avviso(String code, {DateTime? fino}) => DeviationReport(
        notice: RawNotice(
            id: 'n$code',
            source: NoticeSource.gtfsRtAlert,
            text: 'La linea non transita dalla fermata $code.',
            validUntil: fino,
            sourceUrl: ''),
        confidence: Confidence.confermata,
        shape: percorso,
        impact: analyzer
            .declaredOnly(officialRoute: percorso, declaredCodes: {code}),
      );

  final chiuse = ['194', '192', '1947', '1765', '1763', '1759'];

  test('sei avvisi diventano due tratti', () {
    final d = ClosureSummary.of(chiuse.map(avviso)).single;
    expect(d.closedCount, equals(6));
    expect(d.runs.length, equals(2));
    expect(d.runs[0].stops.map((s) => s.code),
        equals(['194', '192', '1947', '1765', '1763']));
    expect(d.runs[1].stops.single.code, equals('1759'));
  });

  test('ai capi dei tratti ci sono fermate aperte', () {
    final d = ClosureSummary.of(chiuse.map(avviso)).single;
    expect(d.runs[0].before?.code, equals('372'));
    // Brin sta in mezzo ed e' aperta: e' il capo di tutti e due i tratti.
    expect(d.runs[0].after?.code, equals('1761'));
    expect(d.runs[1].before?.code, equals('1761'));
    expect(d.runs[1].after?.code, equals('1757'));
  });

  test('la striscia va dalla prima aperta prima all ultima aperta dopo', () {
    final d = ClosureSummary.of(chiuse.map(avviso)).single;
    expect(d.window.first.stop.code, equals('372'));
    expect(d.window.last.stop.code, equals('1757'));
    expect(d.window.where((w) => w.closed).length, equals(6));
  });

  test('stessa data di fine per tutti: si dice una volta', () {
    final r = chiuse.map((c) => avviso(c, fino: DateTime(2026, 9, 29, 3, 30)));
    expect(ClosureSummary.commonEnd(r), equals(DateTime(2026, 9, 29)));
  });

  test('date diverse: nessun «fino al» unico', () {
    expect(
        ClosureSummary.commonEnd([
          avviso('194', fino: DateTime(2026, 9, 29)),
          avviso('192', fino: DateTime(2026, 10, 3)),
        ]),
        isNull);
  });

  test('nessuna fermata chiusa, nessun tratto', () {
    expect(ClosureSummary.of(const []), isEmpty);
  });
}
