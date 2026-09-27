import 'package:flutter/material.dart';

import '../core/deviation_service.dart';
import '../core/models/notice.dart';
import '../core/models/saved_stop.dart';
import '../core/models/transit.dart';
import '../core/pipeline/closure_summary.dart';
import '../core/pipeline/stop_impact.dart';
import '../core/text/display_names.dart';
import '../data/app_repository.dart';
import 'line_badge.dart';
import 'line_map.dart';
import 'live_watch_card.dart';
import 'theme.dart';

/// Il dettaglio di una linea: cosa succede, dove, e cosa fare.
///
/// L'ordine conta. Prima la risposta — quali fermate non sono servite e
/// dove salire invece — detta per tratti e non per avviso; poi la mappa,
/// che serve a confermare; poi gli avvisi, e in fondo sempre il testo
/// originale di GTT, cosi' se il sistema sbaglia il dato grezzo resta a
/// disposizione (§6.2). I mezzi in tempo reale si aprono da un pulsante
/// che fluttua in basso al centro: prima erano una scheda in fondo alla
/// lista, e con due avvisi aperti bisognava scorrere fino alla fine per
/// trovarla.
class LineScreen extends StatefulWidget {
  const LineScreen({
    required this.repo,
    required this.line,
    this.initialStopId,
    super.key,
  });

  final AppRepository repo;
  final TransitLine line;

  /// La fermata da mostrare subito sulla mappa: quella salvata da cui si
  /// e' arrivati.
  final String? initialStopId;

  @override
  State<LineScreen> createState() => _LineScreenState();
}

class _LineScreenState extends State<LineScreen> {
  // L'osservazione NON sta qui: sta nel repository, perche' deve
  // continuare anche quando questa schermata viene chiusa.

  /// Oltre questo numero gli avvisi si raccolgono in una voce chiusa.
  ///
  /// La 10N il 26/09 ne aveva sedici, uno per fermata: sedici schede
  /// quasi uguali, e la risposta vera spariva in fondo. Il riassunto in
  /// cima la dice gia'; gli avvisi restano a un tocco.
  static const _avvisiApertiMax = 3;

