import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/deviation_service.dart';
import 'package:gtt_deviazioni/core/geo/projection.dart';
import 'package:gtt_deviazioni/core/llm/llm_client.dart';
import 'package:gtt_deviazioni/core/llm/llm_con_budget.dart';
import 'package:gtt_deviazioni/core/models/notice.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/publish/pubblicatore.dart';

/// Un modello che legge sempre «fermata 100 sospesa»: niente rete dopo,
/// perche' senza vie da cercare non servono ne' Photon ne' Valhalla.
class _Lettore implements LlmClient {
  int richieste = 0;

  @override
  String get name => 'lettore';

  @override
  Future<String> complete(String prompt, {Map<String, dynamic>? jsonSchema}) {
    richieste++;
    return Future.value('{"deviations":[{"lines":["4","15"],'
        '"deviation_type":"sospensione_fermate","via_sequence":[],'
        '"suspended_stop_codes":["100"]}]}');
  }
}

void main() {
  final fermata = TransitStop(
      id: 'S1', code: '100', name: 'Fermata 100 - SABOTINO',
      position: const GeoPoint(45.0700, 7.6650));
  RouteShape shape(String route) => RouteShape(
        shapeId: '$route:0', routeId: route, directionId: 0, headsign: 'X',
        points: const [GeoPoint(45.07, 7.66), GeoPoint(45.07, 7.69)],
        stops: [fermata], tripCount: 10,
      );
  final index = GtfsIndex(
    feedVersion: 'f',
    builtAt: DateTime(2026),
    lines: const {
      '4U': TransitLine(routeId: '4U', shortName: '4', sortOrder: 3),
      '15U': TransitLine(routeId: '15U', shortName: '15', sortOrder: 10),
      '65U': TransitLine(routeId: '65U', shortName: '65', sortOrder: 79),
    },
    shapes: {'4U': [shape('4U')], '15U': [shape('15U')], '65U': [shape('65U')]},
    stops: {fermata.id: fermata},
  );
  // Un avviso solo, che riguarda due linee.
  final avviso = RawNotice(
    id: 'a1',
    source: NoticeSource.gtfsRtAlert,
    text: 'Fermata 100 Sabotino temporaneamente sospesa.',
    routeIds: const ['4U', '15U'],
    sourceUrl: '',
  );

  test('tutte le linee, anche quelle senza avvisi', () async {
    final giro = await Pubblicatore(
      index: index,
      service: DeviationService(index: index, llm: _Lettore()),
    ).calcola(avvisi: [avviso]);
    expect(giro.stati.keys, containsAll(['4U', '15U', '65U']));
    expect(giro.stati['65U']!.reports, isEmpty);
    expect(giro.stati['4U']!.allSkippedStops.single.stop.code, '100');
    expect(giro.errori, isEmpty);
  });

  test('un avviso su due linee si legge una volta', () async {
    final llm = _Lettore();
    await Pubblicatore(
      index: index,
      service: DeviationService(index: index, llm: llm),
    ).calcola(avvisi: [avviso]);
    expect(llm.richieste, 1);
  });

  test('il giro dopo, se niente e cambiato, non chiede niente', () async {
    final primo = await Pubblicatore(
      index: index,
      service: DeviationService(index: index, llm: _Lettore()),
    ).calcola(avvisi: [avviso]);

    final llm = _Lettore();
    final secondo = await Pubblicatore(
      index: index,
      service: DeviationService(index: index, llm: llm),
    ).calcola(avvisi: [avviso], precedenti: primo.stati);
    expect(llm.richieste, 0);
    expect(secondo.stati['15U']!.allSkippedStops.single.stop.code, '100');
  });

  test('senza modello pubblica lo stesso, con le fermate lette dal testo',
      () async {
    final giro = await Pubblicatore(
      index: index,
      service: DeviationService(
          index: index,
          llm: LlmConBudget(const NessunLlm(), maxRichieste: 10)),
    ).calcola(avvisi: [avviso]);
    final r = giro.stati['15U']!.reports.single;
    expect(r.retryable, isTrue);
    expect(r.skippedStops.single.stop.code, '100');
    expect(giro.daRitentare, 1);
    expect(r.whyIncomplete, contains('letto a breve'));
  });
}
