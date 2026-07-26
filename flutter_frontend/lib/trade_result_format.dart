double? calculateOperationPoints({
  required String direction,
  required String entryText,
  required String exitText,
}) {
  final entry = _parseTradeNumber(entryText);
  final exit = _parseTradeNumber(exitText);
  if (entry == null || exit == null) return null;
  return direction == 'Compra' ? exit - entry : entry - exit;
}

String formatOperationPoints(double? value) {
  if (value == null || !value.isFinite) return '';
  final sign = value > 0 ? '+' : '';
  final absoluteText = value.abs() == value.abs().roundToDouble()
      ? value.abs().toStringAsFixed(0)
      : value
          .abs()
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
  final parts = absoluteText.split('.');
  final integer = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final decimal = parts.length == 2 ? ',${parts[1]}' : '';
  return '$sign${value < 0 ? '-' : ''}$integer$decimal '
      '${value.abs() == 1 ? 'ponto' : 'pontos'}';
}

double? _parseTradeNumber(String value) {
  var text = value.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (text.isEmpty) return null;
  if (text.contains(',')) {
    text = text.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^[+-]?\d{1,3}(\.\d{3})+$').hasMatch(text)) {
    text = text.replaceAll('.', '');
  }
  final parsed = double.tryParse(text);
  return parsed != null && parsed.isFinite ? parsed : null;
}
