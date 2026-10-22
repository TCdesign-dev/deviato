import 'saved_stop.dart';

/// Un pezzo di tragitto su una linea: in che direzione, dove sali e dove
/// scendi.
class Tratta {
  const Tratta({
    required this.routeId,
    required this.directionId,
    required this.salitaId,
    required this.discesaId,
    this.salitaCodice,
    this.discesaCodice,
  });

  final String routeId;
  final int directionId;

  /// Il palo dove sali e quello dove scendi: id del GTFS, e numero sulla
  /// fermata, come per le fermate salvate.
  final String salitaId;
  final String? salitaCodice;
  final String discesaId;
  final String? discesaCodice;

  SavedStop get salita => SavedStop(
    routeId: routeId,
    directionId: directionId,
    stopId: salitaId,
    stopCode: salitaCodice,
  );

  SavedStop get discesa => SavedStop(
    routeId: routeId,
    directionId: directionId,
    stopId: discesaId,
    stopCode: discesaCodice,
  );

  Map<String, Object?> toJson() => {
    'route': routeId,
    'dir': directionId,
    'sali': salitaId,
    if (salitaCodice != null) 'saliCodice': salitaCodice,
    'scendi': discesaId,
    if (discesaCodice != null) 'scendiCodice': discesaCodice,
  };

  static Tratta? fromJson(Object? j) {
    if (j is! Map) return null;
    final route = j['route'], dir = j['dir'];
    final sali = j['sali'], scendi = j['scendi'];
    if (route is! String || dir is! int || sali is! String) return null;
    if (scendi is! String) return null;
    return Tratta(
      routeId: route,
      directionId: dir,
      salitaId: sali,
      salitaCodice: j['saliCodice'] as String?,
      discesaId: scendi,
      discesaCodice: j['scendiCodice'] as String?,
    );
  }
}

/// Un tragitto che fai spesso, anche con dei cambi: «casa–lavoro, la 15
/// fino a Porta Nuova e poi la 68».
///
/// Una fermata salvata risponde per una fermata; chi cambia linea ne ha
/// due o tre da tenere d'occhio, e anche dove scende conta. Idea presa da
/// un fork del 15/10/2026; il modello e' nostro.
class Tragitto {
  const Tragitto({required this.id, required this.nome, required this.tratte});

  /// Tre cambi: quattro tratte.
  static const maxTratte = 4;

  final String id;
  final String nome;
  final List<Tratta> tratte;

  /// Le linee del tragitto, nell'ordine del viaggio, senza doppioni.
  List<String> get linee => [
    for (final (i, t) in tratte.indexed)
      if (!tratte.take(i).any((p) => p.routeId == t.routeId)) t.routeId,
  ];

  Tragitto copyWith({String? nome, List<Tratta>? tratte}) => Tragitto(
    id: id,
    nome: nome ?? this.nome,
    tratte: tratte ?? this.tratte,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'nome': nome,
    'tratte': [for (final t in tratte) t.toJson()],
  };

  static Tragitto? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], nome = j['nome'], tratte = j['tratte'];
    if (id is! String || nome is! String || tratte is! List) return null;
    final lette = [for (final t in tratte) ?Tratta.fromJson(t)];
    if (lette.isEmpty) return null;
    return Tragitto(id: id, nome: nome, tratte: lette);
  }
}
