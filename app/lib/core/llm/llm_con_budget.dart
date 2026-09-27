import 'llm_client.dart';

/// Un [LlmClient] che smette di chiedere quando non ha piu' senso.
///
/// Serve al job che calcola per tutti: gira ogni mezz'ora, e ogni giro
/// deve restare dentro un tetto di richieste e di tempo. Tre casi in cui
/// si smette:
///
/// - **tetto del giro**: oltre [maxRichieste] le letture restano in coda
///   per il giro dopo. Il primo giro, con 265 avvisi da leggere, non deve
///   bruciare in un colpo la quota del giorno;
/// - **scadenza**: dopo [scadenza] non si inizia piu' niente, perche' il
///   job deve avere il tempo di pubblicare. Una lettura col modello
///   gratuito puo' durare un minuto e mezzo;
/// - **quota finita o chiave rifiutata**: dopo il primo errore di questo
///   tipo tutte le altre richieste fallirebbero allo stesso modo. Si
///   risponde subito con lo stesso errore, senza chiedere.
///
/// Gli errori prodotti qui sono [LlmException] come gli altri: l'avviso
/// risulta «da ritentare» e il giro successivo lo rilegge.
class LlmConBudget implements LlmClient {
  LlmConBudget(this._interno, {required this.maxRichieste, this.scadenza});

  final LlmClient _interno;
  final int maxRichieste;
  final DateTime? scadenza;

  int richieste = 0;
  LlmException? _fermo;

  /// Perche' ha smesso, se ha smesso per un errore del fornitore.
  LlmException? get fermoPer => _fermo;

  /// Testo che [DeviationService.explainExtractionFailure] riconosce come
  /// «avviso non ancora letto»: non e' un guasto, e' la coda.
  static const inCoda = 'in coda per il prossimo giro';

  @override
  String get name => _interno.name;

  @override
  Future<String> complete(String prompt,
      {Map<String, dynamic>? jsonSchema}) async {
    final fermo = _fermo;
    if (fermo != null) throw fermo;
    // Senza modello non parte niente: non e' una richiesta.
    if (_interno is NessunLlm) throw LlmException(name, inCoda);
    final s = scadenza;
    if (richieste >= maxRichieste || (s != null && DateTime.now().isAfter(s))) {
      throw LlmException(name, inCoda);
    }
    richieste++;
    try {
      return await _interno.complete(prompt, jsonSchema: jsonSchema);
    } on LlmException catch (e) {
      if (_definitivoPerOggi(e)) _fermo = e;
      rethrow;
    }
  }

  /// Quota del giorno finita, chiave rifiutata o credito esaurito.
  static bool _definitivoPerOggi(LlmException e) {
    final t = '${e.statusCode ?? ""} ${e.detail}';
    return t.contains('free-models-per-day') ||
        e.statusCode == 401 ||
        e.statusCode == 402 ||
        e.statusCode == 403;
  }
}

/// Nessun modello configurato: ogni avviso resta in coda.
///
/// Il job pubblica comunque: le fermate sospese dichiarate si leggono con
/// una regex e non hanno bisogno di nessun modello.
class NessunLlm implements LlmClient {
  const NessunLlm();

  @override
  String get name => 'nessuno';

  @override
  Future<String> complete(String prompt,
          {Map<String, dynamic>? jsonSchema}) =>
      Future.error(LlmException(name, LlmConBudget.inCoda));
}
