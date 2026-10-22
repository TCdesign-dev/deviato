import 'package:flutter/material.dart';

import '../core/models/transit.dart';
import '../core/pipeline/line_search.dart';
import '../core/pipeline/stop_search.dart';
import '../core/text/display_names.dart';
import '../data/app_repository.dart';
import 'line_badge.dart';
import 'scanner_fermata.dart';
import 'stop_screen.dart';
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

  /// Chiude la ricerca, inquadra il QR e apre la fermata letta.
  Future<void> _scansiona() async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = widget.repo;
    nav.pop();
    final palina = await nav.push<String>(
      MaterialPageRoute(builder: (_) => const ScannerFermata()),
    );
    if (palina == null) return;
    await repo.caricaFermate(forza: repo.fermateRete == null);
    final trovate = [
      for (final f in repo.fermateRete?.fermate ?? const <FermataCercabile>[])
        if (f.stop.code == palina) f,
    ];
    if (trovate.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            repo.fermateRete == null
                ? 'Impossibile caricare le fermate. Controlla la '
                      'connessione e riprova.'
                : 'La fermata $palina non risulta fra quelle di GTT. '
                      'Prova a cercarla per nome.',
          ),
        ),
      );
      return;
    }
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => StopScreen(repo: repo, fermata: trovate.first),
      ),
    );
  }

  /// Apre la fermata, chiudendo la ricerca.
  void _apri(FermataCercabile f) {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => StopScreen(repo: widget.repo, fermata: f),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
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
          // Il QR sulla palina: alla fermata e' il modo piu' rapido, e non
          // serve sapere come si chiama.
          if (_query.text.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _scansiona,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Inquadra il QR della fermata'),
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
      onTap: () => _apri(f),
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
