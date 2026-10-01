import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/deviation_service.dart';
import '../core/models/transit.dart';
import '../core/pipeline/closure_summary.dart';
import '../core/text/display_names.dart';
import '../data/app_repository.dart';
import 'cartina.dart';
import 'line_badge.dart';
import 'line_map.dart';
import 'scheda_mappa.dart';

/// La mappa a tutto schermo, con una scheda che galleggia in basso.
///
/// Nel dettaglio la mappa e' alta 280 punti: basta per capire dove passa
/// la linea, non per leggere una deviazione. Qui la cartina e' tutta, e la
/// scheda ([SchedaMappa]) dice quello che serve senza coprirla: lo stato,
/// le fermate non servite per tratti, gli avvisi, e la fermata toccata
/// quando se ne tocca una. In alto si puo' tenere una direzione sola.
class FullMapScreen extends StatefulWidget {
  const FullMapScreen({
    required this.repo,
    required this.line,
    this.isSaved,
    this.onToggleSave,
    super.key,
  });

  final AppRepository repo;
  final TransitLine line;
  final bool Function(TransitStop stop, RouteShape shape)? isSaved;
  final void Function(TransitStop stop, RouteShape shape)? onToggleSave;

  @override
  State<FullMapScreen> createState() => _FullMapScreenState();
}

class _FullMapScreenState extends State<FullMapScreen> {
  final _mappa = MapController();
  final _scelta = ValueNotifier<FermataScelta?>(null);

  /// La direzione mostrata, fra i percorsi principali. null: tutte e due.
  int? _direzione;

  /// Quanto e' alta la scheda in basso, misurata: la mappa le fa posto.
  var _scheda = 200.0;

  /// L'altezza della barra in alto, sotto la barra di stato.
  static const _barra = 56.0;

  /// Lo spazio fra la scheda e i bordi.
  static const _margine = 10.0;

  @override
  void dispose() {
    _scelta.dispose();
    super.dispose();
  }

  /// Quanto spazio copre la scheda, dal fondo dello schermo.
  double _sotto(BuildContext context) =>
      _scheda + _margine * 2 + MediaQuery.paddingOf(context).bottom;

  List<RouteShape> _direzioni(LineStatus status) => [
    for (final s in status.mainShapes)
      if (s.points.length > 1) s,
  ];