  @override
  void initState() {
    super.initState();
    // Dopo il frame: cambiarlo durante la costruzione farebbe partire un
    // notifyListeners mentre l'albero si sta ancora montando.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.repo.setVisibleLine(widget.line.routeId),
    );
  }

  @override
  void dispose() {
    // La striscia in cima sta FUORI dal Navigator: uscendo di qui non
    // viene ricostruita da sola, va avvisata. Senza questo ricompariva
    // solo al primo aggiornamento successivo — cioe' aprendo un'altra
    // linea o ricontrollando qualcosa.
    //
    // Dopo il frame, perche' durante lo smontaggio non si puo' far
    // ricostruire l'albero.
    final routeId = widget.line.routeId;
    final repo = widget.repo;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => repo.clearVisibleLine(routeId),
    );
    super.dispose();
  }

  final _mappa = GlobalKey();

  void _startWatch() => widget.repo.startWatch(widget.line);

  /// Il pannello dei mezzi, dal fondo.
  ///
  /// Si ricostruisce da solo mentre l'osservazione va avanti: ascolta il
  /// repository, come la schermata. Quando si fa partire, si chiude e la
  /// pagina scorre alla mappa: e' li' che i mezzi compaiono.
  Future<void> _apriMezzi() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => ListenableBuilder(
      listenable: widget.repo,
      builder: (sheet, _) {
        final status = widget.repo.statusOf(widget.line.routeId);
        if (status == null) return const SizedBox.shrink();
        final osservando = widget.repo.isWatching(widget.line.routeId);
        return SafeArea(
          child: SingleChildScrollView(
            child: LiveWatchCard(
              inCard: false,
              running: osservando,
              samples: widget.repo.watchSamples,
              liveTracks: osservando ? widget.repo.liveTracks : const [],
              result: widget.repo.watchResultOf(widget.line.routeId),
              error: widget.repo.watchError,
              shape: status.shape,
              altraLinea: widget.repo.watchingRouteId != null && !osservando
                  ? widget.repo.watchingLineName
                  : null,
              onStart: () {
                _startWatch();
                Navigator.pop(sheet);
                _vaiAllaMappa();
              },
              onStop: widget.repo.stopWatch,
            ),
          ),
        );
      },
    ),
  );

  void _vaiAllaMappa() {
    final c = _mappa.currentContext;
    if (c == null) return;
    Scrollable.ensureVisible(
      c,
      duration: const Duration(milliseconds: 300),
      alignment: 0.05,
    );
  }

  SavedStop _salvata(TransitStop stop, RouteShape shape) => SavedStop(
    routeId: widget.line.routeId,
    directionId: shape.directionId,
    stopId: stop.id,
    stopCode: stop.code,
  );

  /// Salva la fermata, o la toglie se c'era gia'.
  Future<void> _salva(TransitStop stop, RouteShape shape) async {
    final s = _salvata(stop, shape);
    final messenger = ScaffoldMessenger.of(context);
    if (widget.repo.isSaved(s)) {
      await widget.repo.unsaveStop(s);
      messenger.showSnackBar(const SnackBar(content: Text('Fermata rimossa')));
    } else {
      await widget.repo.saveStop(s);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${DisplayNames.stop(stop)} salvata nelle tue '
            'fermate',
          ),
        ),
      );
    }
  }

  /// "controllata alle 19:08" se e' di oggi, "ieri alle 19:08" se no.
  ///
  /// Da quando gli esiti sopravvivono alla chiusura dell'app, la sola ora
  /// non basta piu': un esito di ieri sera mostrato come "alle 19:08"
  /// sembrerebbe di adesso, ed e' esattamente il tipo di bugia che questo
  /// progetto non si permette.
  String get _checkedLabel {
    final t = widget.repo.checkedAt(widget.line.routeId);
    if (t == null) return '';
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');

    final oggi = DateTime.now();
    final giorno = DateTime(t.year, t.month, t.day);
    final scarto = DateTime(
      oggi.year,
      oggi.month,
      oggi.day,
    ).difference(giorno).inDays;

    return switch (scarto) {
      0 => 'aggiornata alle $h:$m',
      1 => 'aggiornata ieri alle $h:$m',
      _ => 'aggiornata il ${t.day}/${t.month} alle $h:$m',
    };
  }

  @override
  Widget build(BuildContext context) {
    // Si ascolta il repository perche' il controllo della singola linea
    // avviene da qui: il risultato deve comparire senza tornare indietro.
    return ListenableBuilder(
      listenable: widget.repo,
      builder: (context, _) => _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final status = widget.repo.statusOf(widget.line.routeId);
    // La schermata si apre solo su una linea gia' controllata, ma toglierla
    // dalla watchlist mentre e' aperta la lascerebbe senza dati.
    if (status == null) return const Scaffold(body: SizedBox.shrink());
    final checking = widget.repo.isRefreshingAll;
    final osservando = widget.repo.isWatching(widget.line.routeId);
    final esito = widget.repo.watchResultOf(widget.line.routeId);
    final testo = Theme.of(context).textTheme;
    final secondario = Theme.of(context).colorScheme.onSurfaceVariant;

    final attivi = _perAvviso(status.activeReports);
    final futuri = _perAvviso(status.scheduledReports);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            LineBadge(line: status.line, height: 30),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Linea ${status.line.shortName}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        // Come nella home: si aggiorna da solo e tirando giu' la pagina; il
        // pulsante compare solo se l'ultimo tentativo non e' riuscito.
        actions: [
          if (checking)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else if (widget.repo.offline)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Riprova',
              onPressed: widget.repo.refreshAll,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              // I capolinea come li scrive il nome lungo della linea
              // («via Massari - piazza XVIII Dicembre»), non il
              // headsign in maiuscolo di una direzione sola.
              // Prima l'ora, che e' corta: se la riga si tronca, si
              // perde la fine del percorso e non l'ora. Il
              // qualificatore («circolare Tram Storici, …») resta
              // fuori: e' un dettaglio, e rubava la riga.
              child: Text(
                [
                  if (_checkedLabel.isNotEmpty) _maiuscola(_checkedLabel),
                  if (status.line.longName != null)
                    DisplayNames.routeParts(status.line.longName!).route,
                ].join('  ·  '),
                style: testo.bodySmall?.copyWith(color: secondario),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _PulsanteMezzi(
        osservando: osservando,
        mezzi: osservando ? widget.repo.liveTracks.length : 0,
        esito: esito != null,
        onPressed: _apriMezzi,
      ),
      body: RefreshIndicator(
        onRefresh: widget.repo.refreshAll,
        child: ListView(
          // Spazio in fondo per il pulsante dei mezzi, che fluttua sopra.
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            _Riassunto(status: status),
            // La mappa c'e' SEMPRE: vedere dove passa la linea serve anche
            // quando la deviazione non si e' potuta ricostruire.
            LineMap(
              key: _mappa,
              status: status,
              vehicles: osservando ? widget.repo.liveTracks : const [],
              observed: esito?.consensus,
              initialStopId: widget.initialStopId,
              isSaved: (stop, shape) =>
                  widget.repo.isSaved(_salvata(stop, shape)),
              onToggleSave: (stop, shape) => _salva(stop, shape),
            ),

            if (attivi.isNotEmpty) ...[
              if (attivi.length > _avvisiApertiMax)
                _AvvisiRaccolti(
                  count: attivi.length,
                  children: [
                    for (final g in attivi)
                      _ReportCard(reports: g, status: status),
                  ],
                )
              else ...[
                _Intestazione(
                  attivi.length == 1 ? 'Avviso di GTT' : 'Avvisi di GTT',
                ),
                for (final g in attivi) _ReportCard(reports: g, status: status),
              ],
            ],

            // Dopo cio' che succede adesso: sapere del 24 agosto e' utile,
            // ma non e' la risposta alla domanda di oggi.
            if (futuri.isNotEmpty) ...[
              const _Intestazione('In programma'),
              for (final g in futuri)
                _ReportCard(reports: g, status: status, daAvvenire: true),
            ],
          ],
        ),
      ),
    );
  }
}

