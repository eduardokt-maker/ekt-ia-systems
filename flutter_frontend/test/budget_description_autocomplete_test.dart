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

  test('despesa preserva competência, vencimento e pagamento independentes',
      () {
    final despesa = BudgetItem.fromJson(<String, dynamic>{
      'id': 10,
      'reference_month': '2026-07',
      'item_type': 'Despesa',
      'due_date': '2026-08-10',
      'payment_date': '2026-09-02',
      'settled': true,
    });

    expect(despesa.referenceMonth, '2026-07');
    expect(despesa.dueDate, '2026-08-10');
    expect(despesa.paymentDate, '2026-09-02');
  });

  test('registro legado sem competência continua válido para listagem', () {
    final item = BudgetItem.fromJson(<String, dynamic>{
      'id': 99,
      'reference_month': null,
      'item_type': 'Despesa',
      'description': 'REGISTRO LEGADO',
      'observation': '',
      'amount_text': '75,00',
      'received_amount_text': '0,00',
      'due_date': '2026-06-10',
      'payment_date': null,
      'settled': false,
    });

    expect(item.referenceMonth, isEmpty);
    expect(item.description, 'REGISTRO LEGADO');
    expect(item.paymentDate, isEmpty);
  });
}
