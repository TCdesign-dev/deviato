import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Il logo di DeviaTo, nella versione adatta al tema.
///
/// Sono due disegni diversi, non uno ricolorato: nel chiaro il «To» giallo
/// ha un bordino scuro, perché il giallo pieno su bianco quasi sparisce.
class DeviatoLogo extends StatelessWidget {
  const DeviatoLogo({this.height = 30, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    final scuro = Theme.of(context).brightness == Brightness.dark;
    return SvgPicture.asset(
      scuro
          ? 'assets/logo/deviato-scuro.svg'
          : 'assets/logo/deviato-chiaro.svg',
      height: height,
      semanticsLabel: 'DeviaTo',
    );
  }
}
