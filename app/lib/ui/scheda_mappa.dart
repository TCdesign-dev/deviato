import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/deviation_service.dart';
import '../core/models/notice.dart';
import '../core/pipeline/closure_summary.dart';
import 'riassunto.dart';

/// La scheda che galleggia in basso sulla mappa a tutto schermo.
///
/// Prima era un pannello attaccato al bordo, largo tutto lo schermo, che
/// si trascinava: pesante, e le fermate non servite stavano dietro «Più
/// dettagli». Gli avvisi non c'erano. Ora e' una scheda staccata dai
/// bordi, alta quanto il suo contenuto — fino a quasi meta' schermo, poi
/// scorre dentro — con tre pagine: Riepilogo, Fermate, Avvisi. Si passa
/// dall'una all'altra toccando le etichette in cima o scorrendo di lato:
/// lo scorrimento non lo conoscono tutti, le etichette si' (Tommaso,
/// 30/09/2026). Le pagine senza contenuto non ci sono, e con una sola le
/// etichette spariscono.
///
/// Toccando una fermata sulla mappa la scheda mostra quella ([fermata]),
/// e chiudendola torna alle pagine.
class SchedaMappa extends StatefulWidget {
  const SchedaMappa({
    required this.status,
    required this.riepilogo,
    this.soloDirezione,
    this.onTratto,
    this.fermata,
    this.onAltezza,
    super.key,
  });

  final LineStatus status;

  /// Cosa sta sotto lo stato nella prima pagina: la legenda.
  final Widget riepilogo;

  /// Solo la direzione di questo percorso (shapeId).
  final String? soloDirezione;

  final ValueChanged<ClosedRun>? onTratto;

  /// La fermata toccata, al posto delle pagine.
  final Widget? fermata;

  /// Quanto e' alta la scheda, a ogni cambio: la mappa le fa posto.
  final ValueChanged<double>? onAltezza;

  @override
  State<SchedaMappa> createState() => _SchedaMappaState();
}

enum _Pagina { riepilogo, fermate, avvisi }

class _SchedaMappaState extends State<SchedaMappa> {
  var _pagina = _Pagina.riepilogo;

  /// Da che parte entra la pagina nuova: 1 da destra, -1 da sinistra.
  var _verso = 1;

  List<_Pagina> get _pagine => [
    _Pagina.riepilogo,
    if (RiassuntoLinea.conTratti(
      widget.status,
      soloDirezione: widget.soloDirezione,
    ))
      _Pagina.fermate,
    if (widget.status.reports.isNotEmpty) _Pagina.avvisi,
  ];

  void _vai(_Pagina p) {
    if (p == _pagina) return;
    final pagine = _pagine;
    setState(() {
      _verso = pagine.indexOf(p) > pagine.indexOf(_pagina) ? 1 : -1;
      _pagina = p;
    });
  }

