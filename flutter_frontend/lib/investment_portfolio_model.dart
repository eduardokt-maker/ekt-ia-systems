typedef PortfolioRecord = Map<String, dynamic>;
double portfolioNumber(Object? value) => (value as num?)?.toDouble() ?? 0;

class PortfolioPosition {
  double quantity = 0, price = 0;
  int balance = 0, deposits = 0, withdrawals = 0, income = 0;
  String? priceDate;
  bool marked = false;
  int get result => balance + withdrawals + income - deposits;
  static PortfolioPosition calculate(
      PortfolioRecord asset, List<PortfolioRecord> events, String cutoff) {
    final result = PortfolioPosition();
    final ordered = events
        .asMap()
        .entries
        .where((e) =>
            e.value['assetId'] == asset['id'] &&
            (e.value['date'] as String).compareTo(cutoff) <= 0)
        .toList()
      ..sort((a, b) {
        final date =
            (a.value['date'] as String).compareTo(b.value['date'] as String);
        return date == 0 ? a.key.compareTo(b.key) : date;
      });
    for (final entry in ordered) {
      final e = entry.value;
      final amount = (e['amount'] as num).toInt(),
          fees = (e['fees'] as num).toInt();
      final type = e['type'];
      if (type == 'income') {
        result.income += amount - fees;
        continue;
      }
      if (type == 'deposit') result.deposits += amount + fees;
      if (type == 'withdraw') result.withdrawals += amount - fees;
      if (asset['kind'] == 'variable') {
        if (type == 'deposit')
          result.quantity += portfolioNumber(e['quantity']);
        if (type == 'withdraw')
          result.quantity -= portfolioNumber(e['quantity']);
        result.price = portfolioNumber(e['price']);
        result.balance = (result.quantity * result.price * 100).round();
      } else {
        if (type == 'valuation') result.balance = amount;
        if (type == 'deposit') result.balance += amount;
        if (type == 'withdraw') result.balance -= amount;
      }
      result.priceDate = e['date'] as String;
      result.marked = type == 'valuation';
    }
    return result;
  }
}
