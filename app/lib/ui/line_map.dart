import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/deviation_service.dart';
import '../core/models/transit.dart';
import '../core/geo/projection.dart';
import '../core/pipeline/route_excursion.dart';
import '../core/pipeline/stop_impact.dart';
import '../core/pipeline/vehicle_heading.dart';
import '../core/pipeline/verso_fermate.dart';
import '../core/pipeline/vehicle_watch.dart';
import '../core/text/display_names.dart';
import '../data/user_location.dart';
import 'cartina.dart';
import 'theme.dart';

/// Una fermata toccata sulla mappa, con il suo esito se non e' servita.
typedef FermataScelta = ({TransitStop stop, StopImpact? impact});

/// La mappa della linea: percorso normale, deviazioni, e le fermate.
///
/// Si mostra SEMPRE, anche quando nessuna deviazione e' stata ricostruita.
/// Vedere dove passa la linea e dove si sale e' utile comunque, e
/// nasconderla proprio quando il testo non si e' capito lascia l'utente
/// senza nulla in mano nel momento peggiore.
///
/// Convenzioni grafiche dalla specifica §6.2: percorso normale sottile e
/// grigio, tratto deviato rosso e spesso, fermate saltate cerchiate.
class LineMap extends StatefulWidget {
  const LineMap({
    required this.status,
    super.key,
    this.height = 280,
    this.vehicles = const [],
    this.observed,
    this.initialStopId,
    this.isSaved,
    this.onToggleSave,
    this.onOpenFullScreen,
    this.fullScreen = false,
    this.controller,
    this.selection,
    this.onlyDirection,
    this.inset = EdgeInsets.zero,
    this.onToggleWatch,
    this.watching = false,
    this.watchCount = 0,
  });

  final LineStatus status;
  final double height;

  /// Nel dettaglio: apre la mappa a tutto schermo, dal pulsante in angolo
  /// o toccando un punto vuoto della mappa.
  final VoidCallback? onOpenFullScreen;

  /// A tutto schermo: la mappa riempie lo spazio che le si da', senza
  /// legenda ne' striscia sotto. La fermata toccata va a [selection], e la
  /// mostra chi sta intorno.
  final bool fullScreen;

  /// Per spostare l'inquadratura da fuori: toccando un tratto nel pannello.
  final MapController? controller;

  /// La fermata toccata, se la tiene qualcun altro.
  final ValueNotifier<FermataScelta?>? selection;

  /// Solo questa direzione (indice fra i percorsi principali). null: tutte.
  ///
  /// Dove andata e ritorno passano per le stesse vie — la 15 in centro —
  /// le due linee e le due file di fermate si coprono a vicenda.
  final int? onlyDirection;

  /// Lo spazio occupato da cio' che sta sopra la mappa: la barra in alto e
  /// il pannello in basso della mappa a tutto schermo. L'inquadratura e i
  /// comandi ne tengono conto.
  final EdgeInsets inset;

  /// A tutto schermo: segui i mezzi, o smetti. Il pulsante sta con gli
  /// altri comandi della mappa, perche' i mezzi compaiono li'.
  final VoidCallback? onToggleWatch;
  final bool watching;

  /// Quanti mezzi si vedono adesso, per dirlo sul pulsante.
  final int watchCount;

  /// I mezzi osservati adesso, se un'osservazione e' in corso o appena
  /// conclusa. Si disegnano sopra tutto il resto: sono la cosa che si
  /// muove, ed e' quella che si guarda.
  final List<VehicleTrack> vehicles;

  /// Il tratto che i mezzi hanno **davvero** percorso fuori dal percorso
  /// normale. Diverso da `deviatedGeometry`, che e' ricostruito dal testo
  /// dell'avviso: qui non c'e' nessuna inferenza, sono posizioni GPS.
  final ExcursionConsensus? observed;

  /// La fermata da aprire subito: si arriva da una fermata salvata.
  final String? initialStopId;

  /// Se la fermata toccata e' fra quelle salvate, e come salvarla. Senza,
  /// la mappa mostra solo il nome.
  final bool Function(TransitStop stop, RouteShape shape)? isSaved;
  final void Function(TransitStop stop, RouteShape shape)? onToggleSave;

  @override
  State<LineMap> createState() => _LineMapState();
}

class _LineMapState extends State<LineMap> {
  /// Il controller serve solo a centrare la mappa su di te quando lo
  /// chiedi: per il resto la mappa si posiziona da sola sul percorso.
  late final MapController _map = widget.controller ?? MapController();

  /// L'inquadratura che mostra tutto il percorso. La calcola `build`, e
  /// serve al pulsante che ci riporta.
  LatLngBounds? _routeBounds;

  final _location = UserLocation();
  StreamSubscription<GeoPoint>? _locationSub;
  GeoPoint? _me;
  bool _locating = false;

  /// La fermata toccata. Dei pallini muti non servono a niente: uno tocca
  /// per sapere COME SI CHIAMA quella fermata. Sta nella
  /// [LineMap.selection] se qualcuno la tiene, se no qui.
  FermataScelta? _interna;
  FermataScelta? get _selected => widget.selection?.value ?? _interna;
  set _selected(FermataScelta? v) {
    final fuori = widget.selection;
    if (fuori != null) {
      fuori.value = v;
    } else {
      _interna = v;
    }
  }

