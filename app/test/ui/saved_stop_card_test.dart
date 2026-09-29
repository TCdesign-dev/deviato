import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/geo/projection.dart';
import 'package:gtt_deviazioni/core/models/saved_stop.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/pipeline/stop_answer.dart';
import 'package:gtt_deviazioni/ui/saved_stop_card.dart';

/// La 10N il 26/09: Largo Giachino Sud chiusa, si sale a Vibò.
void main() {
  TransitStop f(String code, String name) => TransitStop(
    id: 'S$code',
    code: code,
    name: 'Fermata $code - $name',
    position: const GeoPoint(45.07, 7.66),
  );
  final giachino = f('422', 'LARGO GIACHINO SUD');
  final vibo = f('1410', 'VIBÒ');
  final statuto = f('373', 'STATUTO NORD');
  final shape = RouteShape(
    shapeId: 'A',
    routeId: '10NU',
    directionId: 0,
    headsign: 'NAVETTA, PIAZZA XVIII DICEMBRE',
    points: const [],
  );
  const line = TransitLine(
    routeId: '10NU',
    shortName: '10N',
    longName: 'via Massari - piazza XVIII Dicembre',
  );
  const saved = SavedStop(routeId: '10NU', directionId: 0, stopId: 'S422');

  Future<void> pump(
    WidgetTester tester,
    StopAnswer a, {
    bool checking = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SavedStopRow(
          answer: a,
          line: line,
          checking: checking,
          onTap: () {},
        ),
      ),
    ),
  );

  testWidgets('chiusa: dice fino a quando e dove salire', (tester) async {
    await pump(
      tester,
      StopAnswer(
        state: StopState.closed,
        saved: saved,
        stop: giachino,
        shape: shape,
        until: DateTime(2026, 9, 29),
        walkTo: [(stop: vibo, meters: 178), (stop: statuto, meters: 240)],
      ),
    );
    expect(
      find.text('Largo Giachino Sud  422', findRichText: true),
      findsOneWidget,
    );
    // Lo stato e il verso sulla stessa riga.
    expect(
      find.text(
        'Non servita fino al 29/09 · verso piazza XVIII Dicembre',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Sali a Vibò, 180 m o a Statuto Nord, 240 m',
        findRichText: true,
      ),
      findsOneWidget,
    );
    // La distanza e' in linea d'aria, e lo dice.
    expect(
      find.textContaining("in linea d'aria", findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('mai controllata: non finge di sapere', (tester) async {
    await pump(
      tester,
      StopAnswer(
        state: StopState.unknown,
        saved: saved,
        stop: giachino,
        shape: shape,
      ),
    );
    expect(
      find.textContaining('Tocca per aggiornare', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Sali a', findRichText: true), findsNothing);
  });

  testWidgets('mentre si controlla la linea, la vecchia risposta non resta', (
    tester,
  ) async {
    await pump(
      tester,
      StopAnswer(
        state: StopState.closed,
        saved: saved,
        stop: giachino,
        shape: shape,
        walkTo: [(stop: vibo, meters: 178)],
      ),
      checking: true,
    );
    expect(
      find.textContaining('Aggiornamento…', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Non servita'), findsNothing);
  });
  testWidgets('la seconda fermata lontana non si dice', (tester) async {
    // Mortara, il 26/09: i capi del tratto chiuso a 680 e a 1430 m.
    await pump(
      tester,
      StopAnswer(
        state: StopState.closed,
        saved: saved,
        stop: giachino,
        shape: shape,
        walkTo: [(stop: vibo, meters: 680), (stop: statuto, meters: 1430)],
      ),
    );
    expect(
      find.textContaining('Sali a Vibò, 680 m in linea', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Statuto', findRichText: true), findsNothing);
  });

  testWidgets('le fermate della stessa linea stanno in una scheda sola', (
    tester,
  ) async {
    StopAnswer servita(TransitStop f) => StopAnswer(
      state: StopState.served,
      saved: SavedStop(routeId: '10NU', directionId: 0, stopId: f.id),
      stop: f,
      shape: shape,
    );
    var aperta = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SavedStopsGroup(
            line: line,
            onOpenLine: () => aperta = true,
            children: [
              for (final f in [giachino, vibo, statuto])
                SavedStopRow(
                  answer: servita(f),
                  line: line,
                  checking: false,
                  onTap: () {},
                ),
            ],
          ),
        ),
      ),
    );
    // Il numero della linea una volta sola, le tre fermate tutte.
    expect(find.text('10N'), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
    expect(find.textContaining('Vibò', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('Servita · verso', findRichText: true),
      findsNWidgets(3),
    );
    // La testa della scheda apre la linea.
    await tester.tap(find.text('10N'));
    expect(aperta, isTrue);
  });
}
