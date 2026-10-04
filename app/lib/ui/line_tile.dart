import 'package:flutter/material.dart';

import '../core/deviation_service.dart';
import '../core/models/transit.dart';
import '../core/pipeline/closure_summary.dart';
import 'line_badge.dart';
import 'theme.dart';

/// Una riga di "Le mie linee": stato in una frase, e i comandi.
///
/// Sta in un file suo perche' e' l'unico pezzo di interfaccia con uno
/// stato transitorio importante — l'avanzamento del controllo — e quello
/// si verifica con un test, non guardandolo: dura pochi secondi.
class LineTile extends StatelessWidget {
  const LineTile({
    required this.line,
    required this.status,
    required this.checking,
    required this.watching,
    required this.watchedVehicles,
    required this.checkedAt,
    this.preparing = false,
    this.onTap,
    super.key,
  });

  final TransitLine line;
  final LineStatus? status;

  /// Si stanno scaricando i suoi dati, e non ce n'e' ancora uno stato da
  /// mostrare. Dura un secondo: il calcolo lo fa il job su GitHub.
  final bool checking;

  /// Appena aggiunta: se ne stanno scaricando percorsi e stato.
  final bool preparing;

  /// Si stanno guardando i mezzi di questa linea, adesso.
  ///
  /// L'osservazione continua anche uscendo dalla schermata della linea:
  /// se qui non si vedesse, uno non saprebbe che e' ancora accesa e la
  /// lascerebbe girare interrogando GTT per niente.
  final bool watching;
  final int watchedVehicles;

  /// Quando e' stato fatto il controllo che si sta mostrando.
  ///
  /// Se non e' di oggi va detto: gli esiti sopravvivono alla chiusura
  /// dell'app, e "2 fermate non servite" senza data sembra adesso.
  final DateTime? checkedAt;
  final VoidCallback? onTap;

