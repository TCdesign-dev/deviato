import '../models/transit.dart';
import 'line_resolver.dart';

/// La ricerca fra le linee di GTT, per aggiungerne una.
///
/// Prima si scriveva il nome a memoria in un campo di testo, nelle
/// impostazioni, senza vedere niente: chi non sapeva che la notturna si
/// chiama «10N» non la trovava. Il GTFS ha gia' l'elenco intero, con i
/// capolinea: si cerca sul numero e sulle vie.
class LineSearch {
  const LineSearch._();

  /// Le linee che rispondono a [query], le piu' pertinenti prima.
  ///
  /// Vuota: tutte, nell'ordine di GTT. Altrimenti, nell'ordine:
  /// il numero identico, quella che riconosce [LineResolver] («N10» è la
  /// 10N), i numeri che cominciano cosi' («5» → 5, 5/, 50…), e infine le
  /// linee che passano dalle vie scritte («massari»).
  static List<TransitLine> filter(List<TransitLine> all, String query) {
    final q = _norm(query);
    final sorted = [...all]..sort(TransitLine.compare);
    if (q.isEmpty) return sorted;

    final risolta = LineResolver.matchIn(all, query);
    final parole = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    int? punteggio(TransitLine l) {
      final nome = _norm(l.shortName);
      if (nome == q) return 0;
      if (risolta != null && risolta.routeId == l.routeId) return 1;
      if (nome.startsWith(q)) return 2;
      final lungo = (l.longName ?? '').toLowerCase();
      if (parole.every(lungo.contains)) return 3;
      return null;
    }

    final trovate = <(int, TransitLine)>[
      for (final l in sorted)
        if (punteggio(l) case final p?) (p, l),
    ];
    // A parita' di punteggio l'ordine di GTT. Va scritto: il sort di Dart
    // non e' stabile, e l'ordine di partenza non si conserva da solo.
    trovate.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : TransitLine.compare(a.$2, b.$2);
    });
    return [for (final t in trovate) t.$2];
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}
