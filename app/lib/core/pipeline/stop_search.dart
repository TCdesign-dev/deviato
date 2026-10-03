import '../models/transit.dart';
import '../text/display_names.dart';

/// Una fermata di GTT con le linee che ci passano, per cercarla.
///
/// Un palo, non un nome: le due banchine della stessa fermata hanno id
/// e numero diversi, e di solito ci passa una direzione sola.
class FermataCercabile {
  FermataCercabile({required this.stop, required this.passaggi});

  final TransitStop stop;

  /// Le linee e le direzioni che fermano qui, nell'ordine di GTT.
  final List<({String routeId, int directionId})> passaggi;

  /// Il nome come si mostra, gia' pronto per il confronto: si calcola
  /// una volta, non a ogni lettera scritta, su qualche migliaio di fermate.
  late final String nomeCercabile = StopSearch.norm(DisplayNames.stop(stop));
}

/// Tutte le fermate della rete, come le pubblica il job (`fermate.json`).
class IndiceFermate {
  const IndiceFermate({
    required this.feed,
    required this.fermate,
    required this.capolinea,
  });

  /// La versione degli orari da cui viene: se cambia, si riscarica.
  final String? feed;
  final List<FermataCercabile> fermate;

  /// Il capolinea di ogni linea in ogni direzione, per dire «verso…».
  final Map<String, Map<int, String>> capolinea;

  String? capolineaDi(String routeId, int directionId) =>
      capolinea[routeId]?[directionId];
}

/// La ricerca fra le fermate, per nome o per numero di palina.
///
/// Chi aspetta alla fermata ha davanti il cartello: il nome («Mongreno») e
/// il numero (587). Sa raramente da che capolinea a che capolinea va la
/// sua linea, che e' come le linee si cercano.
class StopSearch {
  const StopSearch._();

  /// Le fermate che rispondono a [query], le piu' pertinenti prima, al
  /// massimo [max].
  ///
  /// Un numero: prima la palina con quel numero, poi quelle che cominciano
  /// cosi'. Delle parole: le fermate che le contengono tutte all'inizio di
  /// una parola del nome («porta nu» trova Porta Nuova), prima quelle il
  /// cui nome comincia cosi'. Maiuscole e accenti non contano.
  static List<FermataCercabile> filter(
    IndiceFermate indice,
    String query, {
    int max = 30,
  }) {
    final q = norm(query);
    if (q.isEmpty) return const [];
    // «piazza castello»: GTT scrive solo «CASTELLO». Le parole che dicono
    // che tipo di strada e' contano solo se sono tutto quello che si e'
    // scritto.
    final tutte = q.split(' ');
    final senzaTipo = [
      for (final p in tutte)
        if (!_tipiDiStrada.contains(p)) p,
    ];
    final parole = senzaTipo.isEmpty ? tutte : senzaTipo;
    final numero = RegExp(r'^\d+$').hasMatch(q);

    int? punteggio(FermataCercabile f, String nome) {
      final codice = f.stop.code ?? '';
      if (numero) {
        if (codice == q) return 0;
        if (codice.startsWith(q)) return 1;
      }
      final pezzi = nome.split(' ');
      if (!parole.every((p) => pezzi.any((w) => w.startsWith(p)))) {
        return null;
      }
      return nome.startsWith(q) ? 2 : 3;
    }

    final trovate = <(int, String, FermataCercabile)>[];
    for (final f in indice.fermate) {
      final nome = f.nomeCercabile;
      if (punteggio(f, nome) case final p?) trovate.add((p, nome, f));
    }
    trovate.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      if (c != 0) return c;
      final ca = a.$3.stop.code ?? '', cb = b.$3.stop.code ?? '';
      // Per numero, il piu' corto prima: scritto «58», la 587 viene prima
      // della 5870.
      if (a.$1 <= 1) {
        final l = ca.length.compareTo(cb.length);
        return l != 0 ? l : ca.compareTo(cb);
      }
      final n = a.$2.compareTo(b.$2);
      return n != 0 ? n : ca.compareTo(cb);
    });
    return [for (final t in trovate.take(max)) t.$3];
  }

  /// Minuscole, senza accenti, la punteggiatura come spazio, spazi
  /// singoli: «Sant'Anna» diventa «sant anna», e «Nizza (Moncalieri)»
  /// «nizza moncalieri».
  static String norm(String s) {
    final b = StringBuffer();
    var spazio = true;
    for (final r in s.toLowerCase().runes) {
      final c = String.fromCharCode(r);
      final lettera =
          _accenti[c] ??
          ((r >= 0x61 && r <= 0x7a) || (r >= 0x30 && r <= 0x39) ? c : null);
      if (lettera != null) {
        b.write(lettera);
        spazio = false;
      } else if (!spazio) {
        b.write(' ');
        spazio = true;
      }
    }
    return b.toString().trimRight();
  }

  static const _tipiDiStrada = {
    'via',
    'corso',
    'c',
    'so',
    'piazza',
    'p',
    'za',
    'piazzale',
    'largo',
    'viale',
    'strada',
    'str',
    'vicolo',
    'fermata',
  };

  static const _accenti = {
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ä': 'a',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'ö': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
  };
}
