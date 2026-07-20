import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'ibovespa_quote.dart';
import 'official_logo_assets.dart';

class IbovespaQuoteCard extends StatefulWidget {
  const IbovespaQuoteCard({
    required this.quote,
    required this.favorite,
    required this.selected,
    required this.badges,
    required this.onTap,
    required this.onFavorite,
    super.key,
  });

  final IbovespaQuote quote;
  final bool favorite;
  final bool selected;
  final List<String> badges;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  State<IbovespaQuoteCard> createState() => _IbovespaQuoteCardState();
}

class _IbovespaQuoteCardState extends State<IbovespaQuoteCard> {
  Color? flashColor;
  Timer? flashTimer;

  @override
  void didUpdateWidget(covariant IbovespaQuoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPrice = oldWidget.quote.price;
    final newPrice = widget.quote.price;
    if (oldPrice == null || newPrice == null || oldPrice == newPrice) return;
    flashTimer?.cancel();
    setState(() => flashColor = newPrice > oldPrice
        ? const Color(0x1F0AA06E)
        : const Color(0x1FE14D50));
    flashTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => flashColor = null);
    });
  }

  @override
  void dispose() {
    flashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quote = widget.quote;
    final colors = Theme.of(context).colorScheme;
    final accent = _accentFor(quote.direction, colors);
    return Semantics(
      button: true,
      label:
          '${quote.symbol}, ${quote.name}, ${formatBrl(quote.price)}, ${formatPercent(quote.changePercent)}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: flashColor ?? colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.selected
                ? colors.primary
                : accent.withValues(alpha: .24),
            width: widget.selected ? 2.2 : 1,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x140B2945),
              blurRadius: 18,
              offset: Offset(0, 7),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            canRequestFocus: true,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _CompanyLogo(symbol: quote.symbol),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              quote.symbol,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Tooltip(
                              message: '${quote.name}\nSetor: ${quote.sector}',
                              child: Text(
                                quote.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: widget.onFavorite,
                        tooltip: widget.favorite
                            ? 'Remover dos favoritos'
                            : 'Adicionar aos favoritos',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          widget.favorite ? Icons.star : Icons.star_border,
                          color: widget.favorite
                              ? const Color(0xFFE2A400)
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (widget.badges.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: widget.badges
                          .map((label) => _HighlightBadge(label: label))
                          .toList(growable: false),
                    ),
                  ],
                  const SizedBox(height: 13),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              formatBrl(quote.price),
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: <Widget>[
                                Icon(_directionIcon(quote.direction),
                                    size: 16, color: accent),
                                const SizedBox(width: 3),
                                Text(
                                  formatPercent(quote.changePercent),
                                  style: TextStyle(
                                      color: accent,
                                      fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  formatBrl(quote.change),
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 112,
                        height: 54,
                        child: CustomPaint(
                          painter: _SparklinePainter(
                            values: quote.intradayPrices,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: <Widget>[
                      _Metric(
                          label: 'Abertura', value: formatBrl(quote.dayOpen)),
                      _Metric(label: 'Máxima', value: formatBrl(quote.dayHigh)),
                      _Metric(label: 'Mínima', value: formatBrl(quote.dayLow)),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Volume financeiro: ${formatCompact(quote.financialVolume, prefix: 'R\$ ')}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _MarketStateChip(quote: quote),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: <Widget>[
                      Icon(Icons.schedule,
                          size: 13, color: colors.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Atualizado às ${quote.timeLabel}${quote.isStale ? ' • dado atrasado' : ''}',
                          style: TextStyle(
                            color: quote.isStale
                                ? const Color(0xFF9A6700)
                                : colors.onSurfaceVariant,
                            fontSize: 10.5,
                            fontWeight: quote.isStale
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      const Icon(Icons.open_in_new, size: 14),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10)),
            const SizedBox(height: 2),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

class _HighlightBadge extends StatelessWidget {
  const _HighlightBadge({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4CC),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Color(0xFF795B00),
                fontSize: 9.5,
                fontWeight: FontWeight.w900)),
      );
}

class _MarketStateChip extends StatelessWidget {
  const _MarketStateChip({required this.quote});
  final IbovespaQuote quote;

  @override
  Widget build(BuildContext context) {
    final state = quote.price == null ? 'UNAVAILABLE' : quote.marketState;
    final (label, color) = switch (state.toUpperCase()) {
      'REGULAR' => ('Mercado aberto', const Color(0xFF087A55)),
      'AUCTION' => ('Em leilão', const Color(0xFF9A6700)),
      'PRE' || 'PREPRE' => ('Pré-abertura', const Color(0xFF2563A8)),
      'POST' || 'POSTPOST' => ('Pós-mercado', const Color(0xFF6D4AA2)),
      'CLOSED' => ('Mercado fechado', const Color(0xFF667085)),
      _ => ('Indisponível', const Color(0xFF8A4548)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.circle, size: 7, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 9.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _CompanyLogo extends StatelessWidget {
  const _CompanyLogo({required this.symbol});
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF1769AA), Color(0xFF42A5F5)],
        ),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(symbol.isEmpty ? '?' : symbol[0],
          style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
    );
    final assetPath = officialLogoAssets[symbol];
    final isAxia = symbol == 'AXIA3';
    final logo = assetPath == null
        ? fallback
        : assetPath.toLowerCase().endsWith('.svg')
            ? SvgPicture.asset(assetPath,
                fit: isAxia ? BoxFit.fitWidth : BoxFit.contain,
                semanticsLabel: 'Logo oficial de $symbol',
                placeholderBuilder: (_) => fallback)
            : Image.asset(assetPath,
                fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback);
    return Container(
      width: isAxia ? 62 : 46,
      height: 46,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: isAxia ? const Color(0xFF17283B) : Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x1F0B5FA5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: logo,
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.values, required this.color});
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      final paint = Paint()
        ..color = color.withValues(alpha: .2)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), paint);
      return;
    }
    final minimum = values.reduce(math.min);
    final maximum = values.reduce(math.max);
    final spread = maximum - minimum;
    final path = Path();
    for (var index = 0; index < values.length; index += 1) {
      final x = index * size.width / (values.length - 1);
      final ratio = spread == 0 ? .5 : (values[index] - minimum) / spread;
      final y = size.height - (ratio * (size.height - 8)) - 4;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

Color _accentFor(QuoteDirection direction, ColorScheme colors) =>
    switch (direction) {
      QuoteDirection.up => const Color(0xFF087A55),
      QuoteDirection.down => const Color(0xFFC83E44),
      QuoteDirection.neutral => const Color(0xFF667085),
      QuoteDirection.unavailable => colors.outline,
    };

IconData _directionIcon(QuoteDirection direction) => switch (direction) {
      QuoteDirection.up => Icons.arrow_upward,
      QuoteDirection.down => Icons.arrow_downward,
      QuoteDirection.neutral => Icons.remove,
      QuoteDirection.unavailable => Icons.question_mark,
    };