  void _ridisegna() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(LineMap old) {
    super.didUpdateWidget(old);
    // Cambiando direzione si torna a inquadrare quella rimasta.
    if (old.onlyDirection != widget.onlyDirection) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitRoute());
    }
  }

  @override
  void initState() {
    super.initState();
    widget.selection?.addListener(_ridisegna);
    final id = widget.initialStopId;
    if (id == null) return;
    final saltate = {
      for (final s in widget.status.allSkippedStops) s.stop.id: s,
    };
    for (final shape in widget.status.mainShapes) {
      for (final s in shape.stops) {
        if (s.id == id) {
          _selected = (stop: s, impact: saltate[id]);
          return;
        }
      }
    }
  }

  /// La direzione a cui appartiene un palo: le banchine opposte hanno id
  /// diversi, quindi e' una sola.
  RouteShape? _shapeOf(TransitStop stop) {
    for (final shape in widget.status.mainShapes) {
      if (shape.stops.any((s) => s.id == stop.id)) return shape;
    }
    return null;
  }

  bool? _savedState(TransitStop stop) {
    final shape = _shapeOf(stop);
    if (shape == null || widget.isSaved == null) return null;
    return widget.isSaved!(stop, shape);
  }

  VoidCallback? _saveAction(TransitStop stop) {
    final shape = _shapeOf(stop);
    final salva = widget.onToggleSave;
    if (shape == null || salva == null) return null;
    return () => salva(stop, shape);
  }

  @override
  void dispose() {
    widget.selection?.removeListener(_ridisegna);
    _locationSub?.cancel();
    _location.stop();
    super.dispose();
  }

  /// Il permesso si chiede QUI, quando l'utente tocca il pulsante — non
  /// all'apertura della schermata. Una richiesta che arriva senza che tu
  /// abbia chiesto niente si nega per riflesso, e poi e' finita.
  Future<void> _showMe() async {
    if (_locationSub != null) {
      // Secondo tocco: si smette di seguire.
      await _locationSub?.cancel();
      _locationSub = null;
      setState(() => _me = null);
      return;
    }

    setState(() => _locating = true);
    final denial = await _location.ensurePermission();
    if (!mounted) return;
    if (denial != null) {
      setState(() => _locating = false);
      _say(UserLocation.explain(denial));
      return;
    }

    final first = await _location.current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _me = first;
    });
    if (first == null) {
      _say(UserLocation.explain(LocationDenial.nessunSegnale));
      return;
    }
    _map.move(LatLng(first.lat, first.lon), 15);

    // Poi il punto continua a seguirti: un pallino fermo dove eri due
    // minuti fa e' peggio che nessun pallino.
    _locationSub = _location.follow().listen((p) {
      if (mounted) setState(() => _me = p);
    }, onError: (_) {});
  }

  /// Torna a inquadrare tutto il percorso.
  ///
  /// Dopo aver seguito un mezzo o essersi centrati su di se', ritrovare la
  /// linea intera a mano — zoom indietro e trascinamenti — e' fastidioso,
  /// e su una linea lunga si finisce fuori senza accorgersene.
  void _fitRoute() {
    final b = _routeBounds;
    if (b == null) return;
    _map.fitCamera(CameraFit.bounds(bounds: b, padding: _margine));
  }

  /// I comandi a tutto schermo: con la scritta, uno sotto l'altro.
  ///
  /// L'app la usano anche persone che non sono cresciute coi telefoni: un
  /// cerchio con un'icona va interpretato, «Dove sono» no. Nel dettaglio
  /// la mappa e' piccola e restano i pulsanti tondi.
  Widget _comandiConScritta() {
    final seguendo = _locationSub != null;
    final n = widget.watchCount;
    // Tutti larghi uguale: una colonna frastagliata sembra disordinata, e
    // pulsanti allineati si leggono come un gruppo. E sempre la stessa
    // larghezza, quella della scritta piu' lunga che puo' comparire: prima
    // era quella della scritta di adesso, e seguendo i mezzi «Tutta la
    // linea» e «Dove sono» si allargavano con «25 mezzi · Interrompi».
    // Scritte corte anche da accese, perche' la colonna non si allarghi
    // sulla mappa: e' il giallo a dire che sono accese.
    return SizedBox(
      width: _Comando.larghezza(context, const [
        'Tutta la linea',
        'Segui i mezzi',
        'Interrompi',
        'Dove sono',
      ]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Comando(
            icon: Icons.zoom_out_map,
            testo: 'Tutta la linea',
            onPressed: _fitRoute,
          ),
          if (widget.onToggleWatch != null) ...[
            const SizedBox(height: 10),
            _Comando(
              icon: Icons.visibility_outlined,
              // Mentre si seguono i mezzi il comando si muove: con la sola
              // icona ferma non si capiva che l'osservazione era attiva.
              // Gira mentre li cerca, pulsa quando ci sono.
              indicatore: !widget.watching
                  ? null
                  : n == 0
                  ? const _Rotella()
                  : const _Pulsazione(),
              // Seguendo, solo l'azione: che i mezzi si seguono lo dice
              // l'indicatore, quanti sono lo dice la mappa.
              testo: widget.watching ? 'Interrompi' : 'Segui i mezzi',
              descrizione: !widget.watching
                  ? null
                  : n == 0
                  ? 'Ricerca dei mezzi in corso. Interrompi'
                  : '$n ${n == 1 ? "mezzo" : "mezzi"} sulla mappa. Interrompi',
              attivo: widget.watching,
              onPressed: widget.onToggleWatch!,
            ),
          ],
          const SizedBox(height: 10),
          _Comando(
            icon: seguendo ? Icons.my_location : Icons.location_searching,
            testo: 'Dove sono',
            descrizione: seguendo ? 'Nascondi dove sono' : null,
            attivo: seguendo,
            busy: _locating,
            onPressed: _showMe,
          ),
        ],
      ),
    );
  }

  /// Il margine dell'inquadratura: un po' d'aria, piu' lo spazio coperto.
  EdgeInsets get _margine => const EdgeInsets.all(28) + widget.inset;

  void _say(String message) => ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final status = widget.status;

    // Andata e ritorno sono percorsi diversi e vanno mostrati entrambi:
    // spesso non coincidono, per via dei sensi unici, e una deviazione ne
    // riguarda spesso una sola.
    final directions = status.mainShapes
        .where((s) => s.points.length > 1)
        .map(
          (s) => (
            shape: s,
            points: s.points
                .map((p) => LatLng(p.lat, p.lon))
                .toList(growable: false),
          ),
        )
        .toList();
    if (directions.isEmpty) return const SizedBox.shrink();
    final official = directions.first.points;
    final sola = widget.onlyDirection;
    // Gli indici restano quelli di tutte le direzioni: il colore di una
    // direzione non deve cambiare quando si nasconde l'altra.
    final mostrate = [
      for (var i = 0; i < directions.length; i++)
        if (sola == null || sola == i || sola >= directions.length) i,
    ];
    final idMostrati = {for (final i in mostrate) directions[i].shape.shapeId};
    final fermateMostrate = {
      for (final i in mostrate)
        for (final s in directions[i].shape.stops) s.id,
    };

    // Solo cio' che e' in corso: disegnare in rosso una deviazione che
    // comincia fra tre settimane farebbe scendere alla fermata sbagliata
    // oggi.
    final deviations = status.activeReports
        .where((r) => r.hasMap && idMostrati.contains(r.shape.shapeId))
        .map(
          (r) => r.deviatedGeometry!
              .map((p) => LatLng(p.lat, p.lon))
              .toList(growable: false),
        )
        .toList();

    // Le fermate saltate hanno la precedenza: se una fermata e' saltata
    // non va disegnata anche come servita.
    final skipped = {
      for (final s in status.allSkippedStops)
        if (fermateMostrate.contains(s.stop.id)) s.stop.id: s,
    };
    // Le fermate di TUTTE le direzioni, senza doppioni: molte sono in
    // comune fra andata e ritorno (banchine opposte hanno id diversi).
    final served = {
      for (final i in mostrate)
        for (final s in directions[i].shape.stops)
          if (!skipped.containsKey(s.id)) s.id: s,
    }.values.toList(growable: false);
    // La direzione di ogni fermata, per il colore e la freccia. Un palo
    // usato da tutte e due (certi capolinea) non ha un verso solo: null.
    final direzioneDi = <String, int?>{};
    for (final i in mostrate) {
      for (final s in directions[i].shape.stops) {
        direzioneDi[s.id] =
            !direzioneDi.containsKey(s.id) || direzioneDi[s.id] == i ? i : null;
      }
    }
    double? versoDi(String id) {
      final d = direzioneDi[id];
      return d == null ? null : VersoFermate.di(directions[d].shape)[id];
    }
    final cartina = Cartina.of(context);

    // La stessa inquadratura serve due volte: all'apertura, e ogni volta
    // che si tocca il pulsante per tornarci dopo aver girovagato.
    final osservato = widget.observed == null
        ? const <LatLng>[]
        : [for (final p in widget.observed!.path) LatLng(p.lat, p.lon)];

    final bounds = LatLngBounds.fromPoints(
      deviations.isNotEmpty
          ? deviations.expand((d) => d).toList()
          : [for (final i in mostrate) ...directions[i].points],
    );
    _routeBounds = bounds;

    final mappa = Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: bounds,
              padding: _margine,
            ),
            interactionOptions: const InteractionOptions(
              flags:
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.drag |
                  InteractiveFlag.doubleTapZoom,
            ),
            // Un tocco a vuoto chiude la fermata aperta; se non ce
            // n'e', nel dettaglio apre la mappa a tutto schermo.
            onTap: (_, _) {
              if (_selected != null) {
                setState(() => _selected = null);
              } else {
                widget.onOpenFullScreen?.call();
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: cartina.url,
              subdomains: cartina.sottodomini,
              retinaMode: Cartina.carto && RetinaMode.isHighDensity(context),
              userAgentPackageName: 'dev.tcdesign.deviato',
            ),
            PolylineLayer(
              polylines: [
                // Le due direzioni con tonalita' diverse: dove i
                // percorsi divergono si deve poter capire quale e' quale.
                for (final i in mostrate)
                  Polyline(
                    points: directions[i].points,
                    strokeWidth: Cartina.spessorePercorso,
                    color: cartina.direzione(i),
                  ),
                for (final d in deviations)
                  Polyline(
                    points: d,
                    strokeWidth: Cartina.spessoreDeviazione,
                    color: cartina.deviazione,
                  ),
                // Il tratto che i mezzi hanno percorso DAVVERO fuori
                // dal percorso normale. Colore diverso dal rosso
                // apposta: quello e' ricostruito da un testo, questo
                // e' misurato, e non sono la stessa cosa.
                if (osservato.length > 1)
                  Polyline(
                    points: osservato,
                    strokeWidth: Cartina.spessoreDeviazione,
                    color: cartina.osservato,
                  ),
              ],
            ),
            // Le fermate servite: piccole e discrete, non devono coprire
            // il percorso.
            MarkerLayer(
              markers: [
                for (final s in served)
                  _stopMarker(
                    stop: s,
                    impact: null,
                    selected: _selected?.stop.id == s.id,
                    direzione: direzioneDi[s.id],
                    verso: versoDi(s.id),
                  ),
              ],
            ),
            // Le saltate sopra, piu' grandi: sono quelle che contano.
            MarkerLayer(
              markers: [
                for (final entry in skipped.entries)
                  _stopMarker(
                    stop: entry.value.stop,
                    impact: entry.value,
                    selected: _selected?.stop.id == entry.key,
                  ),
              ],
            ),
            MarkerLayer(
              markers: [
                _endMarker(official.first, Colors.green.shade700),
                _endMarker(official.last, Colors.blueGrey.shade700),
              ],
            ),
            // I mezzi, sopra a tutto.
            if (widget.vehicles.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (final t in widget.vehicles)
                    if (t.points.isNotEmpty &&
                        _nellaDirezione(t, directions, sola))
                      _vehicleMarker(t, [for (final d in directions) d.shape]),
                ],
              ),
            if (_me != null) MarkerLayer(markers: [_meMarker(_me!)]),
            // Sempre visibile: CARTO non la vuole dietro un tocco, e
            // l'icona «i» di prima la nascondeva.
            // Una scritta nostra e non SimpleAttributionWidget, che mette
            // davanti «flutter_map | ©» e ripete il simbolo. In alto:
            // in basso la copre il pulsante dei mezzi, che fluttua sulla
            // pagina, e CARTO la vuole sempre visibile.
            Align(
              alignment: Alignment.topLeft,
              child: Container(
                margin: EdgeInsets.fromLTRB(4, widget.inset.top + 4, 4, 4),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: cartina.fondoAttribuzione,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  cartina.attribuzione,
                  style: TextStyle(
                    fontSize: 10,
                    color: cartina.scura ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 10,
          bottom: 10 + widget.inset.bottom,
          child: widget.fullScreen
              ? _comandiConScritta()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Nel dettaglio la mappa e' piccola: il pulsante la
                    // apre. A tutto schermo torna a inquadrare il percorso.
                    if (widget.onOpenFullScreen != null)
                      _MapButton(
                        icon: Icons.open_in_full,
                        tooltip: 'Mappa a tutto schermo',
                        onPressed: widget.onOpenFullScreen!,
                      )
                    else
                      _MapButton(
                        icon: Icons.zoom_out_map,
                        tooltip: 'Inquadra tutto il percorso',
                        onPressed: _fitRoute,
                      ),
                    const SizedBox(height: 8),
                    _MapButton(
                      icon: _locationSub != null
                          ? Icons.my_location
                          : Icons.location_searching,
                      tooltip: _locationSub != null
                          ? 'Non seguire la mia posizione'
                          : 'La mia posizione',
                      active: _locationSub != null,
                      busy: _locating,
                      onPressed: _showMe,
                    ),
                  ],
                ),
        ),
      ],
    );
    if (widget.fullScreen) return mappa;

    return Column(
      children: [
        SizedBox(height: widget.height, child: mappa),
        if (_selected != null)
          FermataToccata(
            stop: _selected!.stop,
            impact: _selected!.impact,
            direction: _shapeOf(_selected!.stop) == null
                ? null
                : DisplayNames.direction(
                    _shapeOf(_selected!.stop)!.headsign,
                    longName: status.line.longName,
                  ),
            saved: _savedState(_selected!.stop),
            onToggleSave: _saveAction(_selected!.stop),
            onClose: () => setState(() => _selected = null),
          )
        else
          _Legend(
            hasDeviation: deviations.isNotEmpty,
            // Nessuna geometria ma delle fermate saltate: puo' succedere
            // solo quando GTT ha nominato le fermate sospese senza
            // annunciare un cambio di percorso. Dire "non ricostruita"
            // sarebbe una bugia — non c'era niente da ricostruire.
            onlySuspendedStops: deviations.isEmpty && skipped.isNotEmpty,
            // Senza avvisi in corso non c'e' niente da ricostruire: dire
            // «deviazione non ricostruita» su una linea regolare, come la 4
            // il 26/09, fa pensare a una deviazione che non esiste.
            hasActiveNotices: status.activeReports.isNotEmpty,
            canSave: widget.onToggleSave != null,
            hasObserved: osservato.length > 1,
            skippedCount: skipped.length,
            servedCount: served.length,
            vehicleCount: widget.vehicles.length,
            vehiclesSeenAt: _lastSeen,
            directions: [
              for (final d in directions)
                DisplayNames.direction(
                  d.shape.headsign,
                  longName: widget.status.line.longName,
                ),
            ],
          ),
      ],
    );
  }

  /// Una fermata. Quelle servite hanno il bordo del colore della loro
  /// direzione e una freccia verso dove va il mezzo che passa di li'
  /// ([verso], preso dal percorso); quelle non servite sono rosse con la
  /// croce, che e' la cosa da vedere.
  Marker _stopMarker({
    required TransitStop stop,
    required StopImpact? impact,
    required bool selected,
    int? direzione,
    double? verso,
  }) {
    final cartina = Cartina.of(context);
    final isSkipped = impact != null;
    // Servite a 17: a 11, com'erano, dentro non ci stava una freccia.
    final dot = isSkipped ? 20.0 : (selected ? 22.0 : 17.0);

    // Il pallino visibile e' piccolo, ma il Marker di flutter_map usa le
    // proprie dimensioni ANCHE come area sensibile al tocco: con 11 px non
    // si prende mai. Il marcatore e' quindi grande [_tapTarget] con il
    // pallino centrato dentro. Verificato sul simulatore: prima il tocco
    // mancava il bersaglio quasi sempre.
    return Marker(
      point: LatLng(stop.position.lat, stop.position.lon),
      width: _tapTarget,
      height: _tapTarget,
      child: GestureDetector(
        onTap: () => setState(() => _selected = (stop: stop, impact: impact)),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: isSkipped
              ? Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: cartina.chiusa,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(Icons.close, size: 11, color: Colors.white),
                )
              : SizedBox.square(
                  dimension: dot,
                  child: CustomPaint(
                    painter: SegnoFermata(
                      colore: direzione == null
                          ? cartina.bordoFermata
                          : cartina.direzione(direzione),
                      bordo: selected ? cartina.selezione : null,
                      gradi: verso,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  /// Un mezzo si mostra se va nella direzione mostrata, o se la sua
  /// direzione non si capisce: nasconderlo per un dubbio farebbe sparire
  /// proprio i mezzi in deviazione.
  static bool _nellaDirezione(
    VehicleTrack t,
    List<({RouteShape shape, List<LatLng> points})> directions,
    int? sola,
  ) {
    if (sola == null) return true;
    final d = VehicleHeading.of(t, [
      for (final x in directions) x.shape,
    ]).directionIndex;
    return d == null || d == sola;
  }

  /// Lato dell'area toccabile di una fermata: i 44 punti delle linee
  /// guida Apple. Era 34, per paura che fermate vicine si rubassero i
  /// tocchi; ma alle distanze normali fra fermate (300 m, una sessantina
  /// di punti allo zoom con cui si apre la mappa) le aree non si
  /// sovrappongono, e 34 si mancava col pollice.
  static const _tapTarget = 44.0;

  /// Quando risale l'ultima posizione ricevuta.
  ///
  /// A osservazione finita i marcatori restano sulla mappa: senza dire
  /// quando sono stati visti, dopo dieci minuti si guarderebbero posizioni
  /// vecchie credendole attuali.
  DateTime? get _lastSeen {
    DateTime? latest;
    for (final t in widget.vehicles) {
      for (final p in t.points) {
        if (latest == null || p.seenAt.isAfter(latest)) latest = p.seenAt;
      }
    }
    return latest;
  }

  /// Un mezzo nella sua ultima posizione nota.
  ///
  /// Quelli fuori percorso sono rossi: e' l'informazione che si sta
  /// cercando quando si accende l'osservazione.
  /// Il pallino azzurro. Deliberatamente diverso dalle fermate e dai
  /// mezzi: e' l'unica cosa sulla mappa che non viene da GTT.
  Marker _meMarker(GeoPoint p) => Marker(
    point: LatLng(p.lat, p.lon),
    width: 26,
    height: 26,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.blue.shade600,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.4),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
    ),
  );

  /// Il mezzo: un pallino con la punta verso dove sta andando.
  ///
  /// Il colore e' quello della direzione che sta facendo, lo stesso delle
  /// due linee del percorso: si vede a colpo d'occhio se il 15 laggiu'
  /// viene verso di te o se ne va. Rosso se e' fuori percorso — e' la
  /// cosa che conta di piu' — e blu se la direzione non si capisce.
  Marker _vehicleMarker(VehicleTrack track, List<RouteShape> directions) {
    final cartina = Cartina.of(context);
    final last = track.points.last;
    final rotta = VehicleHeading.of(track, directions);
    final Color colore;
    if (track.isOffRoute) {
      colore = cartina.chiusa;
    } else {
      colore = cartina.mezzo(rotta.directionIndex);
    }
    return Marker(
      point: LatLng(last.position.lat, last.position.lon),
      width: 40,
      height: 40,
      child: CustomPaint(
        painter: SegnoMezzo(colore: colore, gradi: rotta.degrees),
        child: const Center(
          child: Icon(Icons.directions_bus, size: 13, color: Colors.white),
        ),
      ),
    );
  }

  static Marker _endMarker(LatLng at, Color colour) => Marker(
    point: at,
    width: 14,
    height: 14,
    child: Container(
      decoration: BoxDecoration(
        color: colour,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    ),
  );
}

/// Cosa si e' toccato. Sostituisce la legenda mentre e' aperto: sono
/// entrambe righe di servizio sotto la mappa, e averle insieme fa
/// disordine.
class FermataToccata extends StatelessWidget {
  const FermataToccata({
    required this.stop,
    required this.impact,
    required this.onClose,
    this.direction,
    this.saved,
    this.onToggleSave,
    super.key,
  });

  final TransitStop stop;
  final StopImpact? impact;

  /// Verso dove va il mezzo da questo palo: salvando la fermata si salva
  /// anche la direzione, e va detto quale.
  final String? direction;

  /// null quando la mappa non sa salvare.
  final bool? saved;
  final VoidCallback? onToggleSave;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final skipped = impact != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      color: skipped
          ? scheme.errorContainer.withValues(alpha: 0.5)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          Icon(
            skipped ? Icons.do_not_disturb_on_outlined : Icons.place_outlined,
            size: 18,
            color: skipped ? scheme.error : scheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DisplayNames.stop(stop),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  [
                    skipped
                        ? (impact!.status == StopStatus.declaredSuspended
                              ? 'sospesa da GTT'
                              : 'non servita')
                        : 'servita',
                    if (stop.code != null) 'fermata ${stop.code}',
                    if (direction != null) 'verso $direction',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (skipped)
                  for (final alt in impact!.alternatives.take(2))
                    Text(
                      '→ ${DisplayNames.stop(alt.stop)}'
                      '${alt.stop.code == null ? "" : " ${alt.stop.code}"} · '
                      '${alt.bestKnownMeters.round()} m'
                      '${alt.sameLine ? "" : " · altre linee"}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
              ],
            ),
          ),
          // Salvarla la porta nella home, con la sua risposta: e' il
          // modo di dire all'app «questa e' la mia fermata».
          if (saved != null && onToggleSave != null)
            TextButton.icon(
              onPressed: onToggleSave,
              icon: Icon(saved! ? Icons.bookmark : Icons.bookmark_add_outlined),
              label: Text(saved! ? 'Salvata' : 'Salva'),
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Chiudi',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Senza legenda pallini e linee colorate non dicono nulla.
class _Legend extends StatelessWidget {
  const _Legend({
    required this.hasDeviation,
    required this.onlySuspendedStops,
    required this.hasActiveNotices,
    required this.hasObserved,
    this.canSave = false,
    required this.skippedCount,
    required this.servedCount,
    required this.vehicleCount,
    required this.vehiclesSeenAt,
    required this.directions,
  });

  final bool hasDeviation;
  final bool onlySuspendedStops;
  final bool hasActiveNotices;
  final bool hasObserved;
  final bool canSave;
  final int skippedCount;
  final int servedCount;
  final int vehicleCount;
  final DateTime? vehiclesSeenAt;

  /// I capolinea delle direzioni disegnate, in ordine.
  final List<String> directions;

  @override
  Widget build(BuildContext context) {
    final cartina = Cartina.of(context);
    final style = Theme.of(context).textTheme.bodySmall;
    final tenue = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (var i = 0; i < directions.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CampioneDirezione(colore: cartina.direzione(i)),
                    const SizedBox(width: 6),
                    Text(
                      directions.length == 1
                          ? 'percorso normale'
                          : 'verso ${_shortHeadsign(directions[i])}',
                      style: style,
                    ),
                  ],
                ),
              if (hasDeviation)
                _line(cartina.deviazione, 'percorso deviato', style)
              else if (onlySuspendedStops)
                Text('nessun cambio di percorso', style: style)
              else if (hasActiveNotices && !hasObserved)
                Text('percorso deviato non disponibile', style: style),
              if (hasObserved)
                _line(cartina.osservato, 'percorso dei mezzi', style),
              _dot(
                Colors.white,
                cartina.bordoFermata,
                '$servedCount fermate',
                style,
              ),
              if (skippedCount > 0)
                _dot(
                  cartina.chiusa,
                  Colors.white,
                  '$skippedCount non servite',
                  style,
                ),
              if (vehicleCount > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.navigation, size: 13, color: tenue),
                    const SizedBox(width: 4),
                    Text(
                      '$vehicleCount in circolazione, con la direzione'
                      '${vehiclesSeenAt == null ? "" : " · ${_hhmm(vehiclesSeenAt!)}"}',
                      style: style,
                    ),
                  ],
                ),
              Text(
                canSave
                    ? 'tocca una fermata per salvarla'
                    : 'tocca una fermata per i dettagli',
                style: style,
              ),
            ],
          ),
          // Il rosso sulla mappa sembra un fatto, ed e' una ricostruzione:
          // le vie dell'avviso cercate sulla cartina e unite dal calcolo
          // del percorso. Va detto accanto al disegno, non solo in fondo
          // alla scheda dell'avviso, dove arriva chi ha gia' deciso.
          if (hasDeviation)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 14, color: tenue),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Il percorso deviato è ricostruito dal testo '
                      'dell\'avviso: potrebbe non essere esatto.',
                      style: style?.copyWith(color: tenue),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _hhmm(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, "0")}:'
        '${l.minute.toString().padLeft(2, "0")}';
  }

  /// Il capolinea sta in una legenda: va accorciato o la riga esplode.
  ///
  /// Arriva gia' ripulito da [DisplayNames.direction]: prima si prendeva
  /// la prima parte del headsign, e sulla 10N — «NAVETTA, VIA MASSARI» e
  /// «NAVETTA, PIAZZA XVIII DICEMBRE» — la legenda diceva «→ NAVETTA» due
  /// volte.
  static String _shortHeadsign(String h) =>
      h.length <= 24 ? h : '${h.substring(0, 23)}…';

  Widget _line(Color c, String label, TextStyle? style) => Row(
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
      Text(label, style: style),
    ],
  );

  Widget _dot(Color fill, Color border, String label, TextStyle? style) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: border, width: 2),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: style),
    ],
  );
}

