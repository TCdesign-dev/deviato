import '../core/models/notice.dart';
import '../core/text/periodo_avviso.dart';

/// Quando vale un avviso, in una riga per chi legge.
///
/// «In vigore dal 05/10 · domani», «Dal 07/09 · fino al 09/10», «Il 04/10
/// · dalle 6:30 alle 23:30», «Solo il sabato, dalle 6:00 alle 15:00»,
/// «Terminato il 15/09». Le date vengono dal testo dell'avviso quando le
/// dice (vedi [RawNotice.periodo]), perche' quelle del feed sono di
/// pubblicazione. Vuota se non si sa niente.
String quandoAvviso(RawNotice n, DateTime ora) {
  String d(DateTime x) =>
      '${x.day.toString().padLeft(2, "0")}/${x.month.toString().padLeft(2, "0")}';
  final inizio = n.inizioDaDire(ora);
  final fine = n.endToShow;
  final fascia = n.fasciaDaDire;

  final String riga;
  switch (n.statoAl(ora)) {
    case StatoPeriodo.finito:
      riga = fine == null ? 'Terminato' : 'Terminato il ${d(fine)}';
    case StatoPeriodo.inProgramma:
      final giorni = n.daysUntilStart(ora);
      riga = [
        if (inizio != null)
          'In vigore dal ${d(inizio)}${switch (giorni) {
            null => '',
            0 => ' · oggi',
            1 => ' · domani',
            2 => ' · dopodomani',
            _ => ' · fra $giorni giorni',
          }}',
        if (fine != null && !_stessoGiorno(inizio, fine)) 'fino al ${d(fine)}',
        ?fascia,
      ].join(' · ');
    case StatoPeriodo.inCorso ||
        StatoPeriodo.fuoriOrario ||
        StatoPeriodo.sconosciuto:
      final unGiorno = _stessoGiorno(inizio, fine);
      riga = [
        if (inizio != null) unGiorno ? 'Il ${d(inizio)}' : 'Dal ${d(inizio)}',
        if (fine != null && !unGiorno) 'fino al ${d(fine)}',
        ?fascia,
      ].join(' · ');
  }
  return riga.isEmpty ? riga : riga[0].toUpperCase() + riga.substring(1);
}

/// La fine cade nel giorno dell'inizio, o nella notte dopo: «dalle 18 a
/// fine servizio» finisce alle 2.
bool _stessoGiorno(DateTime? inizio, DateTime? fine) {
  if (inizio == null || fine == null) return false;
  final giorno = DateTime(inizio.year, inizio.month, inizio.day);
  return fine.difference(giorno) <= const Duration(hours: 26);
}
