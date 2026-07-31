import 'package:ekt_ia_flutter_frontend/budget_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('busca ignora maiúsculas, minúsculas e acentuação', () {
    final result = rankBudgetDescriptionSuggestions(
      <String>['ÁGUA', 'ENERGIA ELÉTRICA', 'ALUGUEL'],
      'agua',
    );

    expect(result, <String>['ÁGUA']);
  });

  test('prioriza correspondência no início e preserva ordem histórica', () {
    final result = rankBudgetDescriptionSuggestions(
      <String>[
        'CONTA ENERGIA',
        'ENERGIA ESCRITÓRIO',
        'ENERGIA APARTAMENTO',
      ],
      'ener',
    );

    expect(result, <String>[
      'ENERGIA ESCRITÓRIO',
      'ENERGIA APARTAMENTO',
      'CONTA ENERGIA',
    ]);
  });

  test('limita sugestões a dez resultados', () {
    final result = rankBudgetDescriptionSuggestions(
      List<String>.generate(15, (index) => 'DESPESA $index'),
      'despesa',
    );

    expect(result, hasLength(10));
  });

  test('exibe categoria fixa e descrição de Outros na receita', () {
    final aluguel = BudgetItem.fromJson(<String, dynamic>{
      'id': 1,
      'item_type': 'Receita',
      'tipo_receita': 'ALUGUEL',
    });
    final outros = BudgetItem.fromJson(<String, dynamic>{
      'id': 2,
      'item_type': 'Receita',
      'tipo_receita': 'OUTROS',
      'tipo_receita_outros': 'Dividendos',
    });

    expect(aluguel.revenueTypeLabel, 'Aluguel');
    expect(outros.revenueTypeLabel, 'Dividendos');
  });

  test('receita antiga permanece identificada sem categoria', () {
    final legado = BudgetItem.fromJson(<String, dynamic>{
      'id': 1,
      'item_type': 'Receita',
    });

    expect(legado.revenueType, isNull);
    expect(legado.revenueTypeLabel, 'Não informado');
  });
}
