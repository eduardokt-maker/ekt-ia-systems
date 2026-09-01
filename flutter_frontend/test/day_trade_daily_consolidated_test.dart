import 'package:ekt_ia_flutter_frontend/day_trade_navigation_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('consolida o resultado líquido por data e mantém os ativos', () {
    final results = consolidateDayTradeResults(const [
      DayTradeDailyEntry(date: '2026-08-20', asset: 'WINV26', netResult: -354),
      DayTradeDailyEntry(date: '2026-08-20', asset: 'WDOU26', netResult: 100),
      DayTradeDailyEntry(
          date: '2026-08-19', asset: 'WINV26', netResult: 842.40),
    ]);

    expect(results.map((result) => result.date), ['2026-08-20', '2026-08-19']);
    expect(results.first.total, -254);
    expect(results.first.entries.map((entry) => entry.asset),
        ['WINV26', 'WDOU26']);
    expect(results.last.total, 842.40);
  });
}
