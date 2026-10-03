import 'package:flutter/material.dart';

import '../core/models/transit.dart';
import '../core/pipeline/line_search.dart';
import '../core/pipeline/stop_search.dart';
import '../core/text/display_names.dart';
import '../core/models/saved_stop.dart';
import '../data/app_repository.dart';
import 'line_badge.dart';
import 'theme.dart';

/// Apre la ricerca delle linee, sopra la schermata da cui la si chiama.
///
/// Un foglio e non una pagina: si aggiunge una linea e si torna dove si
/// era, senza passare dalle impostazioni come prima.
Future<void> showLinePicker(BuildContext context, AppRepository repo) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: LinePicker(repo: repo),
      ),
    );

/// Cerca fra tutte le linee di GTT, per numero o per via, e fra le
/// fermate, per nome o numero di palina.
///
/// Le fermate dal 03/10/2026: chi aspetta ha davanti il cartello, con il
/// nome e il numero, e sa raramente da che capolinea a che capolinea va
/// la sua linea. Toccandone una si sceglie linea e direzione, e la fermata
/// finisce salvata in home, con la linea se mancava.
class LinePicker extends StatefulWidget {
  const LinePicker({required this.repo, super.key});

  final AppRepository repo;

  @override
  State<LinePicker> createState() => _LinePickerState();
}

class _LinePickerState extends State<LinePicker> {
  final _query = TextEditingController();

  /// La fermata toccata: al posto dei risultati, le sue linee.
  FermataCercabile? _fermata;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _cambiata(String testo) {
    // Le fermate si scaricano alla prima lettera, non all'apertura: chi
    // aggiunge una linea dall'elenco non ne ha bisogno.
    if (testo.trim().isNotEmpty) widget.repo.caricaFermate();
    setState(() {});
  }

