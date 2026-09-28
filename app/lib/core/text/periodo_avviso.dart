/// Quando vale un avviso, letto dal suo testo.
///
/// Il feed di GTT data gli avvisi con l'ora di PUBBLICAZIONE: MISURATO il
/// 01/08/2026, 161 avvisi su 161 risultavano gia' iniziati. Le date vere
/// le scrive il testo, in italiano e in molti modi — tutti visti negli
/// avvisi del 28/09/2026:
///
/// - «Da lunedì 14 settembre 2026 e sino a nuove comunicazioni»
/// - «Dalle ore 8.00 di mercoledi' 23 alle ore 5.00 di lunedi' 28 settembre
///   2026» (il primo giorno senza mese)
/// - «Mercoledi' 16 settembre dalle ore 10 e sino a nuove comunicazioni»
/// - «dalle 7.00 del 28 settembre alle 19.00 del 1 ottobre»
/// - «lunedì 21 e lunedì 28 settembre 2026, dalle ore 08:00 alle 16:00»
/// - «Tutte le domeniche a partire dal 12 luglio 2026»
/// - «Da sabato 23 Maggio e sino a sabato 7 novembre 2026 per tutte le
///   giornate del sabato dalle ore 6:00 alle ore 15:00 circa»
/// - «le corse serali dopo ore 20.00»
///
/// Quello che non si capisce resta null: meglio «date non trovate» di una
/// data inventata.
class PeriodoAvviso {
  const PeriodoAvviso({
    this.inizio,
    this.fine,
    this.giorni = const [],
    this.giornoSettimana,
    this.daMinuto,
    this.aMinuto,
  });

  static const nessuno = PeriodoAvviso();

  /// Da quando. Col giorno solo, dalle 00:00.
  final DateTime? inizio;

  /// Fino a quando, compreso. null per «sino a nuove comunicazioni».
  final DateTime? fine;

  /// Giorni singoli («lunedì 21 e lunedì 28 settembre»), se il testo
  /// elenca quelli invece di un intervallo.
  final List<DateTime> giorni;

  /// Solo un giorno della settimana: 1 lunedi' ... 7 domenica.
  final int? giornoSettimana;

  /// Solo in una fascia oraria, in minuti dalla mezzanotte. [aMinuto] puo'
  /// essere minore di [daMinuto] (dopo mezzanotte).
  final int? daMinuto;
  final int? aMinuto;

  bool get trovato => inizio != null || giorni.isNotEmpty;

  /// Se l'avviso vale adesso, se deve ancora cominciare, se e' finito, o
  /// se vale oggi ma in un altro giorno od orario.
  StatoPeriodo stato(DateTime ora) {
    if (!trovato) return StatoPeriodo.sconosciuto;
    final oggi = DateTime(ora.year, ora.month, ora.day);
    if (giorni.isNotEmpty) {
      final dopo = giorni.where((g) => !g.isBefore(oggi)).toList();
      if (dopo.isEmpty) return StatoPeriodo.finito;
      if (!giorni.any((g) => g == oggi)) return StatoPeriodo.inProgramma;
      return _inFascia(ora) ? StatoPeriodo.inCorso : StatoPeriodo.fuoriOrario;
    }
    if (ora.isBefore(inizio!)) return StatoPeriodo.inProgramma;
    final f = fine;
    if (f != null && ora.isAfter(f)) return StatoPeriodo.finito;
    if (giornoSettimana != null && ora.weekday != giornoSettimana) {
      return StatoPeriodo.fuoriOrario;
    }
    return _inFascia(ora) ? StatoPeriodo.inCorso : StatoPeriodo.fuoriOrario;
  }

  bool _inFascia(DateTime ora) {
    final da = daMinuto, a = aMinuto;
    if (da == null || a == null) return true;
    final m = ora.hour * 60 + ora.minute;
    return da <= a ? m >= da && m < a : m >= da || m < a;
  }

