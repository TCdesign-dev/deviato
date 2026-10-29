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
//   MINUTI_MAX              dopo quanti minuti non si iniziano altre letture,
//                           ne' si rifanno avvisi col nuovo algoritmo
//                           (predefinito 12): il job deve poter pubblicare.
//                           Quattro minuti dopo non si rifa' piu' nessun
//                           percorso: gli avvisi rimasti tengono l'esito di
//                           prima, o il solo testo, fino al giro dopo.
//   ALGORITMO_PERCORSI      "1" (predefinito) o "2": quale algoritmo
//                           ricostruisce i percorsi deviati. Il primo e'
//                           quello in servizio fino al 28/09/2026, il
//                           secondo la sua copia da migliorare. Cambiando
//                           valore gli avvisi si rianalizzano: subito quelli
//                           con la lettura salvata, gli altri pochi per giro.
//   RILETTURE_CAMBIO_ALGORITMO  quanti avvisi dell'altro algoritmo senza
//                           lettura salvata rileggere per giro (predefinito
//                           5): gli altri tengono l'esito vecchio.
//   USA_TABELLA_VARIAZIONI  "true" per usare anche la tabella del sito GTT.
//                           Spenta di proposito: i dati aperti con licenza
//                           sono il GTFS e il GTFS-RT; la tabella sta sul
//                           sito, le cui note legali proteggono i contenuti.
//                           Si accende quando GTT lo permette.
//
// Scrive solo i file cambiati: i percorsi cambiano con gli orari nuovi, gli
// stati quando cambiano gli avvisi. L'indice ogni volta, con l'ora del giro.
import 'dart:async';
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
import 'package:gtt_deviazioni/core/ricostruzione/ricostruzione.dart';
import 'package:gtt_deviazioni/core/sources/alerts_source.dart';
import 'package:gtt_deviazioni/core/sources/scioperi_mit.dart';
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
  // Una riga per fase, non una per blocco scaricato: il registro di
  // GitHub ne mostrava decine uguali.
  //
  // Dal 23 al 28/10/2026 il sito di GTT non rispondeva: lo scaricamento
  // andava in errore e il giro con lui, 115 volte di fila, una mail per
  // ognuna. Gli orari cambiano di rado e la cache del job ha quelli del
  // giorno prima: si usano quelli, e lo si dice.
  String? ultimaFase;
  final orari = GtfsDownloader(directory: gtfsDir);
  try {
    await orari.ensureAvailable(
      maxAge: const Duration(hours: 20),
      onProgress: (p, f) {
        if (p == ultimaFase) return;
        ultimaFase = p;
        _log(p);
      },
    );
  } on GtfsDownloadException catch (e) {
    final quando = orari.isPresent ? orari.lastDownload : null;
    if (quando == null) {
      _log('::warning::Gli orari di GTT non si scaricano (${_breve(e)}) e '
          'non ce n\'e\' una copia: questo giro non pubblica niente.');
      _segnalaSeDura(uscita, env, _breve(e));
      _scrivi(uscita, 'salute.json',
          FormatoPubblicato.salute(avvisiGtt: false, controllato: DateTime.now()));
      await stdout.flush();
      exit(0);
    }
    _log('::warning::Gli orari di GTT non si scaricano (${_breve(e)}): si '
        'usano quelli scaricati il ${quando.day}/${quando.month} alle '
        '${quando.hour}:${quando.minute.toString().padLeft(2, '0')}.');
  }
  final parser = GtfsParser(directory: gtfsDir);
  final index = await parser.build(await parser.allShortNames());
  _log('orari ${index.feedVersion}: ${index.lines.length} linee, '
      '${index.stops.length} fermate');

  // 1b. Gli scioperi che possono fermare bus e tram, dal calendario del
  // Ministero dei Trasporti. Prima degli avvisi: si pubblicano anche
  // quando GTT non risponde. Se il Ministero non risponde resta il file di
  // prima.
  try {
    final oggi = DateTime.now();
    final scioperi = [
      for (final s in await _conTentativi(
        'scioperi',
        ScioperiMit().scarica,
        volte: 2,
      ))
        if (s.riguardaGtt && s.nonFinitoIl(oggi)) s,
    ]..sort((a, b) => a.giorniTpl.inizio.compareTo(b.giorniTpl.inizio));
    _scrivi(uscita, 'scioperi.json', {
      'versione': FormatoPubblicato.versione,
      'fonte': 'Ministero delle Infrastrutture e dei Trasporti, '
          'scioperi.mit.gov.it',
      'scioperi': [for (final s in scioperi) s.toJson()],
    });
    _log('scioperi che toccano GTT: ${scioperi.length}');
  } on Object catch (e) {
    _log('::warning::Il calendario degli scioperi non risponde '
        '(${_breve(e)}): resta quello di prima.');
  }

  // 2. Gli avvisi.
  //
  // Il 04/10/2026 dalle 9:13 il feed di GTT rispondeva 500 («Runtime
  // Error») a ogni giro e il job si fermava con un'eccezione: sei giri
  // falliti di fila, una mail per ognuno. Si riprova un paio di volte; se
  // GTT continua a non rispondere il giro non pubblica niente — restano i
  // dati di prima, con la loro ora, che sito e app mostrano — e finisce
  // senza errore: da questa parte non c'e' niente da sistemare.
  final List<RawNotice> avvisi;
  try {
    avvisi = [...await _conTentativi('avvisi di GTT', AlertsSource().fetch)];
  } on Object catch (e) {
    _log('::warning::Gli avvisi di GTT non rispondono (${_breve(e)}). '
        'Questo giro non pubblica niente: restano i dati del giro prima.');
    _segnalaSeDura(uscita, env, _breve(e));
    // Gli stati restano quelli di prima, e l'indice con la sua ora: l'app
    // vede dati vecchi, e da qui sa perche'.
    _scrivi(uscita, 'salute.json',
        FormatoPubblicato.salute(avvisiGtt: false, controllato: DateTime.now()));
    await stdout.flush();
    exit(0);
  }
  if (env['USA_TABELLA_VARIAZIONI'] == 'true') {
    avvisi.addAll(await VariazioniSource().fetch());
  }
  _log('avvisi: ${avvisi.length}');

  // 3. Gli esiti del giro prima: gli avvisi uguali non si rileggono.
  final precedenti = _leggiPrecedenti(uscita, index);
  _log('esiti precedenti: ${precedenti.length} linee');

  // 3b. Le linee in quarantena. Il 28/10 un giro dopo l'altro si e'
  // fermato sulla stessa linea finche' il job non e' stato interrotto, e
  // nessuna linea si aggiornava piu'. Il giro scrive su quale linea sta
  // lavorando (`giro.json`); se il workflow lo interrompe li', il giro dopo
  // per un giorno aggiorna quella linea col solo testo degli avvisi, e le
  // altre vanno avanti.
  final quarantena = _Quarantena.leggi(uscita);
  for (final e in quarantena.linee.entries) {
    final nome = index.lines[e.key]?.shortName ?? e.key;
    _log('::warning::Linea $nome col solo testo degli avvisi fino al '
        '${_quando(e.value.add(_Quarantena.durata))}: il suo calcolo si era '
        'bloccato.');
  }

  // 4. Il calcolo, con un tetto di richieste e di tempo.
  final chiave = env['OPENROUTER_API_KEY'] ?? '';
  final LlmClient modello = chiave.isEmpty
      ? const NessunLlm()
      : OpenAiCompatibleClient.openRouter(
          apiKey: chiave,
          model: _nonVuoto(env['LLM_MODELLO']) ??
              GttConfig.llmModelloPredefinito,
        );
  final scadenza = inizio.add(
      Duration(minutes: int.tryParse(env['MINUTI_MAX'] ?? '') ?? 12));
  // Il job ha 25 minuti in tutto: i preparativi ne prendono uno, un avviso
  // gia' cominciato puo' durarne tre o quattro (Overpass, Photon e
  // Valhalla a tempo massimo), poi i file e la pubblicazione.
  final scadenzaGiro = scadenza.add(const Duration(minutes: 4));
  final llm = LlmConBudget(
    modello,
    maxRichieste: int.tryParse(env['LLM_MAX_RICHIESTE'] ?? '') ?? 40,
    scadenza: scadenza,
  );
  final algoritmo = AlgoritmoPercorsi.daTesto(env['ALGORITMO_PERCORSI']);
  _log('algoritmo dei percorsi: ${algoritmo.numero}');
  final service = DeviationService(
    index: index,
    llm: llm,
    algoritmo: algoritmo,
    rilettureCambioAlgoritmo:
        int.tryParse(env['RILETTURE_CAMBIO_ALGORITMO'] ?? '') ?? 5,
    // Anche il cambio di algoritmo si ferma: il resto al giro dopo.
    scadenzaCambioAlgoritmo: scadenza,
    scadenzaGiro: scadenzaGiro,
  );
  // Una riga ogni due minuti su dove si e' arrivati: se il giro non
  // finisce, il log dice dove si e' fermato.
  var fase = '', lineaInCorso = '';
  var dal = DateTime.now(), faseDal = DateTime.now();
  final sentinella = Timer.periodic(const Duration(minutes: 2), (_) {
    _log('in corso: linea $lineaInCorso, $fase '
        '(da ${DateTime.now().difference(dal).inSeconds} s)');
  });
  final giro = await Pubblicatore(index: index, service: service).calcola(
    avvisi: avvisi,
    precedenti: precedenti,
    log: _log,
    soloTesto: quarantena.linee.keys.toSet(),
    inizio: (l) {
      lineaInCorso = l.shortName;
      fase = '';
      dal = faseDal = DateTime.now();
      quarantena.inCorso(uscita, l.routeId);
    },
    // Le fasi lente si scrivono con la loro durata: il 29/10 la 5137
    // prendeva dieci minuti a giro, e dalla sola riga ogni due minuti non
    // si capiva se il tempo andasse in Photon, in Overpass o nel modello.
    fase: (l, f) {
      final durata = DateTime.now().difference(faseDal);
      if (fase.isNotEmpty && durata >= const Duration(seconds: 20)) {
        _log('lento: linea ${l.shortName}, $fase: ${durata.inSeconds} s');
      }
      fase = f;
      faseDal = DateTime.now();
    },
  );
  sentinella.cancel();
  quarantena.finito(uscita);

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
  // Tutte le fermate, per cercarle dall'app. Cambia solo con gli orari.
  if (_scrivi(
      uscita,
      'fermate.json',
      FormatoPubblicato.fermate({
        for (final linea in index.lines.values)
          if (index.shapesOf(linea.routeId).isNotEmpty)
            linea.routeId: index.shapesOf(linea.routeId),
      }, feed: index.feedVersion))) {
    scritti++;
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
  _scrivi(uscita, 'salute.json',
      FormatoPubblicato.salute(avvisiGtt: true, controllato: DateTime.now()));

  _log('fatto in ${DateTime.now().difference(inizio).inSeconds} s: '
      '${giro.stati.length} linee, ${giro.avvisi} avvisi, '
      '${llm.richieste} richieste al modello, '
      '${giro.daRitentare} da ritentare, '
      '$scritti file cambiati'
      '${service.rimandati > 0 ? ", ${service.rimandati} rimandati al giro dopo" : ""}'
      '${llm.fermoPer != null ? ", modello fermo: ${llm.fermoPer}" : ""}');
  if (giro.errori.isNotEmpty) {
    _log('linee con errori: ${giro.errori.length}');
  }
  _segnalaModello(llm, env);
}

