import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// I colori che dicono qualcosa: regolare, attenzione, informazione.
///
/// Prima erano sparsi nel codice come `Colors.green.shade700`,
/// `Colors.orange.shade800`, `Colors.blue.shade700`, e nessuno dei tre
/// arrivava a 4,5:1 sullo sfondo dell'app — l'arancio si fermava a 2,93,
/// sotto la soglia anche del testo grande. E restavano gli stessi in
/// modalità scura, dove la striscia azzurra dell'osservazione diventava
/// una macchia chiara su fondo nero.
///
/// Qui ogni colore ha la sua versione chiara e scura, misurata:
///
/// | Ruolo       | Chiaro    | su sfondo | Scuro     | su sfondo |
/// |-------------|-----------|-----------|-----------|-----------|
/// | regolare    | `2E7D32`  | 5,13      | `81C784`  | 8,28      |
/// | attenzione  | `9A4D00`  | 6,11      | `FFB74D`  | 9,63      |
/// | info        | `1565C0`  | 5,75      | `90CAF9`  | 9,53      |
///
/// (sullo sfondo bianco in chiaro e grafite `1E1E1E` in scuro; vedi
/// [buildTheme]). Il blu di «info» resta: è il colore del tempo reale,
/// un significato, non un'identità.
///
/// Il rosso resta quello del tema (`colorScheme.error`), che passa già.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.ok,
    required this.warning,
    required this.info,
    required this.observed,
  });

  final Color ok;
  final Color warning;
  final Color info;

  /// Il percorso visto sui mezzi: il viola della linea sulla mappa.
  final Color observed;

  static const light = StatusColors(
    ok: Color(0xFF2E7D32),
    warning: Color(0xFF9A4D00),
    info: Color(0xFF1565C0),
    observed: Color(0xFF6A1B9A),
  );

  static const dark = StatusColors(
    ok: Color(0xFF81C784),
    warning: Color(0xFFFFB74D),
    info: Color(0xFF90CAF9),
    observed: Color(0xFFCE93D8),
  );

  static StatusColors of(BuildContext context) =>
      Theme.of(context).extension<StatusColors>() ?? light;

  @override
  StatusColors copyWith({
    Color? ok,
    Color? warning,
    Color? info,
    Color? observed,
  }) => StatusColors(
    ok: ok ?? this.ok,
    warning: warning ?? this.warning,
    info: info ?? this.info,
    observed: observed ?? this.observed,
  );

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    return StatusColors(
      ok: Color.lerp(ok, other.ok, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      observed: Color.lerp(observed, other.observed, t)!,
    );
  }
}

const _grafite = Color(0xFF1E1E1E);
const _giallo = Color(0xFFF9D400);

