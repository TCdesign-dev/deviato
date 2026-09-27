import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/deviation_service.dart';
import '../core/io/formato_pubblicato.dart';
import '../core/models/saved_stop.dart';
import '../core/models/transit.dart';
import '../core/pipeline/line_resolver.dart';
import '../core/pipeline/stop_answer.dart';
import '../core/pipeline/vehicle_watch.dart';
import 'fonte_dati.dart';
import 'settings.dart';

/// A che punto e' l'avvio.
enum LoadState { idle, loading, ready, error }

/// Tiene insieme dati e servizi, e avvisa l'interfaccia quando cambia
/// qualcosa.
///
/// L'app non calcola piu' niente: legge cio' che il job su GitHub ha
/// calcolato per tutti (vedi `tool/pubblica.dart`). Prima ogni telefono
/// scaricava 24 MB di orari, leggeva gli avvisi col modello usando una
/// chiave sua, cercava le vie e calcolava i percorsi: mille persone
/// avrebbero fatto mille volte lo stesso lavoro, ognuna con cinquanta
/// letture al giorno. Ora «Aggiorna» scarica qualche KB.
///
/// Resta qui cio' che e' di chi usa l'app: le sue linee, le sue fermate,
/// e l'osservazione dei mezzi, che legge il feed di GTT direttamente.
class AppRepository extends ChangeNotifier {
  AppRepository(this.settings, {FonteDati? fonte})
    : _fonte = fonte ?? DatiPubblicati();

  final Settings settings;
  final FonteDati _fonte;

  LoadState state = LoadState.idle;
  String? error;

  void clearError() {
    error = null;
    notifyListeners();
  }

  /// Percorsi e fermate delle linee scelte.
  GtfsIndex? index;

  final Map<String, LineStatus> _statuses = {};

  LineStatus? statusOf(String routeId) => _statuses[routeId];
  List<LineStatus> get statuses => _statuses.values.toList(growable: false);

  /// Quando il job ha fatto il giro da cui vengono i dati mostrati.
  DateTime? generato;

  /// Versione degli orari GTT dei dati mostrati («20260922»).
  String? _feed;
  String? get feed => _feed;

  /// L'ultimo aggiornamento non e' arrivato: si mostrano i dati salvati.
  bool offline = false;

  DateTime? get lastRefresh => generato;

  /// Quando e' stato calcolato lo stato di [routeId]: l'ora del giro.
  DateTime? checkedAt(String routeId) =>
      _statuses.containsKey(routeId) ? generato : null;

  bool _aggiornando = false;

  /// Si sta scaricando l'ultimo stato pubblicato.
  bool get isRefreshingAll => _aggiornando;

  /// Quando e' finito l'ultimo tentativo di scaricare, riuscito o no.
  DateTime? _ultimoTentativo;

  /// Riscarica se l'ultimo tentativo e' vecchio di piu' di [dopo], o se
  /// non era riuscito.
  ///
  /// Serve quando l'app torna in primo piano. Prima i dati restavano
  /// quelli dell'apertura: iOS tiene l'app in memoria per ore, e chi la
  /// riapriva la sera vedeva gli avvisi del mattino finché non premeva
  /// «Aggiorna». Due minuti bastano a non riscaricare a ogni occhiata.
  Future<void> aggiornaSeServe({
    Duration dopo = const Duration(minutes: 2),
  }) async {
    final t = _ultimoTentativo;
    if (!offline && t != null && DateTime.now().difference(t) < dopo) return;
    await refreshAll();
  }

  final Set<String> _busy = {};

  /// Si stanno scaricando i dati di [routeId].
  bool isChecking(String routeId) =>
      _busy.contains(routeId) ||
      (_aggiornando && !_statuses.containsKey(routeId));

  /// Tutte le linee di GTT, per cercarle e aggiungerle dalla home.
  List<TransitLine> allLines = const [];

  /// L'elenco delle linee non e' arrivato e non ce n'e' una copia.
  String? get catalogError =>
      allLines.isEmpty && offline && !_aggiornando ? error : null;

  bool get preparingCatalog => allLines.isEmpty && _aggiornando;