  /// Il periodo detto a parole, per il banco di prova.
  String get descrizione {
    if (!trovato) return 'date non trovate nel testo';
    String g(DateTime d) => '${d.day}/${d.month}';
    String h(int m) => '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
    final parti = <String>[
      if (giorni.isNotEmpty)
        'solo ${giorni.map(g).join(', ')}'
      else ...[
        'dal ${g(inizio!)}',
        fine == null ? 'fino a nuove comunicazioni' : 'al ${g(fine!)}',
      ],
      if (giornoSettimana != null) 'solo di ${_nomiGiorni[giornoSettimana! - 1]}',
      if (daMinuto != null && aMinuto != null)
        'dalle ${h(daMinuto!)} alle ${h(aMinuto!)}',
    ];
    return parti.join(', ');
  }

  static const _nomiGiorni = [
    'lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato',
    'domenica',
  ];

  /// Legge il periodo da [testo]. [pubblicato] (la data del feed) serve a
  /// mettere l'anno quando il testo non lo scrive.
  static PeriodoAvviso leggi(String testo, {DateTime? pubblicato}) {
    final t = _normalizza(testo);
    final date = _date(t, pubblicato);
    final fascia = _fascia(t, date);
    final settimana = _ricorrenza(t);
    if (date.isEmpty) return PeriodoAvviso.nessuno;

    // Giorni elencati: «lunedì 21 e lunedì 28 settembre», «nelle giornate
    // di sabato 26 e domenica 27». Due o piu' date unite solo da «e».
    final elenco = date.length >= 2 && _unitiDaE(t, date);
    if (elenco) {
      return PeriodoAvviso(
        giorni: [for (final d in date) d.giorno],
        daMinuto: fascia?.$1,
        aMinuto: fascia?.$2,
      );
    }

    // La prima data e' l'inizio, la seconda la fine: a meno che fra le due
    // ci sia «sino a nuove comunicazioni» («Da martedì 26 maggio 2026 e
    // sino a nuove comunicazioni. Le fermate del 30 maggio…»).
    final primo = date.first;
    final fineData = date.length >= 2 ? date[1] : null;
    final inizio = primo.giorno.add(Duration(minutes: primo.minuto ?? 0));
    DateTime? fine;
    if (fineData != null && !_nuoveComunicazioni(t, prima: fineData.posizione)) {
      fine = fineData.minuto != null
          ? fineData.giorno.add(Duration(minutes: fineData.minuto!))
          : fineData.giorno.add(const Duration(hours: 23, minutes: 59));
    } else if (_soloQuelGiorno(t)) {
      // «Dalle ore 18,00 a termine del servizio di martedì 15 settembre»:
      // un giorno solo, fino a fine servizio (le 2 di notte, per stare
      // larghi).
      fine = primo.giorno.add(const Duration(hours: 26));
    }
    return PeriodoAvviso(
      inizio: inizio,
      fine: fine,
      giornoSettimana: settimana,
      // La fascia vale solo se non e' gia' l'ora d'inizio o di fine.
      daMinuto: fascia?.$1,
      aMinuto: fascia?.$2,
    );
  }

  // ------------------------------------------------------------ dettagli

  static const _mesi = {
    'gennaio': 1, 'febbraio': 2, 'marzo': 3, 'aprile': 4, 'maggio': 5,
    'giugno': 6, 'luglio': 7, 'agosto': 8, 'settembre': 9, 'ottobre': 10,
    'novembre': 11, 'dicembre': 12,
  };

  static const _settimana = {
    'lunedi': 1, 'lunedì': 1, 'martedi': 2, 'martedì': 2, 'mercoledi': 3,
    'mercoledì': 3, 'giovedi': 4, 'giovedì': 4, 'venerdi': 5, 'venerdì': 5,
    'sabato': 6, 'sabati': 6, 'domenica': 7, 'domeniche': 7,
  };

