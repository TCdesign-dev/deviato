import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/sources/scioperi_mit.dart';
import 'package:gtt_deviazioni/ui/scioperi.dart';

void main() {
  final usb = Sciopero(
    inizio: DateTime(2026, 10, 30),
    fine: DateTime(2026, 10, 30),
    sindacati: 'USB',
    settore: 'Generale',
    modalita: "INTERA GIORNATA - TPL: DURATA E MODALITA' STABILITE A "
        'LIVELLO TERRITORIALE; AUTOSTRADE: DALLE 22.00',
    rilevanza: 'Nazionale',
    regione: 'Italia',
  );

  Future<void> mostra(WidgetTester tester, DateTime oggi) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ScioperoBanner(scioperi: [usb], oggi: oggi)),
      ));

  testWidgets('entro una settimana compare in cima, con il giorno',
      (tester) async {
    await mostra(tester, DateTime(2026, 10, 25, 9));
    expect(find.text('Sciopero venerdì 30/10'), findsOneWidget);
    expect(find.textContaining('Bus e tram: durata e modalità'), findsOneWidget);
  });

  testWidgets('piu\' in la\' no: non si legge ogni giorno per niente',
      (tester) async {
    await mostra(tester, DateTime(2026, 10, 22, 9));
    expect(find.textContaining('Sciopero'), findsNothing);
  });

  testWidgets('passato, sparisce', (tester) async {
    await mostra(tester, DateTime(2026, 10, 31, 9));
    expect(find.textContaining('Sciopero'), findsNothing);
  });

  testWidgets('toccandolo si vedono i dettagli e il calendario',
      (tester) async {
    await mostra(tester, DateTime(2026, 10, 30, 7));
    expect(find.text('Sciopero oggi'), findsOneWidget);
    await tester.tap(find.text('Sciopero oggi'));
    await tester.pumpAndSettle();
    expect(find.text('Scioperi'), findsOneWidget);
    expect(find.text('Calendario del Ministero dei Trasporti'), findsOneWidget);
  });
}
