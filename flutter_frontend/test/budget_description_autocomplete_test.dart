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
}