/// Il pulsante dei mezzi in tempo reale, in basso al centro.
///
/// Dice a che punto e' l'osservazione anche da chiuso: quanti mezzi sono
/// sulla mappa mentre si guarda, e che c'e' un esito da leggere quando e'
/// finita.
class _PulsanteMezzi extends StatelessWidget {
  const _PulsanteMezzi({
    required this.osservando,
    required this.mezzi,
    required this.esito,
    required this.onPressed,
  });

  final bool osservando;
  final int mezzi;
  final bool esito;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final String testo;
    if (osservando) {
      testo = mezzi == 0
          ? 'Ricerca dei mezzi…'
          : '$mezzi ${mezzi == 1 ? "mezzo" : "mezzi"} sulla mappa';
    } else if (esito) {
      testo = 'Esito dei mezzi';
    } else {
      testo = 'Segui i mezzi';
    }
    return FloatingActionButton.extended(
      onPressed: onPressed,
      icon: osservando
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : const Icon(Icons.visibility_outlined),
      label: Text(testo),
    );
  }
}

class _Intestazione extends StatelessWidget {
  const _Intestazione(this.testo);

  final String testo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
    child: Text(testo, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// Tanti avvisi, raccolti in una voce che si apre.
class _AvvisiRaccolti extends StatelessWidget {
  const _AvvisiRaccolti({required this.count, required this.children});

  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ExpansionTile(
        leading: const Icon(Icons.article_outlined),
        title: Text('$count avvisi di GTT'),
        subtitle: const Text('Testi originali'),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.only(bottom: 12),
        children: children,
      ),
    );
  }
}

/// La risposta, in cima: cosa non e' servito e dove salire invece.
///
/// Si legge sul percorso, non avviso per avviso: sulla 10N il 26/09 GTT
/// aveva pubblicato sedici avvisi, uno per fermata, e per chi aspetta il
/// bus erano una cosa sola — nove fermate chiuse di fila in una
/// direzione, sei nell'altra.
class _Riassunto extends StatelessWidget {
  const _Riassunto({required this.status});

  final LineStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colori = StatusColors.of(context);
    final testo = Theme.of(context).textTheme;
    final attivi = status.activeReports;

