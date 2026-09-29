import 'package:ekt_ia_flutter_frontend/day_trade_bi_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily net enters financial metrics without inventing trades', () {
    final analytics = BiAnalytics([
      const BiTrade(
          date: '2026-09-25',
          asset: 'WIN',
          strategy: 'Teste',
          weekday: 'sexta-feira',
          status: 'ENCERRADA',
          net: 75),
    ], dailyResults: const [
      BiDailyNet(date: '2026-09-28', net: 250.50),
      BiDailyNet(date: '2026-09-29', net: -350),
      BiDailyNet(date: '2026-09-30', net: 0),
    ]);
    expect(analytics.net, -24.50);
    expect(analytics.total, 1);
    expect(analytics.average, 75);
    expect(analytics.winRate, 100);
    expect(analytics.byAsset, {'WIN': 75});
    expect(analytics.equityCurve, [75, 325.50, -24.50, -24.50]);
    expect(analytics.maxDrawdown, 350);
    expect(analytics.daily.length, 4);
    expect(analytics.daily[1].result, 250.50);
    expect(analytics.daily[1].count, 0);
    expect(analytics.daily[1].applicableWinRate, isNull);
    expect(analytics.byWeekday['Segunda-feira'], 250.50);
  });

  test('only daily results has no operation success rate', () {
    final analytics = BiAnalytics([], dailyResults: const [
      BiDailyNet(date: '2026-09-28', net: 0),
    ]);
    expect(analytics.net, 0);
    expect(analytics.closed, isEmpty);
    expect(analytics.applicableWinRate, isNull);
    expect(analytics.profitFactorText, 'Não aplicável');
    expect(analytics.daily.single.dailyNet, 0);
  });
}
