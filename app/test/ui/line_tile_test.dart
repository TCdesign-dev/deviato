import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/deviation_service.dart';
import 'package:gtt_deviazioni/core/models/notice.dart';
import 'package:gtt_deviazioni/core/models/transit.dart';
import 'package:gtt_deviazioni/ui/line_badge.dart';
import 'package:gtt_deviazioni/ui/line_tile.dart';

/// Mezzo minuto davanti a una rotella che gira e basta e' indistinguibile
/// da un'app bloccata. Questi test tengono ferma la differenza.
///
/// Si verificano qui e non a schermo perche' lo stato dura pochi secondi:
/// fotografarlo e' una gara che si perde.
void main() {
  Widget schermo(Widget child) => MaterialApp(
    home: Scaffold(body: ListView(children: [child])),
  );

  testWidgets('mentre scarica una linea nuova mostra la barra', (
    tester,
  ) async {
    await tester.pumpWidget(
      schermo(
        const LineTile(
          line: _l65,
          status: null,
          watching: false,
          watchedVehicles: 0,
          checkedAt: null,
          checking: true,
        ),
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Aggiornamento…'), findsOneWidget);
  });

  testWidgets('appena aggiunta dice che si sta preparando', (tester) async {
    await tester.pumpWidget(
      schermo(
        const LineTile(
          line: _l65,
          status: null,
          watching: false,
          watchedVehicles: 0,
          checkedAt: null,
          checking: false,
          preparing: true,
        ),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Aggiornamento…'), findsOneWidget);
  });

  testWidgets('il riassunto vecchio sparisce mentre si ricontrolla', (
    tester,
  ) async {
    // Lasciare "2 fermate non servite" mentre si sta ricalcolando
    // significa mostrare un dato che potrebbe non essere piu' vero.
    await tester.pumpWidget(
      schermo(
        const LineTile(
          line: _l65,
          status: null,
          watching: false,
          watchedVehicles: 0,
          checkedAt: null,
          checking: true,
        ),
      ),
    );

    expect(find.text('Tocca per aggiornare'), findsNothing);
  });

  testWidgets('a riposo niente barra, e si vede lo stato', (tester) async {
    await tester.pumpWidget(
      schermo(
        const LineTile(
          line: _l65,
          status: null,
          watching: false,
          watchedVehicles: 0,
          checkedAt: null,
          checking: false,
        ),
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Tocca per aggiornare'), findsOneWidget);
  });

  testWidgets('nessun pulsante di aggiornamento sulla riga', (tester) async {
    // Aggiornare una linea sola costa quanto aggiornarle tutte: un
    // secondo, perche' il calcolo lo fa il job su GitHub.
    await tester.pumpWidget(
      schermo(
        const LineTile(
          line: _l65,
          status: null,
          watching: false,
          watchedVehicles: 0,
          checkedAt: null,
          checking: false,
        ),
      ),
    );
    expect(find.byIcon(Icons.refresh), findsNothing);
  });

  testWidgets('mentre guarda i mezzi lo dice, anche fuori dal dettaglio', (
    tester,
  ) async {
    // L'osservazione continua uscendo dalla schermata della linea: se qui
    // non si vedesse, uno la lascerebbe girare senza sapere che e' accesa.
    await tester.pumpWidget(
      schermo(
        const LineTile(
          line: _l15,
          status: null,
          watching: true,
          watchedVehicles: 3,
          checkedAt: null,
          checking: false,
        ),
      ),
    );

    expect(find.text('3 mezzi in tempo reale'), findsOneWidget);
    // L'occhio, come sul pulsante «Guarda adesso»: e' la stessa cosa.
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    // Prende il posto del riassunto: quello non e' cio' che sta
    // succedendo adesso.
    expect(find.text('Tocca per aggiornare'), findsNothing);
  });

  testWidgets('un mezzo solo si dice al singolare', (tester) async {
    await tester.pumpWidget(
      schermo(
        const LineTile(
          line: _l15,
          status: null,
          watching: true,
          watchedVehicles: 1,
          checkedAt: null,
          checking: false,
        ),
      ),
    );
    expect(find.text('1 mezzo in tempo reale'), findsOneWidget);
  });

  testWidgets('prima di vedere qualcosa non dice "zero mezzi"', (tester) async {
    await tester.pumpWidget(
      schermo(
        const LineTile(
          line: _l15,
          status: null,
          watching: true,
          watchedVehicles: 0,
          checkedAt: null,
          checking: false,
        ),
      ),
    );
    expect(find.text('Ricerca dei mezzi…'), findsOneWidget);
  });
  testWidgets('l etichetta dice se e un tram o un bus', (tester) async {
    await tester.pumpWidget(
      schermo(
        const LineTile(
          line: _l15,
          status: null,
          watching: false,
          watchedVehicles: 0,
          checkedAt: null,
          checking: false,
        ),
      ),
    );
    expect(find.byIcon(Icons.tram), findsOneWidget);
    // Per chi usa il lettore di schermo: l'icona da sola non si legge.
    expect(
        find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'tram 15'),
        findsOneWidget);
  });
  testWidgets('finita l osservazione, i dettagli tornano al loro posto', (
    tester,
  ) async {
    // Visto sul simulatore il 26/09: finita l'osservazione della 68, la
    // riga ridisegnava «2 avvisi» in alto a sinistra, sopra l'etichetta.
    // Il sottotitolo passava da assente a presente e la riga non veniva
    // ridisposta.
    Widget riga({required bool watching}) => schermo(
          LineTile(
            line: _l65,
            status: null,
            watching: watching,
            watchedVehicles: 3,
            checkedAt: DateTime(2020),
            checking: false,
          ),
        );
    await tester.pumpWidget(riga(watching: true));
    await tester.pumpWidget(riga(watching: false));

    final etichetta = tester.getTopLeft(find.byType(LineBadge));
    final dettagli = tester.getTopLeft(find.textContaining('aggiornata'));
    expect(dettagli.dx, greaterThan(etichetta.dx + 40),
        reason: 'i dettagli devono stare a destra dell etichetta');
  });
  testWidgets('un avviso non letto non diventa «fermate servite»', (
    tester,
  ) async {
    // La 7 il 26/09: «Linea 7 sospesa domenica 27», non letto per la quota
    // esaurita. La riga diceva «Deviata, fermate servite».
    final shape = RouteShape(
      shapeId: 'S',
      routeId: '65U',
      directionId: 0,
      headsign: 'X',
      points: const [],
    );
    final status = LineStatus(
      line: _l65,
      shape: shape,
      checkedAt: DateTime(2026, 9, 26),
      reports: [
        DeviationReport(
          notice: const RawNotice(
            id: 'n',
            source: NoticeSource.gtfsRtAlert,
            text: 'Linea temporaneamente sospesa.',
            sourceUrl: '',
          ),
          confidence: Confidence.soloTesto,
          shape: shape,
        ),
      ],
    );
    await tester.pumpWidget(
      schermo(
        LineTile(
          line: _l65,
          status: status,
          watching: false,
          watchedVehicles: 0,
          checkedAt: null,
          checking: false,
        ),
      ),
    );
    expect(find.text('Avviso in corso'), findsOneWidget);
    expect(find.textContaining('servite'), findsNothing);
  });
}


const _l65 = TransitLine(
    routeId: '65U', shortName: '65', color: 'FF9900', routeType: 3);
const _l15 = TransitLine(
    routeId: '15U', shortName: '15', color: 'CC9900', routeType: 0);
