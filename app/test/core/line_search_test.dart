import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/pipeline/line_search.dart';

/// Nomi, capolinea e ordine veri, dal GTFS di GTT del 22/09/2026.
void main() {
  TransitLine l(
    String id,
    String name,
    int order,
    String longName, {
    int type = 3,
  }) => TransitLine(
    routeId: id,
    shortName: name,
    sortOrder: order,
    routeType: type,
    longName: longName,
  );

  final tutte = [
    l('65U', '65', 79, 'via Servais - corso Bolzano'),
    l('4U', '4', 3, 'via delle Querce - strada del Drosso', type: 0),
    l('55U', '55', 69, 'via Moncalieri (Grugliasco) - corso Farini'),
    l('10NU', '10N', 7, 'via Massari - piazza XVIII Dicembre'),
    l('5U', '5', 5, 'piazza Dalla Chiesa (Orbassano) - piazza Arbarello'),
    l(
      '5BU',
      '5/',
      6,
      'lunedì-venerdì, via Bertani (cimitero Parco) - piazza Arbarello',
    ),
    l('51U', '51', 65, 'feriale, corso Vercelli (Park Stura) - corso Bolzano'),
    l('15U', '15', 10, 'via Brissogne - piazza Coriolano', type: 0),
  ];

  List<String> nomi(String q) =>
      LineSearch.filter(tutte, q).map((x) => x.shortName).toList();

  test('senza ricerca: tutte, nell ordine di GTT', () {
    expect(nomi(''), equals(['4', '5', '5/', '10N', '15', '51', '55', '65']));
  });

  test('il numero esatto viene prima di quelli che cominciano cosi', () {
    expect(nomi('5'), equals(['5', '5/', '51', '55']));
  });

  test('maiuscole e spazi non contano', () {
    expect(nomi('10n').first, equals('10N'));
    expect(nomi(' 6 5 ').first, equals('65'));
  });

  test('si trova anche dalle vie', () {
    // Chi non sa il numero della notturna sa dove va.
    expect(nomi('massari'), equals(['10N']));
    expect(nomi('corso bolzano'), equals(['51', '65']));
  });

  test('una ricerca che non trova niente restituisce niente', () {
    expect(nomi('zzz'), isEmpty);
  });
}