    if (status.reports.isEmpty) {
      return _Riga(
        colore: colori.ok,
        icona: Icons.check_circle_outline,
        titolo: 'Percorso regolare',
        dettaglio: 'Nessun avviso di GTT su questa linea.',
      );
    }
    if (attivi.isEmpty) {
      return _Riga(
        colore: colori.ok,
        icona: Icons.check_circle_outline,
        titolo: 'Percorso regolare',
        dettaglio:
            'C\'è una variazione in programma: trovi i dettagli più '
            'in basso.',
      );
    }

    final direzioni = ClosureSummary.of(attivi);
    if (direzioni.isEmpty) {
      final ricostruito = attivi.any((r) => r.impact != null);
      // Senza un avviso letto non si sa nemmeno se sia una deviazione:
      // quello della 7 il 26/09 diceva «sospesa». Si dice la stessa cosa
      // della home, e si rimanda al testo.
      return _Riga(
        colore: colori.warning,
        icona: ricostruito ? Icons.alt_route : Icons.article_outlined,
        titolo: ricostruito ? 'Deviata, fermate servite' : 'Avviso in corso',
        dettaglio: ricostruito
            ? 'Il percorso cambia, ma tutte le fermate restano servite.'
            : 'Non è stato possibile ricavarne le fermate: leggi il testo '
                  'di GTT più in basso.',
      );
    }

    final totale = {
      for (final d in direzioni)
        for (final r in d.runs) ...r.stops.map((s) => s.id),
    }.length;
    final fine = ClosureSummary.commonEnd(attivi);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.do_not_disturb_on_outlined,
                size: 20,
                color: scheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  totale == 1
                      ? '1 fermata non servita'
                      : '$totale fermate non servite',
                  style: testo.titleMedium?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (fine != null)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 2),
              child: Text(
                'fino al ${_data(fine)}',
                style: testo.bodyMedium?.copyWith(color: scheme.error),
              ),
            ),
          for (final d in direzioni) _Direzione(d: d, line: status.line),
        ],
      ),
    );
  }
}

class _Riga extends StatelessWidget {
  const _Riga({
    required this.colore,
    required this.icona,
    required this.titolo,
    this.dettaglio,
  });

  final Color colore;
  final IconData icona;
  final String titolo;
  final String? dettaglio;

