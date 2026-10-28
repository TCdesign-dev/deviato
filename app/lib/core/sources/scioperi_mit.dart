import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../net/gtt_http.dart';

/// Uno sciopero che puo' toccare GTT, dal calendario del Ministero dei
/// Trasporti.
///
/// Il calendario e' pubblico (scioperi.mit.gov.it) ed e' l'unico posto in
/// cui gli scioperi stanno tutti, con le date e le modalita' dette dai
/// sindacati: GTT li annuncia a ridosso, e non sempre nel feed degli
/// avvisi. Idea presa da un fork del 15/10/2026; il codice e' nostro.
class Sciopero {
  const Sciopero({
    required this.inizio,
    required this.fine,
    required this.sindacati,
    required this.settore,
    required this.modalita,
    required this.rilevanza,
    this.categoria = '',
    this.note = '',
    this.regione = '',
    this.provincia = '',
  });

  /// Il primo e l'ultimo giorno, compresi.
  final DateTime inizio;
  final DateTime fine;

  final String sindacati;

  /// «Trasporto pubblico locale», «Generale», «Plurisettoriale»…
  final String settore;
  final String categoria;

  /// Durata e orari, come li scrivono i sindacati. Negli scioperi generali
  /// ci sono tutti i settori: per il trasporto locale vedi [modalitaTpl].
  final String modalita;

  /// «Nazionale», «Regionale», «Locale»…
  final String rilevanza;
  final String note;
  final String regione;
  final String provincia;

  /// La parte delle modalita' che riguarda il trasporto locale: «TPL:
  /// durata e modalita' stabilite a livello territoriale». Tutta la frase,
  /// se non distingue i settori.
  String get modalitaTpl {
    final m = RegExp(
      r'\*?TPL\s*:\s*([^;]+)',
      caseSensitive: false,
    ).firstMatch(modalita);
    return (m?[1] ?? modalita).trim();
  }

  /// I giorni in cui si ferma il trasporto locale. Di solito quelli dello
  /// sciopero; ma «CUB 20–21/11, ferrovie dalle 21 del 20, *TPL: intera
  /// prestazione del 21/11» ferma bus e tram il 21 soltanto.
  ({DateTime inizio, DateTime fine}) get giorniTpl {
    final m = RegExp(
      r'\bDEL\s+(\d{1,2})/(\d{1,2})',
      caseSensitive: false,
    ).firstMatch(modalitaTpl);
    if (m == null) return (inizio: inizio, fine: fine);
    var giorno = DateTime(inizio.year, int.parse(m[2]!), int.parse(m[1]!));
    // «del 2/1» in uno sciopero che comincia a dicembre e' l'anno dopo.
    if (giorno.isBefore(inizio)) {
      giorno = DateTime(inizio.year + 1, giorno.month, giorno.day);
    }
    if (giorno.isAfter(fine) && fine.difference(inizio).inDays > 0) {
      return (inizio: inizio, fine: fine);
    }
    return (inizio: giorno, fine: giorno);
  }

  /// Puo' fermare bus e tram di GTT?
  ///
  /// Si', se e' del trasporto locale (nazionale, in Piemonte, o citando
  /// GTT), o se e' uno sciopero generale o di piu' settori nazionale che
  /// non esclude il trasporto locale. Il 22/10/2026 due dei tre scioperi
  /// generali del 30/10 escludevano i trasporti nelle note.
  bool get riguardaGtt {
    final tutto = '$settore $categoria $modalita $note'.toUpperCase();
    final escluso =
        RegExp(r'ESCLUS[IAO]').hasMatch(note.toUpperCase()) &&
        RegExp(r'\bTPL\b|TRASPORT').hasMatch(note.toUpperCase());
    if (escluso) return false;
    final nazionale =
        rilevanza.toLowerCase().startsWith('nazionale') ||
        regione.toLowerCase() == 'italia';
    final piemonte =
        regione.toLowerCase().contains('piemonte') &&
        (provincia.isEmpty ||
            RegExp('tutte|torino', caseSensitive: false).hasMatch(provincia));
    if (RegExp(r'\bGTT\b').hasMatch(tutto)) return true;
    if (settore.toLowerCase().contains('trasporto pubblico locale')) {
      return nazionale || piemonte;
    }
    if (settore == 'Generale') return nazionale || piemonte;
    if (settore == 'Plurisettoriale') {
      return (nazionale || piemonte) && RegExp(r'\bTPL\b').hasMatch(tutto);
    }
    return false;
  }

