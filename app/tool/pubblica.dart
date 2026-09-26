// Il giro del job su GitHub: calcola lo stato di tutte le linee e lo
// pubblica come file JSON, che l'app legge.
//
//   cd app && dart run tool/pubblica.dart --uscita ../sito/v1 --gtfs ../.gtfs
//
// Variabili d'ambiente, tutte facoltative:
//
//   OPENROUTER_API_KEY      la chiave del modello. Senza, gli avvisi restano
//                           in coda: si pubblicano solo le fermate sospese
//                           che GTT scrive col numero, lette con una regex.
//   LLM_MODELLO             il modello (predefinito: GttConfig).
//   LLM_MAX_RICHIESTE       tetto di letture per giro (predefinito 40).
//   MINUTI_MAX              dopo quanti minuti non si iniziano altre letture
//                           (predefinito 12): il job deve poter pubblicare.
//   USA_TABELLA_VARIAZIONI  "true" per usare anche la tabella del sito GTT.
//                           Spenta di proposito: i dati aperti con licenza
//                           sono il GTFS e il GTFS-RT; la tabella sta sul
//                           sito, le cui note legali proteggono i contenuti.
//                           Si accende quando GTT lo permette.
//
// Scrive solo i file cambiati: i percorsi cambiano con gli orari nuovi, gli
// stati quando cambiano gli avvisi. L'indice ogni volta, con l'ora del giro.
import 'dart:convert';
import 'dart:io';

import 'package:gtt_deviazioni/core/config.dart';
import 'package:gtt_deviazioni/core/deviation_service.dart';
import 'package:gtt_deviazioni/core/gtfs/gtfs_downloader.dart';
import 'package:gtt_deviazioni/core/gtfs/gtfs_parser.dart';
import 'package:gtt_deviazioni/core/io/formato_pubblicato.dart';
import 'package:gtt_deviazioni/core/llm/llm_client.dart';
import 'package:gtt_deviazioni/core/llm/llm_con_budget.dart';
import 'package:gtt_deviazioni/core/llm/openai_compatible_client.dart';
import 'package:gtt_deviazioni/core/models/notice.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/publish/pubblicatore.dart';
import 'package:gtt_deviazioni/core/sources/alerts_source.dart';
import 'package:gtt_deviazioni/core/sources/variazioni_source.dart';

/// Il testo d'attribuzione che la licenza di GTT chiede.
const _fonte = 'Data source: GTT S.p.A. – Gruppo Torinese Trasporti '
    '(https://www.gtt.to.it). Mappe © contributori di OpenStreetMap.';

