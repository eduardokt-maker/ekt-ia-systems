import 'package:ekt_ia_flutter_frontend/day_trade_navigation_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resultado líquido na edição da navegação', () {
    double calculate({
      String direction = 'Compra',
      String market = 'Outro',
      String result = 'Gain',
      String entry = '100,00',
      String stop = '95,00',
      String target = '110,00',
      String pointValue = '0,50',
      String costs = '2,00',
      String quantity = '2',
    }) =>
        calculateNavigationNetResult(
          direction: direction,
          market: market,
          quantityText: quantity,
          entryText: entry,
          stopText: stop,
          targetText: target,
          pointValueText: pointValue,
          costsText: costs,
          operationResult: result,
        );

    test('compra com gain usa alvo, quantidade, valor por ponto e custos', () {
      expect(calculate(), 8);
    });

    test('compra com stop loss usa preço de stop', () {
      expect(calculate(result: 'stop loss'), -7);
    });

    test('venda com gain inverte a diferença entre entrada e alvo', () {
      expect(calculate(direction: 'Venda', target: '90,00'), 8);
    });

    test('break even conserva somente os custos no resultado líquido', () {
      expect(calculate(result: 'BREAK_EVEN'), -2);
    });

    test('mini índice mantém valor por ponto de 0,20 definido no backend', () {
      expect(
        calculate(market: 'Mini índice', pointValue: '999', costs: '1,00'),
        3,
      );
    });

    test('mini dólar usa R\$ 10 por ponto e multiplica apenas o financeiro',
        () {
      expect(
        calculate(
          market: 'Mini dólar',
          entry: '5430',
          target: '5440',
          quantity: '3',
          pointValue: '999',
          costs: '0',
        ),
        300,
      );
    });

    test('preço de saída segue o resultado selecionado', () {
      expect(
        navigationDerivedExitPrice(
          entryText: '100',
          stopText: '95',
          targetText: '110',
          operationResult: 'Gain',
        ),
        '110',
      );
      expect(
        navigationDerivedExitPrice(
          entryText: '100',
          stopText: '95',
          targetText: '110',
          operationResult: 'BREAK_EVEN',
        ),
        '100',
      );
    });
  });
}