  @override
  Widget build(BuildContext context) {
    final testo = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icona, size: 22, color: colore),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titolo,
                  style: testo.titleMedium?.copyWith(
                    color: colore,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (dettaglio != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(dettaglio!, style: testo.bodyMedium),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una direzione: quali fermate, in fila, e dove salire.
///
/// Con un tratto solo si disegna la striscia e si dice dove salire. Con
/// piu' tratti sparsi — la 68 il 26/09 ne aveva quattro verso Frejus, fra
/// Cimitero Monumentale e Palagiustizia — la striscia diventava una fila
/// di ventisette pallini, e «Sali a» elencava sette fermate senza dire a
/// quale tratto appartenessero. Li' si va per righe: un tratto, le sue due
/// fermate aperte.
class _Direzione extends StatelessWidget {
  const _Direzione({required this.d, required this.line});

  final DirectionClosures d;
  final TransitLine line;

  @override
  Widget build(BuildContext context) {
    final testo = Theme.of(context).textTheme;
    final unTratto = d.runs.length == 1;
    final verso = DisplayNames.direction(
      d.shape.headsign,
      longName: line.longName,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Verso $verso', style: testo.titleSmall),
          const SizedBox(height: 2),
          if (unTratto) ...[
            Text(
              _descrivi(d.runs.single, conteggio: true),
              style: testo.bodyMedium,
            ),
            // Oltre una quindicina di pallini non si distinguono piu' su
            // un telefono: il testo sopra basta.
            if (d.window.length <= 15) ...[
              const SizedBox(height: 10),
              _Striscia(d: d),
            ],
            _SaliA(run: d.runs.single),
          ] else
            for (final r in d.runs)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.do_not_disturb_on_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _descrivi(r, conteggio: false),
                            style: testo.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          _SaliA(run: r, compatto: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  /// «3 di fila, da Verona a Cimitero Monumentale», o solo il nome.
  static String _descrivi(ClosedRun r, {required bool conteggio}) {
    final nome = DisplayNames.stop;
    if (r.stops.length == 1) return nome(r.stops.single);
    final tratto = 'da ${nome(r.stops.first)} a ${nome(r.stops.last)}';
    return conteggio
        ? '${r.stops.length} di fila, $tratto'
        : '${_maiuscola(tratto)} (${r.stops.length})';
  }

  static String _maiuscola(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// «Sali a Vibò o a Statuto Nord»: le fermate aperte ai capi del tratto.
/// Stessa linea, stessa direzione, aperte per costruzione.
class _SaliA extends StatelessWidget {
  const _SaliA({required this.run, this.compatto = false});

  final ClosedRun run;
  final bool compatto;

  @override
  Widget build(BuildContext context) {
    final aperte = [?run.before, ?run.after];
    if (aperte.isEmpty) return const SizedBox.shrink();
    final stile = compatto
        ? Theme.of(context).textTheme.bodySmall
        : Theme.of(context).textTheme.bodyMedium;
    final testo = Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Sali a '),
          TextSpan(
            text: DisplayNames.stop(aperte.first),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (aperte.length > 1) ...[
            const TextSpan(text: ' o a '),
            TextSpan(
              text: DisplayNames.stop(aperte.last),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
      style: stile,
    );
    if (compatto) {
      return Padding(padding: const EdgeInsets.only(top: 2), child: testo);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.directions_walk, size: 18),
          const SizedBox(width: 6),
          Expanded(child: testo),
        ],
      ),
    );
  }
}

/// Le fermate in fila: aperte vuote, chiuse piene. Il testo sopra dice
/// gia' tutto; questa serve a vedere a colpo d'occhio dov'e' il buco.
class _Striscia extends StatelessWidget {
  const _Striscia({required this.d});

  final DirectionClosures d;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final linea = scheme.onSurfaceVariant.withValues(alpha: 0.5);
    final w = d.window;
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 16,
            child: Row(
              children: [
                for (var i = 0; i < w.length; i++) ...[
                  if (i > 0)
                    Expanded(child: Container(height: 2, color: linea)),
                  w[i].closed
                      ? Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: scheme.error,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            size: 10,
                            color: scheme.onError,
                          ),
                        )
                      : Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: scheme.onSurfaceVariant,
                              width: 2,
                            ),
                          ),
                        ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  DisplayNames.stop(w.first.stop),
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  DisplayNames.stop(w.last.stop),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Gli esiti raggruppati per avviso, nell'ordine in cui arrivano.
///
/// Un avviso che riguarda tutte e due le direzioni viene analizzato due
/// volte — ed e' giusto, le fermate saltate sono diverse per senso di
/// marcia — ma mostrarlo come DUE schede significa ristampare per intero
/// lo stesso testo di GTT. Sulla 68, tre avvisi diventavano sei schede.
List<List<DeviationReport>> _perAvviso(List<DeviationReport> reports) {
  final per = <String, List<DeviationReport>>{};
  for (final r in reports) {
    per.putIfAbsent(r.notice.id, () => []).add(r);
  }
  return per.values.toList(growable: false);
}

String _maiuscola(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _verso(RouteShape shape, TransitLine line) =>
    DisplayNames.direction(shape.headsign, longName: line.longName);

String _data(DateTime d) =>
    '${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}';

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.reports,
    required this.status,
    this.daAvvenire = false,
  });

  /// Lo stesso avviso, una volta per direzione interessata.
  final List<DeviationReport> reports;
  final LineStatus status;

  /// La variazione deve ancora cominciare.
  final bool daAvvenire;

  DeviationReport get _primo => reports.first;

  @override
  Widget build(BuildContext context) {
    // Le direzioni in cui l'avviso non tocca niente non hanno niente da
    // dire, se in un'altra tocca qualcosa. Sulla 10N ogni avviso nomina
    // una fermata di UNA direzione: l'analisi dell'altra diceva «GTT nomina
    // la 422, che non risulta su questo percorso», e la scheda sembrava
    // contraddirsi — verificata in verde, e sotto un dubbio.
    final conEffetto = reports.where((r) => r.skippedStops.isNotEmpty).toList();
    final rilevanti = conEffetto.isNotEmpty ? conEffetto : reports;
    // Con piu' direzioni si mostra la piu' incerta: dire "verificata"
    // quando una delle due non lo e' sarebbe una promessa piu' grande del
    // dato.
    final peggiore = rilevanti.reduce(
      (a, b) => a.confidence.index >= b.confidence.index ? a : b,
    );
    final piuDirezioni = conEffetto.length > 1;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (daAvvenire)
            _ScheduledStrip(notice: _primo.notice, now: status.checkedAt),

          // 1. La risposta, per ogni direzione.
          for (final r in conEffetto) ...[
            if (piuDirezioni)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'Verso ${_verso(r.shape, status.line)}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            _SkippedStops(stops: r.skippedStops),
          ],
          if (conEffetto.isEmpty && reports.any((r) => r.impact != null))
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Il percorso cambia, ma tutte le fermate '
                'restano servite.',
              ),
            ),

          // 2. Il testo di GTT, UNA volta sola.
          _OriginalText(report: _primo),

          // 3. Quanto fidarsi, in fondo: e' un dettaglio della risposta,
          // non la risposta. Prima stava in cima, in una fascia colorata,
          // e la prima cosa che si leggeva era «Ricostruita e verificata».
          _Affidabilita(report: peggiore),
        ],
      ),
    );
  }
}

