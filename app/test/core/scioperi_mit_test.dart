import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/sources/scioperi_mit.dart';
import 'package:gtt_deviazioni/ui/scioperi.dart';

/// Il calendario degli scioperi del Ministero, com'era il 22/10/2026.
void main() {
  final tutti = ScioperiMit.leggi(
    File('test/fixtures/scioperi_mit.html').readAsStringSync(),
  );
  final perGtt = tutti.where((s) => s.riguardaGtt).toList();

  test('si leggono tutte le righe, colonne per nome', () {
    expect(tutti, hasLength(27));
    final primo = tutti.first;
    expect(primo.inizio.isBefore(DateTime(2027)), isTrue);
    expect(primo.sindacati, isNotEmpty);
  });

  test('restano quelli che possono fermare GTT', () {
    expect(
      [for (final s in perGtt) '${s.inizio.day}/${s.inizio.month} ${s.sindacati}'],
      [
        '30/10 USB',
        '20/11 CUB TRASPORTI/SGB FERROVIE',
        '20/11 CGIL',
        '4/12 CUB/ADL VARESE/SGB/SBM/SGC/SI-COBAS',
      ],
    );
  });

  test('i generali che escludono i trasporti non contano', () {
    final esclusi = tutti.where(
      (s) => s.settore == 'Generale' && s.inizio == DateTime(2026, 10, 30),
    );
    expect(esclusi, hasLength(3));
    expect(esclusi.where((s) => s.riguardaGtt), hasLength(1));
  });

  test('gli scioperi locali di altre citta\' non contano', () {
    expect(
      tutti.where((s) => s.regione == 'Puglia' || s.regione == 'Campania')
          .any((s) => s.riguardaGtt),
      isFalse,
    );
  });

  test('il giorno del trasporto locale, quando e\' diverso', () {
    final cub = perGtt.firstWhere((s) => s.sindacati.startsWith('CUB TRASP'));
    expect(cub.inizio, DateTime(2026, 11, 20));
    expect(cub.giorniTpl.inizio, DateTime(2026, 11, 21));
    expect(cub.giorniTpl.fine, DateTime(2026, 11, 21));
    expect(cub.nonFinitoIl(DateTime(2026, 11, 21, 23)), isTrue);
    expect(cub.nonFinitoIl(DateTime(2026, 11, 22)), isFalse);
  });

  test('si pubblica e si rilegge uguale', () {
    for (final s in perGtt) {
      final r = Sciopero.fromJson(s.toJson())!;
      expect(r.toJson(), s.toJson());
    }
  });

  test('detto a parole', () {
    final usb = perGtt.first;
    expect(quandoSciopero(usb, DateTime(2026, 10, 22)), 'venerdì 30/10');
    expect(quandoSciopero(usb, DateTime(2026, 10, 29)), 'domani');
    expect(quandoSciopero(usb, DateTime(2026, 10, 30)), 'oggi');
    expect(
      descriviSciopero(usb),
      'Generale, USB. Bus e tram: durata e modalità stabilite a livello '
      'territoriale.',
    );
  });
}
