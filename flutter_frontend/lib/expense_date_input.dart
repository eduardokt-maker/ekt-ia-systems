import 'package:flutter/services.dart';

class ExpenseDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 8) return oldValue;
    var caretDigits = newValue.text
        .substring(
            0, newValue.selection.extentOffset.clamp(0, newValue.text.length))
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;
    // Backspace on a separator also removes the preceding digit.
    if (oldValue.selection.isCollapsed &&
        newValue.selection.isCollapsed &&
        oldValue.text.length == newValue.text.length + 1 &&
        digits == oldValue.text.replaceAll(RegExp(r'[^0-9]'), '') &&
        newValue.selection.extentOffset < oldValue.selection.extentOffset &&
        caretDigits > 0) {
      digits =
          digits.substring(0, caretDigits - 1) + digits.substring(caretDigits);
      caretDigits--;
    }
    final buffer = StringBuffer();
    var caret = 0;
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) buffer.write('/');
      buffer.write(digits[i]);
      if (i < caretDigits) caret = buffer.length;
    }
    return TextEditingValue(
        text: buffer.toString(),
        selection: TextSelection.collapsed(offset: caret));
  }
}

bool isValidExpenseDate(String value) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(value.trim());
  if (match == null) return false;
  final day = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final year = int.parse(match[3]!);
  final date = DateTime(year, month, day);
  return year > 0 &&
      date.year == year &&
      date.month == month &&
      date.day == day;
}
