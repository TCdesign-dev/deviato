// Confronta i due algoritmi dei percorsi deviati sugli avvisi pubblicati.
//
//   cd app && dart run tool/confronta_algoritmi.dart
//   cd app && dart run tool/confronta_algoritmi.dart --letture tool/letture_di_prova.json
//
// Scarica i dati dal sito, e per ogni avviso di cui ha la lettura del
// modello — salvata nel file pubblicato, o in --letture (id avviso -> elenco
// di deviazioni nel formato del modello) — rifa' l'analisi con l'algoritmo 1
// e con il 2, sulla stessa lettura. Nessuna richiesta al modello: usa solo
// Photon e Valhalla, con le pause di cortesia.
//
// Stampa le misure del 28/09/2026 (andare e tornare, inizio e fine lontani
// dalla linea, rosso sopra la linea, verso contrario) per i due algoritmi e
// scrive build/confronto/index.html: la linea normale in blu, il rosso
// dell'1 chiaro e largo, quello del 2 scuro sopra.
//
// Opzioni: --sito (predefinito https://deviato.it/v1), --linee 9U,S04U
// per limitarsi ad alcune linee, --uscita (predefinito build/confronto).
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
import 'package:gtt_deviazioni/core/ricostruzione/rifinitura.dart';
import 'package:gtt_deviazioni/core/ricostruzione/ricostruzione.dart';
import 'package:gtt_deviazioni/core/ricostruzione/ricostruzione_1.dart';
import 'package:gtt_deviazioni/core/ricostruzione/ricostruzione_2.dart';

Future<void> main(List<String> args) async {
  final sito = _arg(args, '--sito') ?? 'https://deviato.it/v1';
  final uscita = Directory(_arg(args, '--uscita') ?? 'build/confronto');
  final soloLinee = _arg(args, '--linee')?.split(',').toSet();
  final fileLetture = _arg(args, '--letture');
  final diProva = <String, List<ParsedDeviation>>{};
  if (fileLetture != null) {
    final j = jsonDecode(File(fileLetture).readAsStringSync()) as Map;
    for (final e in j.entries) {
      if (e.value is! List) continue;
      diProva[e.key as String] = [
        for (final d in (e.value as List).cast<Map<String, dynamic>>())
          ParsedDeviation.fromJson(d),
      ];
    }
  }

  final http = HttpClient()..userAgent = 'DeviaTo-confronto';
  Future<Map<String, dynamic>?> scarica(String percorso) async {
    final req = await http.getUrl(Uri.parse('$sito/$percorso'));
    final res = await req.close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      return null;
    }
    return jsonDecode(await res.transform(utf8.decoder).join())
        as Map<String, dynamic>;
  }

  final indice = FormatoPubblicato.leggiIndice((await scarica('indice.json'))!);
  final geocoder = Geocoder();
  final router = RouteBuilder();
  final righe = <Map<String, Object?>>[];

  for (final linea in indice.linee) {
    if (soloLinee != null && !soloLinee.contains(linea.routeId)) continue;
    final nome = FormatoPubblicato.nomeFile(linea.routeId);
    final stato = await scarica('stato/$nome');
    if (stato == null) continue;
    final avvisi = (stato['avvisi'] as List).cast<Map<String, dynamic>>();
    // Si scarica il resto solo se c'e' qualcosa da confrontare.
    final conLettura = avvisi.any((a) =>
        a['lettura'] != null ||
        diProva.containsKey((a['avviso'] as Map)['id']));
    if (!conLettura) continue;
    final percorsi = await scarica('percorsi/$nome');
    if (percorsi == null) continue;
    final shapes = FormatoPubblicato.leggiPercorsi(percorsi).shapes;
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
    final algoritmi = <int, Ricostruzione>{
      1: Ricostruzione1(geocoder: geocoder, router: router, impact: impatto),
      2: Ricostruzione2(geocoder: geocoder, router: router, impact: impatto),
    };
    final andata = index.mainShape(linea.routeId, 0);
    final ritorno = index.mainShape(linea.routeId, 1);

    final visti = <String>{};
    for (final r in letto.reports) {
      final notice = r.notice;
      if (!visti.add(notice.id)) continue;
      final letture = diProva[notice.id] ??
          (r.letture.isNotEmpty ? r.letture : null);
      if (letture == null) continue;
      final lettura =
          ExtractionResult(status: ExtractionStatus.ok, deviations: letture);
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
          'avviso': notice.id,
          'direzione': shape.headsign,
          'testo': notice.fullText,
          'normale': _coppie(shape.points),
          for (final e in esiti.entries)
            'a${e.key}': _misura(e.value, shape),
        };
        righe.add(riga);
        stdout.writeln(_rigaTabella(riga));
      }
    }
  }
  http.close();

  stdout.writeln();
  stdout.writeln('${righe.length} confronti');
  for (final (nome, prova) in <(String, bool Function(Map<String, Object?>))>[
    ('disegnate', (m) => (m['metri'] as int) > 0),
    ('andare e tornare >= 100 m', (m) => (m['ripercorso'] as int) >= 100),
    ('inizio a oltre 50 m', (m) => (m['inizio'] as int) > 50),
    ('fine a oltre 50 m', (m) => (m['fine'] as int) > 50),
    ('rosso sulla linea >= 300 m in testa',
        (m) => (m['sopraInTesta'] as int) >= 300),
    ('rosso sulla linea >= 300 m in coda',
        (m) => (m['sopraInCoda'] as int) >= 300),
    ('verso contrario', (m) => m['contrario'] == true),
    ('Verificato', (m) => m['affidabilita'] == 'confermata'),
  ]) {
    int conta(String a) => righe
        .where((r) => prova(r[a] as Map<String, Object?>))
        .length;
    stdout.writeln('$nome: algoritmo 1 ${conta('a1')}, algoritmo 2 ${conta('a2')}');
  }

  uscita.createSync(recursive: true);
  File('${uscita.path}/index.html')
      .writeAsStringSync(_pagina.replaceFirst('/*DATI*/', jsonEncode(righe)));
  stdout.writeln('pagina: ${uscita.path}/index.html');
}