/// Un pulsante tondo sopra la mappa.
///
/// Stanno sulla mappa e non nella scheda sotto perche' sono comandi della
/// mappa, ed e' li' che uno li cerca.
/// Un comando della mappa a tutto schermo: icona e parola.
///
/// Alto 48 punti, con la scritta a 15: si prende col pollice e si legge
/// senza occhiali. Acceso, prende il giallo di DeviaTo.
class _Comando extends StatelessWidget {
  const _Comando({
    required this.icon,
    required this.testo,
    required this.onPressed,
    this.attivo = false,
    this.busy = false,
    this.indicatore,
    this.descrizione,
  });

  /// Quanto e' largo il comando con la scritta piu' lunga fra [scritte]:
  /// icona, spazio, scritta e margini, con la dimensione del testo scelta
  /// sul telefono.
  static double larghezza(BuildContext context, List<String> scritte) {
    final scala = MediaQuery.textScalerOf(context);
    var massima = 0.0;
    for (final t in scritte) {
      final p = TextPainter(
        text: TextSpan(text: t, style: _stile),
        textDirection: TextDirection.ltr,
        textScaler: scala,
        maxLines: 1,
      )..layout();
      if (p.width > massima) massima = p.width;
    }
    // Margini 16 + 16, icona 20, spazio 8, e un punto per gli arrotondamenti.
    final w = massima + 61;
    // Mai piu' di due terzi dello schermo: con il testo grandissimo la
    // scritta va a capo invece di coprire la mappa.
    return w.clamp(0, MediaQuery.sizeOf(context).width * 2 / 3).toDouble();
  }

