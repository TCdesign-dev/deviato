import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/deviation_service.dart';
import 'package:gtt_deviazioni/core/geo/projection.dart';
import 'package:gtt_deviazioni/core/io/formato_pubblicato.dart';
import 'package:gtt_deviazioni/core/models/notice.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/core/pipeline/stop_impact.dart';
import 'package:gtt_deviazioni/data/app_repository.dart';
import 'package:gtt_deviazioni/data/fonte_dati.dart';
import 'package:gtt_deviazioni/data/settings.dart';
import 'package:gtt_deviazioni/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Il sito del job, in memoria: si puo' spegnere la rete e contare cosa
/// si scarica.
class _Fonte implements FonteDati {
  final Map<String, Map<String, dynamic>> pubblicati = {};
  final Map<String, Map<String, dynamic>> copie = {};
  final List<String> scaricati = [];
  bool rete = true;
  Completer<void>? attesa;

  @override
  Future<Map<String, dynamic>?> scarica(String percorso) async {
    await attesa?.future;
    if (!rete) throw const FonteNonRaggiungibile('rete spenta');
    scaricati.add(percorso);
    final f = pubblicati[percorso];
    if (f != null) copie[percorso] = f;
    return f;
  }

  @override
  Future<Map<String, dynamic>?> salvato(String percorso) async =>
      copie[percorso];
}

