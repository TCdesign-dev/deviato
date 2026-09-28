// Il banco di prova dei percorsi deviati: una pagina, solo sul Mac, che
// mette a confronto i due algoritmi e li misura contro i mezzi veri.
//
//   cd app && dart run tool/banco.dart
//   poi http://localhost:8768
//
// Opzioni: --porta (8768), --letture (predefinito tool/letture_di_prova.json
// se c'e'), --sito (https://deviato.it/v1).
//
// Cosa fa:
// - rifa' l'analisi degli avvisi pubblicati con l'algoritmo 1 e col 2,
//   sulla stessa lettura del modello (quella salvata nei file, o quella
//   di --letture), e la tiene in build/banco/confronti.json: la pagina si
//   apre subito, «Ricalcola» la rifa';
// - con «Segui i mezzi» legge ogni 20 s il feed delle posizioni di GTT
//   per quella linea, e dice per ogni algoritmo quanta parte dei punti in
//   cui i mezzi escono dal percorso cade sul suo rosso, e quanta parte del
//   suo rosso e' stata percorsa davvero. Le tracce si salvano in
//   build/banco/mezzi/: sono la verita' con cui misurare gli algoritmi.
//
// Non tocca l'app, non tocca il job, non fa richieste al modello.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gtt_deviazioni/core/sources/vehicles_source.dart';
import 'package:gtt_deviazioni/core/text/periodo_avviso.dart';

import 'src/confronto.dart';
import 'src/mezzi.dart';

Future<void> main(List<String> args) async {
  final porta = int.tryParse(_arg(args, '--porta') ?? '') ?? 8768;
  final fileLetture = _arg(args, '--letture') ??
      (File('tool/letture_di_prova.json').existsSync()
          ? 'tool/letture_di_prova.json'
          : null);
  final banco = Banco(
    Confronto(
      sito: _arg(args, '--sito') ?? 'https://deviato.it/v1',
      letture:
          fileLetture == null ? const {} : Confronto.leggiLetture(fileLetture),
    ),
  );
  banco.carica();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, porta);
  stdout.writeln('Banco di prova: http://localhost:$porta');
  await for (final req in server) {
    unawaited(banco.rispondi(req));
  }
}

class Banco {
  Banco(this.confronto);

  final Confronto confronto;
  final _cartella = Directory('build/banco');
  List<Map<String, Object?>> confronti = [];
  DateTime? calcolatoIl;
  bool calcolando = false;
  int fatte = 0, totale = 0;

  final Map<String, LineaSeguita> seguite = {};
  final _mezzi = VehiclesSource();
  Timer? _timer;

  /// Tetto di sicurezza: dopo due ore si smette da soli, come nell'app.
  static const durataMassima = Duration(hours: 2);
  static const ogni = Duration(seconds: 20);

  File get _cache => File('${_cartella.path}/confronti.json');

  void carica() {
    if (!_cache.existsSync()) {
      unawaited(ricalcola());
      return;
    }
    final j = jsonDecode(_cache.readAsStringSync()) as Map<String, dynamic>;
    confronti = (j['confronti'] as List).cast<Map<String, Object?>>();
    calcolatoIl = DateTime.tryParse(j['calcolato'] as String? ?? '');
  }

  Future<void> ricalcola() async {
    if (calcolando) return;
    calcolando = true;
    final nuovi = <Map<String, Object?>>[];
    try {
      await confronto.calcola(
        ogni: (r) {
          nuovi.add(r);
          // Si vedono man mano, mescolati ai vecchi delle linee non ancora
          // rifatte.
          confronti = [
            ...nuovi,
            ...confronti.where((c) => !nuovi.any((n) =>
                n['avviso'] == c['avviso'] && n['percorso'] == c['percorso'])),
          ];
        },
        avanzamento: (f, t) {
          fatte = f;
          totale = t;
        },
      );
      confronti = nuovi;
      calcolatoIl = DateTime.now();
      _cartella.createSync(recursive: true);
      _cache.writeAsStringSync(jsonEncode({
        'calcolato': calcolatoIl!.toIso8601String(),
        'confronti': confronti,
      }));
    } on Object catch (e) {
      stderr.writeln('calcolo non riuscito: $e');
    } finally {
      calcolando = false;
    }
  }

  Future<void> segui(String routeId) async {
    if (seguite.containsKey(routeId)) return;
    final percorsi = await confronto.percorsi(routeId);
    if (percorsi.isEmpty) return;
    seguite[routeId] = LineaSeguita(routeId, percorsi);
    _timer ??= Timer.periodic(ogni, (_) => unawaited(_campione()));
    await _campione();
  }