  static const _stile = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);

  final IconData icon;
  final String testo;
  final VoidCallback onPressed;
  final bool attivo;
  final bool busy;

  /// Al posto dell'icona, qualcosa che si muove: il comando resta
  /// toccabile, a differenza di [busy].
  final Widget? indicatore;

  /// Per i lettori di schermo, quando la scritta non dice tutto.
  final String? descrizione;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fondo = attivo ? scheme.primaryContainer : scheme.surface;
    final colore = attivo ? scheme.onPrimaryContainer : scheme.onSurface;
    final pulsante = Material(
      color: fondo,
      shape: const StadiumBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: busy ? null : onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: colore,
                    ),
                  )
                else if (indicatore != null)
                  IconTheme(
                    data: IconThemeData(color: colore, size: 20),
                    child: SizedBox(width: 20, height: 20, child: indicatore),
                  )
                else
                  Icon(icon, size: 20, color: colore),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    testo,
                    style: _stile.copyWith(color: colore),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final d = descrizione;
    return d == null
        ? pulsante
        : Semantics(
            button: true,
            label: d,
            onTap: busy ? null : onPressed,
            excludeSemantics: true,
            child: pulsante,
          );
  }
}

/// La rotellina del comando dei mezzi, mentre li si cerca.
class _Rotella extends StatelessWidget {
  const _Rotella();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: CircularProgressIndicator(
      strokeWidth: 2.5,
      color: IconTheme.of(context).color,
    ),
  );
}

