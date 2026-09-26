import '../deviation_service.dart';
import '../geo/polyline.dart';
import '../geo/projection.dart';
import '../models/notice.dart';
import '../models/transit.dart';
import '../pipeline/stop_impact.dart';

/// Il formato dei file che il job su GitHub pubblica e che l'app legge.
///
/// E' il contratto fra le due parti, e sta qui — in `core/`, Dart puro —
/// perche' lo scrive un programma a riga di comando e lo legge l'app: lo
/// stesso codice, provato una volta sola.
///
/// Tre file:
///
/// - `indice.json`: tutte le linee di GTT, per cercarle, e quando e' stato
///   fatto il giro. Piccolo, si scarica sempre.
/// - `percorsi/<linea>.json`: percorsi e fermate di una linea. Cambia solo
///   quando GTT pubblica orari nuovi. Prende il posto dei 24 MB di GTFS
///   che ogni telefono scaricava per usarne poche centinaia di KB.
/// - `stato/<linea>.json`: gli avvisi della linea e cosa comportano. Si
///   riscrive solo quando cambia qualcosa.
///
/// Le date si scrivono in UTC con la «Z» e si rileggono in ora locale: il
/// job gira su un server che non sta a Torino.
class FormatoPubblicato {
  const FormatoPubblicato._();

  /// Cambia solo se il formato cambia in modo che le app vecchie non
  /// capirebbero. Sta anche nel percorso (`v1/`): una versione nuova si
  /// pubblica accanto, e le app installate continuano a leggere la loro.
  static const versione = 1;

  /// Le polilinee a sei decimali: circa 10 cm, e il 40% in meno di spazio
  /// rispetto alle coordinate scritte per esteso.
  static const _precisione = 6;

  // ---------------------------------------------------------------- indice

  static Map<String, Object?> indice({
    required String? feed,
    required DateTime generato,
    required List<TransitLine> linee,
    required String fonte,
  }) =>
      {
        'versione': versione,
        'generato': _data(generato),
        'feed': feed,
        'fonte': fonte,
        'linee': [for (final l in linee) _linea(l)],
      };

  static ({String? feed, DateTime generato, List<TransitLine> linee})
      leggiIndice(Map<String, dynamic> j) => (
            feed: j['feed'] as String?,
            generato: _leggiData(j['generato']) ?? DateTime.now(),
            linee: [
              for (final l in (j['linee'] as List).cast<Map<String, dynamic>>())
                _leggiLinea(l),
            ]..sort(TransitLine.compare),
          );

  // -------------------------------------------------------------- percorsi

  static Map<String, Object?> percorsi(
    TransitLine linea,
    List<RouteShape> shapes, {
    required String? feed,
  }) {
    final fermate = <String, TransitStop>{
      for (final s in shapes)
        for (final f in s.stops) f.id: f,
    };
    return {
      'versione': versione,
      'feed': feed,
      'linea': _linea(linea),
      'percorsi': [
        for (final s in shapes)
          {
            'id': s.shapeId,
            'dir': s.directionId,
            'capolinea': s.headsign,
            'corse': s.tripCount,
            'punti': PolylineCodec.encode(s.points, precision: _precisione),
            'fermate': [for (final f in s.stops) f.id],
          },
      ],
      'fermate': {for (final f in fermate.values) f.id: _fermata(f)},
    };
  }

  static ({TransitLine linea, List<RouteShape> shapes, String? feed})
      leggiPercorsi(Map<String, dynamic> j) {
    final linea = _leggiLinea(j['linea'] as Map<String, dynamic>);
    final fermate = _leggiFermate(j['fermate']);
    return (
      linea: linea,
      feed: j['feed'] as String?,
      shapes: [
        for (final s in (j['percorsi'] as List).cast<Map<String, dynamic>>())
          RouteShape(
            shapeId: s['id'] as String,
            routeId: linea.routeId,
            directionId: s['dir'] as int,
            headsign: s['capolinea'] as String? ?? '',
            tripCount: s['corse'] as int? ?? 0,
            points: PolylineCodec.decode(s['punti'] as String,
                precision: _precisione),
            stops: [
              for (final id in (s['fermate'] as List).cast<String>())
                ?fermate[id],
            ],
          ),
      ],
    );
  }

  // ----------------------------------------------------------------- stato

