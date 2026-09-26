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
/// | regolare    | `2E7D32`  | 4,88      | `81C784`  | 9,23      |
/// | attenzione  | `9A4D00`  | 5,82      | `FFB74D`  | 10,74     |
/// | info        | `1565C0`  | 5,47      | `90CAF9`  | 10,62     |
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
  }) =>
      StatusColors(
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

/// Il tema dell'app, chiaro o scuro.
ThemeData buildTheme(Brightness brightness) {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF0B5FA5),
      brightness: brightness,
    ),
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
