// Regras recorrentes do calendário de negociação B3, conferidas para 2026:
// https://www.b3.com.br/pt_br/noticias/calendario-de-negociacao-da-b3-confira-o-funcionamento-da-bolsa-em-2026.htm
// Exceções futuras devem ser atualizadas conforme os comunicados da bolsa.
DateTime _easter(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final value = h + l - 7 * m + 114;
  return DateTime(year, value ~/ 31, value % 31 + 1);
}

bool isB3TradingDay(DateTime date) {
  if (date.weekday >= DateTime.saturday) return false;
  const fixedClosures = {
    101,
    421,
    501,
    907,
    1012,
    1102,
    1120,
    1224,
    1225,
    1231,
  };
  if (fixedClosures.contains(date.month * 100 + date.day)) return false;
  final easter = _easter(date.year);
  for (final offset in [-48, -47, -2, 60]) {
    final holiday = easter.add(Duration(days: offset));
    if (date.month == holiday.month && date.day == holiday.day) return false;
  }
  return true;
}

DateTime b3TradingDayOnOrAfter(DateTime date) {
  var day = DateTime(date.year, date.month, date.day);
  while (!isB3TradingDay(day)) {
    day = day.add(const Duration(days: 1));
  }
  return day;
}

DateTime previousB3TradingDay(DateTime date) {
  var day = DateTime(date.year, date.month, date.day)
      .subtract(const Duration(days: 1));
  while (!isB3TradingDay(day)) {
    day = day.subtract(const Duration(days: 1));
  }
  return day;
}

// O calendário acompanha a data da bolsa, inclusive fora do fuso brasileiro.
DateTime b3Today() {
  final brazil = DateTime.now().toUtc().subtract(const Duration(hours: 3));
  return DateTime(brazil.year, brazil.month, brazil.day);
}
