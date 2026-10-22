import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/models/saved_stop.dart';
import 'package:gtt_deviazioni/core/models/tragitto.dart';
import 'package:gtt_deviazioni/core/pipeline/risposta_tragitto.dart';
import 'package:gtt_deviazioni/core/pipeline/stop_answer.dart';

void main() {
  const t = Tragitto(
    id: 'casa-lavoro',
    nome: 'Casa → lavoro',
    tratte: [
      Tratta(
        routeId: '15U',
        directionId: 1,
        salitaId: 'A',
        salitaCodice: '587',
        discesaId: 'B',
      ),
      Tratta(routeId: '68U', directionId: 1, salitaId: 'C', discesaId: 'D'),
      Tratta(routeId: '15U', directionId: 0, salitaId: 'E', discesaId: 'F'),
    ],
  );

  test('si salva e si rilegge uguale', () {
    final r = Tragitto.fromJson(t.toJson())!;
    expect(r.toJson(), t.toJson());
    expect(r.tratte.first.salita.stopCode, '587');
    expect(Tragitto.fromJson({'id': 'x', 'nome': 'y', 'tratte': []}), isNull);
    expect(Tragitto.fromJson('rotto'), isNull);
  });

  test('le linee nell\'ordine del viaggio, senza doppioni', () {
    expect(t.linee, ['15U', '68U']);
  });

  RispostaTragitto con(Map<String, StopState> stati) => RispostaTragitto.of(
    t,
    (SavedStop s) =>
        StopAnswer(state: stati[s.stopId] ?? StopState.served, saved: s),
  );

  test('tutto servito', () {
    expect(con({}).tuttoServito, isTrue);
    expect(con({}).primoIntoppo, isNull);
  });

  test('il primo intoppo, nell\'ordine del viaggio', () {
    final r = con({'D': StopState.closed, 'B': StopState.closed});
    expect(r.primoIntoppo!.indice, 0);
    expect(r.primoIntoppo!.salita, isFalse); // dove scendi dalla 15
  });

  test('una fermata non servita conta prima di un avviso non letto', () {
    final r = con({'A': StopState.uncertain, 'E': StopState.closed});
    expect(r.primoIntoppo!.risposta.saved.stopId, 'E');
  });

  test('senza esito non si dice «tutto servito»', () {
    final r = RispostaTragitto.of(t, (_) => null);
    expect(r.tuttoServito, isFalse);
    expect(r.primoIntoppo!.risposta.state, StopState.unknown);
  });
}
