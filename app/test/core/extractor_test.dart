import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/llm/llm_client.dart';
import 'package:gtt_deviazioni/core/models/notice.dart';
import 'package:gtt_deviazioni/core/pipeline/extractor.dart';

/// Il modello non viene interrogato: le risposte sono finte e costruite
/// per mettere alla prova cosa succede quando sbaglia. Un estrattore si
/// giudica soprattutto da come regge le risposte malfatte, perche' quelle
/// arrivano davvero.
///
/// La qualita' dell'estrazione vera si misura altrove, sui 34 avvisi
/// annotati a mano: tool/eval_extractor.dart.
void main() {
  const notice = RawNotice(
    id: 'test',
    source: NoticeSource.webVariazioni,
    text: 'Da via Pininfarina deviata in via Ferrero, via Di Vittorio, '
        'percorso normale.',
    sourceUrl: '',
  );

  String goodJson() => jsonEncode({
        'deviations': [
          {
            'lines': ['56'],
            'direction_desc': null,
            'deviation_type': 'deviazione',
            'municipality': 'Torino',
            'detach_point': {'street': 'via Pininfarina', 'cross_street': null},
            'via_sequence': [
              {'street': 'via Ferrero'},
              {'street': 'via Di Vittorio'}
            ],
            'rejoin_point': {'street': null, 'phrase': 'percorso normale'},
            'suspended_stop_codes': <String>[],
            'temporary_terminus': null,
            'ambiguities': <String>[],
          }
        ]
      });

  group('Estrazione riuscita', () {
    test('legge i campi e conserva l ordine delle vie', () async {
      final r = await NoticeExtractor(llm: _FakeLlm([goodJson()]))
          .extract(notice);
      expect(r.status, equals(ExtractionStatus.ok));
      final d = r.deviations.single;
      expect(d.type, equals(DeviationType.deviazione));
      expect(d.detachStreet, equals('via Pininfarina'));
      // L'ordine conta: diventa la sequenza di waypoint per il routing.
      expect(d.viaSequence, equals(['via Ferrero', 'via Di Vittorio']));
      expect(d.municipality, equals('Torino'));
    });

    test('allToponyms mette insieme stacco, vie e rientro in ordine',
        () async {
      final r = await NoticeExtractor(llm: _FakeLlm([goodJson()]))
          .extract(notice);
      expect(r.deviations.single.allToponyms,
          equals(['via Pininfarina', 'via Ferrero', 'via Di Vittorio']));
    });

    test('piu direzioni diventano piu oggetti', () async {
      final json = jsonEncode({
        'deviations': [
          {
            'deviation_type': 'limitazione',
            'direction_desc': 'via Corradino',
            'via_sequence': <Map<String, String>>[],
          },
          {
            'deviation_type': 'deviazione',
            'direction_desc': 'via Ponchielli',
            // Una via del testo: quelle che il testo non nomina si
            // scartano (vedi sotto).
            'via_sequence': [
              {'street': 'via Ferrero'}
            ],
          },
        ]
      });
      final r = await NoticeExtractor(llm: _FakeLlm([json])).extract(notice);
      expect(r.deviations.length, equals(2));
      expect(r.deviations[0].type, equals(DeviationType.limitazione));
      expect(r.deviations[1].type, equals(DeviationType.deviazione));
    });
  });

  group('Le vie devono stare nel testo', () {
    String lettura(List<String> vie) => jsonEncode({
          'deviations': [
            {
              'deviation_type': 'deviazione',
              'detach_point': {'street': 'via Pininfarina'},
              'via_sequence': [
                for (final v in vie) {'street': v}
              ],
            }
          ]
        });

    test('una via inventata scarta la lettura, senza ritentare', () async {
      // gemma-4-26b, a luglio: «corso Marradoncelli», fuso da due nomi.
      final llm = _FakeLlm([lettura(['via Ferrero', 'corso Marradoncelli'])]);
      final r = await NoticeExtractor(llm: llm).extract(notice);
      expect(r.status, ExtractionStatus.parseFailed);
      expect(r.detail, contains('corso Marradoncelli'));
      expect(llm.calls, 1);
    });

    test('di due deviazioni resta quella che torna col testo', () async {
      final json = jsonEncode({
        'deviations': [
          {
            'deviation_type': 'deviazione',
            'via_sequence': [
              {'street': 'via Ferrero'}
            ],
          },
          {
            'deviation_type': 'deviazione',
            'via_sequence': [
              {'street': 'via Inesistente'}
            ],
          },
        ]
      });
      final r = await NoticeExtractor(llm: _FakeLlm([json])).extract(notice);
      expect(r.status, ExtractionStatus.ok);
      expect(r.deviations.single.viaSequence, ['via Ferrero']);
    });

    test('abbreviazioni, accenti, numeri e iniziali di GTT passano', () {
      const testo = 'Da c.so V. Emanuele II angolo p.za Solferino, deviata '
          'in via XX Settembre, Lungo Po Cadorna, via Nizza, Piazza Carlo '
          'Felice, percorso normale. Fermata 123 sospesa.';
      final d = ParsedDeviation.fromJson({
        'deviation_type': 'deviazione',
        'detach_point': {
          'street': 'corso Vittorio Emanuele II',
          'cross_street': 'piazza Solferino',
        },
        'via_sequence': [
          {'street': 'via Venti Settembre'},
          {'street': 'lungo Po Luigi Cadorna'},
          {'street': 'via Nizza'},
          {'street': 'piazza Carlo Felice'},
        ],
      });
      // «Venti» e «Luigi» non sono nel testo: si scartano...
      expect(NoticeExtractor.vieNonNelTesto(d, testo),
          ['via Venti Settembre', 'lungo Po Luigi Cadorna']);
      // ...mentre i nomi come li scrive GTT, abbreviati, passano.
      final giusta = ParsedDeviation.fromJson({
        'deviation_type': 'deviazione',
        'detach_point': {
          'street': 'corso Vittorio Emanuele II',
          'cross_street': 'piazza Solferino',
        },
        'via_sequence': [
          {'street': 'via XX Settembre'},
          {'street': 'lungo Po Cadorna'},
          {'street': 'via Nizza'},
        ],
      });
      expect(NoticeExtractor.vieNonNelTesto(giusta, testo), isEmpty);
    });
  });

  group('Quando il modello risponde male', () {
    test('il JSON dentro un blocco markdown viene comunque letto', () async {
      // Succede spesso coi modelli senza schema nativo.
      final r = await NoticeExtractor(
              llm: _FakeLlm(['```json\n${goodJson()}\n```']))
          .extract(notice);
      expect(r.status, equals(ExtractionStatus.ok));
    });

    test('una risposta non JSON fa scattare UN secondo tentativo', () async {
      final llm = _FakeLlm(['mi dispiace, non posso aiutarti', goodJson()]);
      final r = await NoticeExtractor(llm: llm).extract(notice);
      expect(r.status, equals(ExtractionStatus.ok));
      expect(r.attempts, equals(2));
      expect(llm.calls, equals(2));
    });

    test('dopo due tentativi si arrende invece di inventare', () async {
      // E' la regola che conta: meglio mostrare il testo originale che
      // una struttura plausibile ma falsa.
      final llm = _FakeLlm(['non e JSON', 'nemmeno questo']);
      final r = await NoticeExtractor(llm: llm).extract(notice);
      expect(r.status, equals(ExtractionStatus.parseFailed));
      expect(r.isUsable, isFalse);
      expect(r.deviations, isEmpty);
      expect(llm.calls, equals(2), reason: 'non deve insistere all infinito');
    });

    test('un JSON valido ma con la forma sbagliata non passa', () async {
      final llm = _FakeLlm([
        jsonEncode({'risultato': 'ok'}),
        jsonEncode({'deviations': 'non e una lista'}),
      ]);
      final r = await NoticeExtractor(llm: llm).extract(notice);
      expect(r.status, equals(ExtractionStatus.parseFailed));
    });

    test('una lista vuota non e un successo', () async {
      // "Nessuna deviazione" e' una risposta legittima solo se il testo non
      // ne parla; qui ne parla, quindi la lista vuota e' un fallimento.
      final llm = _FakeLlm([
        jsonEncode({'deviations': <dynamic>[]}),
        jsonEncode({'deviations': <dynamic>[]}),
      ]);
      final r = await NoticeExtractor(llm: llm).extract(notice);
      expect(r.status, equals(ExtractionStatus.parseFailed));
    });

    test('un errore di rete non viene scambiato per estrazione fallita',
        () async {
      // Sono cose diverse: sull errore di rete ha senso ritentare piu'
      // tardi, sull estrazione fallita no.
      final r = await NoticeExtractor(llm: _FailingLlm()).extract(notice);
      expect(r.status, equals(ExtractionStatus.error));
      expect(r.attempts, equals(1), reason: 'inutile insistere su un 500');
    });
  });

  group('Il prompt', () {
    test('contiene il testo dell avviso e le regole che contano', () {
      final p = NoticeExtractor.buildPrompt(notice);
      expect(p, contains('via Pininfarina'));
      expect(p, contains('Non inventare vie'));
      expect(p, contains('Non produrre coordinate'));
      // Le due trappole trovate annotando a mano.
      expect(p, contains('CAUSA'));
      expect(p, contains('percorso attuale'));
    });
  });
}

class _FakeLlm implements LlmClient {
  _FakeLlm(this.responses);

  final List<String> responses;
  int calls = 0;

  @override
  String get name => 'fake';

  @override
  Future<String> complete(String prompt,
      {Map<String, dynamic>? jsonSchema}) async {
    final r = responses[calls.clamp(0, responses.length - 1)];
    calls++;
    return r;
  }
}

class _FailingLlm implements LlmClient {
  @override
  String get name => 'failing';

  @override
  Future<String> complete(String prompt,
          {Map<String, dynamic>? jsonSchema}) async =>
      throw LlmException('failing', 'servizio non disponibile', statusCode: 500);
}