/// La tavolozza di DeviaTo: grafite, giallo e grigi neutri, come il logo,
/// l'icona e il sito.
///
/// Prima i colori nascevano da un seme blu (`0B5FA5`) e l'app sembrava
/// azzurra anche negli sfondi, che Material 3 tinge del colore di
/// partenza. Qui ogni ruolo è scritto a mano.
///
/// Il giallo non fa mai da testo su fondo chiaro: su bianco si ferma a
/// 1,45:1. In chiaro sta *sotto* il testo grafite (11,47:1) — la striscia
/// dei mezzi in tempo reale, le etichette senza colore di GTT, l'«Annulla»
/// sugli avvisi scuri — e al buio diventa il colore degli elementi attivi
/// (11,47:1 sul fondo, 10,14 sui riquadri). Misurati:
///
/// | Coppia                          | Contrasto |
/// |---------------------------------|-----------|
/// | testo `1E1E1E` su bianco        | 16,67     |
/// | tenue `5B5B5B` su riquadro      | 6,11      |
/// | grafite su giallo pallido       | 14,65     |
/// | tenue `B9B9B9` su riquadro scuro| 7,51      |
/// | giallo chiaro su oliva `4A4012` | 8,35      |
/// | bordi `767672` / `8E8E8A`       | 4,56 / 5,07 |
ColorScheme _tavolozza(Brightness b) => b == Brightness.light
    ? const ColorScheme(
        brightness: Brightness.light,
        primary: _grafite,
        onPrimary: Colors.white,
        primaryContainer: _giallo,
        onPrimaryContainer: _grafite,
        secondary: Color(0xFF5B5B5B),
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFFDF1B8),
        onSecondaryContainer: _grafite,
        tertiary: _giallo,
        onTertiary: _grafite,
        error: Color(0xFFB3261E),
        onError: Colors.white,
        errorContainer: Color(0xFFF9DEDC),
        onErrorContainer: Color(0xFF410E0B),
        surface: Colors.white,
        onSurface: _grafite,
        onSurfaceVariant: Color(0xFF5B5B5B),
        surfaceDim: Color(0xFFE6E6E2),
        surfaceBright: Colors.white,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Color(0xFFF7F7F5),
        surfaceContainer: Color(0xFFF3F3F1),
        surfaceContainerHigh: Color(0xFFEDEDEA),
        surfaceContainerHighest: Color(0xFFE6E6E2),
        outline: Color(0xFF767672),
        outlineVariant: Color(0xFFDCDCD8),
        inverseSurface: _grafite,
        onInverseSurface: Colors.white,
        inversePrimary: _giallo,
        shadow: Colors.black,
        scrim: Colors.black,
        surfaceTint: Colors.transparent,
      )
    : const ColorScheme(
        brightness: Brightness.dark,
        primary: _giallo,
        onPrimary: _grafite,
        primaryContainer: Color(0xFF4A4012),
        onPrimaryContainer: Color(0xFFFFE866),
        secondary: Color(0xFFB9B9B9),
        onSecondary: _grafite,
        secondaryContainer: Color(0xFF3A3520),
        onSecondaryContainer: Colors.white,
        tertiary: _giallo,
        onTertiary: _grafite,
        error: Color(0xFFF2B8B5),
        onError: Color(0xFF601410),
        errorContainer: Color(0xFF8C1D18),
        onErrorContainer: Color(0xFFF9DEDC),
        surface: _grafite,
        onSurface: Colors.white,
        onSurfaceVariant: Color(0xFFB9B9B9),
        surfaceDim: Color(0xFF161616),
        surfaceBright: Color(0xFF3A3A3A),
        surfaceContainerLowest: Color(0xFF171717),
        surfaceContainerLow: Color(0xFF232323),
        surfaceContainer: Color(0xFF282828),
        surfaceContainerHigh: Color(0xFF303030),
        surfaceContainerHighest: Color(0xFF3A3A3A),
        outline: Color(0xFF8E8E8A),
        outlineVariant: Color(0xFF3A3A3A),
        inverseSurface: Color(0xFFF3F3F1),
        onInverseSurface: _grafite,
        inversePrimary: _grafite,
        shadow: Colors.black,
        scrim: Colors.black,
        surfaceTint: Colors.transparent,
      );

/// Il tema dell'app, chiaro o scuro.
ThemeData buildTheme(Brightness brightness) {
  final base = ThemeData(
    colorScheme: _tavolozza(brightness),
    useMaterial3: true,
    extensions: [
      brightness == Brightness.dark ? StatusColors.dark : StatusColors.light,
    ],
  );
  // Su iOS la spaziatura fra lettere di Material 3 — pensata per Roboto,
  // fino a 0,5 punti — allarga il San Francisco di sistema: le scritte
  // piccole sembravano spaziate a mano. Su Android si lascia com'è.
  if (defaultTargetPlatform != TargetPlatform.iOS) return base;
  return base.copyWith(textTheme: _senzaSpaziatura(base.textTheme));
}

TextTheme _senzaSpaziatura(TextTheme t) {
  TextStyle? z(TextStyle? s) => s?.copyWith(letterSpacing: 0);
  return t.copyWith(
    displayLarge: z(t.displayLarge),
    displayMedium: z(t.displayMedium),
    displaySmall: z(t.displaySmall),
    headlineLarge: z(t.headlineLarge),
    headlineMedium: z(t.headlineMedium),
    headlineSmall: z(t.headlineSmall),
    titleLarge: z(t.titleLarge),
    titleMedium: z(t.titleMedium),
    titleSmall: z(t.titleSmall),
    bodyLarge: z(t.bodyLarge),
    bodyMedium: z(t.bodyMedium),
    bodySmall: z(t.bodySmall),
    labelLarge: z(t.labelLarge),
    labelMedium: z(t.labelMedium),
    labelSmall: z(t.labelSmall),
  );
}
