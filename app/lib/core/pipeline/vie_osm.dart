import 'dart:convert';

import '../config.dart';
import '../geo/geometry.dart';
import '../geo/projection.dart';
import '../models/transit.dart';
import '../net/gtt_http.dart';
import 'geocoder.dart';

/// Le vie intere di un avviso, prese da OpenStreetMap con Overpass.
///
/// Photon da' un punto per nome, e per una via lunga il punto cade dove
/// capita: corso Re Umberto finiva 2 km a sud, e il percorso calcolato ci
/// andava e tornava (la S4, 7,7 km per un giro di 1,5). Con la forma
/// intera delle vie si possono cercare gli incroci fra una via e la
/// successiva, che sono le svolte del bus.
///
/// Una richiesta per avviso e direzione, limitata a un riquadro attorno
/// alla linea: le vie omonime di altri quartieri restano fuori.
class ViePerNome {
  ViePerNome({GttHttp? http, this.pausa = const Duration(seconds: 5)})
    : _http = http ?? GttHttp();

  /// Quanto aspettare prima di provare il server di riserva.
  final Duration pausa;

  final GttHttp _http;
  final Map<String, Map<String, List<List<GeoPoint>>>> _gia = {};

  /// Overpass non ha risposto, da nessuno dei due server: per il resto di
  /// questo giro non si chiama piu'. Ogni tentativo puo' costare due
  /// minuti, e il job deve pubblicare; gli avvisi restano da rifare.
  bool _giu = false;

  /// Per ogni nome di [nomi], i tratti di via con quel nome: vuoto se
  /// OpenStreetMap non ce l'ha. Si cerca attorno ad [attorno] (i punti
  /// dell'avviso gia' trovati), o se non ce ne sono attorno a [vicino].
  /// Lancia [GttHttpException] se Overpass non risponde.
  Future<Map<String, List<List<GeoPoint>>>> cerca(
    List<String> nomi,
    RouteShape vicino, {
    List<GeoPoint> attorno = const [],
  }) async {
    final unici = nomi.toSet().toList();
    final chiave = '${vicino.shapeId}|${unici.join('|')}';
    final gia = _gia[chiave];
    if (gia != null) return gia;

    final parti = {
      for (final n in unici)
        if (_perRegex(scomponi(n).resto) case final r when r.length >= 3) r,
    };
    if (parti.isEmpty) return {for (final n in unici) n: const []};
    // Il riquadro della linea intera, per una linea che attraversa la
    // citta' come la S4, fa scadere Overpass (504 il 28/09): basta la
    // zona dell'avviso.
    final zona = _zona(attorno);
    final b = zona.isNotEmpty
        ? Geometry.boundsOf(zona, paddingMeters: GttConfig.vieOsmMargineMetri)
        : vicino.boundsWithPadding(GttConfig.vieOsmMargineMetri);
    final risposta = await _chiedi(
      '[out:json][timeout:25];'
      'way["highway"]["name"~"${parti.join('|')}",i]'
      '(${b.minLat},${b.minLon},${b.maxLat},${b.maxLon});'
      'out tags geom;',
    );
    final out = abbina(unici, leggi(risposta));
    _gia[chiave] = out;
    return out;
  }

  /// Una richiesta a Overpass, col server di riserva. Se nessuno dei due
  /// risponde, per il resto del giro non si richiama.
  Future<String> _chiedi(String query) async {
    if (_giu) {
      throw GttHttpException(
        GttConfig.overpassUrl,
        null,
        'Overpass non ha risposto prima, in questo giro',
      );
    }
    String url(String server) =>
        Uri.parse(server).replace(queryParameters: {'data': query}).toString();
    // Il principale, la riserva, di nuovo il principale: il 29/09 il
    // principale alternava 504 e risposte in mezzo secondo, e la riserva
    // ci metteva 14 s quando rispondeva.
    const server = [
      GttConfig.overpassUrl,
      GttConfig.overpassRiserva,
      GttConfig.overpassUrl,
    ];
    for (var i = 0; ; i++) {
      try {
        return await _http.getTextPolite(
          url(server[i]),
          timeout: GttConfig.overpassTimeout,
        );
      } on GttHttpException catch (e) {
        // Troppo carico (429), tempo scaduto (504) o rete: si riprova
        // dopo una pausa. Una richiesta sbagliata (400) no.
        if (e.statusCode == 400) rethrow;
        if (i == server.length - 1) {
          _giu = true;
          rethrow;
        }
        await Future<void>.delayed(pausa);
      }
    }
  }

