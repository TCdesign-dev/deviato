// Misura il lettore a regole contro le letture del modello gia' pubblicate.
//
//   cd app && dart run tool/misura_regole.dart corpus.json
//
// `corpus.json` e' {idAvviso: {titolo, testo, lettura}}, dai file `stato/`.
// Per ogni avviso che le regole leggono dice se le vie sono le stesse che
// aveva letto il modello: dove differiscono va guardato a mano, perche'
// puo' aver sbagliato l'uno o l'altro.
import 'dart:convert';
import 'dart:io';

import 'package:gtt_deviazioni/core/pipeline/extractor.dart';
import 'package:gtt_deviazioni/core/pipeline/lettore_a_regole.dart';

String _n(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[’‘`´]'), "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

void main(List<String> args) {
  final corpus =
      jsonDecode(File(args.first).readAsStringSync()) as Map<String, dynamic>;
  var lette = 0, uguali = 0;
  for (final e in corpus.entries) {
    final v = e.value as Map<String, dynamic>;
    final r = LettoreARegole.leggi(v['titolo'] as String, v['testo'] as String);
    if (r == null) continue;
    lette++;
    final modello = [
      for (final d in (v['lettura'] as List).cast<Map<String, dynamic>>())
        ParsedDeviation.fromJson(d),
    ];
    // Le vie percorse, in ordine; lo stacco il modello a volte lo ripete
    // come prima via, e non conta.
    String vie(ParsedDeviation d) {
      final s = [for (final x in d.viaSequence) _n(x)];
      if (s.isNotEmpty && d.detachStreet != null && s.first == _n(d.detachStreet!)) {
        s.removeAt(0);
      }
      return '${_n(d.detachStreet ?? '')} > ${s.join(' > ')}';
    }

    final a = r.map(vie).join(' | '), b = modello.map(vie).join(' | ');
    if (a == b) {
      uguali++;
    } else {
      stdout.writeln('\n--- ${v['titolo']}\n${(v['testo'] as String).replaceAll('\n', ' ')}');
      stdout.writeln('REGOLE : $a\nMODELLO: $b');
    }
  }
  stdout.writeln('\n${corpus.length} avvisi, $lette letti dalle regole, '
      '$uguali uguali al modello');
}