  /// Riprova a scaricare l'elenco delle linee, dalla ricerca.
  Future<void> retryCatalog() => refreshAll();

  /// Le linee appena aggiunte, mentre se ne scaricano percorsi e stato.
  final Map<String, TransitLine> _preparing = {};
  bool isPreparing(String routeId) => _preparing.containsKey(routeId);

  /// Le linee da mostrare: quelle pronte e quelle in preparazione,
  /// nell'ordine di GTT.
  List<TransitLine> get lines => [
    ...?index?.lines.values,
    for (final l in _preparing.values)
      if (!(index?.lines.containsKey(l.routeId) ?? false)) l,
  ]..sort(TransitLine.compare);

  // ---------------------------------------------------------------
  // Osservazione dei mezzi
  //
  // Vive QUI e non nella schermata perche' deve sopravvivere alla
  // navigazione: uno fa partire l'osservazione sulla 15, va a guardare
  // la 4, e quando torna la deve ritrovare in corso. Nella schermata
  // moriva al primo `Navigator.pop`.
  //
  // **Una linea alla volta.** Non e' una limitazione tecnica ma una
  // scelta: due osservazioni in parallelo raddoppiano le richieste al
  // feed di GTT, e nessuno guarda due linee insieme. Farne partire una
  // nuova ferma la precedente, e l'interfaccia lo dice.
  // ---------------------------------------------------------------

  /// La linea che si sta osservando adesso. null se nessuna.
  String? watchingRouteId;

  /// Da quando si sta guardando.
  DateTime? watchStartedAt;

  /// Un tetto, non una durata: si guarda finche' non si interrompe, ma chi
  /// se ne dimentica non deve consumare batteria e dati per una giornata.
  /// Due ore sono ben oltre qualsiasi attesa alla fermata.
  static const watchSafetyLimit = Duration(hours: 2);

  /// Da quanto si sta guardando.
  Duration? get watchElapsed => watchStartedAt == null
      ? null
      : DateTime.now().difference(watchStartedAt!);

  int watchSamples = 0;
  List<VehicleTrack> liveTracks = const [];
  String? watchError;

  /// Gli esiti, per linea: tornando su una linea si rivede il suo.
  final Map<String, WatchResult> _watchResults = {};
  WatchResult? watchResultOf(String routeId) => _watchResults[routeId];

  bool isWatching(String routeId) => watchingRouteId == routeId;

  /// Il nome della linea osservata, per dirlo altrove nell'app.
  String? get watchingLineName =>
      watchingRouteId == null ? null : index?.lines[watchingRouteId]?.shortName;

  bool _stopWatchRequested = false;

  /// Comincia a guardare i mezzi di [line], finche' non si chiama
  /// [stopWatch] (o fino a [watchSafetyLimit]).
  ///
  /// Se se ne stava gia' guardando un'altra, quella si ferma: [stopWatch]
  /// viene chiamato prima, e il ciclo vecchio se ne accorge al giro
  /// successivo perche' `watchingRouteId` non e' piu' il suo.
  Future<void> startWatch(TransitLine line) async {
    if (watchingRouteId != null) stopWatch();

    watchingRouteId = line.routeId;
    watchStartedAt = DateTime.now();
    _stopWatchRequested = false;
    watchSamples = 0;
    liveTracks = const [];
    watchError = null;
    _watchResults.remove(line.routeId);
    notifyListeners();

    final status = _statuses[line.routeId];
    if (status == null) {
      watchingRouteId = null;
      notifyListeners();
      return;
    }

    try {
      final result = await VehicleWatch(maxDuration: watchSafetyLimit).watch(
        line: status.line,
        shapes: status.allShapes.isNotEmpty ? status.allShapes : [status.shape],
        onProgress: (samples, tracks) {
          // Se nel frattempo si e' passati a un'altra linea, questo ciclo
          // e' un fantasma: non deve scrivere piu' niente.
          if (watchingRouteId != line.routeId) return;
          watchSamples = samples;
          liveTracks = tracks;
          notifyListeners();
        },
        shouldStop: () =>
            _stopWatchRequested || watchingRouteId != line.routeId,
      );
      // L'esito si tiene anche quando si e' interrotto a mano: senza
      // durate e' l'unico modo di finire, e prima andava perso — il
      // ciclo trovava `watchingRouteId` gia' vuoto e non salvava niente.
      // Si butta solo se nel frattempo si e' passati a un'altra linea.
      if (watchingRouteId == line.routeId || watchingRouteId == null) {
        _watchResults[line.routeId] = result;
        liveTracks = result.tracks;
      }
    } on Object catch (e) {
      if (watchingRouteId == line.routeId) watchError = '$e';
    } finally {
      if (watchingRouteId == line.routeId) {
        watchingRouteId = null;
        watchStartedAt = null;
      }
      notifyListeners();
    }
  }