/// Il pallino «in diretta»: un punto fermo e un anello che si allarga e
/// svanisce, una volta ogni secondo e mezzo. Con le animazioni ridotte
/// resta il punto.
class _Pulsazione extends StatefulWidget {
  const _Pulsazione();

  @override
  State<_Pulsazione> createState() => _PulsazioneState();
}

class _PulsazioneState extends State<_Pulsazione>
    with SingleTickerProviderStateMixin {
  late final _giro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _giro.stop();
    } else if (!_giro.isAnimating) {
      _giro.repeat();
    }
  }

  @override
  void dispose() {
    _giro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colore = IconTheme.of(context).color ?? Colors.black;
    final fermo = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _giro,
      builder: (context, _) {
        final t = fermo ? 0.0 : Curves.easeOut.transform(_giro.value);
        return Stack(
          alignment: Alignment.center,
          children: [
            if (!fermo)
              Container(
                width: 8 + 12 * t,
                height: 8 + 12 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colore.withValues(alpha: 0.7 * (1 - t)),
                    width: 2,
                  ),
                ),
              ),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(shape: BoxShape.circle, color: colore),
            ),
          ],
        );
      },
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Acceso: la funzione e' in corso (per ora solo "ti sto seguendo").
  final bool active;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surface,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: busy ? null : onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(13),
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Icon(
                    icon,
                    size: 22,
                    color: active
                        ? StatusColors.of(context).info
                        : scheme.onSurface,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Il segno del mezzo: un cerchio con una punta nella direzione di marcia.
///
/// Senza rotta nota resta un cerchio: una freccia orientata a caso
/// direbbe una cosa che non sappiamo.
class SegnoMezzo extends CustomPainter {
  const SegnoMezzo({required this.colore, required this.gradi});

  final Color colore;

  /// 0 nord, in senso orario. null se non si sa.
  final double? gradi;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const raggio = 10.5;
    const punta = 17.0;
    var forma = ui.Path()..addOval(Rect.fromCircle(center: c, radius: raggio));
    final g = gradi;
    if (g != null) {
      // Sullo schermo y cresce verso il basso: il nord e' -y.
      final a = g * math.pi / 180;
      Offset verso(double angolo, double r) =>
          c + Offset(math.sin(angolo), -math.cos(angolo)) * r;
      final cima = verso(a, punta);
      final destra = verso(a + 0.62, raggio);
      final sinistra = verso(a - 0.62, raggio);
      final freccia = ui.Path()
        ..moveTo(cima.dx, cima.dy)
        ..lineTo(destra.dx, destra.dy)
        ..lineTo(sinistra.dx, sinistra.dy)
        ..close();
      forma = ui.Path.combine(PathOperation.union, forma, freccia);
    }
    canvas.drawShadow(forma, Colors.black, 2, false);
    canvas.drawPath(forma, Paint()..color = colore);
    canvas.drawPath(
      forma,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(SegnoMezzo old) =>
      old.colore != colore || old.gradi != gradi;
}

/// Il segno di una fermata servita: un pallino bianco col bordo del colore
/// della direzione e, dentro, una freccia verso dove va il mezzo.
///
/// Senza verso resta un pallino: una freccia a caso direbbe una cosa che
/// non sappiamo.
class SegnoFermata extends CustomPainter {
  const SegnoFermata({required this.colore, this.bordo, this.gradi});

  /// Il colore della direzione: bordo e freccia.
  final Color colore;

  /// Il bordo della fermata toccata, se diverso da [colore].
  final Color? bordo;

  /// 0 nord, in senso orario. null se non si sa.
  final double? gradi;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final spessore = bordo == null ? 2.0 : 3.0;
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      r - spessore / 2,
      Paint()
        ..color = bordo ?? colore
        ..style = PaintingStyle.stroke
        ..strokeWidth = spessore,
    );
    final g = gradi;
    if (g == null) return;
    // Una freccia vera, asta e punta, come quelle dei cartelli: la punta
    // da sola, col retro incavato, sembrava una punta di lancia. Si
    // disegna verso l'alto (il nord, perche' sullo schermo y cresce verso
    // il basso) e si gira della rotta.
    final l = r - spessore - 1.2;
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(g * math.pi / 180);
    canvas.drawLine(
      Offset(0, l * 0.9),
      Offset(0, -l * 0.15),
      Paint()
        ..color = colore
        ..strokeWidth = math.max(1.6, r * 0.2)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      ui.Path()
        ..moveTo(0, -l)
        ..lineTo(l * 0.62, -l * 0.08)
        ..lineTo(-l * 0.62, -l * 0.08)
        ..close(),
      Paint()..color = colore,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(SegnoFermata old) =>
      old.colore != colore || old.bordo != bordo || old.gradi != gradi;
}

/// Il campione di una direzione nelle legende: un tratto di linea con una
/// fermata e la sua freccia, come sulla mappa.
class CampioneDirezione extends StatelessWidget {
  const CampioneDirezione({super.key, required this.colore});

  final Color colore;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    height: 16,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: 5,
          decoration: BoxDecoration(
            color: colore,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox.square(
          dimension: 16,
          child: CustomPaint(
            painter: SegnoFermata(colore: colore, gradi: 90),
          ),
        ),
      ],
    ),
  );
}
