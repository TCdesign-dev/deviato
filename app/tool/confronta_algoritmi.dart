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

import 'src/confronto.dart';

Future<void> main(List<String> args) async {
  final uscita = Directory(_arg(args, '--uscita') ?? 'build/confronto');
  final fileLetture = _arg(args, '--letture');
  final confronto = Confronto(
    sito: _arg(args, '--sito') ?? 'https://deviato.it/v1',
    letture: fileLetture == null ? const {} : Confronto.leggiLetture(fileLetture),
  );
  final righe = await confronto.calcola(
    soloLinee: _arg(args, '--linee')?.split(',').toSet(),
    ogni: (r) => stdout.writeln(_rigaTabella(r)),
  );
  confronto.chiudi();

  stdout.writeln();
  stdout.writeln('${righe.length} confronti');
  for (final (nome, prova) in <(String, bool Function(Map<String, Object?>))>[
    ('disegnate', (m) => (m['metri'] as int) > 0),
    ('andare e tornare >= 100 m', (m) => (m['ripercorso'] as int) >= 100),
    ('inizio a oltre 50 m', (m) => (m['inizio'] as int) > 50),
    ('fine a oltre 50 m', (m) => (m['fine'] as int) > 50),
    (
      'rosso sulla linea >= 300 m in testa',
      (m) => (m['sopraInTesta'] as int) >= 300,
    ),
    (
      'rosso sulla linea >= 300 m in coda',
      (m) => (m['sopraInCoda'] as int) >= 300,
    ),
    ('verso contrario', (m) => m['contrario'] == true),
    ('Verificato', (m) => m['affidabilita'] == 'confermata'),
  ]) {
    int conta(String a) =>
        righe.where((r) => prova(r[a] as Map<String, Object?>)).length;
    stdout.writeln(
      '$nome: algoritmo 1 ${conta('a1')}, algoritmo 2 ${conta('a2')}',
    );
  }

  uscita.createSync(recursive: true);
  File(
    '${uscita.path}/index.html',
  ).writeAsStringSync(_pagina.replaceFirst('/*DATI*/', jsonEncode(righe)));
  stdout.writeln('pagina: ${uscita.path}/index.html');
}

String _rigaTabella(Map<String, Object?> r) {
  String m(String a) {
    final x = r[a] as Map<String, Object?>;
    return '${x['affidabilita']} ${x['metri']} m, va e torna ${x['ripercorso']}, '
        'inizio ${x['inizio']}, fine ${x['fine']}, sopra ${x['sopraInTesta']}/'
        '${x['sopraInCoda']}${x['contrario'] == true ? ', AL CONTRARIO' : ''}, '
        '${(x['nonServite'] as List).length} non servite';
  }

  return '${r['linea']} verso ${r['direzione']}\n  1: ${m('a1')}\n  2: ${m('a2')}';
}

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