  void ferma(String routeId) {
    final l = seguite.remove(routeId);
    if (l != null) _salva(l);
    if (seguite.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _campione() async {
    if (seguite.isEmpty) return;
    final VehicleSnapshot foto;
    try {
      foto = await _mezzi.fetch();
    } on Object catch (e) {
      stderr.writeln('feed dei mezzi non raggiungibile: $e');
      return;
    }
    for (final l in [...seguite.values]) {
      l.aggiungi(foto);
      _salva(l);
      if (DateTime.now().difference(l.da) > durataMassima) ferma(l.routeId);
    }
  }

  /// Le tracce su disco, una per linea e per sessione: sono il dato da
  /// cui misurare gli algoritmi nei giorni dopo.
  void _salva(LineaSeguita l) {
    final dir = Directory('${_cartella.path}/mezzi')..createSync(recursive: true);
    final nome = '${l.routeId}-${l.da.toIso8601String().replaceAll(':', '-')}';
    File('${dir.path}/$nome.json').writeAsStringSync(jsonEncode({
      'linea': l.routeId,
      'da': l.da.toIso8601String(),
      'campioni': l.campioni,
      'mezzi': [
        for (final t in l.tracce.values)
          {
            'id': t.vehicleId,
            'punti': [
              for (final o in t.points)
                [
                  o.position.lat,
                  o.position.lon,
                  o.seenAt.toIso8601String(),
                  o.tripId,
                  o.bearing,
                ],
            ],
          },
      ],
    }));
  }

  Future<void> rispondi(HttpRequest req) async {
    final r = req.response;
    try {
      final percorso = req.uri.path;
      final linea = req.uri.queryParameters['linea'];
      if (percorso == '/' || percorso == '/index.html') {
        r.headers.contentType = ContentType.html;
        // Riletta a ogni richiesta: si ritocca senza riavviare.
        r.write(File('tool/banco.html').readAsStringSync());
      } else if (percorso == '/api/stato') {
        _json(r, {
          'calcolando': calcolando,
          'fatte': fatte,
          'totale': totale,
          'calcolato': calcolatoIl?.toIso8601String(),
          'seguite': seguite.keys.toList(),
          'confronti': [for (final c in confronti) {...c, ..._periodo(c)}],
        });
      } else if (percorso == '/api/ricalcola' && req.method == 'POST') {
        unawaited(ricalcola());
        _json(r, {'ok': true});
      } else if (percorso == '/api/segui' && linea != null) {
        await segui(linea);
        _json(r, {'ok': seguite.containsKey(linea)});
      } else if (percorso == '/api/ferma' && linea != null) {
        ferma(linea);
        _json(r, {'ok': true});
      } else if (percorso == '/api/mezzi' && linea != null) {
        final l = seguite[linea];
        _json(r, l == null
            ? {'linea': linea, 'attivo': false}
            : {
                'attivo': true,
                ...l.json([
                  for (final c in confronti)
                    if (c['id'] == linea) c,
                ]),
              });
      } else {
        r.statusCode = HttpStatus.notFound;
      }
    } on Object catch (e) {
      r.statusCode = HttpStatus.internalServerError;
      r.write('$e');
    }
    await r.close();
  }

  /// Se la deviazione vale adesso, letto dal testo dell'avviso: il feed
  /// data gli avvisi con l'ora di pubblicazione. Si rifa' a ogni richiesta,
  /// cosi' «fuori orario» diventa «in corso» quando arriva l'ora.
  static Map<String, Object?> _periodo(Map<String, Object?> c) {
    final ora = DateTime.now();
    final pubblicato = DateTime.tryParse(c['pubblicato'] as String? ?? '');
    final p = PeriodoAvviso.leggi(
      c['solotesto'] as String? ?? c['testo'] as String? ?? '',
      pubblicato: pubblicato?.toLocal(),
    );
    var stato = p.stato(ora);
    var descrizione = p.descrizione;
    var daDove = 'testo';
    if (stato == StatoPeriodo.sconosciuto) {
      // Il testo non dice quando: si guardano le date del feed, che per
      // gli avvisi brevi («non transita dalla fermata 1763») sono giuste.
      final scade = DateTime.tryParse(c['scade'] as String? ?? '');
      if (pubblicato != null) {
        daDove = 'feed';
        stato = ora.isBefore(pubblicato)
            ? StatoPeriodo.inProgramma
            : scade != null && ora.isAfter(scade)
            ? StatoPeriodo.finito
            : StatoPeriodo.inCorso;
        String g(DateTime d) => '${d.toLocal().day}/${d.toLocal().month}';
        descrizione = 'dal ${g(pubblicato)}'
            '${scade == null ? '' : ' al ${g(scade)}'} (date del feed)';
      }
    }
    return {
      'stato': stato.name,
      'periodo': descrizione,
      'periodoDa': daDove,
      'inCorso':
          stato == StatoPeriodo.inCorso || stato == StatoPeriodo.fuoriOrario,
    };
  }

  static void _json(HttpResponse r, Object dati) {
    r.headers.contentType = ContentType.json;
    r.write(jsonEncode(dati));
  }
}

String? _arg(List<String> args, String nome) {
  final i = args.indexOf(nome);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}
