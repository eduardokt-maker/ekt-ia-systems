import 'package:flutter_test/flutter_test.dart';
import 'package:ekt_ia_flutter_frontend/win_calendar_screen.dart';

void main() {
  test('gera os seis vencimentos oficiais de 2026', () {
    final contracts = winContractsForYear(2026);
    expect(contracts.map((item) => item.symbol),
        ['WING26', 'WINJ26', 'WINM26', 'WINQ26', 'WINV26', 'WINZ26']);
    expect(contracts.map((item) => item.expiry.day), [18, 15, 17, 12, 14, 16]);
    expect(contracts.last.nextSymbol, 'WING27');
  });

  test('remove vencidos e alerta somente nos dois dias anteriores', () {
    expect(remainingWinContracts(DateTime(2026, 8, 8)).first.symbol, 'WINQ26');
    expect(winExpiryAlert(DateTime(2026, 8, 9)), isNull);
    expect(winExpiryAlert(DateTime(2026, 8, 10))?.symbol, 'WINQ26');
    expect(
        winExpiryAlert(DateTime(2026, 8, 11))?.daysUntil(DateTime(2026, 8, 11)),
        1);
  });
}
