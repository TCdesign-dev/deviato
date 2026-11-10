import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/pipeline/lettore_a_regole.dart';

/// Testi veri di GTT, novembre 2026. Misurato su 102 avvisi pubblicati
/// (tool/misura_regole.dart): 10 letti, 10 uguali alla lettura del modello.
void main() {
  test('lo schema fisso: stacco, angolo, vie in ordine', () {
    final r = LettoreARegole.leggi(
      'Linea 1511 deviata in direzione Torino.',
      'Dalle ore 8.30 di lunedi\' 05 e sino alle ore 19.00 circa di '
          'venerdi’ 30 novembre 2026 da via Di Nanni angolo via De Gasperi '
          'prosegue per via Di Nanni, via Torino, percorso regolare.\n'
          'Causa lavori Italgas nel comune di Orbassano.',
    )!;
    expect(r, hasLength(1));
    expect(r.single.detachStreet, 'via Di Nanni');
    expect(r.single.detachCrossStreet, 'via De Gasperi');
    expect(r.single.viaSequence, ['via Di Nanni', 'via Torino']);
    expect(r.single.directionDesc, 'Torino');
  });

  test('una direzione devia, l\'altra ha il percorso regolare', () {
    final r = LettoreARegole.leggi(
      'Linea 19 deviata in direzione corso Cadore',
      'Da lunedi\' 16 febbraio sino a nuove comunicazioni. Nella sola '
          'direzione di corso Cadore: da lungo Dora Colletta prosegue per '
          'lungo Dora Colletta, via Racagni, via Varano, percorso normale. '
          'Causa avanzamento lavori SMAT in via Varano.',
    )!;
    expect(r.single.directionDesc, 'corso Cadore');
    expect(r.single.viaSequence,
        ['lungo Dora Colletta', 'via Racagni', 'via Varano']);
  });

  group('nel dubbio non legge, e l\'avviso va al modello', () {
    test('un\'inversione di marcia in mezzo', () {
      expect(
        LettoreARegole.leggi(
          'Linea 65 deviata in direzione Servais',
          'Direzione via Servais: da via Asinari di Bernezzo angolo via '
              'Pietro Cossa, devia per via Pietro Cossa, via Servais, '
              'effettua inversione di marcia all’altezza di corso Sacco e '
              'Vanzetti, via Servais, capolinea. Direzione corso Bolzano: '
              'percorso regolare.',
        ),
        isNull,
      );
    });

    test('«percorso regolare dopo via…»: il rientro e\' un\'altra cosa', () {
      expect(
        LettoreARegole.leggi(
          'Linee 27 e 27F in direzione XX Settembre',
          'da via Gottardo angolo via Monte Rosa, deviata per via Gottardo, '
              'corso Giulio Cesare carreggiata veicolare percorso regolare '
              'dopo via Cherubini.',
        ),
        isNull,
      );
    });

    test('una limitazione o una fermata sospesa', () {
      expect(
        LettoreARegole.leggi('Linea 5 limitata in direzione Orbassano',
            'Limitata in via Torino.'),
        isNull,
      );
      expect(LettoreARegole.leggi('Fermata 2686 sospesa', 'da lunedì'), isNull);
    });
  });
}