/// Le misure di un esito, piu' la geometria per la pagina.
Map<String, Object?> _misura(DeviationReport r, RouteShape shape) {
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
    sopraInTesta = (i * 10).clamp(0, 1 << 30);
    var j = fitto.length - 1;
    while (j >= 0 && sopra(fitto[j])) {
      j--;
    }
    sopraInCoda = ((fitto.length - 1 - j) * 10).clamp(0, 1 << 30);
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
    'nonServite': r.impact?.skipped.length ?? 0,
    'lettura': r.parsed?.toString(),
    'geometria': _coppie(g),
  };
}

String _rigaTabella(Map<String, Object?> r) {
  String m(String a) {
    final x = r[a] as Map<String, Object?>;
    return '${x['affidabilita']} ${x['metri']} m, va e torna ${x['ripercorso']}, '
        'inizio ${x['inizio']}, fine ${x['fine']}, sopra ${x['sopraInTesta']}/'
        '${x['sopraInCoda']}${x['contrario'] == true ? ', AL CONTRARIO' : ''}, '
        '${x['nonServite']} non servite';
  }

  return '${r['linea']} verso ${r['direzione']}\n  1: ${m('a1')}\n  2: ${m('a2')}';
}

List<List<double>> _coppie(List<GeoPoint> g) => [
      for (final p in g)
        [(p.lat * 1e5).round() / 1e5, (p.lon * 1e5).round() / 1e5],
    ];

