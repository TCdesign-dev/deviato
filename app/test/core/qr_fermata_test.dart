import 'package:flutter_test/flutter_test.dart';
import 'package:gtt_deviazioni/core/pipeline/qr_fermata.dart';

/// Il QR sulle paline GTT, com'e' nel tutorial di GTT (22/10/2026).
void main() {
  test('il QR di una palina da\' il suo numero', () {
    expect(
      QrFermata.palina('http://www.gtt.to.it/cms/percorari/arrivi?palina=597'),
      '597',
    );
    expect(
      QrFermata.palina(
        'https://gtt.to.it/cms/percorari/arrivi?palina=40&bacino=U',
      ),
      '40',
    );
    expect(QrFermata.palina('  587 '), '587');
  });

  test('gli altri QR non sono fermate', () {
    expect(QrFermata.palina('http://www.gtt.to.it'), isNull);
    expect(QrFermata.palina('https://esempio.it/arrivi?palina=597'), isNull);
    expect(QrFermata.palina('https://www.gtt.to.it/x?palina=abc'), isNull);
    expect(QrFermata.palina('WIFI:S:rete;T:WPA;P:segreta;;'), isNull);
    expect(QrFermata.palina(''), isNull);
  });
}
