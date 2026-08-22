import 'package:ekt_ia_flutter_frontend/trading_plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('distribui o stop entre operações e contratos', () {
    final plan = buildTradingPlan(
      dailyStop: 1000,
      operations: 4,
      contracts: 2,
    );
    expect(plan.stopPerOperation, 250);
    expect(plan.stopPerContract, 125);
    expect(formatTradingCurrency(plan.stopPerContract), 'R\$ 125,00');
  });

  test('Monte Carlo é reprodutível e retorna probabilidades válidas', () {
    final plan = buildTradingPlan(
      dailyStop: 40,
      operations: 2,
      contracts: 1,
    );
    final first = runTradingMonteCarlo(plan: plan, trials: 1000, seed: 7);
    final second = runTradingMonteCarlo(plan: plan, trials: 1000, seed: 7);

    expect(first.survivalProbability, inInclusiveRange(0, 1));
    expect(first.profitableProbability, inInclusiveRange(0, 1));
    expect(first.survivalProbability, second.survivalProbability);
    expect(first.medianFinalBalance, second.medianFinalBalance);
  });

  testWidgets('coleta limites e apresenta o plano diário',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TradingPlanScreen(now: DateTime(2026, 8, 22))),
    );

    expect(find.text('Bom dia!'), findsOneWidget);
    expect(find.text('sábado, 22 de agosto de 2026'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('daily-stop-field')), '1000');
    await tester.enterText(find.byKey(const Key('operations-field')), '4');
    await tester.enterText(find.byKey(const Key('contracts-field')), '2');
    await tester.ensureVisible(find.byKey(const Key('generate-trading-plan')));
    await tester.tap(find.byKey(const Key('generate-trading-plan')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('trading-plan-result')), findsOneWidget);
    expect(find.text('R\$ 250,00'), findsOneWidget);
    expect(find.text('R\$ 125,00'), findsOneWidget);
    expect(find.text('Operação 4 • 2 contratos'), findsOneWidget);
    expect(find.byKey(const Key('monte-carlo-result')), findsOneWidget);
    expect(find.text('Análise Monte Carlo • 100 dias'), findsOneWidget);
    expect(find.byKey(const Key('survival-probability')), findsOneWidget);
  });
}