  /// Lo stato di una linea. Le fermate citate — quelle saltate e quelle
  /// proposte al loro posto, che possono essere di altre linee — viaggiano
  /// dentro il file: l'app non ha l'elenco di tutte le fermate di Torino.
  ///
  /// Nessuna data del giro qui dentro: cambierebbe a ogni giro, e il file
  /// si riscriverebbe anche quando non e' cambiato niente. Quando e' stato
  /// fatto il giro lo dice l'indice.
  static Map<String, Object?> stato(LineStatus s) {
    final fermate = <String, TransitStop>{};
    for (final r in s.reports) {
      for (final i in r.impact?.impacts ?? const <StopImpact>[]) {
        fermate[i.stop.id] = i.stop;
        for (final a in i.alternatives) {
          fermate[a.stop.id] = a.stop;
        }
      }
    }
    return {
      'versione': versione,
      'linea': s.line.routeId,
      'avvisi': [for (final r in s.reports) _rapporto(r)],
      'fermate': {for (final f in fermate.values) f.id: _fermata(f)},
    };
  }

  /// Rilegge uno stato. [index] deve avere i percorsi della linea; le
  /// fermate si cercano prima nel file, poi nell'indice.
  ///
  /// Un avviso agganciato a un percorso che non c'e' piu' si scarta:
  /// mostrarlo sul percorso sbagliato darebbe fermate sbagliate.
  static LineStatus? leggiStato(
    Map<String, dynamic> j,
    GtfsIndex index, {
    required DateTime controllata,
  }) {
    final line = index.lines[j['linea']];
    if (line == null) return null;
    final andata = index.mainShape(line.routeId, 0);
    final ritorno = index.mainShape(line.routeId, 1);
    final shape = andata ?? ritorno;
    if (shape == null) return null;

    final nelFile = _leggiFermate(j['fermate']);
    TransitStop? fermata(String id) => nelFile[id] ?? index.stops[id];
    final percorsi = {for (final s in index.shapesOf(line.routeId)) s.shapeId: s};

    return LineStatus(
      line: line,
      shape: shape,
      shapeReturn: identical(shape, andata) ? ritorno : null,
      allShapes: index.shapesOf(line.routeId),
      checkedAt: controllata,
      reports: [
        for (final r in (j['avvisi'] as List).cast<Map<String, dynamic>>())
          ?_leggiRapporto(r, percorsi, fermata),
      ],
    );
  }

  // ---------------------------------------------------------- dettagli

  static Map<String, Object?> _linea(TransitLine l) => {
        'id': l.routeId,
        'nome': l.shortName,
        if (l.longName != null) 'lungo': l.longName,
        if (l.color != null) 'colore': l.color,
        if (l.routeType != null) 'tipo': l.routeType,
        if (l.sortOrder != null) 'ordine': l.sortOrder,
      };

  static TransitLine _leggiLinea(Map<String, dynamic> j) => TransitLine(
        routeId: j['id'] as String,
        shortName: j['nome'] as String,
        longName: j['lungo'] as String?,
        color: j['colore'] as String?,
        routeType: j['tipo'] as int?,
        sortOrder: j['ordine'] as int?,
      );

  static Map<String, Object?> _fermata(TransitStop f) => {
        if (f.code != null) 'c': f.code,
        'n': f.name,
        // Sei decimali sono 10 cm: di piu' e' rumore, e pesa.
        'p': [_arrotonda(f.position.lat), _arrotonda(f.position.lon)],
      };

  static Map<String, TransitStop> _leggiFermate(Object? j) {
    if (j is! Map) return const {};
    return {
      for (final e in j.entries)
        e.key as String: TransitStop(
          id: e.key as String,
          code: (e.value as Map)['c'] as String?,
          name: (e.value as Map)['n'] as String? ?? '',
          position: GeoPoint(
            (((e.value as Map)['p'] as List)[0] as num).toDouble(),
            (((e.value as Map)['p'] as List)[1] as num).toDouble(),
          ),
        ),
    };
  }

  static double _arrotonda(double x) => (x * 1e6).round() / 1e6;

  static Map<String, Object?> _rapporto(DeviationReport r) => {
        'percorso': r.shape.shapeId,
        'affidabilita': r.confidence.name,
        if (r.whyIncomplete != null) 'perche': r.whyIncomplete,
        if (r.retryable) 'ritentare': true,
        'avviso': _avviso(r.notice),
        if (r.deviatedGeometry != null)
          'geometria': PolylineCodec.encode(r.deviatedGeometry!,
              precision: _precisione),
        if (r.impact != null) 'impatto': _impatto(r.impact!),
      };

  static DeviationReport? _leggiRapporto(
    Map<String, dynamic> j,
    Map<String, RouteShape> percorsi,
    TransitStop? Function(String) fermata,
  ) {
    final shape = percorsi[j['percorso']];
    if (shape == null) return null;
    final avviso = _leggiAvviso(j['avviso'] as Map<String, dynamic>);
    if (avviso == null) return null;
    return DeviationReport(
      notice: avviso,
      shape: shape,
      confidence: Confidence.values
              .where((c) => c.name == j['affidabilita'])
              .firstOrNull ??
          Confidence.soloTesto,
      whyIncomplete: j['perche'] as String?,
      retryable: j['ritentare'] as bool? ?? false,
      deviatedGeometry: j['geometria'] == null
          ? null
          : PolylineCodec.decode(j['geometria'] as String,
              precision: _precisione),
      impact: j['impatto'] == null
          ? null
          : _leggiImpatto(j['impatto'] as Map<String, dynamic>, fermata),
    );
  }

