// Il confronto fra i due algoritmi dei percorsi deviati, sugli avvisi
// pubblicati. Lo usano tool/confronta_algoritmi.dart (da riga di comando) e
// tool/banco.dart (il banco di prova coi mezzi).
import 'dart:convert';
import 'dart:io';

import 'package:gtt_deviazioni/core/deviation_service.dart';
import 'package:gtt_deviazioni/core/geo/geometry.dart';
import 'package:gtt_deviazioni/core/geo/projection.dart';
import 'package:gtt_deviazioni/core/io/formato_pubblicato.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/pipeline/extractor.dart';
import 'package:gtt_deviazioni/core/pipeline/geocoder.dart';
import 'package:gtt_deviazioni/core/pipeline/route_builder.dart';
import 'package:gtt_deviazioni/core/pipeline/stop_impact.dart';
import 'package:gtt_deviazioni/core/pipeline/vie_osm.dart';
import 'package:gtt_deviazioni/core/ricostruzione/rifinitura.dart';
import 'package:gtt_deviazioni/core/ricostruzione/ricostruzione.dart';
import 'package:gtt_deviazioni/core/ricostruzione/ricostruzione_1.dart';
import 'package:gtt_deviazioni/core/ricostruzione/ricostruzione_2.dart';

/// Rifa' l'analisi degli avvisi pubblicati con i due algoritmi, sulla
/// stessa lettura del modello: quella salvata nel file, o quella di
/// [letture] (id avviso -> deviazioni). Nessuna richiesta al modello.
class Confronto {
  Confronto({this.sito = 'https://deviato.it/v1', this.letture = const {}});

  final String sito;
  final Map<String, List<ParsedDeviation>> letture;
  final HttpClient _http = HttpClient()..userAgent = 'DeviaTo-confronto';

  /// Le letture di un file come tool/letture_di_prova.json.
  static Map<String, List<ParsedDeviation>> leggiLetture(String percorso) {
    final j = jsonDecode(File(percorso).readAsStringSync()) as Map;
    return {
      for (final e in j.entries)
        if (e.value is List)
          e.key as String: [
            for (final d in (e.value as List).cast<Map<String, dynamic>>())
              ParsedDeviation.fromJson(d),
          ],
    };
  }