Future<void> main(List<String> args) async {
  final inizio = DateTime.now();
  final uscita = Directory(_arg(args, '--uscita') ?? '../sito/v1');
  final gtfsDir = Directory(_arg(args, '--gtfs') ?? '../.gtfs');
  final env = Platform.environment;

  // 1. Gli orari di oggi.
  await GtfsDownloader(directory: gtfsDir).ensureAvailable(
    maxAge: const Duration(hours: 20),
    onProgress: (p, f) => _log('$p ${(f * 100).round()}%'),
  );
  final parser = GtfsParser(directory: gtfsDir);
  final index = await parser.build(await parser.allShortNames());
  _log('orari ${index.feedVersion}: ${index.lines.length} linee, '
      '${index.stops.length} fermate');

  // 2. Gli avvisi.
  final avvisi = <RawNotice>[...await AlertsSource().fetch()];
  if (env['USA_TABELLA_VARIAZIONI'] == 'true') {
    avvisi.addAll(await VariazioniSource().fetch());
  }
  _log('avvisi: ${avvisi.length}');

  // 3. Gli esiti del giro prima: gli avvisi uguali non si rileggono.
  final precedenti = _leggiPrecedenti(uscita, index);
  _log('esiti precedenti: ${precedenti.length} linee');

  // 4. Il calcolo, con un tetto di richieste e di tempo.
  final chiave = env['OPENROUTER_API_KEY'] ?? '';
  final LlmClient modello = chiave.isEmpty
      ? const NessunLlm()
      : OpenAiCompatibleClient.openRouter(
          apiKey: chiave,
          model: _nonVuoto(env['LLM_MODELLO']) ??
              GttConfig.llmModelloPredefinito,
        );
  final llm = LlmConBudget(
    modello,
    maxRichieste: int.tryParse(env['LLM_MAX_RICHIESTE'] ?? '') ?? 40,
    scadenza: inizio.add(
        Duration(minutes: int.tryParse(env['MINUTI_MAX'] ?? '') ?? 12)),
  );
  final giro = await Pubblicatore(
    index: index,
    service: DeviationService(index: index, llm: llm),
  ).calcola(avvisi: avvisi, precedenti: precedenti, log: _log);

  // 5. I file.
  var scritti = 0;
  for (final linea in index.lines.values) {
    final shapes = index.shapesOf(linea.routeId);
    if (shapes.isEmpty) continue;
    if (_scrivi(
        uscita,
        'percorsi/${FormatoPubblicato.nomeFile(linea.routeId)}',
        FormatoPubblicato.percorsi(linea, shapes, feed: index.feedVersion))) {
      scritti++;
    }
  }
  for (final s in giro.stati.values) {
    if (_scrivi(uscita, 'stato/${FormatoPubblicato.nomeFile(s.line.routeId)}',
        FormatoPubblicato.stato(s))) {
      scritti++;
    }
  }
  _scrivi(
    uscita,
    'indice.json',
    FormatoPubblicato.indice(
      feed: index.feedVersion,
      generato: DateTime.now(),
      linee: [
        for (final l in index.lines.values)
          if (index.shapesOf(l.routeId).isNotEmpty) l,
      ]..sort(TransitLine.compare),
      fonte: _fonte,
    ),
  );

  _log('fatto in ${DateTime.now().difference(inizio).inSeconds} s: '
      '${giro.stati.length} linee, ${giro.avvisi} avvisi, '
      '${llm.richieste} richieste al modello, '
      '${giro.daRitentare} da ritentare, '
      '$scritti file cambiati'
      '${llm.fermoPer != null ? ", modello fermo: ${llm.fermoPer}" : ""}');
  if (giro.errori.isNotEmpty) {
    _log('linee con errori: ${giro.errori.length}');
  }
}

/// Gli stati del giro precedente, riletti con i percorsi di oggi. Un
/// avviso agganciato a un percorso sparito si perde, e si rilegge.
Map<String, LineStatus> _leggiPrecedenti(Directory uscita, GtfsIndex index) {
  final f = File('${uscita.path}/indice.json');
  if (!f.existsSync()) return {};
  try {
    final generato = FormatoPubblicato.leggiIndice(
            jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)
        .generato;
    final out = <String, LineStatus>{};
    final dir = Directory('${uscita.path}/stato');
    if (!dir.existsSync()) return out;
    for (final e in dir.listSync().whereType<File>()) {
      try {
        final s = FormatoPubblicato.leggiStato(
          jsonDecode(e.readAsStringSync()) as Map<String, dynamic>,
          index,
          controllata: generato,
        );
        if (s != null) out[s.line.routeId] = s;
      } on Object catch (err) {
        _log('stato illeggibile ${e.path}: $err');
      }
    }
    return out;
  } on Object catch (err) {
    _log('indice illeggibile, si riparte da zero: $err');
    return {};
  }
}

/// Scrive [contenuto] se e' diverso da quello che c'e'. Vero se ha scritto.
bool _scrivi(Directory base, String percorso, Map<String, Object?> contenuto) {
  final f = File('${base.path}/$percorso');
  final testo = jsonEncode(contenuto);
  if (f.existsSync() && f.readAsStringSync() == testo) return false;
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(testo);
  return true;
}

String? _arg(List<String> args, String nome) {
  final i = args.indexOf(nome);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

String? _nonVuoto(String? s) => s == null || s.trim().isEmpty ? null : s;

void _log(String riga) => stdout.writeln(riga);