  void stopWatch() {
    _stopWatchRequested = true;
    watchingRouteId = null;
    watchStartedAt = null;
    notifyListeners();
  }

  /// La linea il cui dettaglio e' aperto adesso.
  ///
  /// Serve alla striscia in cima: sulla schermata della linea osservata
  /// e' di troppo, perche' li' la scheda dice gia' tutto e ha il suo
  /// pulsante per fermare. Ripetere le stesse cose a due dita di
  /// distanza toglie spazio e non aggiunge niente.
  String? visibleLineRouteId;

  void setVisibleLine(String? routeId) {
    if (visibleLineRouteId == routeId) return;
    visibleLineRouteId = routeId;
    notifyListeners();
  }

  /// La schermata di [routeId] se n'e' andata.
  ///
  /// Si controlla che sia ancora la sua: uscendo da una linea per entrare
  /// subito in un'altra, la nuova puo' essersi gia' annunciata, e questa
  /// cancellerebbe il suo annuncio.
  void clearVisibleLine(String routeId) {
    if (visibleLineRouteId != routeId) return;
    visibleLineRouteId = null;
    notifyListeners();
  }

  /// La linea che si sta osservando, per aprirla da un punto qualsiasi.
  TransitLine? get watchingLine =>
      watchingRouteId == null ? null : index?.lines[watchingRouteId];

  /// Mostra subito l'ultimo stato salvato, poi scarica quello nuovo.
  Future<void> initialise() async {
    error = null;
    await _caricaSalvati();
    // Senza niente di salvato e con delle linee da mostrare, si aspetta la
    // rete con la schermata di caricamento; altrimenti la lista c'e' gia'.
    state = settings.watchlist.isNotEmpty && _statuses.isEmpty
        ? LoadState.loading
        : LoadState.ready;
    notifyListeners();
    await refreshAll();
  }

  /// L'ultimo stato scaricato, dal telefono.
  Future<void> _caricaSalvati() async {
    final ind = await _fonte.salvato('indice.json');
    if (ind == null) return;
    await _applica(ind, (p) => _fonte.salvato(p));
  }

  /// Scarica l'ultimo stato pubblicato delle linee scelte.
  ///
  /// Sono l'indice e due file per linea: qualche KB, un secondo. Per
  /// questo non c'e' piu' un aggiornamento per singola linea: aggiornarle
  /// tutte costa quanto aggiornarne una.
  Future<void> refreshAll() async {
    if (_aggiornando) return;
    _aggiornando = true;
    notifyListeners();
    try {
      final ind = await _fonte.scarica('indice.json');
      if (ind == null) {
        throw const FonteNonRaggiungibile('indice non pubblicato');
      }
      await _applica(ind, (p) => _fonte.scarica(p), rete: true);
      offline = false;
      error = null;
      state = LoadState.ready;
    } on FonteNonRaggiungibile catch (e) {
      debugPrint('aggiornamento non riuscito: $e');
      offline = true;
      final quando = generato;
      error = quando == null
          ? 'Nessuna connessione. Riprova quando sei online.'
          : 'Nessuna connessione: dati delle ${_ora(quando)}.';
      state = _statuses.isEmpty && settings.watchlist.isNotEmpty
          ? LoadState.error
          : LoadState.ready;
    } finally {
      _aggiornando = false;
      _ultimoTentativo = DateTime.now();
      notifyListeners();
    }
  }

  /// Aggiornare una linea e' aggiornarle tutte: costa uguale.
  Future<void> refreshLine(TransitLine line) => refreshAll();