  /// I punti di [attorno] vicini fra loro: uno finito lontano (un corso
  /// lungo, la via omonima di un altro quartiere) allargherebbe il
  /// riquadro a mezza citta'.
  static List<GeoPoint> _zona(List<GeoPoint> attorno) {
    if (attorno.length < 3) return attorno;
    final c = Geometry.centroid(attorno).meters;
    final vicini = [
      for (final p in attorno)
        if (p.meters.distanceTo(c) <= _raggioZona) p,
    ];
    return vicini.isEmpty ? attorno : vicini;
  }

  static const _raggioZona = 3000.0;

  /// I binari del tram attorno ad [attorno] (o a [vicino]): la rete su cui
  /// un tram deviato puo' davvero passare. In OpenStreetMap la rete di
  /// Torino c'e' tutta, anche i raccordi fuori servizio.
  Future<List<List<GeoPoint>>> binari(
    RouteShape vicino, {
    List<GeoPoint> attorno = const [],
  }) async {
    final zona = _zona(attorno);
    final b = zona.isNotEmpty
        ? Geometry.boundsOf(zona, paddingMeters: GttConfig.vieOsmMargineMetri)
        : vicino.boundsWithPadding(GttConfig.vieOsmMargineMetri);
    final chiave =
        'binari|${b.minLat.toStringAsFixed(3)},'
        '${b.minLon.toStringAsFixed(3)},${b.maxLat.toStringAsFixed(3)},'
        '${b.maxLon.toStringAsFixed(3)}';
    final gia = _gia[chiave];
    if (gia != null) return gia['binari'] ?? const [];
    final vie = leggi(
      await _chiedi(
        '[out:json][timeout:25];'
        'way["railway"="tram"]'
        '(${b.minLat},${b.minLon},${b.maxLat},${b.maxLon});'
        'out geom;',
      ),
      conNome: false,
    );
    final out = [
      for (final v in vie)
        if (v.punti.length >= 2) v.punti,
    ];
    _gia[chiave] = {'binari': out};
    return out;
  }

