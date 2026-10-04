import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/models/notice.dart';
import 'package:gtt_deviazioni/core/text/periodo_avviso.dart';

/// Le date di un avviso vengono dal suo testo: quelle del feed sono di
/// pubblicazione. Testi degli avvisi veri del 04/10/2026.
void main() {
  RawNotice avviso(String testo, {DateTime? dal, DateTime? al}) => RawNotice(
    id: testo.hashCode.toString(),
    source: NoticeSource.gtfsRtAlert,
    text: testo,
    sourceUrl: '',
    validFrom: dal ?? DateTime(2026, 10, 3, 13),
    validUntil: al,
  );
  final domenica = DateTime(2026, 10, 4, 11);

  test('annunciato in anticipo: in programma, non in corso', () {
    // La 65: pubblicato venerdì 3, comincia lunedì 5.
    final n = avviso(
      'Dalle ore 8:00 di lunedì 5 ottobre 2026 e sino a nuove '
      'comunicazioni Direzione via Servais: da via Asinari di Bernezzo…',
    );
    expect(n.statoAl(domenica), StatoPeriodo.inProgramma);
    expect(n.startsAfter(domenica), isTrue);
    expect(n.daysUntilStart(domenica), 1);
    expect(n.inizioDaDire(domenica), DateTime(2026, 10, 5, 8));
    // Lunedì alle 7 non ancora, alle 9 sì.
    expect(n.statoAl(DateTime(2026, 10, 5, 7)), StatoPeriodo.inProgramma);
    expect(n.daysUntilStart(DateTime(2026, 10, 5, 7)), 0);
    expect(n.statoAl(DateTime(2026, 10, 5, 9)), StatoPeriodo.inCorso);
  });

  test('finito ma ancora pubblicato: non conta', () {
    final n = avviso(
      'Dalle ore 18,00 a termine del servizio di martedì 15 '
      'Settembre 2026 Direzione Crescentino…',
      dal: DateTime(2026, 9, 10),
    );
    expect(n.statoAl(domenica), StatoPeriodo.finito);
    expect(n.startsAfter(domenica), isFalse);
  });

  test('solo il sabato: la domenica e\' fuori orario', () {
    final n = avviso(
      'Da sabato 23 Maggio e sino a sabato 7 novembre 2026 '
      'per tutte le giornate del sabato dalle ore 6:00 alle ore 15:00 '
      'circa…',
      dal: DateTime(2026, 5, 20),
    );
    expect(n.statoAl(domenica), StatoPeriodo.fuoriOrario);
    expect(n.statoAl(DateTime(2026, 10, 10, 9)), StatoPeriodo.inCorso);
    expect(n.fasciaDaDire, 'solo il sabato, dalle 6:00 alle 15:00');
    expect(n.endToShow, DateTime(2026, 11, 7, 23, 59));
  });

  test('la fine scritta nel testo vince su quella del feed', () {
    final n = avviso(
      'Dalle ore 7.30 di lunedi’ 05 e sino alle ore 19.00 '
      'circa di venerdi’ 09 ottobre 2026.',
      al: DateTime(2027, 10, 2),
    );
    expect(n.endToShow, DateTime(2026, 10, 9, 19));
  });

  test('senza date nel testo, come prima: la data del feed', () {
    final n = avviso(
      'Fermata 3445 Sabotino sospesa.',
      dal: DateTime(2026, 10, 6),
    );
    expect(n.statoAl(domenica), StatoPeriodo.inProgramma);
    expect(
      avviso('Fermata 3445 Sabotino sospesa.').statoAl(domenica),
      StatoPeriodo.inCorso,
    );
  });
}