  /// Costruisce indice e stati dall'indice [ind] e dai file che [leggi]
  /// restituisce. Con [rete] i percorsi si riscaricano solo se gli orari
  /// sono cambiati: sono la parte pesante, e cambiano di rado.
  Future<void> _applica(
    Map<String, dynamic> ind,
    Future<Map<String, dynamic>?> Function(String) leggi, {
    bool rete = false,
  }) async {
    final i = FormatoPubblicato.leggiIndice(ind);
    allLines = i.linee;
    final cambiatiOrari = i.feed != _feed;

    final scelte = <TransitLine>[
      for (final nome in settings.watchlist)
        ?LineResolver.matchIn(i.linee, nome),
    ];
    final vecchio = index;
    final lines = <String, TransitLine>{};
    final shapes = <String, List<RouteShape>>{};
    final stops = <String, TransitStop>{};

    await Future.wait([
      for (final l in scelte)
        () async {
          final file = FormatoPubblicato.nomeFile(l.routeId);
          var percorsi = vecchio?.shapesOf(l.routeId) ?? const <RouteShape>[];
          if (percorsi.isEmpty || cambiatiOrari || !rete) {
            final j =
                await leggi('percorsi/$file') ??
                (rete ? await _fonte.salvato('percorsi/$file') : null);
            if (j != null) percorsi = FormatoPubblicato.leggiPercorsi(j).shapes;
          }
          if (percorsi.isEmpty) return;
          lines[l.routeId] = l;
          shapes[l.routeId] = percorsi;
          for (final s in percorsi) {
            for (final f in s.stops) {
              stops[f.id] = f;
            }
          }
        }(),
    ]);

    final nuovo = GtfsIndex(
      feedVersion: i.feed,
      builtAt: DateTime.now(),
      lines: lines,
      shapes: shapes,
      stops: stops,
    );

    final stati = <String, LineStatus>{};
    await Future.wait([
      for (final l in lines.values)
        () async {
          final j = await leggi(
            'stato/${FormatoPubblicato.nomeFile(l.routeId)}',
          );
          if (j == null) return;
          final s = FormatoPubblicato.leggiStato(
            j,
            nuovo,
            controllata: i.generato,
          );
          if (s != null) stati[l.routeId] = s;
        }(),
    ]);

    index = nuovo;
    _feed = i.feed;
    generato = i.generato;
    _statuses
      ..clear()
      ..addAll(stati);
  }

  /// Aggiunge [line]: se ne scaricano percorsi e stato, e basta.
  Future<void> addLine(TransitLine line) async {
    if (index?.lines.containsKey(line.routeId) ?? false) return;
    if (_preparing.containsKey(line.routeId)) return;
    await settings.addLine(line.shortName);
    _preparing[line.routeId] = line;
    error = null;
    notifyListeners();

    try {
      final file = FormatoPubblicato.nomeFile(line.routeId);
      final p = await _fonte.scarica('percorsi/$file');
      if (p == null) {
        throw const FonteNonRaggiungibile('percorsi non pubblicati');
      }
      final percorsi = FormatoPubblicato.leggiPercorsi(p).shapes;
      final idx = index ??= GtfsIndex(
        feedVersion: _feed,
        builtAt: DateTime.now(),
        lines: {},
        shapes: {},
        stops: {},
      );
      idx.lines[line.routeId] = line;
      idx.shapes[line.routeId] = percorsi;
      for (final s in percorsi) {
        for (final f in s.stops) {
          idx.stops[f.id] = f;
        }
      }
      final st = await _fonte.scarica('stato/$file');
      if (st != null) {
        final s = FormatoPubblicato.leggiStato(
          st,
          idx,
          controllata: generato ?? DateTime.now(),
        );
        if (s != null) _statuses[line.routeId] = s;
      }
      state = LoadState.ready;
    } on FonteNonRaggiungibile catch (e) {
      debugPrint('linea ${line.shortName}: $e');
      await settings.removeLine(line.shortName);
      index?.lines.remove(line.routeId);
      error =
          'Impossibile aggiungere la linea ${line.shortName}. '
          'Controlla la connessione e riprova.';
    } finally {
      _preparing.remove(line.routeId);
      notifyListeners();
    }
  }