/// "Comincia fra 23 giorni": la data da sola fa fare il conto a mano.
class _ScheduledStrip extends StatelessWidget {
  const _ScheduledStrip({required this.notice, required this.now});

  final RawNotice notice;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final giorni = notice.daysUntilStart(now) ?? 0;
    final quando = switch (giorni) {
      1 => 'domani',
      2 => 'dopodomani',
      _ => 'fra $giorni giorni',
    };
    final d = notice.validFrom!;
    final data = '${_data(d)}/${d.year}';
    final blu = StatusColors.of(context).info;

    return Container(
      width: double.infinity,
      color: blu.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.event_outlined, size: 18, color: blu),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'In vigore dal $data · $quando',
              style: TextStyle(color: blu, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Affidabilita extends StatelessWidget {
  const _Affidabilita({required this.report});

  final DeviationReport report;

  @override
  Widget build(BuildContext context) {
    final colori = StatusColors.of(context);
    final secondario = Theme.of(context).colorScheme.onSurfaceVariant;
    final (
      Color colore,
      IconData icon,
      String label,
    ) = switch (report.confidence) {
      Confidence.confermata => (
        colori.ok,
        Icons.verified_outlined,
        'Verificato',
      ),
      Confidence.probabile => (
        colori.warning,
        Icons.help_outline,
        'Da confermare',
      ),
      Confidence.soloTesto => (
        secondario,
        Icons.article_outlined,
        'Solo il testo di GTT',
      ),
    };

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colore),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: colore,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (report.whyIncomplete != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      report.whyIncomplete!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: secondario),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkippedStops extends StatelessWidget {
  const _SkippedStops({required this.stops});

  final List<StopImpact> stops;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final piccolo = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    // «in linea d'aria» si dice una volta, sotto, e non a ogni riga: sulla
    // 10N era ripetuto tre volte per scheda, sedici schede.
    final tutteInLineaDAria = stops
        .expand((s) => s.alternatives)
        .every((a) => a.walkingMeters == null);
    final ciSonoAlternative = stops.any((s) => s.alternatives.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stops.length == 1
                ? '1 fermata non servita'
                : '${stops.length} fermate non servite',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: scheme.error),
          ),
          const SizedBox(height: 8),
          for (final s in stops) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.do_not_disturb_on_outlined,
                    size: 18,
                    color: scheme.error,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: DisplayNames.stop(s.stop),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            // Il numero sul palo: serve a riconoscerla.
                            if (s.stop.code != null)
                              TextSpan(
                                text: '  ${s.stop.code}',
                                style: piccolo,
                              ),
                          ],
                        ),
                      ),
                      if (s.status == StopStatus.declaredSuspended)
                        Text('sospesa da GTT', style: piccolo),
                      for (final alt in s.alternatives)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.directions_walk, size: 15),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  // Il numero sul palo: due pali della
                                  // stessa piazza hanno lo stesso nome, e
                                  // «Largo Giachino Sud» aperta accanto a
                                  // «Largo Giachino Sud» chiusa confonde.
                                  '${DisplayNames.stop(alt.stop)}'
                                  '${alt.stop.code == null ? "" : " ${alt.stop.code}"} · '
                                  '${alt.bestKnownMeters.round()} m'
                                  '${tutteInLineaDAria
                                      ? ""
                                      : alt.walkingMeters != null
                                      ? " a piedi"
                                      : " in linea d'aria"}'
                                  '${alt.sameLine ? "" : " · altre linee"}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (s.alternatives.isEmpty)
                        Text(
                          'nessuna fermata aperta entro 400 m',
                          style: piccolo,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (ciSonoAlternative && tutteInLineaDAria)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('Distanze in linea d\'aria.', style: piccolo),
            ),
        ],
      ),
    );
  }
}

