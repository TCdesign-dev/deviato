import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models/saved_stop.dart';
import '../core/models/transit.dart';
import '../core/pipeline/stop_answer.dart';
import '../core/pipeline/stop_search.dart';
import '../core/text/display_names.dart';
import '../data/app_repository.dart';
import 'line_badge.dart';
import 'line_screen.dart';
import 'saved_stop_card.dart';
import 'theme.dart';

/// Una fermata: le linee che ci passano e se adesso ci fermano.
///
/// Ci si arriva cercandola per nome o numero, o inquadrando il QR della
/// palina. Le linee che non segui si leggono al volo (qualche KB l'una):
/// chi aspetta vuole sapere di tutte, non solo delle sue. I passaggi in
/// tempo reale non li calcoliamo: il pulsante in fondo apre la pagina di
/// GTT di quella palina, la stessa che apre il loro QR.
class StopScreen extends StatefulWidget {
  const StopScreen({required this.repo, required this.fermata, super.key});

  final AppRepository repo;
  final FermataCercabile fermata;

  /// La pagina dei passaggi di GTT per una palina: e' l'indirizzo scritto
  /// nei loro QR («…/cms/percorari/arrivi?palina=597»).
  static Uri paginaGtt(String palina) => Uri.parse(
    'https://www.gtt.to.it/cms/percorari/arrivi?palina='
    '${Uri.encodeQueryComponent(palina)}',
  );

  @override
  State<StopScreen> createState() => _StopScreenState();
}

class _StopScreenState extends State<StopScreen> {
  /// La risposta per ogni linea e direzione, mentre arrivano.
  final Map<(String, int), StopAnswer?> _risposte = {};
  final Set<(String, int)> _inArrivo = {};

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final f = widget.fermata;
    setState(
      () => _inArrivo.addAll([
        for (final p in f.passaggi) (p.routeId, p.directionId),
      ]),
    );
    await Future.wait([
      for (final p in f.passaggi)
        () async {
          final r = await widget.repo.rispostaPer(
            _salvata(p.routeId, p.directionId),
          );
          if (!mounted) return;
          setState(() {
            _risposte[(p.routeId, p.directionId)] = r;
            _inArrivo.remove((p.routeId, p.directionId));
          });
        }(),
    ]);
  }

  SavedStop _salvata(String routeId, int dir) => SavedStop(
    routeId: routeId,
    directionId: dir,
    stopId: widget.fermata.stop.id,
    stopCode: widget.fermata.stop.code,
  );

  Future<void> _salva(TransitLine linea, int dir) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await widget.repo.salvaFermataCercata(
      widget.fermata.stop,
      linea.routeId,
      dir,
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${DisplayNames.stop(widget.fermata.stop)} salvata nelle tue '
                    'fermate, linea ${linea.shortName}'
              : 'Impossibile salvare la fermata. Controlla la connessione '
                    'e riprova.',
        ),
      ),
    );
  }

  void _apriLinea(TransitLine linea) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => LineScreen(
        repo: widget.repo,
        line: linea,
        initialStopId: widget.fermata.stop.id,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final f = widget.fermata;
    final testo = Theme.of(context).textTheme;
    final tenue = Theme.of(context).colorScheme.onSurfaceVariant;
    final perId = {for (final l in widget.repo.allLines) l.routeId: l};

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: DisplayNames.stop(f.stop)),
              if (f.stop.code != null)
                TextSpan(
                  text: '  ${f.stop.code}',
                  style: TextStyle(color: tenue),
                ),
            ],
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.repo,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Le linee che passano da qui, e se adesso fermano. '
                'Salvane una per ritrovarla nella home.',
                style: testo.bodyMedium?.copyWith(color: tenue),
              ),
            ),
            for (final p in f.passaggi)
              if (perId[p.routeId] case final linea?)
                _RigaLinea(
                  linea: linea,
                  risposta: _risposte[(p.routeId, p.directionId)],
                  inArrivo: _inArrivo.contains((p.routeId, p.directionId)),
                  capolinea: widget.repo.fermateRete?.capolineaDi(
                    p.routeId,
                    p.directionId,
                  ),
                  salvata: widget.repo.isSaved(
                    _salvata(p.routeId, p.directionId),
                  ),
                  seguita: widget.repo.lines.any((l) => l.routeId == p.routeId),
                  onSalva: () => _salva(linea, p.directionId),
                  onApri: () => _apriLinea(linea),
                ),
            if (f.stop.code != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    StopScreen.paginaGtt(f.stop.code!),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.schedule),
                  label: const Text('Passaggi in tempo reale, sul sito di GTT'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Una linea della fermata: verso dove va, se adesso ferma, e «Salva».
class _RigaLinea extends StatelessWidget {
  const _RigaLinea({
    required this.linea,
    required this.risposta,
    required this.inArrivo,
    required this.capolinea,
    required this.salvata,
    required this.seguita,
    required this.onSalva,
    required this.onApri,
  });

  final TransitLine linea;
  final StopAnswer? risposta;
  final bool inArrivo;
  final String? capolinea;
  final bool salvata;
  final bool seguita;
  final VoidCallback onSalva;
  final VoidCallback onApri;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = risposta;
    final verso = capolinea == null
        ? null
        : DisplayNames.direction(capolinea!, longName: linea.longName);
    final (colore, icona, stato) = r == null
        ? (
            scheme.onSurfaceVariant,
            inArrivo ? Icons.sync : Icons.help_outline,
            inArrivo ? 'Aggiornamento…' : 'Non si sa: controlla la connessione',
          )
        : r.state == StopState.notOnRoute
        // Ci passano solo alcune corse, su una variante che non e' quella
        // principale: le deviazioni si calcolano sulla principale, e di
        // questa fermata non si saprebbe dire niente. Niente «Salva».
        ? (
            scheme.onSurfaceVariant,
            Icons.alt_route,
            'Solo alcune corse fermano qui',
          )
        : statoFermata(context, r, false);
    final chiusa = r?.state == StopState.closed;
    final salvabile = r?.state != StopState.notOnRoute;

    return Material(
      color: chiusa
          ? scheme.errorContainer.withValues(alpha: 0.45)
          : Colors.transparent,
      child: InkWell(
        // Si apre la linea solo se la segui: le altre non hanno ancora un
        // dettaglio da mostrare. «Salva» la aggiunge.
        onTap: seguita ? onApri : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 60,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: LineBadge(line: linea, height: 30),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verso == null
                          ? 'Linea ${linea.shortName}'
                          : 'verso $verso',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(icona, size: 16, color: colore),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            stato,
                            style: TextStyle(
                              color: colore,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (chiusa && r!.walkTo.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Sali a ${DisplayNames.stop(r.walkTo.first.stop)}, '
                          '${r.walkTo.first.meters.round()} m in linea d\'aria',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
              if (!salvabile)
                const SizedBox(width: 12)
              else if (salvata)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Semantics(
                    label: 'Già fra le tue fermate',
                    child: Icon(
                      Icons.check,
                      color: StatusColors.of(context).ok,
                    ),
                  ),
                )
              else
                TextButton.icon(
                  onPressed: onSalva,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Salva'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
