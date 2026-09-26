/// Una fermata che l'utente usa: linea, direzione, palo.
///
/// Tutte e tre servono. Il palo da solo non basta — la stessa fermata la
/// servono piu' linee, e una puo' essere deviata e l'altra no — e la linea
/// da sola nemmeno: le deviazioni sono quasi sempre per direzione, e chi
/// aspetta alla 2291 va verso via Cafasso, non verso Frejus.
///
/// Si salva l'id del GTFS e anche il codice sul palo: gli id del GTFS di
/// GTT sono stabili da un giorno all'altro, ma se un giorno non lo fossero
/// il codice resta quello scritto sulla fermata.
class SavedStop {
  const SavedStop({
    required this.routeId,
    required this.directionId,
    required this.stopId,
    this.stopCode,
  });

  final String routeId;
  final int directionId;
  final String stopId;
  final String? stopCode;

  bool same(SavedStop o) =>
      o.routeId == routeId &&
      o.directionId == directionId &&
      o.stopId == stopId;

  Map<String, Object?> toJson() => {
    'route': routeId,
    'dir': directionId,
    'stop': stopId,
    if (stopCode != null) 'code': stopCode,
  };

  static SavedStop? fromJson(Object? j) {
    if (j is! Map) return null;
    final route = j['route'], dir = j['dir'], stop = j['stop'];
    if (route is! String || dir is! int || stop is! String) return null;
    return SavedStop(
      routeId: route,
      directionId: dir,
      stopId: stop,
      stopCode: j['code'] as String?,
    );
  }

  @override
  String toString() => '$routeId/$directionId/$stopId';
}
