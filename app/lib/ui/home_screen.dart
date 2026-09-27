import 'package:flutter/material.dart';

import '../core/models/saved_stop.dart';
import '../core/models/transit.dart';
import '../data/app_repository.dart';
import 'line_picker.dart';
import 'line_screen.dart';
import 'line_tile.dart';
import 'logo.dart';
import 'saved_stop_card.dart';
import 'info_screen.dart';

/// La home: le fermate che usi, e sotto le linee.
///
/// Si risponde guardando, prima di uscire di casa. Le fermate salvate
/// stanno in cima perche' rispondono alla domanda vera — la MIA fermata
/// e' servita? — mentre una linea dice solo quante ne salta. Le linee si
/// aggiungono da qui, con «+», e si tolgono scorrendo: prima si passava
/// dalle impostazioni, scrivendo il nome a memoria.
class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.repo, super.key});

  final AppRepository repo;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const DeviatoLogo(),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Aggiungi una linea',
                onPressed: () => showLinePicker(context, repo),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Informazioni',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => InfoScreen(repo: repo),
                  ),
                ),
              ),
            ],
          ),
          body: _body(context),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    // `idle` significa che il caricamento non e' ancora partito. Con una
    // watchlist da caricare va mostrato l'avanzamento: altrimenti nei
    // primi istanti la schermata resta bianca senza spiegazioni.
    if (repo.state == LoadState.loading ||
        (repo.state == LoadState.idle && repo.settings.watchlist.isNotEmpty)) {
      return const _Loading();
    }
    if (repo.state == LoadState.error) {
      return _Message(
        icon: Icons.cloud_off,
        title: 'Impossibile caricare le linee',
        detail: repo.error ?? '',
        action: FilledButton(
          onPressed: repo.initialise,
          child: const Text('Riprova'),
        ),
      );
    }

    final lines = repo.lines;
    if (lines.isEmpty) {
      return _Message(
        icon: Icons.directions_bus_outlined,
        title: 'Aggiungi le tue linee',
        detail:
            'Cercale per numero o per via: vedrai subito se sono '
            'deviate.',
        action: FilledButton.icon(
          onPressed: () => showLinePicker(context, repo),
          icon: const Icon(Icons.add),
          label: const Text('Aggiungi una linea'),
        ),
      );
    }

    final byId = {for (final l in lines) l.routeId: l};
    final fermate = [
      for (final s in repo.savedStops)
        if (byId.containsKey(s.routeId)) s,
    ];

    return RefreshIndicator(
      onRefresh: repo.refreshAll,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (repo.error != null)
            _ErrorBanner(message: repo.error!, onClose: repo.clearError),

          if (fermate.isNotEmpty) ...[
            const _SectionTitle('Le tue fermate'),
            for (var i = 0; i < fermate.length; i++)
              _fermata(context, fermate[i], byId[fermate[i].routeId]!, i),
          ] else if (!repo.settings.stopsHintSeen)
            _StopsHint(onClose: repo.dismissStopsHint),

          _LinesHeader(
            lastCheck: _ultimoControllo(lines),
            refreshing: repo.isRefreshingAll,
            failed: repo.offline,
            onRefreshAll: repo.refreshAll,
          ),
          for (final line in lines) _linea(context, line),
          ListTile(
            leading: SizedBox(
              width: 60,
              child: Icon(
                Icons.add,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text(
              'Aggiungi una linea',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            onTap: () => showLinePicker(context, repo),
          ),
        ],
      ),
    );
  }

  /// Il controllo piu' recente fra le linee: quello che dice quanto e'
  /// fresca la lista. Le righe vecchie dicono da sole di quando sono.
  DateTime? _ultimoControllo(List<TransitLine> lines) {
    DateTime? ultimo;
    for (final l in lines) {
      final t = repo.checkedAt(l.routeId);
      if (t != null && (ultimo == null || t.isAfter(ultimo))) ultimo = t;
    }
    return ultimo;
  }

  void _apri(BuildContext context, TransitLine line, {String? stopId}) {
    // Un «Annulla» della home non ha senso nel dettaglio: seguirebbe
    // l'utente in un'altra schermata, sopra la mappa.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            LineScreen(repo: repo, line: line, initialStopId: stopId),
      ),
    );
  }

  Widget _fermata(
    BuildContext context,
    SavedStop s,
    TransitLine line,
    int posizione,
  ) {
    final risposta = repo.answerFor(s);
    if (risposta == null) return const SizedBox.shrink();
    return Dismissible(
      key: ValueKey('fermata-$s'),
      direction: DismissDirection.endToStart,
      background: const _SwipeBackground(label: 'Rimuovi'),
      onDismissed: (_) {
        repo.unsaveStop(s);
        _conAnnulla(
          context,
          'Fermata rimossa',
          () => repo.restoreSavedStop(s, posizione),
        );
      },
      child: SavedStopCard(
        answer: risposta,
        line: line,
        checking: repo.isChecking(line.routeId),
        // Mai controllata: toccarla la controlla, come una riga della
        // lista. Altrimenti apre la linea, con la fermata gia' scelta.
        onTap: repo.statusOf(line.routeId) == null
            ? () => repo.refreshLine(line)
            : () => _apri(context, line, stopId: s.stopId),
      ),
    );
  }

  Widget _linea(BuildContext context, TransitLine line) {
    final preparing = repo.isPreparing(line.routeId);
    final checking = repo.isChecking(line.routeId);
    final tile = LineTile(
      line: line,
      status: repo.statusOf(line.routeId),
      checking: checking,
      preparing: preparing,
      watching: repo.isWatching(line.routeId),
      watchedVehicles: repo.liveTracks.length,
      checkedAt: repo.checkedAt(line.routeId),
      // Una riga mai controllata non ha niente da aprire: toccarla la
      // controlla. Prima non succedeva nulla, e una riga che sembra
      // toccabile e non risponde sembra rotta.
      onTap: preparing
          ? null
          : repo.statusOf(line.routeId) == null
          ? () => repo.refreshLine(line)
          : () => _apri(context, line),
    );
    // Non si toglie una linea mentre la si prepara o la si controlla: il
    // controllo finirebbe su una riga che non c'e' piu'.
    if (preparing || checking) return tile;
    return Dismissible(
      key: ValueKey('linea-${line.routeId}'),
      direction: DismissDirection.endToStart,
      background: const _SwipeBackground(label: 'Rimuovi'),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final lettore = MediaQuery.accessibleNavigationOf(context);
        final tolta = await repo.removeLine(line);
        final fermate = tolta.savedStops.length;
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            _annullabile(
              switch (fermate) {
                0 => 'Linea ${line.shortName} rimossa',
                1 => 'Linea ${line.shortName} rimossa con la sua fermata',
                _ =>
                  'Linea ${line.shortName} rimossa con le sue $fermate '
                      'fermate',
              },
              () => repo.restoreLine(tolta),
              lettore: lettore,
            ),
          );
      },
      child: tile,
    );
  }

  static void _conAnnulla(
    BuildContext context,
    String testo,
    VoidCallback annulla,
  ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        _annullabile(
          testo,
          annulla,
          lettore: MediaQuery.accessibleNavigationOf(context),
        ),
      );
  }

  /// Un avviso in basso con «Annulla».
  ///
  /// Flutter tiene fermo per sempre uno SnackBar che ha un pulsante, finché
  /// qualcuno non lo chiude: «Fermata rimossa» restava lì sopra la home.
  /// Sparisce dopo cinque secondi, tranne con VoiceOver o TalkBack
  /// ([lettore]), dove raggiungere il pulsante richiede più tempo.
  static SnackBar _annullabile(
    String testo,
    VoidCallback annulla, {
    required bool lettore,
  }) => SnackBar(
    content: Text(testo),
    duration: const Duration(seconds: 5),
    persist: lettore,
    action: SnackBarAction(label: 'Annulla', onPressed: annulla),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// «Le tue linee», quando sono state controllate, e il modo di rifarlo.
///
/// Prima era un pulsante flottante in basso a destra, che copriva l'ultima
/// riga e faceva la stessa cosa del trascinamento verso il basso.
class _LinesHeader extends StatelessWidget {
  const _LinesHeader({
    required this.lastCheck,
    required this.refreshing,
    required this.failed,
    required this.onRefreshAll,
  });

  final DateTime? lastCheck;
  final bool refreshing;

  /// L'ultimo tentativo di scaricare non e' riuscito.
  final bool failed;
  final VoidCallback onRefreshAll;

  @override
  Widget build(BuildContext context) {
    final testo = Theme.of(context).textTheme;
    final secondario = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Le tue linee', style: testo.titleSmall),
                Text(
                  _quando(lastCheck),
                  style: testo.bodySmall?.copyWith(color: secondario),
                ),
              ],
            ),
          ),
          // Mentre scarica, una rotella piccola: dura un secondo, e le righe
          // restano quelle di prima finche' non arrivano le nuove.
          //
          // Il pulsante c'e' solo se l'ultimo tentativo non e' riuscito.
          // Negli altri casi i dati si scaricano da soli, aprendo l'app e
          // tornandoci, e si puo' sempre tirare giu' la lista: un
          // «Aggiorna» sempre in vista faceva pensare che i dati fossero
          // vecchi anche quando non lo erano.
          if (refreshing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          else if (failed || lastCheck == null)
            TextButton.icon(
              onPressed: onRefreshAll,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Riprova'),
            ),
        ],
      ),
    );
  }

  static String _quando(DateTime? t) {
    if (t == null) return 'Non ancora aggiornate';
    final h =
        '${t.hour.toString().padLeft(2, "0")}:'
        '${t.minute.toString().padLeft(2, "0")}';
    final oggi = DateTime.now();
    final giorni = DateTime(
      oggi.year,
      oggi.month,
      oggi.day,
    ).difference(DateTime(t.year, t.month, t.day)).inDays;
    return switch (giorni) {
      0 => 'Aggiornate alle $h',
      1 => 'Aggiornate ieri alle $h',
      _ => 'Aggiornate il ${t.day}/${t.month}',
    };
  }
}

/// Come si salva una fermata: una volta, finche' non la si chiude o se ne
/// salva una.
class _StopsHint extends StatelessWidget {
  const _StopsHint({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      elevation: 0,
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.bookmark_add_outlined,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Salva le tue fermate',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Apri una linea e tocca una fermata sulla mappa: qui '
                    'vedrai subito se è servita.',
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: scheme.onSecondaryContainer),
              tooltip: 'Chiudi',
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

/// Lo sfondo che compare scorrendo una riga verso sinistra.
class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.errorContainer,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: scheme.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      color: scheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.cloud_off, color: scheme.onErrorContainer),
        title: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
        trailing: Semantics(
          button: true,
          label: 'Chiudi',
          child: IconButton(
            icon: Icon(Icons.close, color: scheme.onErrorContainer),
            onPressed: onClose,
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 20),
            Text('Caricamento delle linee…', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}
