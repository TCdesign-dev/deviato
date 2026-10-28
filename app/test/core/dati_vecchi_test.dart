import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/io/formato_pubblicato.dart';
import 'package:gtt_deviazioni/core/pipeline/dati_vecchi.dart';

void main() {
  group('Quando i dati sono vecchi', () {
    test('di giorno bastano due ore senza giri', () {
      final ora = DateTime(2026, 10, 28, 17, 0);
      expect(DatiVecchi.sono(DateTime(2026, 10, 28, 15, 20), ora), isFalse);
      expect(DatiVecchi.sono(DateTime(2026, 10, 28, 14, 50), ora), isTrue);
    });

    test('di notte fra le 3:13 e le 6:13 passano tre ore di regola', () {
      // Il giro delle 3:13 pubblica verso le 3:20: alle 6:30 i dati hanno
      // tre ore e dieci, e non sono vecchi.
      expect(
        DatiVecchi.sono(
          DateTime(2026, 10, 28, 3, 20),
          DateTime(2026, 10, 28, 6, 30),
        ),
        isFalse,
      );
      // Alle 7, se i giri delle 6:13 e delle 6:43 non hanno pubblicato, si'.
      expect(
        DatiVecchi.sono(
          DateTime(2026, 10, 28, 3, 20),
          DateTime(2026, 10, 28, 7, 30),
        ),
        isTrue,
      );
    });

    test('il 28/10: sei giorni dopo il 20 alle 23:20', () {
      expect(
        DatiVecchi.sono(
          DateTime(2026, 10, 20, 23, 20),
          DateTime(2026, 10, 28, 9, 0),
        ),
        isTrue,
      );
    });
  });

  group('Da quando, detto', () {
    final ora = DateTime(2026, 10, 28, 17, 0); // un mercoledi'
    test('oggi, ieri, in settimana, prima', () {
      expect(
        DatiVecchi.daQuando(DateTime(2026, 10, 28, 9, 5), ora),
        'dalle 09:05',
      );
      expect(
        DatiVecchi.daQuando(DateTime(2026, 10, 27, 1, 20), ora),
        'da ieri alle 01:20',
      );
      expect(
        DatiVecchi.daQuando(DateTime(2026, 10, 26, 23, 20), ora),
        'da lunedì alle 23:20',
      );
      // Oltre sei giorni il giorno della settimana sarebbe ambiguo.
      expect(
        DatiVecchi.daQuando(DateTime(2026, 10, 20, 23, 20), ora),
        'dal 20/10 alle 23:20',
      );
    });
  });

  test('salute.json: si scrive e si rilegge', () {
    final quando = DateTime(2026, 10, 28, 17, 13);
    final giu = FormatoPubblicato.leggiSalute(
      FormatoPubblicato.salute(avvisiGtt: false, controllato: quando),
    );
    expect(giu?.avvisiGtt, isFalse);
    expect(giu?.controllato, quando);
    expect(
      FormatoPubblicato.leggiSalute(
        FormatoPubblicato.salute(avvisiGtt: true, controllato: quando),
      )?.avvisiGtt,
      isTrue,
    );
    expect(FormatoPubblicato.leggiSalute({'versione': 1}), isNull);
  });
}
