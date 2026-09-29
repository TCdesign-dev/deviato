import 'dart:collection';
import 'dart:math' as math;

import '../geo/geometry.dart';
import '../geo/projection.dart';

/// Il cammino fra due punti restando su certe vie: quelle nominate
/// dall'avviso, o i binari per un tram.
///
/// Il calcolo del percorso per autobus (Valhalla) fra due svolte sceglie la
/// strada che gli sembra migliore, e non e' detto che sia quella scritta:
/// per la 9, fra piazza Statuto e corso Tassoni, prendeva corso Francia
/// invece di via Cibrario. E non conosce i binari. Qui invece si cammina
/// solo sui tratti dati: se l'avviso dice via Cibrario, si va per via
/// Cibrario.
///
/// I tratti sono i «way» di OpenStreetMap: due tratti si toccano quando
/// hanno un vertice in comune, e i vertici in comune in OpenStreetMap
/// hanno le stesse coordinate.
class LungoLeVie {
  LungoLeVie(List<List<GeoPoint>> tratti, {this.svoltaMassima}) {
    for (final t in tratti) {
      for (var i = 0; i < t.length - 1; i++) {
        _arco(_nodo(t[i]), _nodo(t[i + 1]));
      }
    }
    if (svoltaMassima == null) _passaggi();
  }

  /// Di quanti gradi al massimo si puo' girare in un nodo. null per le
  /// vie, dove a un incrocio si gira dove si vuole; per i binari no: dove
  /// due binari si incrociano in OpenStreetMap c'e' un nodo in comune, ma
  /// un tram li' tira dritto. Le curve vere sono disegnate a piccoli passi.
  final double? svoltaMassima;

  final _chiavi = <String, int>{};
  final _punti = <Point>[];
  final _vicini = <int, Map<int, double>>{};

  /// Oltre questa distanza dai tratti un punto non ci si aggancia.
  static const aggancio = 40.0;

  /// Un punto agganciato a meno di cosi' da un nodo sta sul nodo: da li'
  /// si parte in qualunque verso.
  static const _sulNodo = 2.0;

  bool get vuoto => _punti.isEmpty;

  int _nodo(GeoPoint p) {
    // Sette decimali sono un centimetro: i vertici in comune coincidono.
    final k = '${p.lat.toStringAsFixed(7)},${p.lon.toStringAsFixed(7)}';
    return _chiavi.putIfAbsent(k, () {
      _punti.add(p.meters);
      return _punti.length - 1;
    });
  }

  void _arco(int a, int b, [double peso = 1]) {
    if (a == b) return;
    final d = _punti[a].distanceTo(_punti[b]) * peso;
    (_vicini[a] ??= {})[b] = d;
    (_vicini[b] ??= {})[a] = d;
  }