/// Il modello che legge gli avvisi non c'e' piu': lo si dice nel log, e
/// il workflow apre una segnalazione sul repository (una mail sola), come
/// quando GTT non risponde. Si chiude da sola al primo giro che legge.
void _segnalaModello(LlmConBudget llm, Map<String, String> env) {
  final cartella = env['GITHUB_WORKSPACE'];
  final fermo = llm.fermoPer;
  if (fermo != null && LlmConBudget.modelloSparito(fermo)) {
    _log('::warning::Il modello ${llm.name} non risponde piu\' '
        '(${_breve(fermo)}): gli avvisi nuovi restano col solo testo. '
        'Va cambiato LLM_MODELLO nelle variabili del repository.');
    if (cartella != null) {
      File('$cartella/modello_giu.txt').writeAsStringSync(
        'Il modello che legge gli avvisi, `${llm.name}`, non risponde piu\': '
        '`${_breve(fermo)}`.\n\n'
        'Gli avvisi nuovi restano col solo testo di GTT finche\' non lo si '
        'cambia: Settings › Secrets and variables › Actions › Variables, '
        '`LLM_MODELLO`. I modelli gratuiti con output strutturato:\n\n'
        '```\ncurl -s https://openrouter.ai/api/v1/models | jq -r \'.data[] '
        '| select(.id|endswith(":free")) '
        '| select(.supported_parameters|index("response_format")) | .id\'\n```\n\n'
        'Questa segnalazione si chiude da sola al primo giro che legge un '
        'avviso.\n',
      );
    }
  } else if (cartella != null && llm.riuscite > 0) {
    File('$cartella/modello_ok.txt').writeAsStringSync('ok\n');
  }
}

