import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/pipeline/qr_fermata.dart';

/// Inquadra il QR code sulla palina e restituisce il numero della fermata.
///
/// Le immagini le analizza il telefono (il lettore di Apple su iPhone,
/// quello di Google Play su Android) e non vanno da nessuna parte: si
/// tiene solo il numero letto. Un QR che non e' di una fermata GTT si
/// dice, e si continua a inquadrare.
class ScannerFermata extends StatefulWidget {
  const ScannerFermata({super.key});

  @override
  State<ScannerFermata> createState() => _ScannerFermataState();
}

class _ScannerFermataState extends State<ScannerFermata> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  var _fatto = false;

  /// L'ultimo QR estraneo segnalato: lo stesso non si ripete a ogni
  /// fotogramma.
  String? _ultimoEstraneo;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _letto(BarcodeCapture cattura) {
    if (_fatto) return;
    for (final b in cattura.barcodes) {
      final testo = b.rawValue;
      if (testo == null) continue;
      final palina = QrFermata.palina(testo);
      if (palina != null) {
        _fatto = true;
        Navigator.pop(context, palina);
        return;
      }
      if (testo != _ultimoEstraneo) {
        _ultimoEstraneo = testo;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Questo QR non è di una fermata GTT. Inquadra quello '
                'sulla palina.',
              ),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('QR della fermata'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _letto,
            errorBuilder: (context, errore) => _Errore(errore: errore),
          ),
          // Il riquadro dove mettere il QR, e cosa fare, scritto. Senza
          // fotocamera no: coprirebbero la spiegazione.
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, stato, _) => stato.error != null
                ? const SizedBox.shrink()
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 240,
                            height: 240,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 3),
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 24,
                        right: 24,
                        bottom: 48,
                        child: IgnorePointer(
                          child: Text(
                            'Inquadra il QR code sulla palina della fermata.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              shadows: [Shadow(blurRadius: 8)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Senza fotocamera: perche', e cosa fare.
class _Errore extends StatelessWidget {
  const _Errore({required this.errore});

  final MobileScannerException errore;

  @override
  Widget build(BuildContext context) {
    final testo = switch (errore.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Per leggere il QR serve la fotocamera. Puoi permetterlo dalle '
            'impostazioni del telefono, oppure cercare la fermata per nome '
            'o numero.',
      MobileScannerErrorCode.unsupported =>
        'Questo telefono non ha una fotocamera da usare qui. Cerca la '
            'fermata per nome o numero.',
      _ =>
        'La fotocamera non si è avviata. Riprova, oppure cerca la fermata '
            'per nome o numero.',
    };
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            testo,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