  /// Fra le carreggiate di un corso. In OpenStreetMap corso Regina
  /// Margherita sono 275 tratti — viale centrale e controviali, a senso
  /// unico — che si toccano solo ogni tanto: due punti sulla stessa via
  /// finivano su carreggiate diverse, e il cammino fra loro faceva 2,8 km
  /// invece di 330 m (la 68, il 29/09). Qui due vertici a meno di
  /// [passaggio] metri si collegano, a un costo maggiorato: si passa da una
  /// carreggiata all'altra solo quando serve.
  void _passaggi() {
    final celle = <(int, int), List<int>>{};
    (int, int) cella(Point p) =>
        ((p.x / passaggio).floor(), (p.y / passaggio).floor());
    for (var i = 0; i < _punti.length; i++) {
      (celle[cella(_punti[i])] ??= []).add(i);
    }
    for (var i = 0; i < _punti.length; i++) {
      final (cx, cy) = cella(_punti[i]);
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          for (final j in celle[(cx + dx, cy + dy)] ?? const <int>[]) {
            if (j <= i || (_vicini[i]?.containsKey(j) ?? false)) continue;
            if (_punti[i].distanceTo(_punti[j]) <= passaggio) {
              _arco(i, j, 3);
            }
          }
        }
      }
    }
  }

  /// Fin dove si passa da una carreggiata all'altra.
  static const passaggio = 25.0;

  /// Il cammino da [da] ad [a] sui tratti, con i due estremi agganciati al
  /// tratto piu' vicino. null se uno dei due e' lontano dai tratti, o se i
  /// tratti fra loro non si toccano.
  List<GeoPoint>? cammino(GeoPoint da, GeoPoint a) {
    final s = _aggancia(da.meters);
    final t = _aggancia(a.meters);
    if (s == null || t == null) return null;
    // Stesso segmento: il tratto dritto fra i due punti.
    if (s.segmento == t.segmento) return [_gradi(s.punto), _gradi(t.punto)];

    // Dijkstra sugli stati (da quale nodo, su quale nodo): per i binari
    // conta da dove si arriva. -1 vuol dire «da nessuna parte», e da li'
    // si va in ogni verso.
    final dist = <(int, int), double>{};
    final prima = <(int, int), (int, int)>{};
    final coda = SplayTreeSet<(double, int, int)>((x, y) {
      var c = x.$1.compareTo(y.$1);
      if (c == 0) c = x.$2.compareTo(y.$2);
      return c != 0 ? c : x.$3.compareTo(y.$3);
    });
    void metti((int, int) stato, double d, (int, int)? da) {
      if (d >= (dist[stato] ?? double.infinity)) return;
      dist[stato] = d;
      if (da != null) prima[stato] = da;
      coda.add((d, stato.$1, stato.$2));
    }

    // Dal punto verso un capo del segmento si va nel verso dell'altro capo
    // verso questo.
    final (s1, s2) = s.segmento;
    for (final (n, altro) in [(s1, s2), (s2, s1)]) {
      final d = s.punto.distanceTo(_punti[n]);
      metti((d < _sulNodo ? -1 : altro, n), d, null);
    }

    final (t1, t2) = t.segmento;
    (int, int)? migliore;
    var totale = double.infinity;
    while (coda.isNotEmpty) {
      final (d, p, n) = coda.first;
      coda.remove(coda.first);
      if (d > (dist[(p, n)] ?? double.infinity)) continue;
      if (d >= totale) break;
      // Arrivati a un capo del segmento d'arrivo: l'ultimo pezzo va verso
      // l'altro capo, e anche li' si guarda la svolta.
      for (final (c, altro) in [(t1, t2), (t2, t1)]) {
        if (n != c) continue;
        final fine = t.punto.distanceTo(_punti[c]);
        if (fine >= _sulNodo && !_gira(p, c, altro)) continue;
        if (d + fine < totale) {
          totale = d + fine;
          migliore = (p, n);
        }
      }
      for (final e in (_vicini[n] ?? const <int, double>{}).entries) {
        if (e.key == p || !_gira(p, n, e.key)) continue;
        metti((n, e.key), d + e.value, (p, n));
      }
    }
    final m = migliore;
    if (m == null) return null;
    final nodi = <int>[m.$2];
    for (var x = prima[m]; x != null; x = prima[x]) {
      nodi.add(x.$2);
    }
    return [
      _gradi(s.punto),
      for (final n in nodi.reversed) _gradi(_punti[n]),
      _gradi(t.punto),
    ];
  }

  /// Da [da] a [su] e poi verso [verso]: la svolta e' consentita?
  bool _gira(int da, int su, int verso) {
    final massima = svoltaMassima;
    if (massima == null || da < 0) return true;
    final a = _punti[da], b = _punti[su], c = _punti[verso];
    final ux = b.x - a.x, uy = b.y - a.y;
    final vx = c.x - b.x, vy = c.y - b.y;
    final lu = math.sqrt(ux * ux + uy * uy);
    final lv = math.sqrt(vx * vx + vy * vy);
    if (lu == 0 || lv == 0) return true;
    final coseno = ((ux * vx + uy * vy) / (lu * lv)).clamp(-1.0, 1.0);
    return math.acos(coseno) * 180 / math.pi <= massima;
  }

  ({Point punto, (int, int) segmento})? _aggancia(Point p) {
    ({Point punto, (int, int) segmento})? meglio;
    var minimo = aggancio;
    for (final e in _vicini.entries) {
      for (final b in e.value.keys) {
        if (b < e.key) continue;
        final q = _proietta(p, _punti[e.key], _punti[b]);
        final d = p.distanceTo(q);
        if (d <= minimo) {
          minimo = d;
          meglio = (punto: q, segmento: (e.key, b));
        }
      }
    }
    return meglio;
  }

  static Point _proietta(Point p, Point a, Point b) {
    final dx = b.x - a.x, dy = b.y - a.y;
    final l2 = dx * dx + dy * dy;
    if (l2 == 0) return a;
    final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0);
    return Point(a.x + t * dx, a.y + t * dy);
  }

  static GeoPoint _gradi(Point p) {
    final (lat, lon) = Projection.toDegrees(p);
    return GeoPoint(lat, lon);
  }

  /// La lunghezza di un cammino, in metri.
  static double lunghezza(List<GeoPoint> c) =>
      Geometry.length([for (final p in c) p.meters]);
}
