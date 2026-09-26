import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/llm/llm_client.dart';
import 'package:gtt_deviazioni/core/llm/llm_con_budget.dart';

class _Finto implements LlmClient {
  _Finto([this.errore]);
  final LlmException? errore;
  int chiamate = 0;

  @override
  String get name => 'finto';

  @override
  Future<String> complete(String prompt, {Map<String, dynamic>? jsonSchema}) {
    chiamate++;
    final e = errore;
    return e == null ? Future.value('{}') : Future.error(e);
  }
}

void main() {
  test('oltre il tetto del giro non chiede piu', () async {
    final f = _Finto();
    final llm = LlmConBudget(f, maxRichieste: 2);
    await llm.complete('a');
    await llm.complete('b');
    await expectLater(llm.complete('c'), throwsA(isA<LlmException>()));
    expect(f.chiamate, 2);
  });

  test('dopo la scadenza non inizia niente', () async {
    final f = _Finto();
    final llm = LlmConBudget(f,
        maxRichieste: 10,
        scadenza: DateTime.now().subtract(const Duration(seconds: 1)));
    await expectLater(llm.complete('a'), throwsA(isA<LlmException>()));
    expect(f.chiamate, 0);
  });

  test('quota del giorno finita: smette subito, con lo stesso errore', () async {
    // Le altre richieste fallirebbero tutte allo stesso modo: chiederle
    // costa tempo e basta.
    final f = _Finto(LlmException('finto', 'free-models-per-day exceeded',
        statusCode: 429));
    final llm = LlmConBudget(f, maxRichieste: 10);
    await expectLater(llm.complete('a'), throwsA(isA<LlmException>()));
    await expectLater(
        llm.complete('b'),
        throwsA(isA<LlmException>().having(
            (e) => e.detail, 'detail', contains('free-models-per-day'))));
    expect(f.chiamate, 1);
  });

  test('un sovraccarico momentaneo non ferma il giro', () async {
    final f = _Finto(LlmException('finto', 'upstream busy', statusCode: 429));
    final llm = LlmConBudget(f, maxRichieste: 10);
    await expectLater(llm.complete('a'), throwsA(isA<LlmException>()));
    await expectLater(llm.complete('b'), throwsA(isA<LlmException>()));
    expect(f.chiamate, 2);
  });

  test('senza modello non conta richieste', () async {
    final llm = LlmConBudget(const NessunLlm(), maxRichieste: 10);
    await expectLater(llm.complete('a'), throwsA(isA<LlmException>()));
    expect(llm.richieste, 0);
  });
}