/// Il testo di GTT, richiudibile quando e' lungo.
///
/// Gli avvisi di GTT arrivano a venti righe — quello della 68 descrive
/// due direzioni, la viabilita' di cantiere e la causa — e con quattro
/// avvisi su una linea la schermata diventa un rotolo in cui il resto
/// (le fermate saltate, la mappa) sparisce.
///
/// Si richiude solo quello lungo: un pulsante sotto un avviso di due
/// righe e' rumore, e nasconde una cosa che si leggeva in un colpo
/// d'occhio.
class _OriginalText extends StatefulWidget {
  const _OriginalText({required this.report});

  final DeviationReport report;

  /// Oltre questa lunghezza il testo si richiude. Tarata sui testi veri:
  /// gli avvisi brevi di GTT ("Fermata 3447 Sabotino sospesa") stanno
  /// sotto i 200 caratteri, quelli che descrivono un percorso li superano
  /// sempre.
  static const _sogliaCaratteri = 240;

  @override
  State<_OriginalText> createState() => _OriginalTextState();
}

class _OriginalTextState extends State<_OriginalText> {
  bool _espanso = false;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final n = report.notice;
    final piccolo = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    // I testi del feed hanno doppi spazi a caso («non transita  alla
    // fermata  422»): si tolgono, le parole restano quelle di GTT.
    final corpo = n.text.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
    final lungo = corpo.length > _OriginalText._sogliaCaratteri;
    final chiuso = lungo && !_espanso;
    final motivo = DisplayNames.reason(n.reason);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Testo originale',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          if (n.headline != null && n.headline!.isNotEmpty)
            Text(
              n.headline!,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          // Chiuso si vedono quattro righe sfumate in fondo: si capisce
          // che continua senza doverlo scrivere.
          //
          // La sfumatura e' una maschera (dstIn: conta solo l'opacita'),
          // non un colore. Prima il gradiente era nero e si fondeva col
          // testo: in chiaro non si notava, in modalita' scura il testo
          // diventava nero su fondo scuro, cioe' illeggibile.
          if (chiuso)
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white,
                  Colors.white,
                  Colors.white.withValues(alpha: 0.06),
                ],
                stops: const [0, 0.62, 1],
              ).createShader(r),
              child: Text(corpo, maxLines: 4, overflow: TextOverflow.clip),
            )
          else
            Text(corpo),
          if (lungo)
            Align(
              alignment: Alignment.centerLeft,
              // L'area di tocco resta alta 44 punti anche se la scritta e'
              // piccola: prima era stretta attorno al testo, venti punti.
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  minimumSize: const Size(64, 44),
                ),
                onPressed: () => setState(() => _espanso = !_espanso),
                child: Text(chiuso ? 'Leggi tutto' : 'Mostra meno'),
              ),
            ),
          // Quando GTT pubblica la stessa variazione in due posti se ne
          // mostra una sola, ed e' giusto dire perche': chi confronta con
          // il sito deve capire da dove vengono le date.
          if (n.isMerged)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Pubblicato da GTT in due versioni: qui la più completa.',
                style: piccolo,
              ),
            ),
          // Il codice del feed («OTHER_CAUSE») si traduce, e «altra causa»
          // non si mostra: una riga per dire che non si sa.
          if (motivo != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Motivo: $motivo', style: piccolo),
            ),
          if (n.validUntil != null)
            Text(
              'Fino al ${_data(n.validUntil!)}/${n.validUntil!.year}',
              style: piccolo,
            )
          else
            Text('Fine non indicata', style: piccolo),
        ],
      ),
    );
  }
}
