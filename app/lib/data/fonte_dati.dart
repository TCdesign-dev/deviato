import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/config.dart';

/// La rete non ha risposto: niente connessione, o il sito non c'e'.
class FonteNonRaggiungibile implements Exception {
  const FonteNonRaggiungibile(this.dettaglio);
  final String dettaglio;

  @override
  String toString() => 'FonteNonRaggiungibile: $dettaglio';
}

/// Da dove arrivano i dati che il job su GitHub pubblica.
///
/// Astratta perche' i test non devono andare in rete: passano una fonte in
/// memoria e controllano cosa fa l'app quando un file c'e', manca, o la
/// rete e' giu'.
abstract class FonteDati {
  /// Il file [percorso] (per esempio `stato/15U.json`) dalla rete. null se
  /// il sito risponde che non esiste; [FonteNonRaggiungibile] se la rete
  /// non risponde. Quello che arriva si salva, e [salvato] lo ritrova.
  Future<Map<String, dynamic>?> scarica(String percorso);

  /// L'ultima copia scaricata di [percorso], anche senza rete.
  Future<Map<String, dynamic>?> salvato(String percorso);
}

/// I file pubblicati su GitHub Pages, con una copia sul telefono.
///
/// La copia serve a due cose: aprire l'app e vedere subito l'ultimo stato
/// noto, prima che la rete risponda; e continuare a vederlo in galleria o
/// in metropolitana, con l'ora a cui risale.
class DatiPubblicati implements FonteDati {
  DatiPubblicati({Uri? base, http.Client? client})
      : _base = base ?? Uri.parse(GttConfig.datiUrl),
        _client = client ?? http.Client();

  final Uri _base;
  final http.Client _client;
  Directory? _cartella;

  Future<Directory> _dir() async => _cartella ??= Directory(
      '${(await getApplicationSupportDirectory()).path}/dati');

  @override
  Future<Map<String, dynamic>?> scarica(String percorso) async {
    final http.Response r;
    try {
      r = await _client
          .get(_base.resolve(percorso),
              headers: {'User-Agent': GttConfig.userAgent})
          .timeout(const Duration(seconds: 20));
    } on Object catch (e) {
      throw FonteNonRaggiungibile('$e');
    }
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) {
      throw FonteNonRaggiungibile('HTTP ${r.statusCode}');
    }
    final Map<String, dynamic> dati;
    try {
      dati = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } on Object catch (e) {
      throw FonteNonRaggiungibile('risposta illeggibile: $e');
    }
    // Salvare non deve mai far fallire la lettura: al massimo la prossima
    // volta senza rete non ci sara' la copia.
    try {
      final f = File('${(await _dir()).path}/$percorso');
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(dati));
    } on Object {
      // niente
    }
    return dati;
  }

  @override
  Future<Map<String, dynamic>?> salvato(String percorso) async {
    try {
      final f = File('${(await _dir()).path}/$percorso');
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } on Object {
      return null;
    }
  }
}
