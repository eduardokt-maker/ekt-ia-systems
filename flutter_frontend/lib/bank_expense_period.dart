/// Older bank imports store DD/MM only. Keep their year stable using the
/// registration date; never move them into a new year when the clock changes.
DateTime? bankExpenseDate(Map<String, dynamic> item) {
  final value = '${item['transaction_date'] ?? ''}'.trim();
  final brazilian =
      RegExp(r'^(\d{1,2})/(\d{1,2})(?:/(\d{2}|\d{4}))?$').firstMatch(value);
  if (brazilian != null) {
    final day = int.parse(brazilian[1]!);
    final month = int.parse(brazilian[2]!);
    final yearText = brazilian[3];
    final year = yearText == null
        ? DateTime.tryParse('${item['created_at'] ?? ''}')?.year
        : int.parse(yearText) + (yearText.length == 2 ? 2000 : 0);
    if (year == null) return null;
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(value)) return null;
  return DateTime.tryParse(value);
}

String bankExpenseMonthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

bool bankExpenseMatchesMonth(Map<String, dynamic> item, String month) {
  if (month == 'all') return true;
  final date = bankExpenseDate(item);
  if (month == 'undated') return date == null;
  return date != null && bankExpenseMonthKey(date) == month;
}
