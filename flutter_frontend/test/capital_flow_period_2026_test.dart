import 'package:ekt_ia_flutter_frontend/capital_flow_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filtro diário permanece no ano-base 2026', () {
    final range = capitalFlowRange2026(
      CapitalPeriod.day,
      DateTime(2024, 8, 21),
    );

    expect(range.start, DateTime(2026, 8, 21));
    expect(range.end, DateTime(2026, 8, 21));
  });

  test('filtro mensal abrange o mês completo de 2026', () {
    final range = capitalFlowRange2026(
      CapitalPeriod.month,
      DateTime(2030, 2, 15),
    );

    expect(range.start, DateTime(2026, 2));
    expect(range.end, DateTime(2026, 2, 28));
  });

  test('filtro bimestral agrupa os meses corretos de 2026', () {
    final range = capitalFlowRange2026(
      CapitalPeriod.bimester,
      DateTime(2026, 8, 21),
    );

    expect(range.start, DateTime(2026, 7));
    expect(range.end, DateTime(2026, 8, 31));
  });
}
