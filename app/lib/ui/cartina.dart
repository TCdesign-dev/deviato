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

  /// Le due direzioni: la linea del percorso normale, e il bordo e la
  /// freccia delle sue fermate.
  ///
  /// Blu e verde, pieni. Il grigio-azzurro di prima sulla cartina grigia
  /// sembrava una strada, e col verde acqua accanto si distingueva poco.
  /// Tutti e due lontani dal rosso della deviazione e dal viola del
  /// percorso visto sui mezzi; dove i colori non bastano (chi non
  /// distingue bene il rosso dal verde) c'e' la freccia nelle fermate.
  Color direzione(int i) => scura
      ? (i == 0 ? const Color(0xFF82A7FF) : const Color(0xFF4FD1A5))
      : (i == 0 ? const Color(0xFF2A5BD7) : const Color(0xFF0B9470));

  /// Spessore della linea del percorso normale, e di quelle che devono
  /// spiccarci sopra: la deviazione e il percorso visto sui mezzi.
  static const spessorePercorso = 5.5;
  static const spessoreDeviazione = 7.0;

  /// Il mezzo che fa quella direzione: pieno, col bordo bianco. Gli
  /// stessi colori delle linee, piu' scuri sotto l'icona bianca; grigio se
  /// la direzione non si capisce.
  Color mezzo(int? direzione) => switch (direzione) {
        0 => const Color(0xFF1F47AD),
        1 => const Color(0xFF087558),
        _ => Colors.blueGrey.shade700,
      };

  Color get deviazione => scura ? Colors.red.shade400 : Colors.red.shade700;

  Color get osservato => scura ? Colors.purple.shade300 : Colors.purple.shade600;

  /// Fermata non servita, mezzo fuori percorso.
  Color get chiusa => scura ? Colors.red.shade600 : const Color(0xFFB3261E);

  /// Il bordo della fermata toccata.
  Color get selezione =>
      scura ? const Color(0xFFF9D400) : const Color(0xFF1E1E1E);

  /// Il bordo di una fermata senza un verso solo: un palo usato da tutte
  /// e due le direzioni, o che non si riesce a mettere sul percorso.
  Color get bordoFermata =>
      scura ? Colors.blueGrey.shade300 : Colors.blueGrey.shade600;

  /// Il fondo della scritta dell'attribuzione.
  Color get fondoAttribuzione => scura
      ? Colors.black.withValues(alpha: 0.6)
      : Colors.white.withValues(alpha: 0.8);
}
