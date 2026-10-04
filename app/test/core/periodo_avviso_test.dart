import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/text/periodo_avviso.dart';

/// Le frasi sono quelle degli avvisi veri del 28/09/2026.
void main() {
  PeriodoAvviso leggi(String t, [String pubblicato = '2026-09-15']) =>
      PeriodoAvviso.leggi(t, pubblicato: DateTime.parse(pubblicato));

  test('da un giorno fino a nuove comunicazioni', () {
    final p = leggi('Da lunedì 14 settembre 2026 e sino a nuove '
        'comunicazioni. Direzione piazza Stampalia: da corso Vittorio…');
    expect(p.inizio, DateTime(2026, 9, 14));
    expect(p.fine, isNull);
  });

  test('il primo giorno senza mese, con le ore', () {
    final p = leggi("Dalle ore 8.00 di mercoledi' 23 alle ore 5.00 di "
        "lunedi' 28 settembre 2026. Da via XX Settembre angolo via Santa "
        'Teresa devia…');
    expect(p.inizio, DateTime(2026, 9, 23, 8));
    expect(p.fine, DateTime(2026, 9, 28, 5));
  });

  test('la data prima dell\'ora, e le corse serali', () {
    final p = leggi("Mercoledi' 16 settembre dalle ore 10 e sino a nuove "
        'comunicazioni le corse serali dopo ore 20.00. Da via Rossini…');
    expect(p.inizio, DateTime(2026, 9, 16));
    expect(p.fine, isNull);
    expect(p.stato(DateTime(2026, 9, 28, 21)), StatoPeriodo.inCorso);
    expect(p.stato(DateTime(2026, 9, 28, 15)), StatoPeriodo.fuoriOrario);
  });

  test('da un\'ora di un giorno a un\'ora di un altro', () {
    final p = leggi('dalle 7.00 del 28 settembre alle 19.00 del 1 ottobre, '
        'in direzione Pessione: da via Riva…', '2026-09-28');
    expect(p.inizio, DateTime(2026, 9, 28, 7));
    expect(p.fine, DateTime(2026, 10, 1, 19));
  });

  test('giorni singoli con una fascia oraria', () {
    final p = leggi('lunedì 21 e lunedì 28 settembre 2026, dalle ore 08:00 '
        'alle 16:00.   Direzione Chivasso: via Madonna D’Isola…', '2026-09-20');
    expect(p.giorni, [DateTime(2026, 9, 21), DateTime(2026, 9, 28)]);
    expect(p.stato(DateTime(2026, 9, 28, 10)), StatoPeriodo.inCorso);
    expect(p.stato(DateTime(2026, 9, 28, 17)), StatoPeriodo.fuoriOrario);
    expect(p.stato(DateTime(2026, 9, 24, 10)), StatoPeriodo.inProgramma);
    expect(p.stato(DateTime(2026, 9, 29, 10)), StatoPeriodo.finito);
  });

  test('tutte le domeniche', () {
    final p = leggi('Tutte le domeniche a partire dal 12 luglio 2026 e sino '
        'a nuove comunicazioni. Direzione corso Bolzano…', '2026-07-11');
    expect(p.inizio, DateTime(2026, 7, 12));
    expect(p.giornoSettimana, 7);
    expect(p.stato(DateTime(2026, 9, 27, 10)), StatoPeriodo.inCorso);
    expect(p.stato(DateTime(2026, 9, 28, 10)), StatoPeriodo.fuoriOrario);
  });

  test('i sabati di un periodo, in una fascia', () {
    final p = leggi('Da sabato 23 Maggio e sino a sabato 7 novembre 2026 per '
        'tutte le giornate del sabato dalle ore 6:00 alle ore 15:00 circa. '
        'Direzione Settimo…', '2026-05-19');
    expect(p.inizio, DateTime(2026, 5, 23));
    expect(p.fine!.day, 7);
    expect(p.fine!.month, 11);
    expect(p.giornoSettimana, 6);
    expect(p.daMinuto, 6 * 60);
    expect(p.aMinuto, 15 * 60);
  });

  test('senza anno: quello dopo la pubblicazione', () {
    final p = leggi("Da lunedi' 16 febbraio sino a nuove comunicazioni.",
        '2025-11-15');
    expect(p.inizio, DateTime(2026, 2, 16));
  });

  test('una sera sola, fino a fine servizio', () {
    final p = leggi('Dalle ore 18,00  a termine del servizio  di martedì 15 '
        'Settembre 2026   Direzione  Crescentino…', '2026-09-14');
    expect(p.inizio, DateTime(2026, 9, 15, 18));
    expect(p.fine!.isAfter(DateTime(2026, 9, 15, 23)), isTrue);
    expect(p.fine!.isBefore(DateTime(2026, 9, 16, 6)), isTrue);
  });

  test('da un giorno a fine servizio di un altro', () {
    final p = leggi('Da martedì 15 a termine servizio di lunedì 28 settembre '
        '2026  Direzione Ceresole…', '2026-09-13');
    expect(p.inizio, DateTime(2026, 9, 15));
    expect(p.fine!.day, 28);
  });

  test('«sino alle 05:00 di»', () {
    final p = leggi('da giovedì 24 e sino alle 05:00 di lunedì 28 settembre '
        '2026.  Direzione piazza Carlo Felice…', '2026-09-24');
    expect(p.inizio, DateTime(2026, 9, 24));
    expect(p.fine, DateTime(2026, 9, 28, 5));
  });

  test('nelle giornate di sabato e domenica', () {
    final p = leggi('temporaneamente sospesa nelle giornate di sabato 26 e '
        'domenica 27 settembre 2026. Causa manifestazione.', '2026-09-22');
    expect(p.giorni, [DateTime(2026, 9, 26), DateTime(2026, 9, 27)]);
  });

  test('«dall\'11 maggio» e «Dal 30 settembre 2024»', () {
    expect(leggi("dall'11 maggio fino a nuove comunicazioni", '2026-05-11')
        .inizio, DateTime(2026, 5, 11));
    expect(leggi('Dal 30 settembre 2024, a causa di lavori edili…',
            '2024-09-30')
        .inizio, DateTime(2024, 9, 30));
  });

  test('una via con una data nel nome non e\' una data', () {
    final p = leggi('lunedì 21 e lunedì 28 settembre 2026, dalle ore 08:00 '
        'alle 16:00. Direzione Chivasso: via Trieste, via 25 Aprile, '
        'corso 4 Novembre, segue percorso normale.', '2026-09-20');
    expect(p.giorni, [DateTime(2026, 9, 21), DateTime(2026, 9, 28)]);
  });

  test('i numeri che non sono date non contano', () {
    final p = leggi('La linea non transita dalla fermata 1763 MORTARA.');
    expect(p.trovato, isFalse);
    expect(p.stato(DateTime(2026, 9, 28)), StatoPeriodo.sconosciuto);
  });

  test('un periodo che comincia domani e\' in programma', () {
    final p = leggi('Da lunedì 5 ottobre 2026 a venerdì 9 ottobre 2026.');
    expect(p.stato(DateTime(2026, 9, 28, 12)), StatoPeriodo.inProgramma);
    expect(p.stato(DateTime(2026, 10, 6, 12)), StatoPeriodo.inCorso);
    expect(p.stato(DateTime(2026, 10, 10, 12)), StatoPeriodo.finito);
  });

  test('una data sola, senza «da» ne\' «sino»: quel giorno e basta', () {
    // La 15 il 04/10/2026.
    final p = leggi('Domenica 04 ottobre 2026 dalle ore 6.30 alle ore 23.30 '
        'circa. Direzione piazza Coriolano (Sassi): da via Napione angolo…',
        '2026-10-03');
    expect(p.inizio, DateTime(2026, 10, 4));
    expect(p.fine, DateTime(2026, 10, 4, 23, 30));
    expect(p.stato(DateTime(2026, 10, 4, 12)), StatoPeriodo.inCorso);
    expect(p.stato(DateTime(2026, 10, 4, 5)), StatoPeriodo.fuoriOrario);
    expect(p.stato(DateTime(2026, 10, 5, 12)), StatoPeriodo.finito);
    expect(p.fascia, 'dalle 6:30 alle 23:30');
  });

  test('«Da…» con una data sola resta aperto', () {
    final p = leggi('Da lunedì 24 novembre 2025. Direzione via Goito…',
        '2025-11-23');
    expect(p.fine, isNull);
    expect(p.fascia, isNull);
    final q = leggi("Modifica d'esercizio da lunedi' 05 ottobre 2026. "
        'corsa n. 3808B…', '2026-10-03');
    expect(q.fine, isNull);
  });

  test('la fascia detta a parole', () {
    expect(
      leggi('Da sabato 23 Maggio e sino a sabato 7 novembre 2026 per tutte '
              'le giornate del sabato dalle ore 6:00 alle ore 15:00 circa')
          .fascia,
      'solo il sabato, dalle 6:00 alle 15:00',
    );
    expect(
      leggi("Mercoledi' 16 settembre dalle ore 10 e sino a nuove "
              'comunicazioni le corse serali dopo ore 20.00.')
          .fascia,
      'dalle 20:00 a fine servizio',
    );
  });
}
