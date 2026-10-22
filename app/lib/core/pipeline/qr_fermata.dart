/// Il numero di palina scritto nel QR code di una fermata GTT.
///
/// I QR sulle paline rimandano alla pagina dei passaggi di GTT, con il
/// numero della palina nell'indirizzo: decodificato dal tutorial di GTT il
/// 22/10/2026, «http://www.gtt.to.it/cms/percorari/arrivi?palina=597».
/// Si accetta anche un numero da solo, se un giorno ci fosse quello.
/// Qualunque altra cosa — un QR di un manifesto, di un biglietto — non e'
/// una fermata: null.
class QrFermata {
  const QrFermata._();

  static String? palina(String testo) {
    final t = testo.trim();
    if (RegExp(r'^\d{1,6}$').hasMatch(t)) return t;
    final uri = Uri.tryParse(t);
    if (uri == null || !uri.host.toLowerCase().endsWith('gtt.to.it')) {
      return null;
    }
    final p = uri.queryParameters['palina']?.trim();
    if (p == null || !RegExp(r'^\d{1,6}$').hasMatch(p)) return null;
    return p;
  }
}
