import 'package:flutter/material.dart';

import '../core/models/tragitto.dart';
import '../core/models/transit.dart';
import '../core/pipeline/line_search.dart';
import '../core/pipeline/stop_search.dart';
import '../core/text/display_names.dart';
import '../data/app_repository.dart';
import 'line_badge.dart';

/// Crea o modifica un tragitto: un nome e da una a quattro tratte.
///
/// Ogni tratta si sceglie a passi (linea, direzione, dove sali, dove
/// scendi) in [SceltaTratta]: qui si vedono in fila, come le si fa.
class EditorTragitto extends StatefulWidget {
  const EditorTragitto({required this.repo, this.tragitto, super.key});

  final AppRepository repo;

  /// Quello da modificare; null per uno nuovo.
  final Tragitto? tragitto;

  @override
  State<EditorTragitto> createState() => _EditorTragittoState();
}

class _EditorTragittoState extends State<EditorTragitto> {
  late final _nome = TextEditingController(text: widget.tragitto?.nome ?? '');
  late final List<Tratta> _tratte = [...?widget.tragitto?.tratte];

  /// I percorsi gia' letti, per mostrare i nomi delle fermate scelte.
  final Map<String, List<RouteShape>> _percorsi = {};
  var _salvando = false;

  @override
  void initState() {
    super.initState();
    for (final r in {for (final t in _tratte) t.routeId}) {
      _leggi(r);
    }
  }

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  Future<void> _leggi(String routeId) async {
    final p = await widget.repo.percorsiPrincipali(routeId);
    if (!mounted || p == null) return;
    setState(() => _percorsi[routeId] = p);
  }

  Future<void> _aggiungi() async {
    final prima = _tratte.isEmpty ? null : _tratte.last;
    final t =
        await Navigator.push<({Tratta tratta, List<RouteShape> percorsi})>(
          context,
          MaterialPageRoute(
            builder: (_) => SceltaTratta(
              repo: widget.repo,
              dopo: prima == null ? null : _fermata(prima, salita: false),
              lineaPrima: prima?.routeId,
            ),
          ),
        );
    if (t == null || !mounted) return;
    setState(() {
      _tratte.add(t.tratta);
      _percorsi[t.tratta.routeId] = t.percorsi;
    });
  }

  TransitStop? _fermata(Tratta t, {required bool salita}) {
    final id = salita ? t.salitaId : t.discesaId;
    for (final s in _percorsi[t.routeId] ?? const <RouteShape>[]) {
      if (s.directionId != t.directionId) continue;
      for (final f in s.stops) {
        if (f.id == id) return f;
      }
    }
    return null;
  }

  /// Il nome proposto se non se ne scrive uno: da dove a dove.
  String _nomeDi(List<Tratta> tratte) {
    final da = _fermata(tratte.first, salita: true);
    final a = _fermata(tratte.last, salita: false);
    if (da == null || a == null) return 'Il mio tragitto';
    return '${DisplayNames.stop(da)} – ${DisplayNames.stop(a)}';
  }

  Future<void> _salva() async {
    if (_tratte.isEmpty || _salvando) return;
    setState(() => _salvando = true);
    final nome = _nome.text.trim();
    // Un nome proposto da noi segue le fermate: cambiata la discesa,
    // «Sabotino – Regina Margherita» non direbbe piu' il vero.
    final vecchio = widget.tragitto;
    final proposto = vecchio != null && nome == _nomeDi(vecchio.tratte);
    final t = Tragitto(
      id:
          widget.tragitto?.id ??
          DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      nome: nome.isEmpty || proposto ? _nomeDi(_tratte) : nome,
      tratte: List.unmodifiable(_tratte),
    );
    // Si chiude subito: le linee nuove si scaricano dopo, e la scheda in
    // home dice «Aggiornamento…» intanto.
    final salvato = widget.repo.salvaTragitto(t);
    Navigator.pop(context);
    await salvato;
  }