  /// Toccando un tratto: la mappa lo inquadra, sopra la scheda.
  void _vaiAlTratto(ClosedRun r) {
    final punti = [
      for (final s in [?r.before, ...r.stops, ?r.after])
        LatLng(s.position.lat, s.position.lon),
    ];
    if (punti.isEmpty) return;
    final alto = MediaQuery.paddingOf(context).top + _barra;
    final basso = _sotto(context);
    _mappa.fitCamera(
      CameraFit.coordinates(
        coordinates: punti,
        padding: EdgeInsets.fromLTRB(48, alto + 48, 48, basso + 48),
        maxZoom: 17,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.repo, _scelta]),
      builder: (context, _) => _contenuto(context),
    );
  }

  Widget _contenuto(BuildContext context) {
    final repo = widget.repo;
    final status = repo.statusOf(widget.line.routeId);
    if (status == null) return const Scaffold(body: SizedBox.shrink());

    final direzioni = _direzioni(status);
    final osservando = repo.isWatching(widget.line.routeId);
    final esito = repo.watchResultOf(widget.line.routeId);
    final alto = MediaQuery.paddingOf(context).top + _barra;
    final cartina = Cartina.of(context);
    final soloDirezione = _direzione == null || _direzione! >= direzioni.length
        ? null
        : direzioni[_direzione!].shapeId;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // La barra di stato sta sopra la cartina: chiara su quella scura.
      value: cartina.scura
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        // Tutto lo schermo, sempre: la scheda in basso e' posizionata, e
        // senza questo la pila prendeva l'altezza della barra in alto — la
        // mappa diventava alta 56 punti.
        body: SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(
                child: LineMap(
                  status: status,
                  fullScreen: true,
                  controller: _mappa,
                  selection: _scelta,
                  onlyDirection: _direzione,
                  vehicles: osservando ? repo.liveTracks : const [],
                  observed: esito?.consensus,
                  isSaved: widget.isSaved,
                  onToggleSave: widget.onToggleSave,
                  inset: EdgeInsets.only(top: alto, bottom: _sotto(context)),
                  watching: osservando,
                  watchCount: osservando ? repo.liveTracks.length : 0,
                  onToggleWatch: osservando
                      ? repo.stopWatch
                      : () => repo.startWatch(widget.line),
                  // La scheda sta dentro la mappa, che le passa i suoi
                  // comandi: cosi' non galleggiano piu' sulla cartina.
                  scheda: (context, comandi) => Positioned(
                    left: _margine,
                    right: _margine,
                    bottom: _margine + MediaQuery.paddingOf(context).bottom,
                    child: SchedaMappa(
                      status: status,
                      soloDirezione: soloDirezione,
                      onTratto: _vaiAlTratto,
                      comandi: comandi,
                      onAltezza: (a) {
                        if ((a - _scheda).abs() > 1 && mounted) {
                          setState(() => _scheda = a);
                        }
                      },
                      fermata: _scelta.value == null
                          ? null
                          : _fermata(status, _scelta.value!),
                      riepilogo: _Legenda(
                        cartina: cartina,
                        direzioni: [
                          for (var i = 0; i < direzioni.length; i++)
                            if (_direzione == null || _direzione == i)
                              (
                                i,
                                DisplayNames.direction(
                                  direzioni[i].headsign,
                                  longName: status.line.longName,
                                ),
                              ),
                        ],
                        deviata: status.activeReports.any((r) => r.hasMap),
                      ),
                    ),
                  ),
                ),
              ),
              _Barra(
                line: status.line,
                direzioni: [
                  for (final d in direzioni)
                    DisplayNames.direction(
                      d.headsign,
                      longName: status.line.longName,
                    ),
                ],
                scelta: _direzione,
                onScelta: (i) {
                  setState(() => _direzione = i);
                  _scelta.value = null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fermata(LineStatus status, FermataScelta f) {
    RouteShape? shape;
    for (final s in status.mainShapes) {
      if (s.stops.any((x) => x.id == f.stop.id)) shape = s;
    }
    final salvaData = widget.onToggleSave;
    final salvata = widget.isSaved;
    return FermataToccata(
      stop: f.stop,
      impact: f.impact,
      direction: shape == null
          ? null
          : DisplayNames.direction(
              shape.headsign,
              longName: status.line.longName,
            ),
      saved: shape == null || salvata == null ? null : salvata(f.stop, shape),
      onToggleSave: shape == null || salvaData == null
          ? null
          : () => salvaData(f.stop, shape!),
      onClose: () => _scelta.value = null,
    );
  }
}

/// In alto, sopra la cartina: indietro, la linea, e quale direzione.
class _Barra extends StatelessWidget {
  const _Barra({
    required this.line,
    required this.direzioni,
    required this.scelta,
    required this.onScelta,
  });

  final TransitLine line;
  final List<String> direzioni;
  final int? scelta;
  final ValueChanged<int?> onScelta;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: _FullMapScreenState._barra,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Material(
                color: scheme.surface,
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Indietro',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 10),
              LineBadge(line: line, height: 30),
              const SizedBox(width: 12),
              // Con una direzione sola non c'e' niente da scegliere. Tutto
              // lo spazio rimasto e' suo: diviso con uno spaziatore, il
              // nome della direzione si tagliava a meta'.
              if (direzioni.length > 1)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _SceltaDirezione(
                      direzioni: direzioni,
                      scelta: scelta,
                      onScelta: onScelta,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SceltaDirezione extends StatelessWidget {
  const _SceltaDirezione({
    required this.direzioni,
    required this.scelta,
    required this.onScelta,
  });

  final List<String> direzioni;
  final int? scelta;
  final ValueChanged<int?> onScelta;

  static const _tutte = -1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final etichetta = scelta == null || scelta! >= direzioni.length
        ? 'Entrambe le direzioni'
        : '→ ${direzioni[scelta!]}';
    return Material(
      color: scheme.surface,
      shape: const StadiumBorder(),
      elevation: 2,
      child: PopupMenuButton<int>(
        tooltip: 'Direzione',
        initialValue: scelta ?? _tutte,
        onSelected: (v) => onScelta(v == _tutte ? null : v),
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: _tutte,
            child: Text('Entrambe le direzioni'),
          ),
          for (var i = 0; i < direzioni.length; i++)
            PopupMenuItem(value: i, child: Text('→ ${direzioni[i]}')),
        ],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  etichetta,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }
}

/// La legenda, in una riga o due: a tutto schermo non ha un posto fisso.
class _Legenda extends StatelessWidget {
  const _Legenda({
    required this.cartina,
    required this.direzioni,
    required this.deviata,
  });

  final Cartina cartina;
  final List<(int, String)> direzioni;
  final bool deviata;

  @override
  Widget build(BuildContext context) {
    final stile = Theme.of(context).textTheme.bodySmall;
    final tenue = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget linea(Color c, String t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 5,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(t, style: stile),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final (i, nome) in direzioni)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CampioneDirezione(colore: cartina.direzione(i)),
                    const SizedBox(width: 6),
                    Text('verso $nome', style: stile),
                  ],
                ),
              if (deviata) linea(cartina.deviazione, 'percorso deviato'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tocca una fermata sulla mappa per vederla.',
            style: stile?.copyWith(color: tenue),
          ),
          if (deviata)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Il percorso deviato è ricostruito dal testo dell\'avviso: '
                'potrebbe non essere esatto.',
                style: stile?.copyWith(color: tenue),
              ),
            ),
        ],
      ),
    );
  }
}
