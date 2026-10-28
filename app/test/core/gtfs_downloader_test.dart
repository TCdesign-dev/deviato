import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/gtfs/gtfs_downloader.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('se GTT non risponde, gli orari di prima restano', () async {
    // Il job ci conta: dal 23 al 28/10/2026 il sito di GTT non
    // rispondeva, e senza la copia di ieri ogni giro andava in errore.
    final dir = await Directory.systemTemp.createTemp('gtfs_');
    addTearDown(() => dir.delete(recursive: true));
    for (final f in GtfsDownloader.neededFiles) {
      File('${dir.path}/$f').writeAsStringSync('vecchio');
    }
    final ieri = DateTime.now().subtract(const Duration(days: 1));
    File('${dir.path}/.scaricato').writeAsStringSync(ieri.toIso8601String());

    final giu = MockClient(
      (_) async => throw http.ClientException(
        'Connection timed out',
        Uri.parse('https://www.gtt.to.it/'),
      ),
    );
    final d = GtfsDownloader(directory: dir, client: giu);
    await expectLater(
      d.ensureAvailable(maxAge: const Duration(hours: 20)),
      throwsA(isA<GtfsDownloadException>()),
    );
    expect(d.isPresent, isTrue);
    expect(d.lastDownload, ieri);
    expect(File('${dir.path}/stops.txt').readAsStringSync(), 'vecchio');
  });
}
