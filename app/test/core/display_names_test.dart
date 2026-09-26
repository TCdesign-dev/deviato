import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/geo/projection.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/text/display_names.dart';

/// I nomi veri del GTFS di GTT, visti sulla 10N il 26/09.
void main() {
  TransitStop fermata(String name) =>
      TransitStop(id: 'x', name: name, position: const GeoPoint(45, 7));

  group('Fermate', () {
    test('toglie il codice e il maiuscolo', () {
      expect(DisplayNames.stop(fermata('Fermata 422 - LARGO GIACHINO SUD')),
          equals('Largo Giachino Sud'));
    });

    test('i numeri romani restano maiuscoli', () {
      expect(DisplayNames.stop(fermata('Fermata 27 - XVIII DICEMBRE')),
          equals('XVIII Dicembre'));
    });

    test('le preposizioni in mezzo vanno in minuscolo', () {
      expect(DisplayNames.stop(fermata('Fermata 8347 - CHIESA DELLA SALUTE')),
          equals('Chiesa della Salute'));
    });

    test('apostrofo: l articolo minuscolo, il nome maiuscolo', () {
      expect(DisplayNames.titleCase("PIAZZA DELL'ARTE"),
          equals("Piazza dell'Arte"));
    });

    test('CAP e il capolinea', () {
      expect(DisplayNames.stop(fermata('Fermata 350 - MASSARI CAP')),
          equals('Massari capolinea'));
    });

    test('le lettere accentate restano', () {
      expect(DisplayNames.stop(fermata('Fermata 1410 - VIBÒ')), equals('Vibò'));
    });
  });

  group('Direzioni', () {
    test('usa il capolinea, non l etichetta uguale per le due direzioni', () {
      // La legenda diceva «→ NAVETTA» due volte.
      expect(DisplayNames.direction('NAVETTA, VIA MASSARI'),
          equals('via Massari'));
      expect(DisplayNames.direction('NAVETTA, PIAZZA XVIII DICEMBRE'),
          equals('piazza XVIII Dicembre'));
    });

    test('il qualificatore della linea non finisce nel capolinea', () {
      // La 7 il 26/09.
      expect(
          DisplayNames.direction('PIAZZA CASTELLO',
              longName: 'circolare Tram Storici, piazza Castello - Porta Nuova'),
          equals('piazza Castello'));
    });

    test('se il nome lungo lo scrive gia bene, usa quello', () {
      expect(
          DisplayNames.direction('NAVETTA, PIAZZA XVIII DICEMBRE',
              longName: 'via Massari - piazza XVIII Dicembre'),
          equals('piazza XVIII Dicembre'));
    });
  });

  group('Altri nomi veri', () {
    test('le sigle restano maiuscole', () {
      expect(DisplayNames.titleCase('STABILIMENTO GTT TORTONA'),
          equals('Stabilimento GTT Tortona'));
    });

    test('il tipo di strada che manca nel headsign lo da il nome lungo', () {
      expect(
          DisplayNames.direction('CAFASSO',
              longName: 'via Cafasso - via Frejus'),
          equals('via Cafasso'));
    });
  });

  group('Percorso della linea', () {
    test('il qualificatore davanti va a parte', () {
      final p = DisplayNames.routeParts(
          'feriale, corso Vercelli (Park Stura) - corso Bolzano');
      expect(p.qualifier, equals('feriale'));
      expect(p.route, equals('corso Vercelli (Park Stura) – corso Bolzano'));
    });

    test('senza qualificatore resta intero', () {
      final p = DisplayNames.routeParts('via Servais - corso Bolzano');
      expect(p.qualifier, isNull);
      expect(p.route, equals('via Servais – corso Bolzano'));
    });
  });

  group('Motivo', () {
    test('il codice del feed si traduce', () {
      expect(DisplayNames.reason('DEMONSTRATION'), equals('manifestazione'));
    });

    test('altra causa non dice niente e non si mostra', () {
      expect(DisplayNames.reason('OTHER_CAUSE'), isNull);
      expect(DisplayNames.reason('UNKNOWN_CAUSE'), isNull);
    });

    test('il testo libero della tabella resta com e', () {
      expect(DisplayNames.reason('Lavori di rifacimento del ponte Rossini'),
          equals('Lavori di rifacimento del ponte Rossini'));
    });
  });
}
