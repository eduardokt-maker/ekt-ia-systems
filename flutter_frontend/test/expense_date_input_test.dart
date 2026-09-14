import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ekt_ia_flutter_frontend/expense_date_input.dart';

void main() {
  final formatter = ExpenseDateInputFormatter();
  TextEditingValue value(String text) => TextEditingValue(
      text: text, selection: TextSelection.collapsed(offset: text.length));
  test('digitar e colar insere barras sem perder o ano', () {
    var current = TextEditingValue.empty;
    for (final digit in '14092026'.split('')) {
      current =
          formatter.formatEditUpdate(current, value(current.text + digit));
    }
    expect(current.text, '14/09/2026');
    expect(current.selection.extentOffset, 10);
    expect(
        formatter
            .formatEditUpdate(TextEditingValue.empty, value('14092026'))
            .text,
        '14/09/2026');
    expect(formatter.formatEditUpdate(current, value('14/09/20267')), current);
  });
  test('apagar sobre a barra não prende o cursor', () {
    final old = value('14/09/2')
        .copyWith(selection: const TextSelection.collapsed(offset: 3));
    final next = value('1409/2')
        .copyWith(selection: const TextSelection.collapsed(offset: 2));
    final edited = formatter.formatEditUpdate(old, next);
    expect(edited.text, '10/92');
    expect(edited.selection.extentOffset, 1);
  });
  test('valida calendário, ano bissexto e campos incompletos', () {
    expect(isValidExpenseDate('29/02/2024'), isTrue);
    for (final date in [
      '29/02/2025',
      '31/04/2026',
      '14/09',
      '00/09/2026',
      '14/13/2026'
    ]) {
      expect(isValidExpenseDate(date), isFalse, reason: date);
    }
  });
}
