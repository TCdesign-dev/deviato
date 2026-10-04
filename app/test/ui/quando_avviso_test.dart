import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/models/notice.dart';
import 'package:gtt_deviazioni/ui/quando_avviso.dart';

/// Quando vale un avviso, detto in una riga.
void main() {
  RawNotice avviso(String testo, [DateTime? dal]) => RawNotice(
    id: testo,
    source: NoticeSource.gtfsRtAlert,
    text: testo,
    sourceUrl: '',
    validFrom: dal ?? DateTime(2026, 10, 3, 13),
  );
  final domenica = DateTime(2026, 10, 4, 11);

  test('in programma, con quanto manca', () {
    expect(
      quandoAvviso(
        avviso(
          'Dalle ore 8:00 di lunedì 5 ottobre 2026 e sino a '
          'nuove comunicazioni.',
        ),
        domenica,
      ),
      'In vigore dal 05/10 · domani',
    );
    expect(
      quandoAvviso(
        avviso(
          'Dalle ore 7.30 di lunedi’ 05 e sino alle ore 19.00 '
          'circa di venerdi’ 09 ottobre 2026.',
        ),
        domenica,
      ),
      'In vigore dal 05/10 · domani · fino al 09/10',
    );
  });

  test('in corso, un giorno solo con la fascia', () {
    expect(
      quandoAvviso(
        avviso(
          'Domenica 04 ottobre 2026 dalle ore 6.30 alle ore '
          '23.30 circa.',
        ),
        domenica,
      ),
      'Il 04/10 · dalle 6:30 alle 23:30',
    );
  });

  test('in altri giorni', () {
    expect(
      quandoAvviso(
        avviso(
          'Da sabato 23 Maggio e sino a sabato 7 novembre '
          '2026 per tutte le giornate del sabato dalle ore 6:00 alle ore '
          '15:00 circa',
          DateTime(2026, 5, 20),
        ),
        domenica,
      ),
      'Dal 23/05 · fino al 07/11 · solo il sabato, dalle 6:00 alle 15:00',
    );
  });

  test('terminato', () {
    expect(
      quandoAvviso(
        avviso(
          'Dalle ore 18,00 a termine del servizio di martedì '
          '15 Settembre 2026',
          DateTime(2026, 9, 10),
        ),
        domenica,
      ),
      'Terminato il 15/09',
    );
  });
}
