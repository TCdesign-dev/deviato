import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/saved_stop.dart';

/// Le poche cose che l'app deve ricordare: le linee e le fermate di chi la
/// usa.
///
/// Niente chiavi: gli avvisi li legge il job su GitHub, per tutti. Una
/// chiave salvata dalle versioni precedenti resta nelle preferenze, ma non
/// la legge piu' nessuno.
class Settings {
  Settings(this._prefs);

  static const _kWatchlist = 'watchlist';
  static const _kSavedStops = 'fermate_salvate';
  static const _kStopsHintSeen = 'suggerimento_fermate_visto';

  final SharedPreferences _prefs;

  static Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Quello che le versioni precedenti salvavano e che ora non serve piu':
    // la chiave del modello — non deve restare sul telefono se nessuno la
    // usa — e gli esiti calcolati in locale, sostituiti dai file del job.
    for (final k in _vecchie) {
      if (prefs.containsKey(k)) await prefs.remove(k);
    }
    return Settings(prefs);
  }

  static const _vecchie = ['openrouter_key', 'llm_model', 'esiti_controlli_v1'];

  /// Le linee che interessano, coi nomi che usa la gente ("55", "STAR 1").
  /// Poche: il sistema lavora per linea, non sulla rete intera.
  List<String> get watchlist => _prefs.getStringList(_kWatchlist) ?? const [];

  Future<void> setWatchlist(List<String> lines) =>
      _prefs.setStringList(_kWatchlist, lines);

  Future<void> addLine(String line) async {
    final l = line.trim();
    if (l.isEmpty) return;
    final current = watchlist.toList();
    if (current.any((x) => x.toUpperCase() == l.toUpperCase())) return;
    current.add(l);
    await setWatchlist(current);
  }

  Future<void> removeLine(String line) async {
    await setWatchlist(
        watchlist.where((x) => x != line).toList(growable: false));
  }

  /// Le fermate che l'utente usa, nell'ordine in cui le ha salvate.
  ///
  /// Una voce illeggibile si salta invece di far fallire tutte le altre:
  /// meglio perdere una fermata che tutte.
  List<SavedStop> get savedStops => [
        for (final raw in _prefs.getStringList(_kSavedStops) ?? const [])
          ?_decode(raw),
      ];

  Future<void> setSavedStops(List<SavedStop> stops) => _prefs.setStringList(
      _kSavedStops, [for (final s in stops) jsonEncode(s.toJson())]);

  Future<void> addSavedStop(SavedStop stop) async {
    final current = savedStops;
    if (current.any(stop.same)) return;
    await setSavedStops([...current, stop]);
  }

  Future<void> removeSavedStop(SavedStop stop) =>
      setSavedStops(savedStops.where((s) => !s.same(stop)).toList());

  static SavedStop? _decode(String raw) {
    try {
      return SavedStop.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  /// Il suggerimento su come salvare una fermata e' gia' stato chiuso.
  bool get stopsHintSeen => _prefs.getBool(_kStopsHintSeen) ?? false;

  Future<void> setStopsHintSeen() => _prefs.setBool(_kStopsHintSeen, true);

}