  void _scorri(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 250) return;
    final pagine = _pagine;
    final i = pagine.indexOf(_pagina) + (v < 0 ? 1 : -1);
    if (i >= 0 && i < pagine.length) _vai(pagine[i]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pagine = _pagine;
    // Una pagina sparita (un avviso tolto, un'altra direzione scelta):
    // si torna al riepilogo.
    final pagina = pagine.contains(_pagina) ? _pagina : _Pagina.riepilogo;
    final massima = MediaQuery.sizeOf(context).height * 0.45;

    final Widget contenuto;
    if (widget.fermata != null) {
      contenuto = KeyedSubtree(
        key: const ValueKey('fermata'),
        child: widget.fermata!,
      );
    } else {
      contenuto = KeyedSubtree(
        key: ValueKey(pagina),
        child: switch (pagina) {
          _Pagina.riepilogo => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              RiassuntoLinea(
                status: widget.status,
                soloDirezione: widget.soloDirezione,
                parte: ParteRiassunto.titolo,
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              ),
              widget.riepilogo,
            ],
          ),
          _Pagina.fermate => RiassuntoLinea(
            status: widget.status,
            soloDirezione: widget.soloDirezione,
            onTratto: widget.onTratto,
            parte: ParteRiassunto.tratti,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          ),
          _Pagina.avvisi => _Avvisi(status: widget.status),
        },
      );
    }

    return _Misura(
      onMisura: (s) => widget.onAltezza?.call(s.height),
      child: Material(
        color: scheme.surface,
        elevation: 6,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.fermata == null && pagine.length > 1)
                _Etichette(
                  pagine: pagine,
                  scelta: pagina,
                  avvisi: _Avvisi.quanti(widget.status),
                  onScelta: _vai,
                ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: massima),
                child: GestureDetector(
                  onHorizontalDragEnd: widget.fermata == null ? _scorri : null,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    layoutBuilder: (attuale, precedenti) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...precedenti, ?attuale],
                    ),
                    transitionBuilder: (figlio, animazione) {
                      final entra = figlio.key == ValueKey(pagina);
                      final da = Offset(
                        entra ? 0.25 * _verso : -0.25 * _verso,
                        0,
                      );
                      return FadeTransition(
                        opacity: animazione,
                        child: SlideTransition(
                          position: Tween(
                            begin: da,
                            end: Offset.zero,
                          ).animate(animazione),
                          child: figlio,
                        ),
                      );
                    },
                    child: SingleChildScrollView(
                      key: contenuto.key,
                      padding: EdgeInsets.only(
                        bottom: widget.fermata == null ? 8 : 0,
                      ),
                      child: contenuto,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le etichette delle pagine, in cima alla scheda. Alte 44 punti da
/// toccare, anche se la pillola disegnata e' piu' bassa.
class _Etichette extends StatelessWidget {
  const _Etichette({
    required this.pagine,
    required this.scelta,
    required this.avvisi,
    required this.onScelta,
  });

  final List<_Pagina> pagine;
  final _Pagina scelta;
  final int avvisi;
  final ValueChanged<_Pagina> onScelta;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String nome(_Pagina p) => switch (p) {
      _Pagina.riepilogo => 'Riepilogo',
      _Pagina.fermate => 'Fermate',
      _Pagina.avvisi => avvisi > 1 ? 'Avvisi · $avvisi' : 'Avviso',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Row(
        children: [
          for (final p in pagine)
            Expanded(
              child: Semantics(
                selected: p == scelta,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => onScelta(p),
                  child: SizedBox(
                    height: 44,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 34,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: p == scelta
                              ? scheme.onSurface
                              : scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Text(
                          nome(p),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: p == scelta
                                ? scheme.surface
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Gli avvisi di GTT della linea, uno per riquadro: titolo, date, le
/// prime righe e il testo completo a richiesta. Lo stesso avviso vale
/// spesso per due direzioni: si mostra una volta.
class _Avvisi extends StatelessWidget {
  const _Avvisi({required this.status});

  final LineStatus status;

  static List<RawNotice> _di(LineStatus status) {
    final visti = <String>{};
    final attivi = <RawNotice>[], dopo = <RawNotice>[];
    for (final r in status.reports) {
      if (!visti.add(r.notice.id)) continue;
      (r.notice.startsAfter(status.checkedAt) ? dopo : attivi).add(r.notice);
    }
    return [...attivi, ...dopo];
  }

  static int quanti(LineStatus status) => _di(status).length;

  @override
  Widget build(BuildContext context) {
    final avvisi = _di(status);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < avvisi.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
          _Avviso(notice: avvisi[i], ora: status.checkedAt),
        ],
      ],
    );
  }
}

class _Avviso extends StatefulWidget {
  const _Avviso({required this.notice, required this.ora});

  final RawNotice notice;
  final DateTime ora;

  @override
  State<_Avviso> createState() => _AvvisoState();
}

class _AvvisoState extends State<_Avviso> {
  var _aperto = false;

  static String _data(DateTime d) =>
      '${d.day.toString().padLeft(2, "0")}/'
      '${d.month.toString().padLeft(2, "0")}';

  @override
  Widget build(BuildContext context) {
    final n = widget.notice;
    final testo = Theme.of(context).textTheme;
    final tenue = Theme.of(context).colorScheme.onSurfaceVariant;
    // I testi del feed hanno doppi spazi a caso: le parole restano quelle.
    final corpo = n.text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    final titolo = n.headline != null && n.headline!.trim().isNotEmpty
        ? n.headline!.trim()
        : null;
    final giorni = n.daysUntilStart(widget.ora);
    final fine = n.endToShow;
    final quando = [
      if (giorni != null && giorni > 0 && n.validFrom != null)
        'In vigore dal ${_data(n.validFrom!)} · '
            '${switch (giorni) {
              1 => 'domani',
              2 => 'dopodomani',
              _ => 'fra $giorni giorni',
            }}'
      else if (n.validFrom != null)
        'Dal ${_data(n.validFrom!)}',
      if (fine != null) 'fino al ${_data(fine)}',
    ].join(' · ');
    final lungo = corpo.length > 160;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titolo != null)
            Text(titolo, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (quando.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                quando,
                style: testo.bodySmall?.copyWith(color: tenue),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            corpo,
            maxLines: _aperto || !lungo ? null : 3,
            overflow: _aperto || !lungo ? null : TextOverflow.ellipsis,
          ),
          if (lungo)
            TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(64, 44),
                alignment: Alignment.centerLeft,
              ),
              onPressed: () => setState(() => _aperto = !_aperto),
              child: Text(_aperto ? 'Mostra meno' : 'Testo completo'),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Dice quanto e' grande il figlio, ogni volta che cambia.
class _Misura extends SingleChildRenderObjectWidget {
  const _Misura({required this.onMisura, required super.child});

  final ValueChanged<Size> onMisura;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMisura(onMisura);

  @override
  void updateRenderObject(BuildContext context, _RenderMisura render) =>
      render.onMisura = onMisura;
}

class _RenderMisura extends RenderProxyBox {
  _RenderMisura(this.onMisura);

  ValueChanged<Size> onMisura;
  Size? _vecchia;

  @override
  void performLayout() {
    super.performLayout();
    final s = size;
    if (s == _vecchia) return;
    _vecchia = s;
    WidgetsBinding.instance.addPostFrameCallback((_) => onMisura(s));
  }
}
