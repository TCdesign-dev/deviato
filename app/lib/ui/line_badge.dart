import 'package:flutter/material.dart';

import '../core/models/transit.dart';

/// Il numero della linea, col colore e il mezzo di GTT.
///
/// Prima erano tutte uguali, azzurrine, e un tram non si distingueva da
/// un bus. Il GTFS lo dice già: `route_color` (CC9900 i tram, FF9900 i bus
/// urbani) e `route_type` (0 tram, 3 bus).
///
/// Il colore del testo invece NON si prende da GTT: `route_text_color` è
/// 0000FF, blu su arancio, e si ferma a 3,3:1 sui tram e 4,0:1 sui bus.
/// Si sceglie chiaro o scuro in base allo sfondo: quasi nero sull'arancio
/// fa 6,7 e 8,1.
class LineBadge extends StatelessWidget {
  const LineBadge({required this.line, this.height = 40, super.key});

  final TransitLine line;
  final double height;

  static const _scuro = Color(0xFF1A1A1A);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ufficiale = _parse(line.color);
    final fondo = ufficiale ?? scheme.primaryContainer;
    final testo = ufficiale == null ? scheme.onPrimaryContainer : _leggibile(fondo);
    final (IconData icona, String mezzo) = line.isTram
        ? (Icons.tram, 'tram')
        : line.isMetro
            ? (Icons.subway, 'metro')
            : (Icons.directions_bus, 'bus');

    return Semantics(
      label: '$mezzo ${line.shortName}',
      excludeSemantics: true,
      child: Container(
        height: height,
        constraints: BoxConstraints(minWidth: height * 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(height / 5),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icona, size: height * 0.38, color: testo),
              const SizedBox(width: 2),
              Text(
                line.shortName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: height * 0.4,
                  color: testo,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bianco o quasi nero, quello che contrasta di più con [fondo].
  static Color _leggibile(Color fondo) {
    final l = fondo.computeLuminance();
    final suBianco = 1.05 / (l + 0.05);
    final suScuro = (l + 0.05) / (_scuro.computeLuminance() + 0.05);
    return suScuro >= suBianco ? _scuro : Colors.white;
  }

  static Color? _parse(String? hex) {
    if (hex == null || hex.length != 6) return null;
    final v = int.tryParse(hex, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }
}