  /// Le vie della risposta di Overpass: nome e punti. Con [conNome] falso
  /// valgono anche quelle senza nome (i binari).
  static List<({String nome, List<GeoPoint> punti})> leggi(
    String json, {
    bool conNome = true,
  }) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return [
      for (final e
          in (j['elements'] as List? ?? const []).cast<Map<String, dynamic>>())
        if ((e['tags'] as Map?)?['name'] as String? ?? (conNome ? null : '')
            case final String nome)
          (
            nome: nome,
            punti: [
              for (final p
                  in (e['geometry'] as List? ?? const [])
                      .cast<Map<String, dynamic>>())
                GeoPoint(
                  (p['lat'] as num).toDouble(),
                  (p['lon'] as num).toDouble(),
                ),
            ],
          ),
    ];
  }

  /// Quali [vie] corrispondono a ogni nome scritto da GTT.
  ///
  /// Conta il nome senza il tipo («Vinzaglio»), e fra quelle col nome
  /// giusto si preferiscono quelle col tipo giusto: «corso Roma» non e'
  /// «via Roma». Se nessuna ha il tipo, valgono tutte: in OpenStreetMap le
  /// strade attorno a piazza XVIII Dicembre si chiamano «XVIII Dicembre».
  static Map<String, List<List<GeoPoint>>> abbina(
    List<String> nomi,
    List<({String nome, List<GeoPoint> punti})> vie,
  ) {
    final scomposte = [for (final v in vie) (via: v, nome: scomponi(v.nome))];
    return {
      for (final n in nomi)
        n: () {
          final cercato = scomponi(n);
          if (cercato.resto.isEmpty) return const <List<GeoPoint>>[];
          final stesse = [
            for (final s in scomposte)
              if (s.nome.resto == cercato.resto) s,
          ];
          // «via Cibrario» in OpenStreetMap e' «Via Luigi Cibrario», e
          // corso Tassoni e' quasi tutto «Corso Alessandro Tassoni»:
          // valgono anche i nomi che finiscono con quello di GTT, col nome
          // proprio davanti. Non quelli che continuano dopo: «via Roma» non
          // e' «via Roma Nuova».
          final simili = [
            ...stesse,
            for (final s in scomposte)
              if (s.nome.resto.endsWith(' ${cercato.resto}')) s,
          ];
          final stessoTipo = [
            for (final s in simili)
              if (s.nome.tipo == cercato.tipo) s,
          ];
          final scelte = stessoTipo.isNotEmpty ? stessoTipo : simili;
          return [
            for (final s in scelte)
              if (s.via.punti.length >= 2) s.via.punti,
          ];
        }(),
    };
  }

  /// Tipo e nome di una via, scritti allo stesso modo: «Corso Massimo
  /// D’Azeglio» e «corso Massimo d'Azeglio» danno lo stesso resto. Le
  /// parentesi di GTT («(SP 186)», «(carreggiata centrale)») si tolgono.
  ///
  /// I numeri si scrivono in cifre: GTT scrive «via XX Settembre» e
  /// OpenStreetMap «Via Venti Settembre», e «I Maggio» e' «Primo Maggio».
  static ({String? tipo, String resto}) scomponi(String nome) {
    final parole = Geocoder.normalizeToponym(nome)
        .toLowerCase()
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .split(' ');
    if (parole.isEmpty || parole.first.isEmpty) return (tipo: null, resto: '');
    final tipo = _tipi.contains(parole.first) ? parole.first : null;
    return (
      tipo: tipo,
      resto: [
        for (final p in tipo == null ? parole : parole.skip(1)) _inCifre(p),
      ].join(' '),
    );
  }

  /// Un numero romano (fino a XXXIX) o scritto in lettere, in cifre. Le
  /// altre parole restano com'erano.
  static String _inCifre(String parola) {
    final n = _numeri[parola] ?? _romano(parola);
    return n == null ? parola : '$n';
  }

  static int? _romano(String w) {
    if (!RegExp(r'^[ivx]+$').hasMatch(w)) return null;
    const valori = {'i': 1, 'v': 5, 'x': 10};
    var totale = 0;
    for (var i = 0; i < w.length; i++) {
      final v = valori[w[i]]!;
      final dopo = i + 1 < w.length ? valori[w[i + 1]]! : 0;
      totale += v < dopo ? -v : v;
    }
    // Solo i romani scritti bene: «iiii» o «vx» sono parole, non numeri.
    return _inRomano(totale) == w ? totale : null;
  }

  static String _inRomano(int n) {
    const simboli = [(10, 'x'), (9, 'ix'), (5, 'v'), (4, 'iv'), (1, 'i')];
    final b = StringBuffer();
    var r = n;
    for (final (v, s) in simboli) {
      while (r >= v) {
        b.write(s);
        r -= v;
      }
    }
    return b.toString();
  }

  static const _numeri = {
    'uno': 1,
    'primo': 1,
    'due': 2,
    'tre': 3,
    'quattro': 4,
    'cinque': 5,
    'sei': 6,
    'sette': 7,
    'otto': 8,
    'nove': 9,
    'dieci': 10,
    'undici': 11,
    'dodici': 12,
    'tredici': 13,
    'quattordici': 14,
    'quindici': 15,
    'sedici': 16,
    'diciassette': 17,
    'diciotto': 18,
    'diciannove': 19,
    'venti': 20,
    'ventuno': 21,
    'ventidue': 22,
    'ventitre': 23,
    'ventitré': 23,
    'ventiquattro': 24,
    'venticinque': 25,
    'ventisei': 26,
    'ventisette': 27,
    'ventotto': 28,
    'ventinove': 29,
    'trenta': 30,
    'trentuno': 31,
  };

  static const _tipi = {
    'via',
    'viale',
    'corso',
    'piazza',
    'piazzale',
    'piazzetta',
    'largo',
    'strada',
    'stradale',
    'rondò',
    'rondo',
    'lungo',
    'lungodora',
    'lungopo',
    'ponte',
    'vicolo',
    'galleria',
    'sottopasso',
    'cavalcavia',
    'traversa',
    'passaggio',
    'regione',
    'borgata',
    'frazione',
  };

  /// Il nome dentro l'espressione regolare di Overpass: senza
  /// maiuscole, coi caratteri speciali protetti, gli apostrofi di
  /// qualunque tipo, e senza i numeri, che OpenStreetMap puo' scrivere in
  /// lettere («Venti Settembre»): il confronto vero lo fa [abbina].
  static String _perRegex(String resto) => [
    for (final p in resto.split(' '))
      if (!RegExp(r'^\d+$').hasMatch(p))
        p
            .replaceAllMapped(
              RegExp(r'[.*+?^${}()|\[\]\\"]'),
              (m) => '\\\\${m[0]}',
            )
            .replaceAll("'", "."),
  ].join('.*');
}
