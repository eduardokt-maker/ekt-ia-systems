enum QuoteDirection { up, down, neutral, unavailable }

class IbovespaQuote {
  const IbovespaQuote({
    required this.symbol,
    required this.name,
    required this.sector,
    required this.price,
    required this.change,
    required this.changePercent,
    required this.volume,
    required this.financialVolume,
    required this.marketCap,
    required this.dayOpen,
    required this.dayHigh,
    required this.dayLow,
    required this.marketTime,
    required this.marketState,
    required this.intradayPrices,
  });

  factory IbovespaQuote.fromJson(Map<String, dynamic> json) => IbovespaQuote(
        symbol: '${json['symbol'] ?? ''}',
        name: '${json['name'] ?? ''}',
        sector: '${json['sector'] ?? 'Outros'}',
        price: _double(json['price']),
        change: _double(json['change']),
        changePercent: _double(json['change_percent']),
        volume: _double(json['volume']),
        financialVolume: _double(json['financial_volume']),
        marketCap: _double(json['market_cap']),
        dayOpen: _double(json['day_open']),
        dayHigh: _double(json['day_high']),
        dayLow: _double(json['day_low']),
        marketTime: '${json['market_time'] ?? ''}',
        marketState: '${json['market_state'] ?? ''}',
        intradayPrices:
            ((json['intraday_prices'] as List<dynamic>?) ?? const [])
                .whereType<num>()
                .map((value) => value.toDouble())
                .toList(growable: false),
      );

  final String symbol;
  final String name;
  final String sector;
  final double? price;
  final double? change;
  final double? changePercent;
  final double? volume;
  final double? financialVolume;
  final double? marketCap;
  final double? dayOpen;
  final double? dayHigh;
  final double? dayLow;
  final String marketTime;
  final String marketState;
  final List<double> intradayPrices;

  QuoteDirection get direction {
    if (changePercent == null) return QuoteDirection.unavailable;
    if (changePercent! > 0.001) return QuoteDirection.up;
    if (changePercent! < -0.001) return QuoteDirection.down;
    return QuoteDirection.neutral;
  }

  bool get isStale {
    final match = RegExp(
      r'^(\d{2})/(\d{2})/(\d{4}) (\d{2}):(\d{2})(?::(\d{2}))?',
    ).firstMatch(marketTime);
    if (match == null) return false;
    final updated = DateTime(
      int.parse(match.group(3)!),
      int.parse(match.group(2)!),
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.tryParse(match.group(6) ?? '') ?? 0,
    );
    return DateTime.now().difference(updated) > const Duration(minutes: 3);
  }

  String get timeLabel {
    final match = RegExp(r'(\d{2}:\d{2}(?::\d{2})?)').firstMatch(marketTime);
    return match?.group(1) ?? '--:--:--';
  }
}

double? _double(dynamic value) => value is num
    ? value.toDouble()
    : double.tryParse('${value ?? ''}'.replaceAll(',', '.'));

String formatBrl(double? value) {
  if (value == null) return '--';
  final fixed = value.abs().toStringAsFixed(2).split('.');
  final groups = fixed.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return '${value < 0 ? '-' : ''}R\$ $groups,${fixed.last}';
}

String formatPercent(double? value) {
  if (value == null) return '--';
  final sign = value > 0
      ? '+'
      : value < 0
          ? '−'
          : '';
  return '$sign${value.abs().toStringAsFixed(2).replaceAll('.', ',')}%';
}

String formatCompact(double? value, {String prefix = ''}) {
  if (value == null) return '--';
  const units = <(double, String)>[
    (1000000000000, 'tri'),
    (1000000000, 'bi'),
    (1000000, 'mi'),
    (1000, 'mil'),
  ];
  for (final unit in units) {
    if (value.abs() >= unit.$1) {
      return '$prefix${(value / unit.$1).toStringAsFixed(2).replaceAll('.', ',')} ${unit.$2}';
    }
  }
  return '$prefix${value.toStringAsFixed(0)}';
}