  /// Il trasporto locale si ferma ancora [oggi] o dopo?
  bool nonFinitoIl(DateTime oggi) =>
      !giorniTpl.fine.isBefore(DateTime(oggi.year, oggi.month, oggi.day));

  Map<String, Object?> toJson() => {
    'inizio': _giorno(inizio),
    'fine': _giorno(fine),
    'sindacati': sindacati,
    'settore': settore,
    if (categoria.isNotEmpty) 'categoria': categoria,
    'modalita': modalita,
    'rilevanza': rilevanza,
    if (note.isNotEmpty) 'note': note,
    if (regione.isNotEmpty) 'regione': regione,
    if (provincia.isNotEmpty) 'provincia': provincia,
  };

  static Sciopero? fromJson(Object? j) {
    if (j is! Map) return null;
    final inizio = DateTime.tryParse('${j['inizio']}');
    final fine = DateTime.tryParse('${j['fine']}');
    if (inizio == null || fine == null) return null;
    String s(String k) => j[k] is String ? j[k] as String : '';
    return Sciopero(
      inizio: inizio,
      fine: fine,
      sindacati: s('sindacati'),
      settore: s('settore'),
      categoria: s('categoria'),
      modalita: s('modalita'),
      rilevanza: s('rilevanza'),
      note: s('note'),
      regione: s('regione'),
      provincia: s('provincia'),
    );
  }

  static String _giorno(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Il calendario degli scioperi del Ministero delle Infrastrutture e dei
/// Trasporti.
class ScioperiMit {
  ScioperiMit({GttHttp? http}) : _http = http ?? GttHttp();

  final GttHttp _http;

  static const url = 'https://scioperi.mit.gov.it/mit2/public/scioperi';

  /// Tutti gli scioperi in calendario.
  ///
  /// La pagina e' UTF-8 ma il Ministero dichiara `text/html` senza la
  /// codifica, e in quel caso il client la legge come latin-1: «Modalità»
  /// diventava «ModalitÃ », la colonna non si trovava, e dal 22 al 28/10
  /// le modalita' sono uscite vuote («Bus e tram: .») e il CUB del
  /// 20–21/11 fermava bus e tram due giorni invece di uno.
  Future<List<Sciopero>> scarica() async =>
      leggi(utf8.decode(await _http.getBytes(url), allowMalformed: true));

  /// Gli scioperi della tabella grande (`scioperiLarge`): la pagina ne ha
  /// anche una per il telefono, con le stesse righe.
  ///
  /// Colonne, il 22/10/2026: (vuota), Inizio, Fine, Sindacati, Settore,
  /// Categoria, Modalità, Rilevanza, Note, Data proclamazione, Regione,
  /// Provincia, Data ricezione. Si cercano per nome nell'intestazione: se
  /// il Ministero le sposta, non si leggono le colonne sbagliate.
  static List<Sciopero> leggi(String pagina) {
    final doc = html.parse(pagina);
    final tabella =
        doc.querySelector('table#scioperiLarge') ?? doc.querySelector('table');
    if (tabella == null) return const [];
    final intestazione = [
      for (final th in tabella.querySelectorAll('th'))
        th.text.replaceAll('*', '').trim().toLowerCase(),
    ];
    // Per l'inizio del nome: «modalit» trova «modalità» anche se un giorno
    // l'accento arrivasse scritto in un altro modo.
    int col(String nome) => intestazione.indexWhere((h) => h.startsWith(nome));
    final cInizio = col('inizio'), cFine = col('fine');
    if (cInizio < 0 || cFine < 0) return const [];

    final out = <Sciopero>[];
    for (final tr in tabella.querySelectorAll('tbody tr')) {
      final celle = [
        for (final td in tr.querySelectorAll('td'))
          td.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
      ];
      if (celle.length != intestazione.length) continue;
      String c(String nome) {
        final i = col(nome);
        return i < 0 ? '' : celle[i];
      }

      final inizio = _data(celle[cInizio]);
      final fine = _data(celle[cFine]) ?? inizio;
      if (inizio == null || fine == null) continue;
      out.add(
        Sciopero(
          inizio: inizio,
          fine: fine,
          sindacati: c('sindacati'),
          settore: c('settore'),
          categoria: c('categoria'),
          modalita: c('modalit'),
          rilevanza: c('rilevanza'),
          note: c('note'),
          regione: c('regione'),
          provincia: c('provincia'),
        ),
      );
    }
    return out;
  }

  static DateTime? _data(String s) {
    final m = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s);
    if (m == null) return null;
    return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  }
}