/// Da quante ore GTT non risponde, se oltre [GttConfig] non si tace piu'.
///
/// Dal 20/10/2026 alle 23:20 il feed degli avvisi ha dato 500 per un
/// giorno e mezzo: il job, fatto per non fallire per un guasto di GTT, ha
/// smesso di pubblicare senza che nessuno se ne accorgesse. Passate
/// [_oreDiSilenzio] ore dall'ultima pubblicazione scrive il file
/// `gtt_giu.txt` nella cartella del repository: il workflow apre una
/// segnalazione su GitHub (una mail, non una a giro) e la chiude quando
/// GTT torna.
void _segnalaSeDura(Directory uscita, Map<String, String> env, String errore) {
  final cartella = env['GITHUB_WORKSPACE'];
  if (cartella == null) return;
  final f = File('${uscita.path}/indice.json');
  if (!f.existsSync()) return;
  final DateTime ultima;
  try {
    ultima = FormatoPubblicato.leggiIndice(
      jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
    ).generato;
  } on Object {
    return;
  }
  final ore = DateTime.now().difference(ultima).inHours;
  if (ore < _oreDiSilenzio) return;
  String due(int n) => n.toString().padLeft(2, '0');
  final quando = '${due(ultima.day)}/${due(ultima.month)} alle '
      '${due(ultima.hour)}:${due(ultima.minute)}';
  File('$cartella/gtt_giu.txt').writeAsStringSync(
    'Il feed degli avvisi di GTT (alerts.aspx) non risponde: $errore.\n\n'
    'I dati di DeviaTo sono fermi all\'ultima pubblicazione, del $quando '
    '($ore ore fa). App e sito mostrano quell\'ora; il job continua a '
    'provare ogni mezz\'ora e questa segnalazione si chiude da sola quando '
    'GTT torna a rispondere.\n\n'
    'Non c\'e\' niente da sistemare nel codice: e\' un guasto di GTT. Se '
    'dura, si puo\' segnalare a GTT (contatto dei dati aperti nel '
    'feed_info: campagna.a@gtt.to.it).',
  );
}

