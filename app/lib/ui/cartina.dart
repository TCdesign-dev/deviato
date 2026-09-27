import 'package:flutter/material.dart';

/// Da dove arrivano le immagini della cartina, e di che colore sono i
/// segni che ci stanno sopra.
///
/// Con la chiave di CARTO — `CARTO_KEY`, passata alla compilazione con
/// `--dart-define-from-file=chiavi.json` — si usano Positron e, col tema
/// scuro, Dark Matter: grigi sobri su cui il rosso della deviazione, le
/// fermate e i mezzi risaltano, e una cartina che al buio diventa scura.
/// Senza chiave si torna alle immagini standard di OpenStreetMap, sempre
/// chiare: l'app funziona lo stesso.
///
/// CARTO e' gratuita per uso non commerciale fino a 5 milioni di immagini
/// al mese. In tutti e due i casi l'attribuzione deve stare sulla mappa,
/// sempre visibile: CARTO la vuole «non nascosta dietro un tocco».
class Cartina {
  const Cartina._({required this.scura});

  factory Cartina.of(BuildContext context) => Cartina._(
        scura: carto && Theme.of(context).brightness == Brightness.dark,
      );

  static const _chiave = String.fromEnvironment('CARTO_KEY');

  /// C'e' la chiave di CARTO.
  static bool get carto => _chiave.isNotEmpty;

  /// La cartina e' scura. Solo con CARTO: quella di OpenStreetMap e'
  /// chiara anche col tema scuro, e i segni devono leggersi su quella.
  final bool scura;

  String get url => carto
      ? 'https://{s}.basemaps.cartocdn.com/'
          '${scura ? 'dark_all' : 'light_all'}/{z}/{x}/{y}{r}.png?key=$_chiave'
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  List<String> get sottodomini =>
      carto ? const ['a', 'b', 'c', 'd'] : const <String>[];

  String get attribuzione => carto
      ? '© contributori di OpenStreetMap · © CARTO'
      : '© contributori di OpenStreetMap';

  // I segni. Sulla cartina chiara quelli di sempre; su quella scura toni
  // piu' chiari, o le due direzioni sparirebbero nel grigio delle strade.

  /// Le due direzioni: la linea sottile del percorso normale.
  Color direzione(int i) => scura
      ? (i == 0 ? Colors.blueGrey.shade200 : Colors.teal.shade300)
          .withValues(alpha: 0.75)
      : (i == 0 ? Colors.blueGrey : Colors.teal).withValues(alpha: 0.55);

  /// Il mezzo che fa quella direzione: pieno, col bordo bianco.
  Color mezzo(int? direzione) => switch (direzione) {
        0 => Colors.blueGrey.shade700,
        1 => Colors.teal.shade700,
        _ => Colors.blue.shade700,
      };

  Color get deviazione => scura ? Colors.red.shade400 : Colors.red.shade700;

  Color get osservato => scura ? Colors.purple.shade300 : Colors.purple.shade600;

  /// Fermata non servita, mezzo fuori percorso.
  Color get chiusa => scura ? Colors.red.shade600 : const Color(0xFFB3261E);

  /// Il bordo della fermata toccata.
  Color get selezione =>
      scura ? const Color(0xFFF9D400) : const Color(0xFF1E1E1E);

  Color get bordoFermata =>
      scura ? Colors.blueGrey.shade300 : Colors.blueGrey.shade600;

  /// Il fondo della scritta dell'attribuzione.
  Color get fondoAttribuzione => scura
      ? Colors.black.withValues(alpha: 0.6)
      : Colors.white.withValues(alpha: 0.8);
}
