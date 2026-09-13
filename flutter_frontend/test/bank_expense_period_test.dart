import 'package:ekt_ia_flutter_frontend/bank_expense_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filtra mês e ano sem misturar exercícios e mantém o histórico', () {
    final old = <String, dynamic>{'transaction_date': '13/09/2025'};
    final current = <String, dynamic>{'transaction_date': '13/09/2026'};
    expect(bankExpenseMatchesMonth(old, '2026-09'), isFalse);
    expect(bankExpenseMatchesMonth(current, '2026-09'), isTrue);
    expect(bankExpenseMatchesMonth(old, 'all'), isTrue);
  });

  test('ano de datas legadas fica estável mesmo após a virada do ano', () {
    final item = <String, dynamic>{
      'transaction_date': '31/12',
      'created_at': '2025-12-31T20:00:00-03:00',
    };
    expect(bankExpenseDate(item), DateTime(2025, 12, 31));
    expect(bankExpenseMatchesMonth(item, '2026-12'), isFalse);
  });

  test('data inválida não vaza para o mês seguinte nem desaparece do histórico',
      () {
    final item = <String, dynamic>{'transaction_date': '31/02/2026'};
    expect(bankExpenseDate(item), isNull);
    expect(bankExpenseMatchesMonth(item, '2026-03'), isFalse);
    expect(bankExpenseMatchesMonth(item, 'undated'), isTrue);
    expect(bankExpenseMatchesMonth(item, 'all'), isTrue);
    expect(bankExpenseDate({'transaction_date': '2026-09-13'}),
        DateTime(2026, 9, 13));
  });
}
