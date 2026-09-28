import '../deviation_service.dart';
import '../geo/projection.dart';
import '../models/notice.dart';
import '../models/transit.dart';
import '../pipeline/extractor.dart';
import '../pipeline/geocoder.dart';
import '../pipeline/rejoin_inference.dart';
import '../pipeline/route_builder.dart';
import '../pipeline/stop_impact.dart';
import 'ricostruzione.dart';

/// Il primo algoritmo: quello in servizio fino al 28/09/2026, copiato
/// com'era da `DeviationService._analyze`.
///
/// **Non si modifica.** E' la versione a cui si torna se il secondo va
/// peggio: le correzioni vanno in [Ricostruzione2]. Vedi [AlgoritmoPercorsi].
///
/// Ogni via nominata diventa un punto solo (Photon), il rientro si deduce
/// dall'ultima via, e Valhalla unisce i punti nell'ordine dell'avviso.
class Ricostruzione1 implements Ricostruzione {
  Ricostruzione1({
    required this._geocoder,
    required this._router,
    required this._impact,
  });

  final Geocoder _geocoder;
  final RouteBuilder _router;
  final StopImpactAnalyzer _impact;

  @override
  Future<DeviationReport> analizza(
    RawNotice notice,
    RouteShape shape,
    ExtractionResult extraction, {
    void Function(String phase)? onProgress,
  }) async {
    // 1. Testo -> struttura: gia' fatto, una volta per avviso.
    //
    // Un errore del modello (quota, rete, chiave) passa; un testo che non
    // descrive un percorso no.
    final estrazioneDaRitentare = extraction.status == ExtractionStatus.error;
    if (!extraction.isUsable) {
      // L'LLM non ha risposto — quota finita, rete, servizio giu'. Ma se
      // GTT ha scritto un numero di fermata, quel numero sta nel testo e
      // lo prende una regex: non serve nessun modello per leggerlo.
      // Sarebbe assurdo perdere il dato piu' certo che abbiamo proprio
      // quando tutto il resto non funziona.
      final impact = _impact.declaredOnly(
          officialRoute: shape,
          declaredCodes: notice.suspendedStopCodes.toSet());
      if (impact.hasImpact) {
        return DeviationReport(
          notice: notice,
          shape: shape,
          impact: impact,
          // Non "confermata": senza estrazione non sappiamo se l'avviso
          // dica anche altro, per esempio un cambio di percorso che non
          // abbiamo ricostruito.
          confidence: Confidence.probabile,
          whyIncomplete: 'La fermata sospesa è indicata da GTT. Il resto '
              'dell\'avviso non è stato letto: '
              '${DeviationService.lowerFirst(DeviationService.explainExtractionFailure(extraction))}',
          retryable: estrazioneDaRitentare,
        );
      }
      return DeviationReport(
        notice: notice,
        shape: shape,
        confidence: Confidence.soloTesto,
        whyIncomplete: DeviationService.explainExtractionFailure(extraction),
        retryable: estrazioneDaRitentare,
      );
    }
    final parsed = extraction.deviations.first;

    // Una sostituzione di mezzo non cambia il percorso: mostrarla come
    // deviazione sarebbe un allarme falso (§10.10).
    if (parsed.type == DeviationType.sostituzioneModale) {
      return DeviationReport(
        notice: notice,
        shape: shape,
        parsed: parsed,
        confidence: Confidence.confermata,
        whyIncomplete: 'Stesso percorso, cambia solo il tipo di mezzo.',
      );
    }

    // 1-bis. Fermate sospese senza cambio di percorso.
    //
    // MISURATO: 14 avvisi su 198 dicono soltanto "Fermata 3447 Sabotino
    // sospesa". Il codice sta nel testo, non in informed_entity, e si
    // estrae con una regex. Prima finivano nel ramo "non nomina abbastanza
    // vie" e l'informazione si perdeva, pur essendo la piu' certa che il
    // sistema abbia: nessuna geometria da ricostruire, solo un codice da
    // cercare nel GTFS.
    final declaredCodes = <String>{
      ...notice.suspendedStopCodes,
      ...parsed.suspendedStopCodes,
    };
    if (declaredCodes.isNotEmpty && parsed.viaSequence.isEmpty) {
      final impact = _impact.declaredOnly(
          officialRoute: shape, declaredCodes: declaredCodes);
      return DeviationReport(
        notice: notice,
        shape: shape,
        parsed: parsed,
        impact: impact,
        confidence: Confidence.confermata,
        whyIncomplete: impact.hasImpact
            ? null
            : declaredCodes.length == 1
                ? 'La fermata ${declaredCodes.first} indicata da GTT non è '
                    'su questo percorso.'
                : 'Le fermate ${declaredCodes.join(", ")} indicate da GTT '
                    'non sono su questo percorso.',
      );
    }

    // 2. Toponimi -> coordinate, vincolate al percorso di questa linea.
    final toponyms = parsed.allToponyms;
    if (toponyms.length < 2) {
      return DeviationReport(
        notice: notice,
        shape: shape,
        parsed: parsed,
        confidence: Confidence.soloTesto,
        whyIncomplete: 'L\'avviso non indica abbastanza vie per disegnare '
            'il percorso.',
      );
    }

    final points = <GeoPoint>[];
    final unresolved = <String>[];
    // Photon non raggiungibile non e' «via non trovata»: si ritenta.
    var geocodingInErrore = false;
    for (var i = 0; i < toponyms.length; i++) {
      final t = toponyms[i];
      // Il geocoding e' il passaggio piu' lento: una chiamata per via,
      // con le pause di cortesia verso Photon. Vale la pena dire a che
      // punto e', e quale via si sta cercando.
      onProgress?.call('ricerca di «$t»');
      final r = await _geocoder.locate(t,
          near: shape, municipality: parsed.municipality);
      if (r.isUsable) {
        points.add(r.point!);
      } else {
        unresolved.add(t);
        if (r.status == GeocodeStatus.error) geocodingInErrore = true;
      }
    }
    if (points.length < 2) {
      return DeviationReport(
        notice: notice,
        shape: shape,
        parsed: parsed,
        confidence: Confidence.soloTesto,
        whyIncomplete: 'Vie non trovate sulla mappa: ${unresolved.join(", ")}.',
        retryable: geocodingInErrore,
      );
    }

    // 2-bis. Dove rientra.
    //
    // MISURATO: 24 avvisi su 28 non nominano la via di rientro, dicono solo
    // "percorso normale". Senza dedurlo il percorso deviato si ferma
    // all'ultima via nominata, il tratto di linea interessato resta
    // troncato, e le fermate fra li' e il rientro vero non vengono valutate.
    final RejoinPoint rejoin;
    if (parsed.rejoinStreet != null) {
      // GTT l'ha detto: il punto e' gia' fra quelli geocodificati.
      rejoin = RejoinPoint(
        source: RejoinSource.dichiarato,
        point: points.last,
      );
    } else {
      rejoin = RejoinInference.infer(
        officialRoute: shape,
        detachPoint: points.first,
        lastVia: points.last,
      );
    }

    // Il punto dedotto diventa l'ultimo waypoint: cosi' il percorso
    // calcolato arriva fino al rientro invece di fermarsi prima.
    final waypoints = [
      ...points,
      if (rejoin.source == RejoinSource.dedotto) rejoin.point!,
    ];

    // 3. Punti -> percorso vero, con le cinque prove.
    onProgress?.call('calcolo del percorso');
    final route = await _router.build(
      waypoints: waypoints,
      officialRoute: shape,
      // Le vie da attraversare restano quelle NOMINATE: il rientro dedotto
      // e' una nostra inferenza, non una promessa di GTT, e pretendere che
      // il percorso ci passi vicino sarebbe verificare noi stessi.
      requiredVias: points.sublist(1),
    );
    if (route.geometry == null) {
      return DeviationReport(
        notice: notice,
        shape: shape,
        parsed: parsed,
        rejoin: rejoin,
        confidence: Confidence.soloTesto,
        whyIncomplete: 'Non è stato possibile calcolare il percorso deviato.',
        retryable: geocodingInErrore || route.status == RouteBuildStatus.error,
      );
    }

    // 4. Quali fermate saltano.
    final impact = _impact.analyze(
      officialRoute: shape,
      deviatedRoute: route.geometry!,
      declaredSuspendedCodes: {
        ...notice.suspendedStopCodes,
        ...parsed.suspendedStopCodes,
      },
    );

    return DeviationReport(
      notice: notice,
      shape: shape,
      parsed: parsed,
      rejoin: rejoin,
      deviatedGeometry: route.geometry,
      impact: impact,
      confidence: route.isUsable && unresolved.isEmpty
          ? Confidence.confermata
          : Confidence.probabile,
      whyIncomplete: route.isUsable && unresolved.isEmpty
          ? null
          // Frasi per chi legge, non l'elenco delle prove fallite: «lungo
          // 4,1 km per sostituire 1,2 km (3,4x, max 3x)» e' utile a chi
          // tara le soglie (lo stampano gli strumenti in tool/), non a chi
          // aspetta il bus.
          : [
              if (unresolved.isNotEmpty)
                'Vie non trovate sulla mappa: ${unresolved.join(", ")}.',
              if (!rejoin.isUsable) 'Il punto di rientro è incerto.',
              if (route.failures.isNotEmpty)
                'Il percorso calcolato non corrisponde del tutto all\'avviso.',
            ].join(' '),
      // Una via non trovata perche' Photon non rispondeva potrebbe
      // completare il percorso al prossimo giro.
      retryable: geocodingInErrore,
    );
  }
}
