import 'package:ekt_ia_flutter_frontend/day_trade_bi_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BI calcula resultado, acerto, profit factor e drawdown', () {
    final analytics = BiAnalytics(<BiTrade>[
      const BiTrade(
        date: '2026-07-01',
        asset: 'WIN',
        strategy: 'Rompimento',
        weekday: 'quarta-feira',
        status: 'ENCERRADA',
        net: 200,
      ),
      const BiTrade(
        date: '2026-07-02',
        asset: 'WIN',
        strategy: 'Rompimento',
        weekday: 'quinta-feira',
        status: 'ENCERRADA',
        net: -50,
      ),
      const BiTrade(
        date: '2026-07-02',
        asset: 'WDO',
        strategy: 'Reversão',
        weekday: 'quinta-feira',
        status: 'ENCERRADA',
        net: -100,
      ),
    ]);

    expect(analytics.net, 50);
    expect(analytics.winRate, closeTo(33.33, .01));
    expect(analytics.profitFactorText, '1,33');
    expect(analytics.maxDrawdown, 150);
    expect(analytics.daily, hasLength(2));
    expect(analytics.byAsset['WIN'], 150);
  });
}
