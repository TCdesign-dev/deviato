import '../deviation_service.dart';
import '../models/notice.dart';
import '../models/transit.dart';
import '../pipeline/extractor.dart';

/// Quale algoritmo trasforma un avviso gia' letto nel percorso deviato e
/// nelle fermate non servite.
///
/// Il primo e' quello in servizio fino al 28/09/2026 e **non si tocca**:
/// e' la rete di sicurezza. Il secondo nasce come sua copia identica, ed
/// e' li' che si correggono i difetti misurati il 28/09 (vie ridotte a un
/// punto, incroci ignorati, un elenco di vie per due direzioni).
///
/// Nel job si sceglie con la variabile `ALGORITMO_PERCORSI` («1» o «2»,
/// predefinito 1): tornare al primo e' cambiare una variabile, non il
/// codice. Ogni esito ricorda da quale algoritmo viene, e cambiando
/// algoritmo gli avvisi si rianalizzano.
enum AlgoritmoPercorsi {
  primo(1),
  secondo(2);

  const AlgoritmoPercorsi(this.numero);

  /// Come si scrive nella variabile e nei file pubblicati.
  final int numero;

  /// Da «1» o «2». Qualunque altra cosa, anche niente, e' il primo: un
  /// errore di battitura non deve mettere in servizio l'algoritmo nuovo.
  static AlgoritmoPercorsi daTesto(String? s) =>
      s?.trim() == '2' ? secondo : primo;

  static AlgoritmoPercorsi daNumero(int? n) => n == 2 ? secondo : primo;
}

/// Un algoritmo che sa dire, dalla lettura, quali direzioni riguarda un
/// avviso. Il primo non lo fa: per lui decidono le parole del testo
/// ([DeviationService.shapesConcernedBy]).
abstract interface class FiltroDirezioni {
  /// Le direzioni di [candidate] a cui si riferisce la lettura. Mai vuota:
  /// nel dubbio, tutte.
  Future<List<RouteShape>> direzioniDi(
    RawNotice notice,
    List<RouteShape> candidate,
    ExtractionResult extraction,
  );
}

/// Da un avviso letto al suo esito, per una direzione.
abstract interface class Ricostruzione {
  Future<DeviationReport> analizza(
    RawNotice notice,
    RouteShape shape,
    ExtractionResult extraction, {
    void Function(String phase)? onProgress,
  });
}
