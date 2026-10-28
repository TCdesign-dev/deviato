import '../deviation_service.dart';
import '../models/notice.dart';
import '../models/transit.dart';

/// Com'e' andato un giro del job.
class GiroPubblicazione {
  const GiroPubblicazione({
    required this.stati,
    required this.avvisi,
    required this.letture,
    required this.daRitentare,
    required this.errori,
  });

  /// Lo stato di ogni linea calcolata, per route_id.
  final Map<String, LineStatus> stati;

  /// Avvisi distinti che riguardano almeno una linea.
  final int avvisi;

  /// Richieste fatte al modello in questo giro.
  final int letture;

  /// Avvisi rimasti da leggere: quota, rete, coda del giro.
  final int daRitentare;

  /// Linee che non si sono potute calcolare, col motivo.
  final List<String> errori;
}

/// Il giro del job su GitHub: lo stato di tutte le linee, per tutti.
///
/// Prima ogni telefono faceva questo lavoro per le sue linee, con la sua
/// chiave e le sue cinquanta richieste al giorno. Qui si fa una volta sola
/// e il risultato si pubblica: le richieste al modello dipendono dagli
/// avvisi nuovi di GTT — una ventina al giorno, misurato il 26/09 — e non
/// da quante persone usano l'app.
///
/// Di suo non tocca ne' file ne' rete: riceve gli avvisi e gli esiti del
/// giro prima, e restituisce quelli nuovi. Scrivere i file e' compito di
/// `tool/pubblica.dart`.
class Pubblicatore {
  Pubblicatore({required this.index, required this.service});

  final GtfsIndex index;
  final DeviationService service;

  /// [soloTesto]: le linee da non ricalcolare (vedi
  /// [DeviationService.statusOf]). [inizio] si chiama prima di ogni linea,
  /// [fase] a ogni passo dentro la linea: servono a dire dove si e'
  /// fermato un giro che non finisce.
  Future<GiroPubblicazione> calcola({
    required List<RawNotice> avvisi,
    Map<String, LineStatus> precedenti = const {},
    void Function(String riga)? log,
    Set<String> soloTesto = const {},
    void Function(TransitLine linea)? inizio,
    void Function(TransitLine linea, String fase)? fase,
  }) async {
    final linee = index.lines.values.toList()..sort(TransitLine.compare);
    final stati = <String, LineStatus>{};
    final errori = <String>[];

    for (final linea in linee) {
      final orologio = Stopwatch()..start();
      inizio?.call(linea);
      try {
        stati[linea.routeId] = await service.statusOf(
          linea,
          allNotices: avvisi,
          previous: precedenti[linea.routeId],
          soloTesto: soloTesto.contains(linea.routeId),
          onProgress: fase == null ? null : (f) => fase(linea, f),
        );
        // Il 28/10 due giri di fila hanno superato i 25 minuti senza dire
        // una riga fra «algoritmo dei percorsi» e l'annullamento: le linee
        // lente si scrivono, cosi' il log dice dove va il tempo.
        if (orologio.elapsed >= const Duration(seconds: 30)) {
          log?.call('linea ${linea.shortName}: '
              '${orologio.elapsed.inSeconds} s');
        }
      } on Object catch (e) {
        // Una linea senza percorsi nel GTFS, o un guasto su un avviso: le
        // altre vanno avanti. L'esito vecchio, se c'era, resta pubblicato.
        errori.add('${linea.shortName}: $e');
        log?.call('linea ${linea.shortName}: $e');
        final prima = precedenti[linea.routeId];
        if (prima != null) stati[linea.routeId] = prima;
      }
    }

    final rapporti = stati.values.expand((s) => s.reports).toList();
    return GiroPubblicazione(
      stati: stati,
      avvisi: {for (final r in rapporti) r.notice.id}.length,
      letture: service.letture,
      daRitentare:
          {for (final r in rapporti.where((r) => r.retryable)) r.notice.id}
              .length,
      errori: errori,
    );
  }
}
