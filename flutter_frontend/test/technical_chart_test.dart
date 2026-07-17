import 'package:ekt_ia_flutter_frontend/technical_chart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('média móvel respeita o período informado', () {
    final result = movingAverage([1, 2, 3, 4, 5], 3);
    expect(result, [null, null, 2, 3, 4]);
  });

  test('bandas de Bollinger usam 20 períodos por padrão', () {
    final values = List<double>.generate(25, (index) => index + 1.0);
    final bands = bollingerBands(values);
    expect(bands.middle[18], isNull);
    expect(bands.middle[19], 10.5);
    expect(bands.upper[19], greaterThan(10.5));
    expect(bands.lower[19], lessThan(10.5));
  });
}