  static String _normalizza(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[’‘`]'), "'")
      // «lunedi'» e «lunedì» sono la stessa parola
      .replaceAllMapped(RegExp(r"([a-z])i'"), (m) => '${m[1]}ì')
      .replaceAll(RegExp(r'\s+'), ' ');

  /// Le date del testo, in ordine, con l'ora che le accompagna e cosa le
  /// introduce. Il mese e l'anno mancanti si prendono dalla data dopo, o
  /// dalla pubblicazione.
  static List<_Data> _date(String t, DateTime? pubblicato) {
    final nomiMesi = _mesi.keys.join('|');
    final re = RegExp(
      '(?:(lunedì|martedì|mercoledì|giovedì|venerdì|sabato|domenica)\\s+)?'
      '\\b(\\d{1,2})(?!\\s*[:.,]\\d)(?:\\s+($nomiMesi))?(?:\\s+(\\d{4}))?\\b',
    );
    final grezze = <({int pos, int fine, int giorno, int? mese, int? anno, bool conSettimana})>[];
    for (final m in re.allMatches(t)) {
      // Il periodo GTT lo scrive in testa; piu' avanti le date parlano
      // d'altro (una fermata sospesa un giorno, una corsa).
      if (m.start > _testa) break;
      // «via 25 Aprile», «corso XX Settembre»: nomi di vie, non date.
      final avanti = t.substring((m.start - 14).clamp(0, m.start), m.start);
      if (RegExp(r"\b(via|viale|corso|c\.so|piazza|p\.zza|piazzale|largo|strada|str\.|rondò|lungo|borgata|regione)\s+$")
          .hasMatch(avanti)) {
        continue;
      }
      final conSettimana = m[1] != null;
      final mese = m[3] == null ? null : _mesi[m[3]];
      // Un numero da solo e' una data solo se ha il mese o il giorno della
      // settimana: «fermata 422», «SP 186», «ore 8» no.
      if (mese == null && !conSettimana) continue;
      final g = int.parse(m[2]!);
      if (g < 1 || g > 31) continue;
      final anno = m[4] == null ? null : int.parse(m[4]!);
      grezze.add((
        pos: m.start,
        fine: m.end,
        giorno: g,
        mese: mese,
        anno: anno,
        conSettimana: conSettimana,
      ));
    }
    if (grezze.isEmpty) return const [];
    final out = <_Data>[];
    for (var i = 0; i < grezze.length; i++) {
      final d = grezze[i];
      var mese = d.mese;
      var anno = d.anno;
      for (var j = i + 1; j < grezze.length && (mese == null || anno == null); j++) {
        mese ??= grezze[j].mese;
        if (grezze[j].mese != null && anno == null) anno = grezze[j].anno;
      }
      if (mese == null) continue;
      anno ??= _annoProbabile(d.giorno, mese, pubblicato);
      final prima = t.substring((d.pos - 60).clamp(0, d.pos), d.pos);
      out.add(_Data(
        giorno: DateTime(anno, mese, d.giorno),
        posizione: d.pos,
        minuto: _oraPrima(prima),
      ));
    }
    return out;
  }

  /// L'anno di una data senza anno: quello che la mette piu' vicino alla
  /// pubblicazione, senza andare indietro di piu' di un mese.
  static int _annoProbabile(int giorno, int mese, DateTime? pubblicato) {
    final p = pubblicato ?? DateTime.now();
    for (final a in [p.year, p.year + 1]) {
      if (!DateTime(a, mese, giorno)
          .isBefore(p.subtract(const Duration(days: 31)))) {
        return a;
      }
    }
    return p.year + 1;
  }

  static const _testa = 220;

  /// L'ora scritta appena prima di una data: «dalle ore 8.00 di», «alle
  /// 19.00 del», «sino alle 05:00 di», «dalle ore 18,00 a termine del
  /// servizio di».
  static int? _oraPrima(String prima) {
    final m = RegExp(
      r"(?:ore|alle|dalle)\s*(\d{1,2})(?:[.:,](\d{2}))?(?:\s+(?!\d)\S+){0,4}\s+(?:di|del|dell')\s*(?:\S+\s*)?$",
    ).firstMatch(prima);
    if (m == null) return null;
    final h = int.parse(m[1]!), min = int.parse(m[2] ?? '0');
    if (h > 24 || min > 59) return null;
    return h * 60 + min;
  }

  /// Una fascia oraria che non e' l'ora di una data: «dalle ore 8.00 alle
  /// ore 18.00», «dalle 6:00 alle 15:00 circa», «dopo ore 20.00».
  static (int, int)? _fascia(String t, List<_Data> date) {
    final m = RegExp(
      r"dalle\s*(?:ore\s*)?(\d{1,2})(?:[.:,](\d{2}))?\s*(?:alle|a)\s*(?:ore\s*)?(\d{1,2})(?:[.:,](\d{2}))?(?!\s*(?:di|del|dell')\b)",
    ).firstMatch(t);
    if (m != null) {
      final da = int.parse(m[1]!) * 60 + int.parse(m[2] ?? '0');
      final a = int.parse(m[3]!) * 60 + int.parse(m[4] ?? '0');
      if (da < 24 * 60 && a <= 24 * 60) return (da, a);
    }
    final dopo = RegExp(r"(?:serali )?dopo (?:le )?(?:ore )?(\d{1,2})(?:[.:,](\d{2}))?")
        .firstMatch(t);
    if (dopo != null && t.contains('corse')) {
      return (int.parse(dopo[1]!) * 60 + int.parse(dopo[2] ?? '0'), 26 * 60 - 24 * 60);
    }
    return null;
  }

  /// «Tutte le domeniche», «per tutte le giornate del sabato», «tutti i
  /// sabati».
  static int? _ricorrenza(String t) {
    final m = RegExp(r"tutt[ei] (?:le )?(?:giornate (?:del |di )?|i )?(sabat[oi]|domenic[ah]e?|lunedì|martedì|mercoledì|giovedì|venerdì)")
        .firstMatch(t);
    if (m == null) return null;
    final p = m[1]!;
    if (p.startsWith('sabat')) return 6;
    if (p.startsWith('domenic')) return 7;
    return _settimana[p];
  }

  static bool _nuoveComunicazioni(String t, {int? prima}) {
    final m = RegExp(r"(nuove? (a )?comunicazion[ei]|cessate esigenze)").firstMatch(t);
    if (m == null) return false;
    return prima == null || m.start < prima;
  }

  /// «a termine del servizio di <data>» con una data sola: quella sera,
  /// fino a fine servizio. (Con due date e' un intervallo, e non si arriva
  /// qui.)
  static bool _soloQuelGiorno(String t) =>
      RegExp(r"(a termine del servizio|a fine servizio) di").hasMatch(t);

  /// Fra una data e l'altra solo la data stessa e una «e»: «sabato 26 e
  /// domenica 27». «Da giovedì 24 e sino alle…» no.
  static bool _unitiDaE(String t, List<_Data> date) {
    for (var i = 0; i < date.length - 1; i++) {
      final fra = t.substring(date[i].posizione, date[i + 1].posizione);
      if (!RegExp(r"^\S+(\s+\S+){0,3}\s+e\s+$").hasMatch(fra)) return false;
    }
    return true;
  }
}

enum StatoPeriodo {
  inCorso,
  inProgramma,
  finito,

  /// Nel periodo, ma non in questo giorno od orario.
  fuoriOrario,

  /// Il testo non dice quando.
  sconosciuto,
}

class _Data {
  const _Data({
    required this.giorno,
    required this.posizione,
    required this.minuto,
  });

  final DateTime giorno;
  final int posizione;
  final int? minuto;
}
