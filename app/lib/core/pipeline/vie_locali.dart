import 'dart:convert';
import 'dart:io';

import '../geo/geometry.dart';
import '../geo/polyline.dart';
import '../geo/projection.dart';

/// Le vie di OpenStreetMap da un file, invece che da Overpass.
///
/// Overpass e' un servizio pubblico che spesso non risponde o ci mette un
/// minuto e mezzo: il 10/11/2026 la linea 9 si ricalcolava a ogni giro,
/// tre minuti ogni volta, perche' la forma delle vie non arrivava. Il file
/// lo prepara una volta a settimana `.github/workflows/vie.yml` (formato in
/// `scripts/vie_da_osm.py`): le strade con un nome e i binari del tram
/// nella zona di GTT, ognuna col suo riquadro.
///
/// Risponde alle stesse due domande che si facevano a Overpass — le vie con
/// un nome in un riquadro, i binari in un riquadro — con le vie INTERE,
/// anche se dal riquadro passano appena, come `out geom`.
class VieLocali {
  VieLocali._(this.data, this._vie, this._binari);

  /// Il giorno dell'estratto («2026-11-08»).
  final String data;
  final List<_Via> _vie;
  final List<_Via> _binari;

  int get quante => _vie.length;

  /// Legge il file, compresso (`.gz`) o no. null se manca o non si legge:
  /// chi chiama torna a Overpass.
  static VieLocali? leggi(File f) {
    if (!f.existsSync()) return null;
    try {
      final byte = f.readAsBytesSync();
      final testo = utf8.decode(
        f.path.endsWith('.gz') ? gzip.decode(byte) : byte,
      );
      return daJson(jsonDecode(testo) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  static VieLocali daJson(Map<String, dynamic> j) => VieLocali._(
    j['data'] as String? ?? '',
    [
      for (final v in (j['vie'] as List).cast<List<dynamic>>())
        _Via(v[0] as String, v, 1),
    ],
    [
      for (final v in (j['binari'] as List? ?? const []).cast<List<dynamic>>())
        _Via('', v, 0),
    ],
  );

  /// Le strade con un nome che toccano il riquadro [b].
  List<({String nome, List<GeoPoint> punti})> vie(Bounds b) => [
    for (final v in _vie)
      if (v.tocca(b)) (nome: v.nome, punti: v.punti),
  ];

  /// I binari del tram che toccano il riquadro [b].
  List<List<GeoPoint>> binari(Bounds b) => [
    for (final v in _binari)
      if (v.tocca(b)) v.punti,
  ];
}

class _Via {
  _Via(this.nome, List<dynamic> v, int da)
    : minLat = (v[da] as num).toDouble(),
      minLon = (v[da + 1] as num).toDouble(),
      maxLat = (v[da + 2] as num).toDouble(),
      maxLon = (v[da + 3] as num).toDouble(),
      _codice = v[da + 4] as String;

  final String nome;
  final double minLat, minLon, maxLat, maxLon;
  final String _codice;

  /// I punti si decodificano solo per le vie che servono, e una volta.
  late final List<GeoPoint> punti = PolylineCodec.decode(
    _codice,
    precision: 7,
  );

  /// Il riquadro della via tocca [b]. Un po' piu' largo di Overpass, che
  /// guarda i nodi: una via che gira attorno al riquadro senza entrarci
  /// passa, e poi la scarta il confronto dei nomi o la distanza.
  bool tocca(Bounds b) =>
      maxLat >= b.minLat &&
      minLat <= b.maxLat &&
      maxLon >= b.minLon &&
      minLon <= b.maxLon;
}
