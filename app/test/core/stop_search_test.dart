import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/geo/projection.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/pipeline/stop_search.dart';

/// La ricerca delle fermate: per nome come sta sul cartello, o per numero
/// di palina.
void main() {
  FermataCercabile f(String id, String code, String nome) => FermataCercabile(
    stop: TransitStop(
      id: id,
      code: code,
      name: 'Fermata $code - $nome',
      position: const GeoPoint(45.07, 7.66),
    ),
    passaggi: const [(routeId: '15U', directionId: 0)],
  );
  final indice = IndiceFermate(
    feed: '20261003',
    capolinea: const {},
    fermate: [
      f('1', '587', 'MONGRENO'),
      f('2', '588', 'MONGRENO'),
      f('3', '5870', 'ALTROVE'),
      f('4', '252', 'PORTA NUOVA'),
      f('5', '7', 'CASTELLO'),
      f('6', '900', "SANT'ANNA"),
      f('7', '901', 'PIAZZA RISORGIMENTO'),
      f('8', '902', 'NIZZA (MONCALIERI)'),
      f('9', '903', 'CITTÀ'),
    ],
  );
  List<String> codici(String q) => [
    for (final r in StopSearch.filter(indice, q)) r.stop.code!,
  ];

  test(
    'per numero: prima la palina esatta, poi quelle che cominciano cosi',
    () {
      expect(codici('587'), ['587', '5870']);
      expect(codici('58'), ['587', '588', '5870']);
    },
  );

  test('per nome, senza badare a maiuscole, accenti e punteggiatura', () {
    expect(codici('mongreno'), ['587', '588']);
    expect(codici('Mongrenò'), ['587', '588']);
    expect(codici('sant anna'), ['900']);
    expect(codici('citta'), ['903']);
    expect(codici('nizza moncalieri'), ['902']);
  });

  test("basta l'inizio delle parole, in qualunque ordine", () {
    expect(codici('porta nu'), ['252']);
    expect(codici('nuova porta'), ['252']);
    expect(codici('orta'), isEmpty);
  });

  test('«piazza» e «via» sono facoltative: GTT spesso non le scrive', () {
    expect(codici('piazza castello'), ['7']);
    // Ma se nel nome c'e', conta come le altre.
    expect(codici('piazza risorgimento'), ['901']);
    expect(codici('piazza'), ['901']);
  });

  test('vuota, nessun risultato', () {
    expect(codici('   '), isEmpty);
  });

  test('ne restituisce al massimo quante chieste', () {
    expect(StopSearch.filter(indice, '5', max: 2), hasLength(2));
  });
}
