import 'package:flutter_test/flutter_test.dart';
import 'package:ekt_ia_flutter_frontend/investment_portfolio_model.dart';

void main() {
  Map<String, dynamic> event(String id, String type, String date, int amount,
          {double quantity = 0, double price = 0, int fees = 0}) =>
      {
        'id': id,
        'assetId': 'a',
        'type': type,
        'date': date,
        'amount': amount,
        'quantity': quantity,
        'price': price,
        'fees': fees
      };
  test('stock purchases, partial sale, dividends and cutoff reconcile cash',
      () {
    final events = [
      event('buy', 'deposit', '2026-01-01', 100000,
          quantity: 100, price: 10, fees: 100),
      event('sale', 'withdraw', '2026-02-01', 48000,
          quantity: 40, price: 12, fees: 200),
      event('dividend', 'income', '2026-03-01', 5000),
      event('quote', 'valuation', '2026-03-02', 0, price: 13)
    ];
    final a = {'id': 'a', 'kind': 'variable'};
    final early = PortfolioPosition.calculate(a, events, '2026-01-31');
    expect(early.quantity, 100);
    expect(early.balance, 100000);
    expect(early.result, -100);
    final end = PortfolioPosition.calculate(a, events, '2026-03-31');
    expect(end.quantity, 60);
    expect(end.balance, 78000);
    expect(end.withdrawals, 47800);
    expect(end.result, 30700);
    expect(end.priceDate, '2026-03-02');
  });
  test(
      'fixed income contributions do not count as return; marks and withdrawals reconcile',
      () {
    final events = [
      event('buy', 'deposit', '2026-01-01', 100000),
      event('mark', 'valuation', '2026-02-01', 110000),
      event('out', 'withdraw', '2026-02-02', 50000, fees: 1000),
      event('extra', 'deposit', '2026-03-01', 20000)
    ];
    final p = PortfolioPosition.calculate(
        {'id': 'a', 'kind': 'fixed'}, events, '2026-03-31');
    expect(p.balance, 80000);
    expect(p.deposits, 120000);
    expect(p.withdrawals, 49000);
    expect(p.result, 9000);
  });
  test('out-of-order entry dates are sorted; same day retains entry order', () {
    final events = [
      event('mark', 'valuation', '2026-02-01', 120000),
      event('buy', 'deposit', '2026-01-01', 100000),
      event('out', 'withdraw', '2026-02-01', 20000)
    ];
    final p = PortfolioPosition.calculate(
        {'id': 'a', 'kind': 'fixed'}, events, '2026-02-01');
    expect(p.balance, 100000);
    expect(p.result, 20000);
    expect(
        PortfolioPosition.calculate(
                {'id': 'other', 'kind': 'fixed'}, events, '2026-03-01')
            .balance,
        0);
  });
}
