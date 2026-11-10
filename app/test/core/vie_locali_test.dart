import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/geo/geometry.dart';
import 'package:gtt_deviazioni/core/geo/polyline.dart';
import 'package:gtt_deviazioni/core/geo/projection.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/net/gtt_http.dart';
import 'package:gtt_deviazioni/core/pipeline/vie_locali.dart';
import 'package:gtt_deviazioni/core/pipeline/vie_osm.dart';

/// Overpass non si deve chiamare affatto, quando le vie stanno sul disco.
class _MaiChiamato extends GttHttp {
  @override
  Future<String> getTextPolite(String url, {Duration? timeout}) =>
      fail('Overpass chiamato: $url');
}

void main() {
  List<dynamic> via(String? nome, List<GeoPoint> p) => [
    ?nome,
    p.map((x) => x.lat).reduce((a, b) => a < b ? a : b),
    p.map((x) => x.lon).reduce((a, b) => a < b ? a : b),
    p.map((x) => x.lat).reduce((a, b) => a > b ? a : b),
    p.map((x) => x.lon).reduce((a, b) => a > b ? a : b),
    PolylineCodec.encode(p, precision: 7),
  ];
  const cibrario = [GeoPoint(45.0791234, 7.6601234), GeoPoint(45.0795, 7.665)];
  const lontana = [GeoPoint(45.2, 7.9), GeoPoint(45.21, 7.91)];
  const binario = [GeoPoint(45.0792, 7.6602), GeoPoint(45.0793, 7.6612)];
  final dati = {
    'versione': 1,
    'data': '2026-11-08',
    'vie': [
      via('Via Luigi Cibrario', cibrario),
      via('Via Luigi Cibrario', lontana),
      via('Corso Francia', cibrario),
    ],
    'binari': [via(null, binario), via(null, lontana)],
  };
  final linea = RouteShape(
    shapeId: 'x',
    routeId: '9U',
    directionId: 0,
    headsign: 'X',
    points: const [GeoPoint(45.079, 7.66), GeoPoint(45.08, 7.666)],
  );

  test('le vie di un riquadro, con le coordinate a sette decimali', () {
    final v = VieLocali.daJson(dati);
    final trovate = v.vie(const Bounds(45.07, 7.65, 45.09, 7.67));
    expect(trovate.map((x) => x.nome), ['Via Luigi Cibrario', 'Corso Francia']);
    // Sette decimali: due vie che si toccano devono avere lo stesso punto.
    expect(trovate.first.punti.first.lat, closeTo(45.0791234, 1e-8));
    expect(v.binari(const Bounds(45.07, 7.65, 45.09, 7.67)), hasLength(1));
  });

  test('con le vie sul disco Overpass non si chiama', () async {
    final vie = ViePerNome(
      http: _MaiChiamato(),
      locali: VieLocali.daJson(dati),
    );
    // GTT scrive «via Cibrario», OpenStreetMap «Via Luigi Cibrario».
    final r = await vie.cerca(['via Cibrario'], linea);
    expect(r['via Cibrario'], hasLength(1));
    expect(await vie.binari(linea), hasLength(1));
  });

  test('si legge dal file compresso, e un file rotto non ferma il giro', () {
    final dir = Directory.systemTemp.createTempSync('vie_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/vie.json.gz')
      ..writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode(dati))));
    expect(VieLocali.leggi(f)?.quante, 3);
    final rotto = File('${dir.path}/rotto.json.gz')..writeAsStringSync('no');
    expect(VieLocali.leggi(rotto), isNull);
    expect(VieLocali.leggi(File('${dir.path}/manca.gz')), isNull);
  });
}
