import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/deviation_service.dart';
import 'package:gtt_deviazioni/core/geo/projection.dart';
import 'package:gtt_deviazioni/core/io/formato_pubblicato.dart';
import 'package:gtt_deviazioni/core/pipeline/extractor.dart';
import 'package:gtt_deviazioni/core/models/notice.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/pipeline/stop_impact.dart';

/// Il contratto fra il job e l'app: quello che uno scrive, l'altra deve
/// rileggerlo uguale. Passando per una stringa JSON vera, come in rete.
void main() {
  Map<String, dynamic> viaJson(Map<String, Object?> m) =>
      jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  final f1 = TransitStop(
      id: 'S1', code: '100', name: 'Fermata 100 - SABOTINO',
      position: const GeoPoint(45.070123, 7.665432));
  final f2 = TransitStop(
      id: 'S2', code: '200', name: 'Fermata 200 - SAN PAOLO',
      position: const GeoPoint(45.071, 7.666));
  // Di un'altra linea: il telefono non la conosce, viaggia nello stato.
  final altrove = TransitStop(
      id: 'S9', code: '900', name: 'Fermata 900 - ALTROVE',
      position: const GeoPoint(45.072, 7.667));
  const linea = TransitLine(
      routeId: '15U', shortName: '15', longName: 'via Brissogne - piazza Coriolano',
      color: 'CC9900', routeType: 0, sortOrder: 10);
  final andata = RouteShape(
    shapeId: '15:0', routeId: '15U', directionId: 0, headsign: 'SASSI',
    points: const [GeoPoint(45.07, 7.66), GeoPoint(45.0712345, 7.69)],
    stops: [f1, f2], tripCount: 120,
  );
  final ritorno = RouteShape(
    shapeId: '15:1', routeId: '15U', directionId: 1, headsign: 'BRISSOGNE',
    points: const [GeoPoint(45.0712345, 7.69), GeoPoint(45.07, 7.66)],
    stops: [f2, f1], tripCount: 118,
  );

  test('l indice si rilegge, nell ordine di GTT', () {
    final j = viaJson(FormatoPubblicato.indice(
      feed: '20260922',
      generato: DateTime.utc(2026, 9, 26, 21),
      linee: const [
        TransitLine(routeId: '68U', shortName: '68', sortOrder: 82),
        linea,
      ],
      fonte: 'GTT',
    ));
    final r = FormatoPubblicato.leggiIndice(j);
    expect(r.feed, '20260922');
    expect(r.linee.map((l) => l.shortName), ['15', '68']);
    expect(r.linee.first.isTram, isTrue);
    // Scritta in UTC, riletta in ora locale: lo stesso istante.
    expect(r.generato.isUtc, isFalse);
    expect(r.generato.toUtc(), DateTime.utc(2026, 9, 26, 21));
  });

  test('i percorsi si rileggono con le fermate in ordine', () {
    final j = viaJson(
        FormatoPubblicato.percorsi(linea, [andata, ritorno], feed: 'f'));
    final r = FormatoPubblicato.leggiPercorsi(j);
    expect(r.linea.longName, linea.longName);
    expect(r.shapes.map((s) => s.shapeId), ['15:0', '15:1']);
    expect(r.shapes.last.stops.map((s) => s.code), ['200', '100']);
    expect(r.shapes.first.tripCount, 120);
    // Sei decimali: sotto il metro.
    expect(r.shapes.first.points.last.lat, closeTo(45.0712345, 1e-6));
    expect(r.shapes.first.stops.first.position.lon, closeTo(7.665432, 1e-6));
  });

  test('lo stato si rilegge intero, con le fermate di altre linee', () {
    final index = GtfsIndex(
      feedVersion: 'f',
      builtAt: DateTime(2026),
      lines: {'15U': linea},
      shapes: {'15U': [andata, ritorno]},
      stops: {f1.id: f1, f2.id: f2},
    );
    final stato = LineStatus(
      line: linea,
      shape: andata,
      shapeReturn: ritorno,
      checkedAt: DateTime(2026, 9, 26, 17),
      reports: [
        DeviationReport(
          notice: RawNotice(
            id: 'a1',
            source: NoticeSource.gtfsRtAlert,
            headline: 'Linea 15 deviata',
            text: 'Fermata 100 Sabotino sospesa.',
            routeIds: const ['15U'],
            reason: 'DEMONSTRATION',
            validFrom: DateTime(2026, 9, 24, 8),
            validUntil: DateTime(2026, 9, 28, 5),
            sourceUrl: 'x',
          ),
          shape: andata,
          confidence: Confidence.probabile,
          whyIncomplete: 'Da confermare.',
          retryable: true,
          deviatedGeometry: const [GeoPoint(45.069, 7.67), GeoPoint(45.069, 7.675)],
          impact: StopImpactResult(
            impacts: [
              StopImpact(
                stop: f1,
                status: StopStatus.declaredSuspended,
                alternatives: [
                  StopAlternative(stop: f2, straightMeters: 140.4, sameLine: true),
                  StopAlternative(stop: altrove, straightMeters: 210, sameLine: false),
                ],
              ),
            ],
            affectedFromMeters: 100,
            affectedToMeters: 900,
          ),
        ),
      ],
    );

    final j = viaJson(FormatoPubblicato.stato(stato));
    final r = FormatoPubblicato.leggiStato(j, index,
        controllata: DateTime(2026, 9, 26, 23))!;
    final rep = r.reports.single;
    expect(r.shape.shapeId, '15:0');
    expect(r.shapeReturn?.shapeId, '15:1');
    expect(r.checkedAt, DateTime(2026, 9, 26, 23));
    expect(rep.confidence, Confidence.probabile);
    expect(rep.retryable, isTrue);
    expect(rep.whyIncomplete, 'Da confermare.');
    expect(rep.notice.validFrom, DateTime(2026, 9, 24, 8));
    expect(rep.notice.reason, 'DEMONSTRATION');
    expect(rep.deviatedGeometry, hasLength(2));
    final saltata = rep.skippedStops.single;
    expect(saltata.stop.code, '100');
    expect(saltata.alternatives.map((a) => a.stop.code), ['200', '900']);
    expect(saltata.alternatives.first.sameLine, isTrue);
    expect(saltata.alternatives.last.stop.name, contains('ALTROVE'));
  });

  test('un avviso su un percorso sparito si scarta', () {
    final index = GtfsIndex(
      feedVersion: 'f', builtAt: DateTime(2026),
      lines: {'15U': linea}, shapes: {'15U': [andata]}, stops: const {},
    );
    final j = {
      'linea': '15U',
      'avvisi': [
        {
          'percorso': 'SPARITO',
          'affidabilita': 'confermata',
          'avviso': {'id': 'a', 'fonte': 'gtfsRtAlert', 'testo': 't', 'url': ''},
        },
      ],
    };
    final r = FormatoPubblicato.leggiStato(j, index, controllata: DateTime(2026));
    expect(r!.reports, isEmpty);
  });

  test('l\'algoritmo si scrive solo se non e\' il primo, e si rilegge', () {
    final index = GtfsIndex(
      feedVersion: 'f', builtAt: DateTime(2026),
      lines: {'15U': linea}, shapes: {'15U': [andata]}, stops: const {},
    );
    Map<String, dynamic> conAlgoritmo(int n) =>
        viaJson(FormatoPubblicato.stato(LineStatus(
          line: linea,
          shape: andata,
          checkedAt: DateTime(2026),
          reports: [
            DeviationReport(
              notice: const RawNotice(
                  id: 'a', source: NoticeSource.gtfsRtAlert, text: 't',
                  sourceUrl: ''),
              shape: andata,
              confidence: Confidence.soloTesto,
              algoritmo: n,
            ),
          ],
        )));

    // I file del primo restano com'erano: niente campo nuovo.
    final primo = conAlgoritmo(1);
    expect((primo['avvisi'] as List).first, isNot(contains('algoritmo')));
    expect(
        FormatoPubblicato.leggiStato(primo, index, controllata: DateTime(2026))!
            .reports.single.algoritmo,
        1);

    final secondo = conAlgoritmo(2);
    expect(
        FormatoPubblicato.leggiStato(secondo, index,
                controllata: DateTime(2026))!
            .reports.single.algoritmo,
        2);
  });

  test('la lettura del modello si pubblica e si rilegge uguale', () {
    final index = GtfsIndex(
      feedVersion: 'f', builtAt: DateTime(2026),
      lines: {'15U': linea}, shapes: {'15U': [andata]}, stops: const {},
    );
    const letta = ParsedDeviation(
      type: DeviationType.deviazione,
      lines: ['15'],
      directionDesc: 'direzione piazza Stampalia',
      municipality: 'Torino',
      detachStreet: 'corso Vittorio Emanuele II',
      detachCrossStreet: 'corso Vinzaglio',
      viaSequence: ['corso Vinzaglio', 'via Cernaia'],
      rejoinStreet: 'corso Tassoni',
      suspendedStopCodes: ['1234'],
      ambiguities: ['carreggiata centrale'],
    );
    final j = viaJson(FormatoPubblicato.stato(LineStatus(
      line: linea,
      shape: andata,
      checkedAt: DateTime(2026),
      reports: [
        DeviationReport(
          notice: const RawNotice(
              id: 'a', source: NoticeSource.gtfsRtAlert, text: 't',
              sourceUrl: ''),
          shape: andata,
          confidence: Confidence.confermata,
          letture: const [letta],
        ),
      ],
    )));
    final r = FormatoPubblicato.leggiStato(j, index,
            controllata: DateTime(2026))!
        .reports
        .single;
    expect(r.letture.single.toJson(), equals(letta.toJson()));
    expect(r.letture.single.detachCrossStreet, 'corso Vinzaglio');
    expect(r.letture.single.viaSequence, ['corso Vinzaglio', 'via Cernaia']);
  });

  test('le fermate lungo la deviazione viaggiano nello stato, in ordine', () {
    final index = GtfsIndex(
      feedVersion: 'f', builtAt: DateTime(2026),
      lines: {'15U': linea}, shapes: {'15U': [andata]}, stops: const {},
    );
    final j = viaJson(FormatoPubblicato.stato(LineStatus(
      line: linea,
      shape: andata,
      checkedAt: DateTime(2026),
      reports: [
        DeviationReport(
          notice: const RawNotice(
              id: 'a', source: NoticeSource.gtfsRtAlert, text: 't',
              sourceUrl: ''),
          shape: andata,
          confidence: Confidence.confermata,
          fermateSulPercorso: [altrove, f2],
        ),
      ],
    )));
    // La fermata di un'altra linea e' nel file: il telefono non la conosce.
    expect((j['fermate'] as Map).keys, contains('S9'));
    final r = FormatoPubblicato.leggiStato(j, index,
            controllata: DateTime(2026))!
        .reports
        .single;
    expect(r.fermateSulPercorso.map((f) => f.code), ['900', '200']);

    // Senza, il campo non c'e': i file di prima restano identici.
    final senza = viaJson(FormatoPubblicato.stato(LineStatus(
      line: linea,
      shape: andata,
      checkedAt: DateTime(2026),
      reports: [
        DeviationReport(
          notice: const RawNotice(
              id: 'a', source: NoticeSource.gtfsRtAlert, text: 't',
              sourceUrl: ''),
          shape: andata,
          confidence: Confidence.confermata,
        ),
      ],
    )));
    expect((senza['avvisi'] as List).first, isNot(contains('sulPercorso')));
  });

  test('il nome del file non esce dalla cartella', () {
    expect(FormatoPubblicato.nomeFile('10NU'), '10NU.json');
    expect(FormatoPubblicato.nomeFile('../x'), '___x.json');
  });
}