  /// "ieri" o "il 30/7" quando l'esito non e' di oggi. null se lo e'.
  String? get _vecchio {
    final t = checkedAt;
    if (t == null) return null;
    final oggi = DateTime.now();
    final giorni = DateTime(
      oggi.year,
      oggi.month,
      oggi.day,
    ).difference(DateTime(t.year, t.month, t.day)).inDays;
    return switch (giorni) {
      0 => null,
      1 => 'ieri',
      _ => 'il ${t.day}/${t.month}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colori = StatusColors.of(context);
    final secondario = scheme.onSurfaceVariant;
    final skipped =
        status?.allSkippedStops.map((s) => s.stop.id).toSet().length ?? 0;
    // Gli avvisi che devono ancora cominciare non entrano nel riassunto
    // di adesso: si dicono a parte, sotto.
    // Per AVVISO, non per rapporto: un avviso che riguarda tutte e due le
    // direzioni viene analizzato due volte, e contarlo due volte diceva
    // "6 avvisi" dove GTT ne ha pubblicati 3.
    final attivi = status?.activeReports
            .map((r) => r.notice.id)
            .toSet()
            .length ??
        0;
    final futuri = status?.scheduledReports
            .map((r) => r.notice.id)
            .toSet()
            .length ??
        0;
    // In vigore ma non adesso («solo il sabato»): adesso le fermate sono
    // servite, e lo si dice senza nasconderlo.
    final altri = status?.otherTimeReports
            .map((r) => r.notice.id)
            .toSet()
            .length ??
        0;

    String avvisi(int n) => '$n ${n == 1 ? "avviso" : "avvisi"}';

    // Il titolo e' LA RISPOSTA, corta e sempre su una riga: e' quello che
    // uno cerca guardando l'elenco. Il colore non basta da solo — c'e'
    // chi non lo distingue — e ogni stato ha anche la sua icona.
    final (Color colour, IconData icon, String label) = switch (status) {
      // Mai vuota: una riga senza titolo sembra un errore di caricamento.
      null => (secondario, Icons.help_outline, 'Tocca per aggiornare'),
      _ when attivi == 0 && futuri > 0 => (
        colori.info,
        Icons.event_outlined,
        'Variazione in programma',
      ),
      _ when attivi == 0 && altri > 0 => (
        colori.info,
        Icons.schedule,
        'Variazione in altri orari',
      ),
      // Senza avvisi, o solo con avvisi finiti che GTT non ha tolto.
      _ when attivi == 0 => (
        colori.ok,
        Icons.check_circle_outline,
        'Percorso regolare',
      ),
      _ when skipped > 0 => (
        scheme.error,
        Icons.do_not_disturb_on_outlined,
        skipped == 1 ? '1 fermata non servita' : '$skipped fermate non servite',
      ),
      // Nessun avviso letto fino in fondo: non si sa quali fermate
      // tocchi. Visto sulla 7 il 26/09 — «Linea 7 sospesa domenica 27»,
      // non letto per la quota esaurita — e la riga diceva «fermate
      // servite», cioe' il contrario di quello che c'era scritto.
      final s when !s.activeReports.any((r) => r.impact != null) => (
        colori.warning,
        Icons.article_outlined,
        'Avviso in corso',
      ),
      _ => (
        colori.warning,
        Icons.alt_route,
        'Deviata, fermate servite',
      ),
    };

    // I dettagli: fino a quando, quanti avvisi, quanti in programma, di
    // quando e' l'esito. Piccoli, perche' si leggono solo se il titolo ti
    // ha gia' interessato.
    final fino = _fino(status);
    final dettagli = <String>[
      ?fino,
      if (attivi > 0) avvisi(attivi),
      if (futuri > 0) '${avvisi(futuri)} in programma',
      if (altri > 0) '${avvisi(altri)} in altri orari',
      if (_vecchio != null) 'aggiornata ${_vecchio!}',
    ].join(' · ');

    final Widget titolo;
    final Widget? sottotitolo;
    if (watching) {
      titolo = Row(
        children: [
          // L'occhio del pulsante «Guarda adesso»: e' la stessa cosa.
          Icon(Icons.visibility_outlined, size: 17, color: colori.info),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              watchedVehicles == 0
                  ? 'Ricerca dei mezzi…'
                  : '$watchedVehicles ${watchedVehicles == 1 ? "mezzo" : "mezzi"} '
                        'in tempo reale',
              style: TextStyle(color: colori.info, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      );
      sottotitolo = null;
    } else if (checking || preparing) {
      titolo = Text(
        'Aggiornamento…',
        style: TextStyle(color: secondario, fontWeight: FontWeight.w500),
      );
      sottotitolo = Padding(
        padding: const EdgeInsets.only(top: 6),
        child: LinearProgressIndicator(
          minHeight: 3,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    } else {
      titolo = Row(
        children: [
          Icon(icon, size: 17, color: colour),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: colour, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
      sottotitolo = dettagli.isEmpty
          ? null
          : Text(
              dettagli,
              style: TextStyle(color: secondario, fontSize: 12.5),
              // Qui si puo' andare a capo: e' piccolo, e una seconda riga
              // si legge senza fatica. Troncare con i puntini nascondeva
              // quando era stato fatto il controllo. Il TITOLO invece
              // resta su una riga, sempre.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            );
    }

    return ListTile(
      // Una riga nuova per ogni modalita', invece di trasformare quella
      // che c'e'. Finita l'osservazione il sottotitolo passava da assente a
      // presente, e ListTile ne chiedeva la linea di base prima di averlo
      // impaginato: «2 avvisi» finiva in alto a sinistra, sopra
      // l'etichetta (visto sul simulatore il 26/09, e c'e' un test).
      key: ValueKey(
        watching
            ? 'osservazione'
            : checking || preparing
            ? 'aggiornamento'
            : 'esito',
      ),
      onTap: onTap,
      leading: SizedBox(
        width: 60,
        child: Align(
          alignment: Alignment.centerLeft,
          child: LineBadge(line: line),
        ),
      ),
      // Il titolo e' lo STATO, non i capolinea. I due capolinea non ci
      // stanno su una riga — si troncavano a meta' — e chi ha aggiunto
      // la linea sa gia' dove va: quello che non sa e' se oggi devia.
      title: titolo,
      subtitle: sottotitolo,
      // Niente pulsanti a destra: tutta la riga si tocca, e aggiornare
      // una linea sola non ha piu' senso — scaricarle tutte costa un
      // secondo, e il calcolo lo fa il job su GitHub.
    );
  }

  /// «fino al 29/09», se tutti gli avvisi in corso finiscono lo stesso
  /// giorno. Con date diverse non si sceglie: lo dice il dettaglio.
  static String? _fino(LineStatus? s) {
    final attivi = s?.activeReports ?? const [];
    if (attivi.isEmpty) return null;
    final fine = ClosureSummary.commonEnd(attivi);
    if (fine == null) return null;
    return 'fino al ${fine.day.toString().padLeft(2, "0")}/'
        '${fine.month.toString().padLeft(2, "0")}';
  }
}