  static Map<String, Object?> _impatto(StopImpactResult i) => {
        'da': i.affectedFromMeters.round(),
        'a': i.affectedToMeters.round(),
        'fermate': [
          for (final s in i.impacts)
            {
              'id': s.stop.id,
              'stato': s.status.name,
              if (s.metersFromDeviatedRoute != null)
                'm': s.metersFromDeviatedRoute!.round(),
              if (s.alternatives.isNotEmpty)
                'alt': [
                  for (final a in s.alternatives)
                    {
                      'id': a.stop.id,
                      'm': a.straightMeters.round(),
                      if (a.walkingMeters != null)
                        'piedi': a.walkingMeters!.round(),
                      if (a.sameLine) 'stessa': true,
                    },
                ],
            },
        ],
      };

  static StopImpactResult _leggiImpatto(
    Map<String, dynamic> j,
    TransitStop? Function(String) fermata,
  ) {
    final impatti = <StopImpact>[];
    for (final s in (j['fermate'] as List).cast<Map<String, dynamic>>()) {
      final stop = fermata(s['id'] as String);
      if (stop == null) continue;
      impatti.add(StopImpact(
        stop: stop,
        status: StopStatus.values
                .where((x) => x.name == s['stato'])
                .firstOrNull ??
            StopStatus.skipped,
        metersFromDeviatedRoute: (s['m'] as num?)?.toDouble(),
        alternatives: [
          for (final a
              in (s['alt'] as List? ?? const []).cast<Map<String, dynamic>>())
            if (fermata(a['id'] as String) case final alt?)
              StopAlternative(
                stop: alt,
                straightMeters: (a['m'] as num).toDouble(),
                walkingMeters: (a['piedi'] as num?)?.toDouble(),
                sameLine: a['stessa'] as bool? ?? false,
              ),
        ],
      ));
    }
    return StopImpactResult(
      impacts: impatti,
      affectedFromMeters: (j['da'] as num?)?.toDouble() ?? 0,
      affectedToMeters: (j['a'] as num?)?.toDouble() ?? 0,
    );
  }

  static Map<String, Object?> _avviso(RawNotice n, {bool annidato = false}) => {
        'id': n.id,
        'fonte': n.source.name,
        if (n.headline != null) 'titolo': n.headline,
        'testo': n.text,
        if (n.routeIds.isNotEmpty) 'linee': n.routeIds,
        if (n.lineHints.isNotEmpty) 'nomi': n.lineHints,
        if (n.directionHint != null) 'direzione': n.directionHint,
        if (n.reason != null) 'motivo': n.reason,
        if (n.effect != null) 'effetto': n.effect,
        if (n.validFrom != null) 'dal': _data(n.validFrom!),
        if (n.validUntil != null) 'al': _data(n.validUntil!),
        'url': n.sourceUrl,
        // Un livello solo: gli avvisi uniti sono due, e i loro sono vuoti.
        if (!annidato && n.mergedFrom.isNotEmpty)
          'uniti': [for (final m in n.mergedFrom) _avviso(m, annidato: true)],
      };

  static RawNotice? _leggiAvviso(Map<String, dynamic> j) {
    final fonte =
        NoticeSource.values.where((s) => s.name == j['fonte']).firstOrNull;
    if (fonte == null) return null;
    return RawNotice(
      id: j['id'] as String? ?? '',
      source: fonte,
      headline: j['titolo'] as String?,
      text: j['testo'] as String? ?? '',
      routeIds: (j['linee'] as List?)?.cast<String>() ?? const [],
      lineHints: (j['nomi'] as List?)?.cast<String>() ?? const [],
      directionHint: j['direzione'] as String?,
      reason: j['motivo'] as String?,
      effect: j['effetto'] as String?,
      validFrom: _leggiData(j['dal']),
      validUntil: _leggiData(j['al']),
      sourceUrl: j['url'] as String? ?? '',
      mergedFrom: [
        for (final m
            in (j['uniti'] as List? ?? const []).cast<Map<String, dynamic>>())
          ?_leggiAvviso(m),
      ],
    );
  }

  /// Il nome del file di una linea. Gli id di GTT sono alfanumerici
  /// («10NU», «5BU»), ma un carattere strano non deve poter uscire dalla
  /// cartella.
  static String nomeFile(String routeId) =>
      '${routeId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json';

  static String _data(DateTime d) => d.toUtc().toIso8601String();

  static DateTime? _leggiData(Object? s) =>
      s is String ? DateTime.tryParse(s)?.toLocal() : null;
}
