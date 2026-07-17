import 'dart:math' as math;

import 'package:flutter/material.dart';

class WeeklyCandle {
  const WeeklyCandle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  factory WeeklyCandle.fromJson(Map<String, dynamic> json) => WeeklyCandle(
        time: '${json['time'] ?? ''}',
        open: (json['open'] as num).toDouble(),
        high: (json['high'] as num).toDouble(),
        low: (json['low'] as num).toDouble(),
        close: (json['close'] as num).toDouble(),
      );

  final String time;
  final double open;
  final double high;
  final double low;
  final double close;
}

List<double?> movingAverage(List<double> values, int period) {
  var sum = 0.0;
  return List<double?>.generate(values.length, (index) {
    sum += values[index];
    if (index >= period) sum -= values[index - period];
    return index >= period - 1 ? sum / period : null;
  });
}

class BollingerBands {
  const BollingerBands(this.upper, this.middle, this.lower);
  final List<double?> upper;
  final List<double?> middle;
  final List<double?> lower;
}

BollingerBands bollingerBands(List<double> values,
    {int period = 20, double deviations = 2}) {
  final middle = movingAverage(values, period);
  final upper = List<double?>.filled(values.length, null);
  final lower = List<double?>.filled(values.length, null);
  for (var i = period - 1; i < values.length; i++) {
    final mean = middle[i]!;
    var squared = 0.0;
    for (var j = i - period + 1; j <= i; j++) {
      squared += math.pow(values[j] - mean, 2).toDouble();
    }
    final standardDeviation = math.sqrt(squared / period);
    upper[i] = mean + deviations * standardDeviation;
    lower[i] = mean - deviations * standardDeviation;
  }
  return BollingerBands(upper, middle, lower);
}

class TechnicalChart extends StatefulWidget {
  const TechnicalChart({required this.candles, super.key});
  final List<WeeklyCandle> candles;

  @override
  State<TechnicalChart> createState() => _TechnicalChartState();
}

class _TechnicalChartState extends State<TechnicalChart> {
  int? selected;

  @override
  Widget build(BuildContext context) {
    if (widget.candles.length < 20) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Histórico insuficiente para montar o gráfico técnico.'),
        ),
      );
    }
    final closes = widget.candles.map((c) => c.close).toList();
    final series = TechnicalSeries(
      ma9: movingAverage(closes, 9),
      ma21: movingAverage(closes, 21),
      ma200: movingAverage(closes, 200),
      bands: bollingerBands(closes),
    );
    final start = math.max(0, widget.candles.length - 104);
    final visible = widget.candles.sublist(start);
    final active = selected == null ? visible.length - 1 : selected!;
    final candle = visible[active.clamp(0, visible.length - 1)];
    final originalIndex = start + active;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Gráfico técnico semanal',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Wrap(spacing: 14, runSpacing: 7, children: [
            _Legend(color: Color(0xFF2563EB), label: 'MM9'),
            _Legend(color: Color(0xFFF59E0B), label: 'MM21'),
            _Legend(color: Color(0xFF8B5CF6), label: 'MM200'),
            _Legend(color: Color(0xFF64748B), label: 'Bollinger 20,2'),
            _Legend(color: Color(0xFF13A471), label: 'Alta'),
            _Legend(color: Color(0xFFE0525C), label: 'Baixa'),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
                color: const Color(0xFFF3F6FA),
                borderRadius: BorderRadius.circular(10)),
            child: Wrap(spacing: 14, runSpacing: 4, children: [
              Text(candle.time,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('A ${_price(candle.open)}'),
              Text('M ${_price(candle.high)}'),
              Text('m ${_price(candle.low)}'),
              Text('F ${_price(candle.close)}'),
              _IndicatorValue('MM9', series.ma9[originalIndex]),
              _IndicatorValue('MM21', series.ma21[originalIndex]),
              _IndicatorValue('MM200', series.ma200[originalIndex]),
            ]),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            return GestureDetector(
              onTapDown: (details) => _select(details.localPosition.dx,
                  constraints.maxWidth, visible.length),
              onHorizontalDragUpdate: (details) => _select(
                  details.localPosition.dx,
                  constraints.maxWidth,
                  visible.length),
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                child: SizedBox(
                  height: 430,
                  width: constraints.maxWidth,
                  child: CustomPaint(
                    painter: _TechnicalChartPainter(
                      candles: widget.candles,
                      series: series,
                      start: start,
                      selected: selected,
                    ),
                  ),
                ),
              ),
            );
          }),
          const Padding(
            padding: EdgeInsets.only(left: 8, top: 5),
            child: Text(
                'Toque ou arraste sobre o gráfico para consultar uma semana.',
                style: TextStyle(fontSize: 11, color: Color(0xFF667085))),
          ),
        ]),
      ),
    );
  }

  void _select(double dx, double width, int length) {
    const left = 8.0;
    const right = 58.0;
    final chartWidth = math.max(1.0, width - left - right);
    final index =
        (((dx - left) / chartWidth) * length).floor().clamp(0, length - 1);
    setState(() => selected = index);
  }
}

class TechnicalSeries {
  const TechnicalSeries(
      {required this.ma9,
      required this.ma21,
      required this.ma200,
      required this.bands});
  final List<double?> ma9;
  final List<double?> ma21;
  final List<double?> ma200;
  final BollingerBands bands;
}

