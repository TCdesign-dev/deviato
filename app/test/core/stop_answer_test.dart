import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/deviation_service.dart';
import 'package:gtt_deviazioni/core/geo/projection.dart';
import 'package:gtt_deviazioni/core/models/notice.dart';
import 'package:gtt_deviazioni/core/models/saved_stop.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/pipeline/stop_answer.dart';
import 'package:gtt_deviazioni/core/pipeline/stop_impact.dart';

/// La 10N verso piazza XVIII Dicembre il 26/09: nove fermate chiuse di
/// fila, da Largo Giachino Sud a Principe Eugenio. Qui ne bastano tre.
void main() {
  var lon = 7.66;
  TransitStop f(String code, String name) => TransitStop(
    id: 'S$code',
    code: code,
    name: 'Fermata $code - $name',
    position: GeoPoint(45.07, lon += 0.002),
  );

  final vibo = f('1410', 'VIBÒ');
  final giachino = f('422', 'LARGO GIACHINO SUD');
  final verolengo = f('1758', 'VEROLENGO');
  final statuto = f('373', 'STATUTO NORD');
  final andata = RouteShape(
    shapeId: 'A',
    routeId: '10NU',
    directionId: 0,
    headsign: 'NAVETTA, PIAZZA XVIII DICEMBRE',
    points: const [GeoPoint(45.07, 7.66), GeoPoint(45.07, 7.67)],
    stops: [vibo, giachino, verolengo, statuto],
    tripCount: 100,
  );
  final index = GtfsIndex(
    feedVersion: 't',
    builtAt: DateTime(2026),
    lines: const {'10NU': TransitLine(routeId: '10NU', shortName: '10N')},
    shapes: {
      '10NU': [andata],
    },
    stops: {for (final s in andata.stops) s.id: s},
  );
  final analyzer = StopImpactAnalyzer(index: index);
  final oggi = DateTime(2026, 9, 26, 17);

  DeviationReport chiude(Set<String> codici, {DateTime? da, DateTime? a}) =>
      DeviationReport(
        notice: RawNotice(
          id: codici.join(),
          source: NoticeSource.gtfsRtAlert,
          text: 'non transita',
          validFrom: da,
          validUntil: a,
          sourceUrl: '',
        ),
        confidence: Confidence.confermata,
        shape: andata,
        impact: analyzer.declaredOnly(
          officialRoute: andata,
          declaredCodes: codici,
        ),
      );

  LineStatus stato(List<DeviationReport> r) => LineStatus(
    line: index.lines['10NU']!,
    shape: andata,
    reports: r,
    checkedAt: oggi,
  );

  SavedStop salvata(TransitStop s, {int dir = 0}) => SavedStop(
    routeId: '10NU',
    directionId: dir,
    stopId: s.id,
    stopCode: s.code,
  );

  test('chiusa: lo dice, con la data e dove salire', () {
    final a = StopAnswer.of(
      salvata(giachino),
      stato([
        chiude({'422', '1758'}, a: DateTime(2026, 9, 29, 3)),
      ]),
      index,
    );
    expect(a.state, StopState.closed);
    expect(a.until, DateTime(2026, 9, 29));
    // Le fermate aperte ai capi del tratto, la piu' vicina prima.
    expect(a.walkTo.map((w) => w.stop.code), ['1410', '373']);
    expect(a.walkTo.first.meters, lessThan(a.walkTo.last.meters));
  });

  test('servita, anche se la linea ha fermate chiuse altrove', () {
    final a = StopAnswer.of(
      salvata(vibo),
      stato([
        chiude({'422'}),
      ]),
      index,
    );
    expect(a.state, StopState.served);
  });

  test('una chiusura in programma non la rende chiusa oggi', () {
    final a = StopAnswer.of(
      salvata(verolengo),
      stato([
        chiude({'1758'}, da: DateTime(2026, 10, 12)),
      ]),
      index,
    );
    expect(a.state, StopState.closesLater);
    expect(a.from, DateTime(2026, 10, 12));
  });

  test('linea non ancora controllata: non si sa, e lo si dice', () {
    expect(StopAnswer.of(salvata(vibo), null, index).state, StopState.unknown);
  });

  test('la stessa fermata nell altra direzione non e la stessa risposta', () {
    // Non c'e' un ritorno nell'indice: la fermata salvata per la direzione
    // 1 non si ritrova, e non si prende quella dell'andata al suo posto.
    final a = StopAnswer.of(
      salvata(giachino, dir: 1),
      stato([
        chiude({'422'}),
      ]),
      index,
    );
    expect(a.state, StopState.notOnRoute);
  });

  test('si ritrova dal codice sul palo se l id e cambiato', () {
    final a = StopAnswer.of(
      const SavedStop(
        routeId: '10NU',
        directionId: 0,
        stopId: 'vecchio',
        stopCode: '422',
      ),
      stato([
        chiude({'422'}),
      ]),
      index,
    );
    expect(a.state, StopState.closed);
  });

  test('si salva e si rilegge', () {
    final s = salvata(giachino);
    final r = SavedStop.fromJson(s.toJson())!;
    expect(r.same(s), isTrue);
    expect(r.stopCode, '422');
    expect(SavedStop.fromJson({'route': 1}), isNull);
  });
  test('un avviso non letto non permette di dire «servita»', () {
    // La 7 il 26/09: sospesa per un giorno, avviso non letto per la quota
    // esaurita. Dire «servita» sarebbe dire il contrario dell'avviso.
    final nonLetto = DeviationReport(
      notice: const RawNotice(
        id: 'x',
        source: NoticeSource.gtfsRtAlert,
        text: 'Linea temporaneamente sospesa.',
        sourceUrl: '',
      ),
      confidence: Confidence.soloTesto,
      shape: andata,
    );
    final a = StopAnswer.of(salvata(vibo), stato([nonLetto]), index);
    expect(a.state, StopState.uncertain);
  });
}
