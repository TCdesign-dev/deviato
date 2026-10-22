import '../models/saved_stop.dart';
import '../models/tragitto.dart';
import 'stop_answer.dart';

/// Com'e' messo un tragitto adesso, tratta per tratta.
///
/// Si guardano tutte e due le fermate di ogni tratta: quella dove sali e
/// quella dove scendi. Una discesa non servita e' un intoppo quanto una
/// salita: si scende prima o dopo, e al cambio si cammina.
class RispostaTragitto {
  const RispostaTragitto({required this.tragitto, required this.tratte});

  final Tragitto tragitto;
  final List<({Tratta tratta, StopAnswer salita, StopAnswer discesa})> tratte;

  static RispostaTragitto of(
    Tragitto t,
    StopAnswer? Function(SavedStop) risposta,
  ) => RispostaTragitto(
    tragitto: t,
    tratte: [
      for (final tr in t.tratte)
        (
          tratta: tr,
          salita:
              risposta(tr.salita) ??
              StopAnswer(state: StopState.unknown, saved: tr.salita),
          discesa:
              risposta(tr.discesa) ??
              StopAnswer(state: StopState.unknown, saved: tr.discesa),
        ),
    ],
  );

  /// Le fermate nell'ordine del viaggio: sali, scendi, sali, scendi…
  Iterable<({int indice, bool salita, StopAnswer risposta})> get _passi sync* {
    for (final (i, t) in tratte.indexed) {
      yield (indice: i, salita: true, risposta: t.salita);
      yield (indice: i, salita: false, risposta: t.discesa);
    }
  }

  /// Il primo passo da dire, nell'ordine del viaggio: prima una fermata
  /// non servita, poi un avviso non letto, poi una chiusura in arrivo.
  /// null se e' tutto servito.
  ({int indice, bool salita, StopAnswer risposta})? get primoIntoppo {
    for (final stato in const [
      StopState.closed,
      StopState.uncertain,
      StopState.closesLater,
      StopState.notOnRoute,
      StopState.unknown,
    ]) {
      for (final p in _passi) {
        if (p.risposta.state == stato) return p;
      }
    }
    return null;
  }

  /// Tutte le fermate servite adesso.
  bool get tuttoServito => primoIntoppo == null;
}