  /// Toglie [line] e restituisce cio' che serve a rimetterla.
  ///
  /// Se ne va solo la sua: prima togliere una linea svuotava gli esiti di
  /// tutte.
  Future<RemovedLine> removeLine(TransitLine line) async {
    final nome = _watchlistNameOf(line) ?? line.shortName;
    if (watchingRouteId == line.routeId) stopWatch();
    final fermate = settings.savedStops
        .where((s) => s.routeId == line.routeId)
        .toList();
    final tolta = RemovedLine(
      line: line,
      watchlistName: nome,
      status: _statuses[line.routeId],
      savedStops: fermate,
    );

    // Prima la memoria, SENZA attese in mezzo: la riga sparisce scorrendo
    // (Dismissible), e se al primo aggiornamento dello schermo la linea
    // fosse ancora nell'elenco Flutter si ferma con un errore.
    //
    // Le geometrie restano nell'indice: servono a rimetterla subito se ci
    // si ripensa, e al prossimo avvio non verranno piu' lette.
    index?.lines.remove(line.routeId);
    _statuses.remove(line.routeId);
    _removedStops.addAll(fermate);
    notifyListeners();

    await settings.removeLine(nome);
    for (final f in fermate) {
      await settings.removeSavedStop(f);
    }
    _removedStops.removeWhere((r) => fermate.any(r.same));
    return tolta;
  }

  /// Rimette una linea appena tolta, con il suo esito e le sue fermate.
  Future<void> restoreLine(RemovedLine r) async {
    await settings.addLine(r.watchlistName);
    for (final f in r.savedStops) {
      await settings.addSavedStop(f);
    }
    index?.lines[r.line.routeId] = r.line;
    if (r.status != null) _statuses[r.line.routeId] = r.status!;
    notifyListeners();
  }

  /// Il nome con cui la linea sta nella watchlist: e' quello scritto da chi
  /// l'ha aggiunta («10n», «58 barrata»), non per forza quello del GTFS.
  String? _watchlistNameOf(TransitLine line) {
    for (final nome in settings.watchlist) {
      if (LineResolver.matchIn([line], nome) != null) return nome;
    }
    return null;
  }

  // ---------------------------------------------------------------
  // Fermate salvate
  // ---------------------------------------------------------------

  /// Tolte insieme a una linea, mentre la rimozione si scrive su disco:
  /// nel frattempo non vanno piu' mostrate.
  final List<SavedStop> _removedStops = [];

  List<SavedStop> get savedStops => [
    for (final s in settings.savedStops)
      if (!_removedStops.any(s.same)) s,
  ];

  bool isSaved(SavedStop s) => savedStops.any(s.same);

  Future<void> saveStop(SavedStop s) async {
    await settings.addSavedStop(s);
    notifyListeners();
  }

  Future<void> unsaveStop(SavedStop s) async {
    await settings.removeSavedStop(s);
    notifyListeners();
  }

  /// Rimette una fermata tolta per sbaglio, nel posto dov'era.
  Future<void> restoreSavedStop(SavedStop s, int at) async {
    final current = settings.savedStops;
    if (current.any(s.same)) return;
    current.insert(at.clamp(0, current.length), s);
    await settings.setSavedStops(current);
    notifyListeners();
  }

  /// Cosa dire di [s] adesso. null finche' gli orari non sono pronti.
  StopAnswer? answerFor(SavedStop s) {
    final idx = index;
    if (idx == null) return null;
    return StopAnswer.of(s, _statuses[s.routeId], idx);
  }

  Future<void> dismissStopsHint() async {
    await settings.setStopsHintSeen();
    notifyListeners();
  }

  static String _ora(DateTime t) =>
      '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';
}

/// Una linea appena tolta, con quello che serve a rimetterla com'era.
class RemovedLine {
  const RemovedLine({
    required this.line,
    required this.watchlistName,
    required this.status,
    required this.savedStops,
  });

  final TransitLine line;
  final String watchlistName;
  final LineStatus? status;
  final List<SavedStop> savedStops;
}