  Future<Map<String, dynamic>?> scarica(String percorso) async {
    final req = await _http.getUrl(Uri.parse('$sito/$percorso'));
    final res = await req.close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      return null;
    }
    return jsonDecode(await res.transform(utf8.decoder).join())
        as Map<String, dynamic>;
  }

  /// I percorsi pubblicati di una linea.
  Future<List<RouteShape>> percorsi(String routeId) async {
    final j = await scarica('percorsi/${FormatoPubblicato.nomeFile(routeId)}');
    return j == null ? const [] : FormatoPubblicato.leggiPercorsi(j).shapes;
  }

  /// Un confronto per ogni direzione di ogni avviso con una lettura. [ogni]
  /// riceve ciascuno appena pronto, [avanzamento] quante linee sono state
  /// guardate su quante.
  Future<List<Map<String, Object?>>> calcola({
    Set<String>? soloLinee,
    void Function(Map<String, Object?> riga)? ogni,
    void Function(int fatte, int totale)? avanzamento,
  }) async {
    final indice = FormatoPubblicato.leggiIndice(
      (await scarica('indice.json'))!,
    );
    final linee = [
      for (final l in indice.linee)
        if (soloLinee == null || soloLinee.contains(l.routeId)) l,
    ];
    final geocoder = Geocoder();
    final router = RouteBuilder();
    final righe = <Map<String, Object?>>[];

    for (var n = 0; n < linee.length; n++) {
      avanzamento?.call(n, linee.length);
      final linea = linee[n];
      final nome = FormatoPubblicato.nomeFile(linea.routeId);
      final stato = await scarica('stato/$nome');
      if (stato == null) continue;
      final avvisi = (stato['avvisi'] as List).cast<Map<String, dynamic>>();
      // Si scarica il resto solo se c'e' qualcosa da confrontare.
      if (!avvisi.any((a) =>
          a['lettura'] != null ||
          letture.containsKey((a['avviso'] as Map)['id']))) {
        continue;
      }
      final shapes = await percorsi(linea.routeId);
      if (shapes.isEmpty) continue;
      final index = GtfsIndex(
        feedVersion: indice.feed,
        builtAt: DateTime.now(),
        lines: {linea.routeId: linea},
        shapes: {linea.routeId: shapes},
        stops: {
          for (final s in shapes)
            for (final f in s.stops) f.id: f,
        },
      );
      final letto = FormatoPubblicato.leggiStato(stato, index,
          controllata: DateTime.now());
      if (letto == null) continue;
      final impatto = StopImpactAnalyzer(index: index);
      final andata = index.mainShape(linea.routeId, 0);
      final ritorno = index.mainShape(linea.routeId, 1);

      final visti = <String>{};
      for (final r in letto.reports) {
        final notice = r.notice;
        if (!visti.add(notice.id)) continue;
        final deviazioni =
            letture[notice.id] ?? (r.letture.isNotEmpty ? r.letture : null);
        if (deviazioni == null) continue;
        final lettura = ExtractionResult(
          status: ExtractionStatus.ok,
          deviations: deviazioni,
        );
        // Un collegamento a Overpass per avviso: nel job, se non risponde,
        // si smette di chiamarlo per tutto il giro; qui un errore
        // passeggero spegnerebbe gli incroci per tutti i confronti.
        final algoritmi = <int, Ricostruzione>{
          1: Ricostruzione1(geocoder: geocoder, router: router, impact: impatto),
          2: Ricostruzione2(
            geocoder: geocoder,
            router: router,
            impact: impatto,
            vie: ViePerNome(),
          ),
        };
        final candidate =
            DeviationService.shapesConcernedBy(notice, andata, ritorno);
        // Come nel job: il secondo algoritmo scarta le direzioni che la
        // lettura esclude.
        final perIlSecondo = {
          for (final s in await (algoritmi[2]! as FiltroDirezioni)
              .direzioniDi(notice, candidate, lettura))
            s.shapeId,
        };
        for (final shape in candidate) {
          final esiti = <int, DeviationReport>{};
          for (final e in algoritmi.entries) {
            esiti[e.key] = e.key == 2 && !perIlSecondo.contains(shape.shapeId)
                ? DeviationReport(
                    notice: notice,
                    shape: shape,
                    confidence: Confidence.confermata,
                    whyIncomplete: 'Non riguarda questa direzione: '
                        'il secondo algoritmo non la analizza.',
                  )
                : await e.value.analizza(notice, shape, lettura);
          }
          final riga = <String, Object?>{
            'linea': linea.shortName,
            'id': linea.routeId,
            'percorso': shape.shapeId,
            'dir': shape.directionId,
            'avviso': notice.id,
            'direzione': shape.headsign,
            'testo': notice.fullText,
            'inCorso': !notice.startsAfter(DateTime.now()),
            'normale': coppie(shape.points),
            for (final e in esiti.entries) 'a${e.key}': misura(e.value, shape),
          };
          righe.add(riga);
          ogni?.call(riga);
        }
      }
    }
    avanzamento?.call(linee.length, linee.length);
    return righe;
  }

  /// Le misure di un esito, piu' la geometria da disegnare.
  static Map<String, Object?> misura(DeviationReport r, RouteShape shape) {
    final g = r.deviatedGeometry ?? const <GeoPoint>[];
    final linea = shape.meters;
    var inizio = 0, fine = 0, sopraInTesta = 0, sopraInCoda = 0;
    var contrario = false;
    if (g.length > 1) {
      final a = Geometry.projectOnPolyline(g.first.meters, linea);
      final b = Geometry.projectOnPolyline(g.last.meters, linea);
      inizio = a.distance.round();
      fine = b.distance.round();
      contrario = b.alongMeters < a.alongMeters - Rifinitura.indietroMassimo;
      final fitto = Geometry.densify([for (final p in g) p.meters], 10);
      bool sopra(Point q) =>
          Geometry.pointToPolyline(q, linea) <= Rifinitura.sopraLaLinea;
      var i = 0;
      while (i < fitto.length && sopra(fitto[i])) {
        i++;
      }
      sopraInTesta = i * 10;
      var j = fitto.length - 1;
      while (j >= 0 && sopra(fitto[j])) {
        j--;
      }
      sopraInCoda = (fitto.length - 1 - j) * 10;
    }
    return {
      'affidabilita': r.confidence.name,
      'perche': r.whyIncomplete,
      'metri': g.length > 1
          ? Geometry.length([for (final p in g) p.meters]).round()
          : 0,
      'ripercorso': Rifinitura.ripercorso(g).round(),
      'inizio': inizio,
      'fine': fine,
      'sopraInTesta': sopraInTesta,
      'sopraInCoda': sopraInCoda,
      'contrario': contrario,
      'nonServite': [
        for (final s in r.impact?.skipped ?? const <StopImpact>[])
          s.stop.name,
      ],
      'lettura': r.parsed?.toString(),
      'geometria': coppie(g),
    };
  }

  static List<List<double>> coppie(List<GeoPoint> g) => [
        for (final p in g)
          [(p.lat * 1e5).round() / 1e5, (p.lon * 1e5).round() / 1e5],
      ];

  static List<GeoPoint> punti(Object? coppie) => [
        for (final c in (coppie as List? ?? const []).cast<List>())
          GeoPoint((c[0] as num).toDouble(), (c[1] as num).toDouble()),
      ];

  void chiudi() => _http.close();
}