  @override
  Widget build(BuildContext context) {
    final perId = {for (final l in widget.repo.allLines) l.routeId: l};
    final testo = Theme.of(context).textTheme;
    final tenue = Theme.of(context).colorScheme.onSurfaceVariant;
    final pieno = _tratte.length >= Tragitto.maxTratte;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.tragitto == null ? 'Nuovo tragitto' : 'Modifica tragitto',
        ),
        actions: [
          TextButton(
            onPressed: _tratte.isEmpty || _salvando ? null : _salva,
            child: const Text('Salva'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _nome,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nome',
              hintText: 'Per esempio: casa – lavoro',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_tratte.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Aggiungi la prima linea che prendi. Se cambi, aggiungi '
                'dopo le altre, nell\'ordine del viaggio.',
                style: testo.bodyMedium?.copyWith(color: tenue),
              ),
            ),
          for (final (i, t) in _tratte.indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
                child: Row(
                  children: [
                    Icon(Icons.transfer_within_a_station, color: tenue),
                    const SizedBox(width: 8),
                    Text('Cambio', style: testo.labelLarge),
                  ],
                ),
              ),
            _RigaTratta(
              linea: perId[t.routeId],
              salita: _fermata(t, salita: true),
              discesa: _fermata(t, salita: false),
              // Si toglie solo l'ultima: in mezzo romperebbe la catena
              // dei cambi.
              onRimuovi: i == _tratte.length - 1
                  ? () => setState(() => _tratte.removeLast())
                  : null,
            ),
          ],
          const SizedBox(height: 12),
          if (pieno)
            Text(
              'Al massimo ${Tragitto.maxTratte} linee per tragitto.',
              style: testo.bodyMedium?.copyWith(color: tenue),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _aggiungi,
                icon: const Icon(Icons.add),
                label: Text(
                  _tratte.isEmpty ? 'Aggiungi una linea' : 'Aggiungi un cambio',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RigaTratta extends StatelessWidget {
  const _RigaTratta({
    required this.linea,
    required this.salita,
    required this.discesa,
    required this.onRimuovi,
  });

  final TransitLine? linea;
  final TransitStop? salita;
  final TransitStop? discesa;
  final VoidCallback? onRimuovi;

  @override
  Widget build(BuildContext context) {
    String nome(TransitStop? s) => s == null ? '…' : DisplayNames.stop(s);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: [
            if (linea != null) LineBadge(line: linea!, height: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sali a ${nome(salita)}'),
                  Text('Scendi a ${nome(discesa)}'),
                ],
              ),
            ),
            if (onRimuovi != null)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Rimuovi questa linea',
                onPressed: onRimuovi,
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// Sceglie una tratta, un passo alla volta: la linea, la direzione, dove
/// sali, dove scendi. Torna la tratta e i percorsi della linea.
///
/// Dopo un cambio ([dopo] e' dove si e' scesi) in cima ci sono le linee
/// che passano di li' o a due passi, e le fermate piu' vicine.
class SceltaTratta extends StatefulWidget {
  const SceltaTratta({
    required this.repo,
    this.dopo,
    this.lineaPrima,
    super.key,
  });

  final AppRepository repo;
  final TransitStop? dopo;

  /// La linea da cui si scende: al cambio non si propone.
  final String? lineaPrima;

  /// Fin dove si cammina, a un cambio, per proporre una fermata.
  static const vicino = 300.0;

  @override
  State<SceltaTratta> createState() => _SceltaTrattaState();
}

class _SceltaTrattaState extends State<SceltaTratta> {
  final _cerca = TextEditingController();

  TransitLine? _linea;
  List<RouteShape>? _percorsi;
  var _errore = false;
  RouteShape? _verso;
  int? _salita;

  @override
  void initState() {
    super.initState();
    // Dopo il primo disegno: il caricamento avvisa chi ascolta il
    // repository, e durante la costruzione non si puo'.
    if (widget.dopo != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.repo.caricaFermate(),
      );
    }
  }

  @override
  void dispose() {
    _cerca.dispose();
    super.dispose();
  }

  void _indietro() => setState(() {
    _cerca.clear();
    if (_salita != null) {
      _salita = null;
    } else if (_verso != null) {
      _verso = null;
    } else {
      _linea = null;
      _percorsi = null;
      _errore = false;
    }
  });

  Future<void> _scegliLinea(TransitLine l) async {
    setState(() {
      _cerca.clear();
      _linea = l;
      _percorsi = null;
      _errore = false;
    });
    final p = await widget.repo.percorsiPrincipali(l.routeId);
    if (!mounted || _linea != l) return;
    setState(() {
      _percorsi = p;
      _errore = p == null || p.isEmpty;
      // Una linea che va in un senso solo (un giro): la direzione e'
      // gia' scelta.
      if (p != null && p.length == 1) _verso = p.single;
    });
  }

  void _scegliDiscesa(int i) {
    final v = _verso!;
    final sali = v.stops[_salita!], scendi = v.stops[i];
    Navigator.pop(context, (
      tratta: Tratta(
        routeId: v.routeId,
        directionId: v.directionId,
        salitaId: sali.id,
        salitaCodice: sali.code,
        discesaId: scendi.id,
        discesaCodice: scendi.code,
      ),
      percorsi: _percorsi!,
    ));
  }

  String get _titolo {
    if (_linea == null) return 'Che linea prendi?';
    if (_verso == null) return 'In che direzione?';
    if (_salita == null) return 'Dove sali?';
    return 'Dove scendi?';
  }

  @override
  Widget build(BuildContext context) {
    final inizio = _linea == null;
    return PopScope(
      canPop: inizio,
      onPopInvokedWithResult: (fatto, _) {
        if (!fatto) _indietro();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titolo),
          leading: inizio ? null : BackButton(onPressed: _indietro),
        ),
        body: _linea == null
            ? _scegliLaLinea()
            : _percorsi == null && !_errore
            ? const Center(child: CircularProgressIndicator())
            : _errore
            ? _senzaPercorsi()
            : _verso == null
            ? _scegliIlVerso()
            : _scegliLaFermata(),
      ),
    );
  }

  Widget _campo(String suggerimento) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: TextField(
      controller: _cerca,
      autocorrect: false,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: suggerimento,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _cerca.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancella',
                onPressed: () => setState(_cerca.clear),
              ),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    ),
  );

  Widget _titoletto(String testo) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(testo, style: Theme.of(context).textTheme.titleSmall),
  );

  // ----------------------------------------------------------- la linea

  /// Le linee che passano da dove si e' scesi, poi quelle a due passi,
  /// ciascun gruppo nell'ordine di GTT. Non quella da cui si scende.
  List<TransitLine> _daQui() {
    final dopo = widget.dopo, rete = widget.repo.fermateRete;
    if (dopo == null || rete == null) return const [];
    final da = dopo.position.meters;
    final qui = <String>{}, vicino = <String>{};
    for (final f in rete.fermate) {
      final stessa = f.stop.id == dopo.id;
      if (!stessa &&
          da.distanceTo(f.stop.position.meters) > SceltaTratta.vicino) {
        continue;
      }
      for (final p in f.passaggi) {
        (stessa ? qui : vicino).add(p.routeId);
      }
    }
    final perId = {for (final l in widget.repo.allLines) l.routeId: l};
    List<TransitLine> ordina(Iterable<String> ids) => [
      for (final id in ids)
        if (id != widget.lineaPrima) ?perId[id],
    ]..sort(TransitLine.compare);
    return [...ordina(qui), ...ordina(vicino.difference(qui))];
  }

  Widget _scegliLaLinea() {
    final repo = widget.repo;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final q = _cerca.text.trim();
        final daQui = q.isEmpty ? _daQui() : const <TransitLine>[];
        // Alla prima tratta, le linee che segui gia': di solito e' una di
        // quelle.
        final tue = q.isEmpty && widget.dopo == null
            ? repo.lines
            : const <TransitLine>[];
        final tutte = LineSearch.filter(repo.allLines, q);
        return Column(
          children: [
            _campo('Numero della linea o via'),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (daQui.isNotEmpty) ...[
                    _titoletto(
                      'Passano da ${DisplayNames.stop(widget.dopo!)} o vicino',
                    ),
                    for (final l in daQui) _rigaLinea(l),
                    _titoletto('Tutte le linee'),
                  ] else if (tue.isNotEmpty) ...[
                    _titoletto('Le tue linee'),
                    for (final l in tue) _rigaLinea(l),
                    _titoletto('Tutte le linee'),
                  ],
                  for (final l in tutte) _rigaLinea(l),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _rigaLinea(TransitLine l) {
    final parti = DisplayNames.routeParts(l.longName ?? '');
    return ListTile(
      leading: SizedBox(
        width: 60,
        child: Align(
          alignment: Alignment.centerLeft,
          child: LineBadge(line: l, height: 32),
        ),
      ),
      title: Text(parti.route, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => _scegliLinea(l),
    );
  }

  Widget _senzaPercorsi() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        const Text(
          'Impossibile caricare le fermate della linea. Controlla la '
          'connessione e riprova.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => _scegliLinea(_linea!),
          child: const Text('Riprova'),
        ),
      ],
    ),
  );

  // ------------------------------------------------------- la direzione

  Widget _scegliIlVerso() {
    final l = _linea!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            LineBadge(line: l, height: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                DisplayNames.routeParts(l.longName ?? '').route,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final p in _percorsi!)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
              title: Text(
                'verso ${DisplayNames.direction(p.headsign, longName: l.longName)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: p.stops.isEmpty
                  ? null
                  : Text(
                      'da ${DisplayNames.stop(p.stops.first)}, '
                      '${p.stops.length} fermate',
                    ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => _verso = p),
            ),
          ),
      ],
    );
  }

  // --------------------------------------------------------- le fermate

  Widget _scegliLaFermata() {
    final v = _verso!;
    final sali = _salita == null;
    final scheme = Theme.of(context).colorScheme;
    final q = StopSearch.norm(_cerca.text);
    bool passa(TransitStop s) =>
        q.isEmpty ||
        (s.code ?? '').startsWith(q) ||
        StopSearch.norm(DisplayNames.stop(s)).contains(q);

    // Dove si scende sta dopo dove si sale.
    final da = sali ? 0 : _salita! + 1;
    final indici = [
      for (var i = da; i < v.stops.length; i++)
        if (passa(v.stops[i])) i,
    ];

    // Dopo un cambio, le fermate a due passi da dove si e' scesi.
    final dopo = widget.dopo;
    final vicine = !sali || dopo == null || q.isNotEmpty
        ? const <({int i, double m})>[]
        : ([
              for (var i = 0; i < v.stops.length - 1; i++)
                (
                  i: i,
                  m: v.stops[i].id == dopo.id
                      ? 0.0
                      : dopo.position.meters.distanceTo(
                          v.stops[i].position.meters,
                        ),
                ),
            ].where((x) => x.m <= SceltaTratta.vicino).toList()
            ..sort((a, b) => a.m.compareTo(b.m)));

    Widget riga(int i, {double? metri}) {
      final s = v.stops[i];
      return ListTile(
        leading: Icon(
          sali ? Icons.login : Icons.logout,
          color: scheme.onSurfaceVariant,
        ),
        title: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: DisplayNames.stop(s)),
              if (s.code != null)
                TextSpan(
                  text: '  ${s.code}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        subtitle: metri == null
            ? null
            : Text(
                metri < 1
                    ? 'La fermata dove scendi'
                    : '${metri.round()} m da dove scendi, in linea d\'aria',
              ),
        onTap: () => sali
            ? setState(() {
                _cerca.clear();
                _salita = i;
              })
            : _scegliDiscesa(i),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              LineBadge(line: _linea!, height: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  sali
                      ? 'verso ${DisplayNames.direction(v.headsign, longName: _linea!.longName)}'
                      : 'Sali a ${DisplayNames.stop(v.stops[_salita!])}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        _campo('Nome o numero della fermata'),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (vicine.isNotEmpty) ...[
                _titoletto('Vicino a dove scendi'),
                for (final x in vicine) riga(x.i, metri: x.m),
                _titoletto('Tutte le fermate'),
              ],
              // Si sale prima del capolinea, si scende dopo la salita.
              for (final i in indici)
                if (!sali || i < v.stops.length - 1) riga(i),
              if (indici.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Nessuna fermata per «${_cerca.text.trim()}»',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