  Future<void> _salva(FermataCercabile f, String routeId, int dir) async {
    final messenger = ScaffoldMessenger.of(context);
    final nome = DisplayNames.stop(f.stop);
    Navigator.pop(context);
    final ok = await widget.repo.salvaFermataCercata(f.stop, routeId, dir);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '$nome salvata nelle tue fermate'
              : 'Impossibile salvare la fermata. Controlla la connessione '
                    'e riprova.',
        ),
      ),
    );
  }

  void _add(TransitLine line) {
    // Il messaggio si prende prima di chiudere il foglio: dopo, questo
    // contesto non c'e' piu'.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    widget.repo.addLine(line);
    messenger.showSnackBar(
      SnackBar(content: Text('Linea ${line.shortName} aggiunta')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final f = _fermata;
    if (f != null) {
      // Indietro, anche col gesto o col tasto del telefono, torna ai
      // risultati e non chiude il foglio.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (fatto, _) {
          if (!fatto) setState(() => _fermata = null);
        },
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: ListenableBuilder(
            listenable: widget.repo,
            builder: (context, _) => _lineeDellaFermata(context, f),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              onChanged: _cambiata,
              decoration: InputDecoration(
                hintText: 'Linea, via, fermata o numero di palina',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Cancella',
                        onPressed: () => setState(_query.clear),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.repo,
              builder: (context, _) => _risultati(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _risultati(BuildContext context) {
    final repo = widget.repo;
    final testo = Theme.of(context).textTheme;
    final secondario = Theme.of(context).colorScheme.onSurfaceVariant;

    if (repo.allLines.isEmpty) {
      // Al primo avvio l'elenco arriva dalla rete: qualche decina di KB.
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (repo.catalogError == null) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Caricamento delle linee…',
                textAlign: TextAlign.center,
                style: testo.bodyMedium,
              ),
            ] else ...[
              Text(
                'Impossibile caricare l\'elenco delle linee. '
                '${repo.catalogError}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: repo.retryCatalog,
                child: const Text('Riprova'),
              ),
            ],
          ],
        ),
      );
    }

    final gia = {for (final l in repo.lines) l.routeId};
    final trovate = LineSearch.filter(repo.allLines, _query.text);
    final cercando = _query.text.trim().isNotEmpty;
    final fermate = cercando && repo.fermateRete != null
        ? StopSearch.filter(repo.fermateRete!, _query.text)
        : const <FermataCercabile>[];
    final attesaFermate =
        cercando && repo.fermateRete == null && repo.caricandoFermate;
    final erroreFermate = cercando && repo.fermateRete == null
        ? repo.erroreFermate
        : null;
    if (trovate.isEmpty &&
        fermate.isEmpty &&
        !attesaFermate &&
        erroreFermate == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Nessun risultato per «${_query.text.trim()}»',
          textAlign: TextAlign.center,
          style: testo.bodyMedium?.copyWith(color: secondario),
        ),
      );
    }

    // Senza ricerca l'elenco intero, diviso per mezzo: 216 righe di fila
    // non si scorrono, e chi cerca un tram sa gia' che lo e'.
    final righe = <Widget>[];
    if (_query.text.trim().isEmpty) {
      for (final (titolo, gruppo) in [
        ('Tram', trovate.where((l) => l.isTram)),
        ('Bus', trovate.where((l) => l.routeType == 3)),
        ('Altre linee', trovate.where((l) => !l.isTram && l.routeType != 3)),
      ]) {
        if (gruppo.isEmpty) continue;
        righe.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(titolo, style: testo.titleSmall),
          ),
        );
        righe.addAll(gruppo.map((l) => _riga(l, gia.contains(l.routeId))));
      }
    } else {
      // Due gruppi, Linee e Fermate. Con un numero prima le linee («15» e'
      // quasi sempre la linea 15), con delle parole prima le fermate.
      final linee = [
        if (trovate.isNotEmpty) ...[
          _titolo('Linee'),
          ...trovate.map((l) => _riga(l, gia.contains(l.routeId))),
        ],
      ];
      final soloFermate = [
        if (fermate.isNotEmpty || attesaFermate || erroreFermate != null)
          _titolo('Fermate'),
        if (attesaFermate)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: LinearProgressIndicator(),
          ),
        if (erroreFermate != null)
          ListTile(
            title: Text(erroreFermate),
            trailing: TextButton(
              onPressed: () => repo.caricaFermate(forza: true),
              child: const Text('Riprova'),
            ),
          ),
        ...fermate.map(_rigaFermata),
      ];
      final numero = RegExp(r'^\s*\d').hasMatch(_query.text);
      righe.addAll(
        numero ? [...linee, ...soloFermate] : [...soloFermate, ...linee],
      );
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      children: righe,
    );
  }

  Widget _titolo(String testo) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(testo, style: Theme.of(context).textTheme.titleSmall),
  );

  /// Una fermata fra i risultati: nome, numero di palina e le linee che
  /// ci passano.
  Widget _rigaFermata(FermataCercabile f) {
    final scheme = Theme.of(context).colorScheme;
    final perId = {for (final l in widget.repo.allLines) l.routeId: l};
    final linee = <TransitLine>[
      for (final id in {for (final p in f.passaggi) p.routeId}) ?perId[id],
    ];
    return ListTile(
      leading: SizedBox(
        width: 60,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Icon(Icons.signpost_outlined, color: scheme.onSurfaceVariant),
        ),
      ),
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: DisplayNames.stop(f.stop)),
            if (f.stop.code != null)
              TextSpan(
                text: '  ${f.stop.code}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
      subtitle: linee.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final l in linee) LineBadge(line: l, height: 22),
                ],
              ),
            ),
      trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
      onTap: () => setState(() => _fermata = f),
    );
  }

  /// Le linee di una fermata, una riga per direzione: si sceglie quella
  /// che si prende e la fermata si salva.
  Widget _lineeDellaFermata(BuildContext context, FermataCercabile f) {
    final repo = widget.repo;
    final testo = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final perId = {for (final l in repo.allLines) l.routeId: l};
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 16, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Indietro',
                onPressed: () => setState(() => _fermata = null),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: DisplayNames.stop(f.stop),
                        style: testo.titleLarge,
                      ),
                      if (f.stop.code != null)
                        TextSpan(
                          text: '  ${f.stop.code}',
                          style: testo.titleMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Quale linea prendi? La fermata si salva nella home, con la '
            'sua risposta.',
            style: testo.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        for (final p in f.passaggi)
          if (perId[p.routeId] case final l?)
            _rigaPassaggio(f, l, p.directionId),
      ],
    );
  }

  Widget _rigaPassaggio(FermataCercabile f, TransitLine l, int dir) {
    final repo = widget.repo;
    final scheme = Theme.of(context).colorScheme;
    final capolinea = repo.fermateRete?.capolineaDi(l.routeId, dir);
    final salvata = repo.isSaved(
      SavedStop(routeId: l.routeId, directionId: dir, stopId: f.stop.id),
    );
    return ListTile(
      leading: SizedBox(
        width: 60,
        child: Align(
          alignment: Alignment.centerLeft,
          child: LineBadge(line: l, height: 32),
        ),
      ),
      title: Text(
        capolinea == null
            ? 'Linea ${l.shortName}'
            : 'verso ${DisplayNames.direction(capolinea, longName: l.longName)}',
      ),
      trailing: salvata
          ? Semantics(
              label: 'Già fra le tue fermate',
              child: Icon(Icons.check, color: StatusColors.of(context).ok),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bookmark_add_outlined, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Salva',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
      onTap: salvata ? null : () => _salva(f, l.routeId, dir),
    );
  }

  Widget _riga(TransitLine line, bool aggiunta) {
    final parti = DisplayNames.routeParts(line.longName ?? '');
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: SizedBox(
        width: 60,
        child: Align(
          alignment: Alignment.centerLeft,
          child: LineBadge(line: line, height: 32),
        ),
      ),
      title: Text(parti.route, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: parti.qualifier == null
          ? null
          : Text(
              parti.qualifier!,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
      trailing: aggiunta
          ? Semantics(
              label: 'Già fra le tue linee',
              child: Icon(Icons.check, color: StatusColors.of(context).ok),
            )
          : Icon(Icons.add, color: scheme.primary),
      onTap: aggiunta ? null : () => _add(line),
    );
  }
}