String? _arg(List<String> args, String nome) {
  final i = args.indexOf(nome);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

const _pagina = r'''<!doctype html>
<html lang="it">
<head>
<meta charset="utf-8">
<title>Confronto algoritmi</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js"></script>
<style>
  body { margin: 0; font: 13px system-ui; display: grid; grid-template-columns: 340px 1fr; height: 100vh; }
  #lista { overflow: auto; border-right: 1px solid #ddd; }
  #lista div { padding: 6px 8px; border-bottom: 1px solid #eee; cursor: pointer; }
  #lista div.sel { background: #fff3b0; }
  .m { color: #555; } .male { color: #b3261e; }
  #destra { display: grid; grid-template-rows: 1fr auto; min-height: 0; }
  #testo { max-height: 28vh; overflow: auto; padding: 8px 12px; border-top: 1px solid #ddd; white-space: pre-wrap; }
</style>
</head>
<body>
<div id="lista"></div>
<div id="destra"><div id="mappa"></div><div id="testo"></div></div>
<script>
const DATI = /*DATI*/;
const mappa = L.map('mappa');
L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {maxZoom: 19, attribution: '© OpenStreetMap'}).addTo(mappa);
const strato = L.layerGroup().addTo(mappa);
function problemi(m) {
  const p = [];
  if (m.contrario) p.push('al contrario');
  if (m.inizio > 50) p.push('inizio a ' + m.inizio + ' m');
  if (m.fine > 50) p.push('fine a ' + m.fine + ' m');
  if (m.ripercorso >= 100) p.push('va e torna ' + m.ripercorso + ' m');
  if (m.sopraInTesta >= 300 || m.sopraInCoda >= 300) p.push('rosso sulla linea');
  return p.join(' · ');
}
function freccette(punti, colore) {
  const g = [];
  for (let i = 1; i < punti.length - 1; i += Math.max(1, Math.floor(punti.length / 10))) {
    const [a, b] = [punti[i], punti[i + 1]];
    const ang = Math.atan2(b[1] - a[1], b[0] - a[0]) * 180 / Math.PI;
    g.push(L.marker(a, {icon: L.divIcon({className: '', html:
      `<div style="transform: rotate(${90 - ang}deg); color:${colore}; font-size:15px; line-height:15px; width:15px; text-align:center">➤</div>`,
      iconSize: [15, 15], iconAnchor: [7, 7]})}));
  }
  return g;
}
DATI.forEach((r, i) => {
  const d = document.createElement('div');
  d.id = 'r' + i;
  d.innerHTML = `<b>${r.linea}</b> verso ${r.direzione}<br>
    <span class="m">1: ${r.a1.affidabilita} · ${(r.a1.metri/1000).toFixed(1)} km</span> <span class="male">${problemi(r.a1)}</span><br>
    <span class="m">2: ${r.a2.affidabilita} · ${(r.a2.metri/1000).toFixed(1)} km</span> <span class="male">${problemi(r.a2)}</span>`;
  d.onclick = () => mostra(r, d);
  document.getElementById('lista').appendChild(d);
});
function mostra(r, el) {
  document.querySelectorAll('#lista .sel').forEach(x => x.classList.remove('sel'));
  el.classList.add('sel');
  history.replaceState(null, '', '#' + el.id);
  strato.clearLayers();
  const blu = L.polyline(r.normale, {color: '#2a5bd7', weight: 5, opacity: .7}).addTo(strato);
  freccette(r.normale, '#2a5bd7').forEach(m => m.addTo(strato));
  if (r.a1.geometria.length > 1) L.polyline(r.a1.geometria, {color: '#ff8a80', weight: 10, opacity: .55}).addTo(strato);
  const g = r.a2.geometria;
  if (g.length > 1) {
    L.polyline(g, {color: '#b71c1c', weight: 4}).addTo(strato);
    freccette(g, '#4a0000').forEach(m => m.addTo(strato));
    L.circleMarker(g[0], {radius: 7, color: '#fff', fillColor: '#0a0', fillOpacity: 1, weight: 2}).addTo(strato);
    L.circleMarker(g[g.length - 1], {radius: 7, color: '#fff', fillColor: '#000', fillOpacity: 1, weight: 2}).addTo(strato);
  }
  const tutti = [...r.a1.geometria, ...g];
  mappa.fitBounds(tutti.length > 1 ? L.polyline(tutti).getBounds().pad(0.3) : blu.getBounds());
  document.getElementById('testo').textContent =
    `1: ${r.a1.affidabilita} — ${r.a1.perche || ''}\n   ${r.a1.lettura || ''}\n` +
    `2: ${r.a2.affidabilita} — ${r.a2.perche || ''}\n   ${r.a2.lettura || ''}\n\n${r.testo}`;
}
const h = document.getElementById(location.hash.slice(1)) || document.getElementById('r0');
if (h) h.click();
</script>
</body>
</html>
''';