class _TechnicalChartPainter extends CustomPainter {
  const _TechnicalChartPainter(
      {required this.candles,
      required this.series,
      required this.start,
      required this.selected});
  final List<WeeklyCandle> candles;
  final TechnicalSeries series;
  final int start;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 8.0;
    const top = 10.0;
    const right = 58.0;
    const bottom = 30.0;
    final rect =
        Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    final visible = candles.sublist(start);
    final candidates = <double>[];
    for (var i = start; i < candles.length; i++) {
      candidates.addAll([candles[i].low, candles[i].high]);
      for (final value in [
        series.ma9[i],
        series.ma21[i],
        series.ma200[i],
        series.bands.upper[i],
        series.bands.lower[i]
      ]) {
        if (value != null) candidates.add(value);
      }
    }
    var minPrice = candidates.reduce(math.min);
    var maxPrice = candidates.reduce(math.max);
    final padding = math.max((maxPrice - minPrice) * .06, .01);
    minPrice -= padding;
    maxPrice += padding;
    double x(int i) => rect.left + (i + .5) * rect.width / visible.length;
    double y(double price) =>
        rect.bottom - (price - minPrice) / (maxPrice - minPrice) * rect.height;

    canvas.drawRect(rect, Paint()..color = const Color(0xFFFAFCFF));
    final grid = Paint()
      ..color = const Color(0xFFE4EAF1)
      ..strokeWidth = 1;
    for (var i = 0; i <= 5; i++) {
      final yy = rect.top + rect.height * i / 5;
      canvas.drawLine(Offset(rect.left, yy), Offset(rect.right, yy), grid);
      final price = maxPrice - (maxPrice - minPrice) * i / 5;
      _text(canvas, _price(price), Offset(rect.right + 5, yy - 7), 10,
          const Color(0xFF667085));
    }

    _bandArea(canvas, rect, x, y);
    _line(canvas, series.bands.upper, start, x, y, const Color(0xFF64748B), 1);
    _line(canvas, series.bands.lower, start, x, y, const Color(0xFF64748B), 1);
    _line(canvas, series.ma9, start, x, y, const Color(0xFF2563EB), 1.8);
    _line(canvas, series.ma21, start, x, y, const Color(0xFFF59E0B), 1.8);
    _line(canvas, series.ma200, start, x, y, const Color(0xFF8B5CF6), 2.1);

    final slot = rect.width / visible.length;
    final bodyWidth = math.max(2.0, math.min(7.0, slot * .66));
    for (var i = 0; i < visible.length; i++) {
      final candle = visible[i];
      final color = candle.close >= candle.open
          ? const Color(0xFF13A471)
          : const Color(0xFFE0525C);
      final paint = Paint()..color = color;
      canvas.drawLine(Offset(x(i), y(candle.high)), Offset(x(i), y(candle.low)),
          paint..strokeWidth = 1);
      final bodyTop = y(math.max(candle.open, candle.close));
      final bodyBottom = y(math.min(candle.open, candle.close));
      canvas.drawRect(
          Rect.fromLTRB(x(i) - bodyWidth / 2, bodyTop, x(i) + bodyWidth / 2,
              math.max(bodyTop + 1.5, bodyBottom)),
          paint);
    }

    for (var i = 0; i < visible.length; i += math.max(1, visible.length ~/ 5)) {
      _text(canvas, visible[i].time, Offset(x(i) - 14, rect.bottom + 8), 9,
          const Color(0xFF667085));
    }
    if (selected != null) {
      final xx = x(selected!.clamp(0, visible.length - 1));
      canvas.drawLine(
          Offset(xx, rect.top),
          Offset(xx, rect.bottom),
          Paint()
            ..color = const Color(0xFF0F172A).withValues(alpha: .35)
            ..strokeWidth = 1);
    }
  }

  void _line(
      Canvas canvas,
      List<double?> values,
      int offset,
      double Function(int) x,
      double Function(double) y,
      Color color,
      double width) {
    final path = Path();
    var started = false;
    for (var i = offset; i < values.length; i++) {
      final value = values[i];
      if (value == null) {
        started = false;
        continue;
      }
      final point = Offset(x(i - offset), y(value));
      if (!started) {
        path.moveTo(point.dx, point.dy);
        started = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true);
  }

  void _bandArea(Canvas canvas, Rect rect, double Function(int) x,
      double Function(double) y) {
    final upper = series.bands.upper;
    final lower = series.bands.lower;
    final path = Path();
    final valid = <int>[];
    for (var i = start; i < candles.length; i++) {
      if (upper[i] != null && lower[i] != null) valid.add(i);
    }
    if (valid.length < 2) return;
    path.moveTo(x(valid.first - start), y(upper[valid.first]!));
    for (final i in valid.skip(1)) {
      path.lineTo(x(i - start), y(upper[i]!));
    }
    for (final i in valid.reversed) {
      path.lineTo(x(i - start), y(lower[i]!));
    }
    path.close();
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawPath(
        path, Paint()..color = const Color(0xFF94A3B8).withValues(alpha: .12));
    canvas.restore();
  }

  void _text(
      Canvas canvas, String text, Offset offset, double size, Color color) {
    final painter = TextPainter(
      text:
          TextSpan(text: text, style: TextStyle(fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TechnicalChartPainter oldDelegate) =>
      oldDelegate.candles != candles || oldDelegate.selected != selected;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 16, height: 3, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ]);
}

class _IndicatorValue extends StatelessWidget {
  const _IndicatorValue(this.label, this.value);
  final String label;
  final double? value;
  @override
  Widget build(BuildContext context) =>
      Text('$label ${value == null ? '--' : _price(value!)}');
}

String _price(double value) => value.toStringAsFixed(2).replaceAll('.', ',');