void main() {
  final fermata = TransitStop(
      id: 'S1', code: '100', name: 'Fermata 100 - SABOTINO',
      position: const GeoPoint(45.07, 7.665));
  RouteShape shape(String route) => RouteShape(
        shapeId: '$route:0', routeId: route, directionId: 0,
        headsign: 'CAPOLINEA',
        points: const [GeoPoint(45.07, 7.66), GeoPoint(45.07, 7.69)],
        stops: [fermata], tripCount: 10,
      );

  /// Quello che il job pubblica per la 55 (una fermata sospesa) e la 65.
  _Fonte fonte() {
    final f = _Fonte();
    final linee = [_l55, _l65];
    final generato = DateTime(2026, 9, 26, 18, 40);
    f.pubblicati['indice.json'] = _json(FormatoPubblicato.indice(
        feed: '20260922', generato: generato, linee: linee, fonte: 'GTT'));
    for (final l in linee) {
      final s = shape(l.routeId);
      f.pubblicati['percorsi/${l.routeId}.json'] =
          _json(FormatoPubblicato.percorsi(l, [s], feed: '20260922'));
      f.pubblicati['stato/${l.routeId}.json'] =
          _json(FormatoPubblicato.stato(LineStatus(
        line: l,
        shape: s,
        checkedAt: generato,
        reports: [
          if (l == _l55)
            DeviationReport(
              notice: const RawNotice(
                  id: 'a', source: NoticeSource.gtfsRtAlert,
                  text: 'Fermata 100 sospesa.', sourceUrl: ''),
              shape: s,
              confidence: Confidence.confermata,
              impact: StopImpactResult(
                impacts: [
                  StopImpact(stop: fermata, status: StopStatus.declaredSuspended),
                ],
                affectedFromMeters: 0,
                affectedToMeters: 100,
              ),
            ),
        ],
      )));
    }
    return f;
  }

  Future<AppRepository> repoWith(Map<String, Object> prefs, _Fonte f) async {
    SharedPreferences.setMockInitialValues(prefs);
    return AppRepository(await Settings.load(), fonte: f);
  }

  testWidgets('senza linee spiega cosa fare, invece di restare vuota',
      (tester) async {
    final repo = await repoWith({}, fonte());
    await repo.initialise();
    await tester.pumpWidget(GttApp(repo: repo));
    await tester.pump();

    expect(find.text('Aggiungi le tue linee'), findsOneWidget);
    expect(find.text('Aggiungi una linea'), findsWidgets);
  });

  testWidgets('al primo avvio mostra il caricamento, non una pagina bianca',
      (tester) async {
    final f = fonte()..attesa = Completer<void>();
    final repo = await repoWith({'watchlist': <String>['55']}, f);
    unawaited(repo.initialise());
    await tester.pumpWidget(GttApp(repo: repo));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    f.attesa!.complete();
    await tester.pumpAndSettle();
    expect(find.text('1 fermata non servita'), findsOneWidget);
  });

  testWidgets('Informazioni dice da dove vengono i dati e che non e GTT',
      (tester) async {
    final repo = await repoWith({}, fonte());
    await repo.initialise();
    await tester.pumpWidget(GttApp(repo: repo));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('Informazioni'), findsOneWidget);
    expect(find.textContaining('non è un\'app di GTT'), findsOneWidget);
    expect(find.textContaining('Data source: GTT S.p.A.'), findsOneWidget);
    // Niente chiavi da inserire: gli avvisi li legge il job.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('una linea si aggiunge dalla home, cercandola', (tester) async {
    final f = fonte();
    final repo = await repoWith({}, f);
    await repo.initialise();
    await tester.pumpWidget(GttApp(repo: repo));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Aggiungi una linea'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'moncalieri');
    await tester.pump();

    // Si trova dalla via, non solo dal numero.
    expect(find.text('via Moncalieri (Grugliasco) – corso Farini'),
        findsOneWidget);
    expect(find.text('via Servais – corso Bolzano'), findsNothing);

    await tester.tap(find.text('via Moncalieri (Grugliasco) – corso Farini'));
    await tester.pumpAndSettle();
    expect(find.text('Linea 55 aggiunta'), findsOneWidget);
    expect(repo.settings.watchlist, contains('55'));
    expect(find.text('1 fermata non servita'), findsOneWidget);
  });

  testWidgets('una linea si toglie scorrendo, e si rimette con Annulla',
      (tester) async {
    final repo = await repoWith({'watchlist': <String>['55', '65']}, fonte());
    await repo.initialise();
    await tester.pumpWidget(GttApp(repo: repo));
    await tester.pump();

    await tester.drag(find.text('65'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(repo.settings.watchlist, equals(['55']));
    expect(find.text('Linea 65 rimossa'), findsOneWidget);
    // Le altre restano dove sono.
    expect(find.text('55'), findsOneWidget);

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(repo.settings.watchlist, containsAll(['55', '65']));
    expect(find.text('65'), findsOneWidget);
  });

  // Flutter tiene fermo per sempre uno SnackBar con un pulsante: «Fermata
  // rimossa» restava sopra la home finché non lo si chiudeva a mano.
  testWidgets('l\'avviso con Annulla sparisce da solo', (tester) async {
    final repo = await repoWith({'watchlist': <String>['55', '65']}, fonte());
    await repo.initialise();
    await tester.pumpWidget(GttApp(repo: repo));
    await tester.pump();

    await tester.drag(find.text('65'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Linea 65 rimossa'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Linea 65 rimossa'), findsNothing);
  });

  testWidgets('con VoiceOver o TalkBack l\'avviso con Annulla resta',
      (tester) async {
    final repo = await repoWith({'watchlist': <String>['55', '65']}, fonte());
    await repo.initialise();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(accessibleNavigation: true),
      child: GttApp(repo: repo),
    ));
    await tester.pump();

    await tester.drag(find.text('65'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Linea 65 rimossa'), findsOneWidget);
  });

  testWidgets('senza rete mostra i dati salvati, e dice di quando sono',
      (tester) async {
    final f = fonte();
    final prima = await repoWith({'watchlist': <String>['55']}, f);
    await prima.initialise();

    // Il giorno dopo, in metropolitana.
    f.rete = false;
    final repo = AppRepository(prima.settings, fonte: f);
    await repo.initialise();
    await tester.pumpWidget(GttApp(repo: repo));
    await tester.pump();

    expect(find.text('1 fermata non servita'), findsOneWidget);
    expect(find.text('Nessuna connessione: dati delle 18:40.'), findsOneWidget);
    // Solo qui, dopo un tentativo non riuscito, c'e' il pulsante.
    expect(find.text('Riprova'), findsOneWidget);
  });

  testWidgets('con i dati scaricati non c\'e\' nessun pulsante Aggiorna',
      (tester) async {
    // Si aggiorna da solo, all'apertura e tornando all'app, e tirando giu'
    // la lista: un pulsante sempre in vista faceva pensare a dati vecchi.
    final repo = await repoWith({'watchlist': <String>['55']}, fonte());
    await repo.initialise();
    await tester.pumpWidget(GttApp(repo: repo));
    await tester.pump();

    expect(find.textContaining('alle 18:40'), findsOneWidget);
    expect(find.text('Aggiorna'), findsNothing);
    expect(find.text('Riprova'), findsNothing);
  });

  testWidgets('dal dettaglio si apre la mappa a tutto schermo, e si torna',
      (tester) async {
    final repo = await repoWith({'watchlist': <String>['55']}, fonte());
    await repo.initialise();
    await tester.pumpWidget(GttApp(repo: repo));
    await tester.pump();

    await tester.tap(find.text('1 fermata non servita'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mappa a tutto schermo'));
    await tester.pumpAndSettle();

    // I comandi della mappa con la scritta, il pulsante dei mezzi fra
    // loro; nel pannello il riassunto, e «Più dettagli» per aprirlo.
    expect(find.text('Tutta la linea'), findsOneWidget);
    expect(find.text('Segui i mezzi'), findsOneWidget);
    expect(find.text('Dove sono'), findsOneWidget);
    expect(find.text('Più dettagli'), findsOneWidget);
    expect(find.textContaining('1 fermata non servita'), findsWidgets);

    await tester.tap(find.text('Più dettagli'));
    await tester.pumpAndSettle();
    expect(find.text('Meno dettagli'), findsOneWidget);

    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Mappa a tutto schermo'), findsOneWidget);
  });

  test('tornando all\'app si riscarica, ma non a ogni occhiata', () async {
    final f = fonte();
    final repo = await repoWith({'watchlist': <String>['55']}, f);
    await repo.initialise();
    final prima = f.scaricati.where((p) => p == 'indice.json').length;

    // Appena scaricato: non si riscarica.
    await repo.aggiornaSeServe();
    expect(f.scaricati.where((p) => p == 'indice.json').length, prima);

    // Passato il tempo, si'.
    await repo.aggiornaSeServe(dopo: Duration.zero);
    expect(f.scaricati.where((p) => p == 'indice.json').length, prima + 1);
  });

  test('dopo un tentativo non riuscito si riprova subito', () async {
    final f = fonte();
    final repo = await repoWith({'watchlist': <String>['55']}, f);
    f.rete = false;
    await repo.initialise();
    expect(repo.offline, isTrue);

    f.rete = true;
    await repo.aggiornaSeServe();
    expect(repo.offline, isFalse);
    expect(f.scaricati, contains('indice.json'));
  });

  test('se gli orari non cambiano, i percorsi non si riscaricano', () async {
    // Sono la parte pesante: lo stato cambia spesso, i percorsi quasi mai.
    final f = fonte();
    final repo = await repoWith({'watchlist': <String>['55']}, f);
    await repo.initialise();
    await repo.refreshAll();
    expect(f.scaricati.where((p) => p == 'percorsi/55U.json').length, 1);
    expect(f.scaricati.where((p) => p == 'stato/55U.json').length, 2);
  });

  test('la stessa linea non si aggiunge due volte', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    await settings.addLine('55');
    await settings.addLine('55');
    await settings.addLine(' 55 ');
    expect(settings.watchlist, equals(['55']));
  });
}

Map<String, dynamic> _json(Map<String, Object?> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

const _l55 = TransitLine(
    routeId: '55U',
    shortName: '55',
    routeType: 3,
    sortOrder: 69,
    longName: 'via Moncalieri (Grugliasco) - corso Farini');
const _l65 = TransitLine(
    routeId: '65U',
    shortName: '65',
    routeType: 3,
    sortOrder: 79,
    longName: 'via Servais - corso Bolzano');
