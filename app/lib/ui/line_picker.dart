import 'package:flutter/material.dart';

import '../core/models/transit.dart';
import '../core/pipeline/line_search.dart';
import '../core/text/display_names.dart';
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

/// Cerca fra tutte le linee di GTT, per numero o per via.
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
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Cerca per numero o via',
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
    if (trovate.isEmpty) {
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
      righe.addAll(trovate.map((l) => _riga(l, gia.contains(l.routeId))));
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      children: righe,
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
