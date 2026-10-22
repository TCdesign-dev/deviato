import 'package:flutter/material.dart';

import '../core/models/tragitto.dart';
import '../core/models/transit.dart';
import '../core/pipeline/risposta_tragitto.dart';
import '../core/pipeline/stop_answer.dart';
import '../core/text/display_names.dart';
import '../data/app_repository.dart';
import 'editor_tragitto.dart';
import 'line_badge.dart';
import 'line_screen.dart';
import 'saved_stop_card.dart';
import 'theme.dart';

/// Il nome di una fermata di un tragitto: dall'esito se c'e', se no dal
/// numero.
String nomeFermata(StopAnswer r) => r.stop == null
    ? 'la fermata ${r.saved.stopCode ?? ''}'.trim()
    : DisplayNames.stop(r.stop!);

/// La riga che riassume un tragitto: «Tutto servito», o il primo intoppo
/// nell'ordine del viaggio.
(Color, IconData, String) statoTragitto(
  BuildContext context,
  RispostaTragitto r,
  Map<String, TransitLine> linee, {
  required Set<String> seguite,
  bool aggiornando = false,
}) {
  final colori = StatusColors.of(context);
  final scheme = Theme.of(context).colorScheme;
  final p = r.primoIntoppo;
  if (p == null) {
    return (colori.ok, Icons.check_circle_outline, 'Tutto servito');
  }
  final a = p.risposta;
  final linea = linee[a.saved.routeId]?.shortName ?? '';
  final dove = nomeFermata(a);
  String data(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  final invece = a.walkTo.isEmpty
      ? ''
      : ' · ${p.salita ? 'sali' : 'scendi'} a '
            '${DisplayNames.stop(a.walkTo.first.stop)}';
  return switch (a.state) {
    StopState.closed => (
      scheme.error,
      Icons.do_not_disturb_on_outlined,
      'Linea $linea: non ferma a $dove$invece',
    ),
    StopState.uncertain => (
      colori.warning,
      Icons.article_outlined,
      'Linea $linea: avviso in corso, controlla i dettagli',
    ),
    StopState.closesLater => (
      colori.warning,
      Icons.event_outlined,
      a.from == null
          ? 'Linea $linea: presto non fermerà a $dove'
          : 'Linea $linea: dal ${data(a.from!)} non ferma a $dove',
    ),
    StopState.notOnRoute => (
      scheme.onSurfaceVariant,
      Icons.wrong_location_outlined,
      'Linea $linea: $dove non è più sulla linea',
    ),
    StopState.unknown || StopState.served => (
      scheme.onSurfaceVariant,
      aggiornando ? Icons.sync : Icons.help_outline,
      aggiornando
          ? 'Aggiornamento…'
          : !seguite.contains(a.saved.routeId)
          ? 'La linea $linea non è più fra le tue'
          : 'Linea $linea: tira giù per aggiornare',
    ),
  };
}

/// Un tragitto nella home: il nome, le linee in fila, e la risposta.
class TragittoCard extends StatelessWidget {
  const TragittoCard({required this.repo, required this.tragitto, super.key});

  final AppRepository repo;
  final Tragitto tragitto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final perId = {for (final l in repo.allLines) l.routeId: l};
    final r = repo.rispostaTragitto(tragitto);
    final (colore, icona, testo) = statoTragitto(
      context,
      r,
      perId,
      seguite: {for (final l in repo.lines) l.routeId},
      aggiornando: repo.isRefreshingAll || tragitto.linee.any(repo.isPreparing),
    );
    // Come le fermate salvate: piatta, sul grigio chiaro.
    final linee = [
      for (final (i, t) in tragitto.tratte.indexed) ...[
        if (i > 0)
          Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
        if (perId[t.routeId] case final l?) LineBadge(line: l, height: 24),
      ],
    ];
    // Con tre linee o piu' accanto al nome non resta spazio per il nome.
    final sotto = tragitto.tratte.length > 2;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => TragittoScreen(repo: repo, id: tragitto.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tragitto.nome,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!sotto) ...linee,
                ],
              ),
              if (sotto)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: linee),
                ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(icona, size: 18, color: colore),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      testo,
                      style: TextStyle(
                        color: colore,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un tragitto per intero: ogni tratta, con dove sali e dove scendi.
class TragittoScreen extends StatelessWidget {
  const TragittoScreen({required this.repo, required this.id, super.key});

  final AppRepository repo;
  final String id;

  /// Quanto si cammina al cambio: «180 m», «1,2 km». null se si cambia
  /// alla stessa fermata, o se una delle due non si trova.
  static String? _aPiedi(StopAnswer scendi, StopAnswer sali) {
    final a = scendi.stop, b = sali.stop;
    if (a == null || b == null || a.id == b.id) return null;
    final m = a.position.meters.distanceTo(b.position.meters);
    if (m < 1000) return '${(m / 10).round() * 10} m';
    return '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  Future<void> _elimina(BuildContext context, Tragitto t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminare «${t.nome}»?'),
        content: const Text(
          'Le linee restano fra le tue: si toglie solo il tragitto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.pop(context);
    await repo.rimuoviTragitto(t.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final t = repo.tragitti.where((x) => x.id == id).firstOrNull;
        if (t == null) return const Scaffold(body: SizedBox.shrink());
        final perId = {for (final l in repo.allLines) l.routeId: l};
        final r = repo.rispostaTragitto(t);
        final testo = Theme.of(context).textTheme;
        final tenue = Theme.of(context).colorScheme.onSurfaceVariant;
        final seguite = {for (final l in repo.lines) l.routeId};
        final mancanti = [
          for (final id in t.linee)
            if (!seguite.contains(id)) ?perId[id],
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text(t.nome),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Modifica',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => EditorTragitto(repo: repo, tragitto: t),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Elimina',
                onPressed: () => _elimina(context, t),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: repo.refreshAll,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                // Una linea tolta dalla home non ha piu' uno stato: si
                // dice, e si rimette con un tocco.
                for (final l in mancanti)
                  Card(
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'La linea ${l.shortName} non è più fra le '
                              'tue: senza, non si sa se ferma.',
                            ),
                          ),
                          TextButton(
                            onPressed: () => repo.addLine(l),
                            child: const Text('Aggiungi'),
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final (i, x) in r.tratte.indexed) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 4, 16, 4),
                      child: Row(
                        children: [
                          Icon(Icons.transfer_within_a_station, color: tenue),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Cambio',
                                    style: testo.labelLarge,
                                  ),
                                  if (_aPiedi(r.tratte[i - 1].discesa, x.salita)
                                      case final m?)
                                    TextSpan(
                                      text: ' · $m a piedi, in linea d\'aria',
                                      style: testo.bodyMedium?.copyWith(
                                        color: tenue,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  _Tratta(
                    linea: perId[x.tratta.routeId],
                    salita: x.salita,
                    discesa: x.discesa,
                    aggiornando:
                        repo.isRefreshingAll ||
                        repo.isPreparing(x.tratta.routeId),
                    seguita: seguite.contains(x.tratta.routeId),
                    onApri:
                        perId[x.tratta.routeId] == null ||
                            !seguite.contains(x.tratta.routeId)
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => LineScreen(
                                repo: repo,
                                line: perId[x.tratta.routeId]!,
                                initialStopId: x.tratta.salitaId,
                              ),
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Tratta extends StatelessWidget {
  const _Tratta({
    required this.linea,
    required this.salita,
    required this.discesa,
    required this.aggiornando,
    required this.seguita,
    required this.onApri,
  });

  final TransitLine? linea;
  final StopAnswer salita;
  final StopAnswer discesa;
  final bool aggiornando;
  final bool seguita;

  /// Apre la linea alla fermata dove si sale; null se non la segui.
  final VoidCallback? onApri;

  @override
  Widget build(BuildContext context) {
    final l = linea;
    final shape = salita.shape ?? discesa.shape;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onApri,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
              child: Row(
                children: [
                  if (l != null) LineBadge(line: l, height: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      shape == null || l == null
                          ? 'Linea ${l?.shortName ?? ''}'
                          : 'verso ${DisplayNames.direction(shape.headsign, longName: l.longName)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (onApri != null)
                    Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
          for (final (verbo, r) in [('Sali a', salita), ('Scendi a', discesa)])
            _Passo(
              verbo: verbo,
              risposta: r,
              aggiornando: aggiornando,
              seguita: seguita,
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _Passo extends StatelessWidget {
  const _Passo({
    required this.verbo,
    required this.risposta,
    required this.aggiornando,
    required this.seguita,
  });

  final String verbo;
  final StopAnswer risposta;
  final bool aggiornando;
  final bool seguita;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var (colore, icona, stato) = statoFermata(context, risposta, aggiornando);
    // Qui la riga non si tocca: si aggiorna tirando giu'.
    if (risposta.state == StopState.unknown && !aggiornando) {
      stato = seguita ? 'Tira giù per aggiornare' : 'Non si sa';
    }
    final chiusa = risposta.state == StopState.closed;
    return Container(
      color: chiusa ? scheme.errorContainer.withValues(alpha: 0.45) : null,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icona, size: 20, color: colore),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '$verbo '),
                      TextSpan(
                        text: nomeFermata(risposta),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (risposta.stop?.code != null)
                        TextSpan(
                          text: '  ${risposta.stop!.code}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                Text(
                  stato,
                  style: TextStyle(
                    color: colore,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (chiusa && risposta.walkTo.isNotEmpty)
                  Text(
                    '${verbo.startsWith('Sali') ? 'Sali' : 'Scendi'} a '
                    '${DisplayNames.stop(risposta.walkTo.first.stop)}, '
                    '${risposta.walkTo.first.meters.round()} m in linea d\'aria',
                    style: const TextStyle(fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