const _oreDiSilenzio = 6;

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
String _quando(DateTime t) {
  String due(int n) => n.toString().padLeft(2, '0');
  return '${due(t.day)}/${due(t.month)} alle ${due(t.hour)}:${due(t.minute)}';
}

/// `giro.json`: la linea su cui il giro sta lavorando, e quelle che da un
/// giorno si aggiornano col solo testo perche' il loro calcolo si era
/// bloccato. Sta accanto ai dati, nel ramo pubblicato: e' l'unico posto che
/// il giro dopo ritrova.
class _Quarantena {
  _Quarantena(this.linee);

  static const durata = Duration(hours: 24);

  /// route_id -> da quando.
  final Map<String, DateTime> linee;

  static File _file(Directory uscita) => File('${uscita.path}/giro.json');

  static _Quarantena leggi(Directory uscita) {
    final linee = <String, DateTime>{};
    final f = _file(uscita);
    if (f.existsSync()) {
      try {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        for (final e in ((j['bloccate'] as Map?) ?? const {}).entries) {
          final quando = DateTime.tryParse('${e.value}');
          if (quando != null) linee['${e.key}'] = quando.toLocal();
        }
        // Il giro prima si e' fermato qui: non ha mai finito la linea.
        final ferma = j['inCorso'];
        if (ferma is String) linee[ferma] = DateTime.now();
      } on Object {
        // Un file rovinato non deve fermare il giro.
      }
    }
    linee.removeWhere(
        (_, quando) => DateTime.now().difference(quando) > durata);
    return _Quarantena(linee);
  }

  void inCorso(Directory uscita, String routeId) =>
      _scriviGiro(uscita, inCorso: routeId);

  void finito(Directory uscita) => _scriviGiro(uscita);

  void _scriviGiro(Directory uscita, {String? inCorso}) {
    final f = _file(uscita);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(jsonEncode({
      'inCorso': ?inCorso,
      'bloccate': {
        for (final e in linee.entries)
          e.key: e.value.toUtc().toIso8601String(),
      },
    }));
  }
}

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

/// Prova [f] fino a [volte] volte, con [pausa] fra un tentativo e l'altro.
Future<T> _conTentativi<T>(
  String cosa,
  Future<T> Function() f, {
  int volte = 3,
  Duration pausa = const Duration(seconds: 20),
}) async {
  for (var i = 1;; i++) {
    try {
      return await f();
    } on Object catch (e) {
      if (i >= volte) rethrow;
      _log('$cosa: tentativo $i non riuscito (${_breve(e)}), si riprova');
      await Future<void>.delayed(pausa);
    }
  }
}

/// La prima riga di un errore, senza la pagina HTML che GTT manda dietro.
String _breve(Object e) {
  final riga = '$e'.split('\n').first;
  final html = riga.indexOf('<');
  return (html > 0 ? riga.substring(0, html) : riga)
      .replaceFirst(RegExp(r'[:\s]+$'), '');
}

void _log(String riga) => stdout.writeln(riga);
