// I mezzi seguiti dal banco di prova, e quanto i due percorsi deviati
// calcolati coincidono con quello che fanno davvero.
import 'package:gtt_deviazioni/core/config.dart';
import 'package:gtt_deviazioni/core/geo/geometry.dart';
import 'package:gtt_deviazioni/core/geo/projection.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/pipeline/route_excursion.dart';
import 'package:gtt_deviazioni/core/pipeline/vehicle_heading.dart';
import 'package:gtt_deviazioni/core/pipeline/vehicle_watch.dart';
import 'package:gtt_deviazioni/core/ricostruzione/rifinitura.dart';
import 'package:gtt_deviazioni/core/sources/vehicles_source.dart';

import 'confronto.dart';

/// Una linea seguita: i mezzi visti, campione dopo campione.
class LineaSeguita {
  LineaSeguita(this.routeId, this.percorsi);

  final String routeId;

  /// Tutte le varianti della linea: un mezzo sulla corsa limitata non sta
  /// deviando.
  final List<RouteShape> percorsi;

  final DateTime da = DateTime.now();
  final Map<String, VehicleTrack> tracce = {};
  int campioni = 0;
  bool feedSpento = false;
  DateTime? ultimo;

  /// Un punto del rosso e' confermato se un mezzo e' passato a meno di cosi'.
  static const vicino = 40.0;

  /// Oltre questo intervallo fra due posizioni la traccia non si unisce:
  /// una corda di minuti taglierebbe gli isolati.
  static const buco = Duration(seconds: 70);

  void aggiungi(VehicleSnapshot foto) {
    campioni++;
    ultimo = DateTime.now();
    feedSpento = foto.feedIsOff;
    for (final o in foto.matching) {
      if (o.routeId != routeId) continue;
      final t = tracce.putIfAbsent(o.vehicleId, () => VehicleTrack(o.vehicleId));
      if (t.points.isNotEmpty && t.points.last.seenAt == o.seenAt) continue;
      t.points.add(o);
    }
  }

  List<RouteShape> get _principali => [
        for (final d in [0, 1]) ?_principale(d),
      ];

  RouteShape? _principale(int direzione) {
    RouteShape? m;
    for (final s in percorsi) {
      if (s.directionId != direzione) continue;
      if (m == null || s.tripCount > m.tripCount) m = s;
    }
    return m;
  }

  /// La direzione di un mezzo: la piu' votata lungo la sua traccia. Un
  /// mezzo in deviazione e' lontano dal percorso, e dall'ultima posizione
  /// sola la direzione non si capisce.
  String? _direzione(VehicleTrack t) {
    final principali = _principali;
    final voti = <int, int>{};
    for (var k = 1; k < t.points.length; k++) {
      final parziale = VehicleTrack(t.vehicleId)..points.addAll(t.points.take(k + 1));
      final d = VehicleHeading.of(parziale, principali).directionIndex;
      if (d != null) voti[d] = (voti[d] ?? 0) + 1;
    }
    if (voti.isEmpty) return null;
    final meglio = voti.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return principali[meglio.key].shapeId;
  }

  bool _fuori(GeoPoint p) {
    final m = p.meters;
    for (final s in percorsi) {
      if (s.points.length < 2) continue;
      if (Geometry.pointToPolyline(m, s.meters) <= GttConfig.offRouteMeters) {
        return false;
      }
    }
    return true;
  }

  /// I mezzi e, per ogni confronto di questa linea, quanto i due rossi
  /// coincidono con loro.
  Map<String, Object?> json(List<Map<String, Object?>> confronti) {
    final direzioni = {for (final t in tracce.values) t.vehicleId: _direzione(t)};
    final mezzi = [
      for (final t in tracce.values)
        {
          'id': t.vehicleId,
          'dir': direzioni[t.vehicleId],
          'punti': [
            for (final o in t.points)
              [o.position.lat, o.position.lon, _fuori(o.position)],
          ],
          'visto': t.points.last.seenAt.toIso8601String(),
        },
    ];

    final perConfronto = <Map<String, Object?>>[];
    for (final c in confronti) {
      final shapeId = c['percorso'] as String;
      final shape = percorsi.where((s) => s.shapeId == shapeId).firstOrNull;
      if (shape == null) continue;
      final mie = [
        for (final t in tracce.values)
          if (direzioni[t.vehicleId] == shapeId) t,
      ];
      final tutti = [for (final t in mie) ...t.points.map((o) => o.position)];
      final fuori = [for (final p in tutti) if (_fuori(p)) p];
      // Un tratto fuori percorso conta solo se lo fanno almeno due mezzi:
      // uno solo puo' essere un rinforzo che rientra al deposito con la
      // posizione accesa (Tommaso, 30/09/2026). Una posizione fuori vale se
      // un altro mezzo e' passato li' vicino.
      final perMezzo = {for (final t in mie) t.vehicleId: _tratti(t)};
      final condivisi = [
        for (final t in mie)
          for (final o in t.points)
            if (_fuori(o.position) &&
                perMezzo.entries.any((e) =>
                    e.key != t.vehicleId &&
                    _passa(e.value, o.position.meters)))
              o.position,
      ];
      final uscite = <List<double>>[], rientri = <List<double>>[];
      for (final t in mie) {
        for (final e in RouteExcursion.detect(
          track: t,
          officialRoute: shape.meters,
          offRouteMeters: GttConfig.offRouteMeters,
          allRoutes: [for (final s in percorsi) s.meters],
        )) {
          uscite.add(_sulla(shape, e.detachAlongMeters));
          if (e.rejoinAlongMeters case final r?) rientri.add(_sulla(shape, r));
        }
      }
      perConfronto.add({
        'percorso': shapeId,
        'avviso': c['avviso'],
        'mezzi': mie.length,
        'punti': tutti.length,
        'fuori': fuori.length,
        'fuoriDaDue': condivisi.length,
        'uscite': uscite,
        'rientri': rientri,
        for (final a in ['a1', 'a2'])
          a: _valuta(
            Confronto.punti((c[a] as Map)['geometria']),
            condivisi,
            perMezzo,
            shape,
          ),
      });
    }
    return {
      'linea': routeId,
      'da': da.toIso8601String(),
      'campioni': campioni,
      'ultimo': ultimo?.toIso8601String(),
      'feedSpento': feedSpento,
      'mezzi': mezzi,
      'confronti': perConfronto,
    };
  }

  /// Quanto un rosso coincide coi mezzi.
  ///
  /// - spiegati: dei punti in cui i mezzi stanno fuori dal percorso
  ///   normale — solo quelli dove e' passato anche un altro mezzo — quanti
  ///   cadono sul rosso. Dice se il rosso va dove vanno loro.
  /// - confermato: del tratto di rosso fuori dalla linea normale, quanto e'
  ///   stato percorso da almeno due mezzi, nel verso del rosso. Dice se il
  ///   rosso inventa vie dove nessuno passa. Vale solo se i mezzi hanno
  ///   fatto tutta la deviazione. Il verso conta: sulla 27 il 30/09 il
  ///   rosso del primo algoritmo verso Barca stava su via Gottardo, che la
  ///   linea fa nell'altro senso, e sembrava percorso.
  Map<String, Object?> _valuta(
    List<GeoPoint> rosso,
    List<GeoPoint> fuori,
    Map<String, List<List<Point>>> perMezzo,
    RouteShape normale,
  ) {
    final r = [for (final p in rosso) p.meters];
    double? spiegati;
    if (fuori.isNotEmpty && r.length >= 2) {
      final ok = fuori
          .where((p) => Geometry.pointToPolyline(p.meters, r) <= vicino)
          .length;
      spiegati = ok / fuori.length;
    }
    double? confermato;
    if (perMezzo.length >= 2 && r.length >= 2) {
      final l = normale.meters;
      final fitto = Geometry.densify(r, 20);
      final campioni = [
        for (var k = 0; k < fitto.length; k++)
          // Il rosso che sta sulla linea normale non e' deviazione.
          if (Geometry.pointToPolyline(fitto[k], l) > Rifinitura.sopraLaLinea)
            (
              punto: fitto[k],
              verso: _verso(
                fitto[k == 0 ? 0 : k - 1],
                fitto[k == fitto.length - 1 ? k : k + 1],
              ),
            ),
      ];
      if (campioni.isNotEmpty) {
        final ok = campioni.where(
          (c) =>
              perMezzo.values
                  .where((t) => _passaNelVerso(t, c.punto, c.verso))
                  .length >=
              2,
        );
        confermato = ok.length / campioni.length;
      }
    }
    return {'spiegati': spiegati, 'confermato': confermato};
  }

  /// La traccia di un mezzo passa a meno di [vicino] da [q]?
  static bool _passa(List<List<Point>> tratti, Point q) =>
      tratti.any((t) => Geometry.pointToPolyline(q, t) <= vicino);

  /// Come [_passa], ma andando nel [verso] dato (un vettore di lunghezza
  /// uno), entro 60 gradi.
  static bool _passaNelVerso(List<List<Point>> tratti, Point q, Point verso) {
    for (final t in tratti) {
      for (var i = 0; i < t.length - 1; i++) {
        final a = t[i], b = t[i + 1];
        if (Geometry.pointToPolyline(q, [a, b]) > vicino) continue;
        final v = _verso(a, b);
        if (v.x * verso.x + v.y * verso.y > 0.5) return true;
      }
    }
    return false;
  }

  /// Il vettore di lunghezza uno da [a] a [b]; zero se coincidono.
  static Point _verso(Point a, Point b) {
    final dx = b.x - a.x, dy = b.y - a.y;
    final l = a.distanceTo(b);
    return l < 1e-6 ? const Point(0, 0) : Point(dx / l, dy / l);
  }

  /// La traccia di un mezzo in tratti senza buchi.
  static List<List<Point>> _tratti(VehicleTrack t) {
    final punti = [...t.points]..sort((a, b) => a.seenAt.compareTo(b.seenAt));
    final out = <List<Point>>[];
    var corrente = <Point>[];
    for (var i = 0; i < punti.length; i++) {
      if (i > 0 && punti[i].seenAt.difference(punti[i - 1].seenAt) > buco) {
        if (corrente.length >= 2) out.add(corrente);
        corrente = [];
      }
      corrente.add(punti[i].position.meters);
    }
    if (corrente.length >= 2) out.add(corrente);
    return out;
  }

  static List<double> _sulla(RouteShape s, double metri) {
    final q = Geometry.pointAtAlong(s.meters, metri)!;
    final (lat, lon) = Projection.toDegrees(q);
    return [lat, lon];
  }
}
