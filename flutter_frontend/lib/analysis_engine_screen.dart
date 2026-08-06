import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api_client.dart';

class AnalysisEngineScreen extends StatefulWidget {
  const AnalysisEngineScreen({required this.apiUriBuilder, super.key});
  final Uri Function(String path) apiUriBuilder;

  @override
  State<AnalysisEngineScreen> createState() => _AnalysisEngineScreenState();
}

class _AnalysisEngineScreenState extends State<AnalysisEngineScreen> {
  bool loading = true;
  String error = '';
  Map<String, dynamic> payload = const {};
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _load();
    timer =
        Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => loading = true);
    try {
      final response = await apiClient.get(
        widget.apiUriBuilder('/api/analysis-engine/status?period=15m'),
        timeout: marketApiTimeout,
      );
      if (response.statusCode != 200) {
        throw const ApiFailure('O Motor de Análise está indisponível.');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        payload = data;
        error = '';
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Não foi possível atualizar a análise. Tente novamente.';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final assets = (payload['assets'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final combined =
        Map<String, dynamic>.from(payload['combined'] as Map? ?? const {});
    return Scaffold(
      appBar: AppBar(
          title: const Text('Motor de Análise',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                tooltip: 'Atualizar')
          ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _Hero(
              combined: combined, updatedAt: '${payload['updated_at'] ?? ''}'),
          const SizedBox(height: 12),
          const Row(children: [
            Icon(Icons.candlestick_chart_rounded, color: Color(0xFF24557A)),
            SizedBox(width: 8),
            Text('Candles de 15 minutos',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
          if (loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator())),
          if (error.isNotEmpty) _Notice(error, isError: true),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth >= 900
                ? (constraints.maxWidth - 14) / 2
                : constraints.maxWidth;
            return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: assets
                    .map((asset) =>
                        SizedBox(width: width, child: _AssetPanel(data: asset)))
                    .toList());
          }),
          if (!loading && assets.isEmpty)
            const _Notice('Nenhuma análise disponível no momento.',
                isError: true),
          const SizedBox(height: 14),
          _Notice(
              '${payload['disclaimer'] ?? 'Indicadores técnicos são ferramentas de apoio e não garantem resultados.'}'),
        ]),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.combined, required this.updatedAt});
  final Map<String, dynamic> combined;
  final String updatedAt;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: const Color(0xFF102A43),
            borderRadius: BorderRadius.circular(18)),
        child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 20,
            runSpacing: 12,
            children: [
              const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ES + EWZ',
                        style: TextStyle(
                            color: Color(0xFFAED4F4),
                            fontWeight: FontWeight.w800)),
                    SizedBox(height: 4),
                    Text('Leitura técnica conjunta',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w900))
                  ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${combined['label'] ?? 'Aguardando dados'}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                Text(
                    'Score ${combined['score'] ?? '—'}  •  atualização automática',
                    style:
                        const TextStyle(color: Color(0xFFD5E5F2), fontSize: 12))
              ]),
            ]),
      );
}

class _AssetPanel extends StatelessWidget {
  const _AssetPanel({required this.data});
  final Map<String, dynamic> data;
  String fmt(dynamic value, {int digits = 2}) => value is num
      ? NumberFormat.decimalPatternDigits(
              locale: 'pt_BR', decimalDigits: digits)
          .format(value)
      : '—';

  @override
  Widget build(BuildContext context) {
    if (data['ok'] != true) {
      return _Notice(
          '${data['ticker'] ?? ''}: ${data['error'] ?? data['technical']?['message'] ?? 'Análise indisponível'}',
          isError: true);
    }
    final technical =
        Map<String, dynamic>.from(data['technical'] as Map? ?? const {});
    final signal =
        Map<String, dynamic>.from(data['signal'] as Map? ?? const {});
    final chart = (data['chart'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final change = data['change_percent'] as num?;
    final positive = (change ?? 0) >= 0;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFD9E2EC)),
          borderRadius: BorderRadius.circular(18)),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                  backgroundColor: const Color(0xFFE8F1FA),
                  child: Text('${data['ticker']}',
                      style: const TextStyle(
                          color: Color(0xFF24557A),
                          fontWeight: FontWeight.w900,
                          fontSize: 12))),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('${data['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16)),
                    Text('${data['market']} • ${data['period']}',
                        style: const TextStyle(
                            color: Color(0xFF667085), fontSize: 11))
                  ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(fmt(data['price']),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900)),
                Text('${positive ? '+' : ''}${fmt(change)}%',
                    style: TextStyle(
                        color: positive
                            ? const Color(0xFF087A55)
                            : const Color(0xFFC83E44),
                        fontWeight: FontWeight.w800))
              ]),
            ]),
            const SizedBox(height: 14),
            const Wrap(spacing: 12, runSpacing: 6, children: [
              _Legend(color: Color(0xFFF3B61F), label: 'Média 9'),
              _Legend(color: Color(0xFF2F80B7), label: 'Média 20'),
              _Legend(color: Color(0xFF8B6FC0), label: 'Bandas de Bollinger'),
            ]),
            const SizedBox(height: 8),
            SizedBox(height: 300, child: _CandleChart(chart: chart)),
            const SizedBox(height: 12),
            Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFF2F6FA),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Expanded(
                      child: Text('${signal['trend'] ?? 'Sem classificação'}',
                          style: const TextStyle(fontWeight: FontWeight.w800))),
                  Text('Score ${signal['score'] ?? '—'}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF24557A)))
                ])),
            const SizedBox(height: 12),
            Text(
                '${technical['engine']} • ${technical['quality']} • ${data['source']}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF667085))),
          ])),
    );
  }
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
            style: const TextStyle(fontSize: 11, color: Color(0xFF667085))),
      ]);
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.isError = false});
  final String text;
  final bool isError;
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: isError ? const Color(0xFFFFF1F0) : const Color(0xFFFFF8E8),
          borderRadius: BorderRadius.circular(12)),
      child: Text(text, textAlign: TextAlign.center));
}

class _CandleChart extends StatelessWidget {
  const _CandleChart({required this.chart});
  final List<Map<String, dynamic>> chart;
  @override
  Widget build(BuildContext context) => CustomPaint(
      size: const Size(double.infinity, 300), painter: _CandlePainter(chart));
}

class _CandlePainter extends CustomPainter {
  const _CandlePainter(this.chart);
  final List<Map<String, dynamic>> chart;

  @override
  void paint(Canvas canvas, Size size) {
    if (chart.length < 2) return;
    final priceCandidates = <double>[];
    for (final item in chart) {
      for (final key in ['low', 'high', 'bollinger_lower', 'bollinger_upper']) {
        final value = (item[key] as num?)?.toDouble();
        if (value != null) priceCandidates.add(value);
      }
    }
    if (priceCandidates.isEmpty) return;
    final minValue = priceCandidates.reduce(math.min),
        maxValue = priceCandidates.reduce(math.max),
        spread = math.max(0.0001, maxValue - minValue);
    const top = 8.0, bottom = 14.0;
    final height = size.height - top - bottom;
    double y(double value) => top + (maxValue - value) / spread * height;
    double x(int index) => (index + .5) / chart.length * size.width;

    final gridPaint = Paint()
      ..color = const Color(0xFFE8EDF3)
      ..strokeWidth = 1;
    for (var row = 0; row <= 4; row++) {
      final gridY = top + height * row / 4;
      canvas.drawLine(Offset(0, gridY), Offset(size.width, gridY), gridPaint);
    }

    final upperPath = _linePath('bollinger_upper', x, y);
    final lowerPath = _linePath('bollinger_lower', x, y);
    if (upperPath != null && lowerPath != null) {
      final fill = Path();
      var started = false;
      for (var index = 0; index < chart.length; index++) {
        final value = (chart[index]['bollinger_upper'] as num?)?.toDouble();
        if (value == null) continue;
        if (!started) {
          fill.moveTo(x(index), y(value));
          started = true;
        } else {
          fill.lineTo(x(index), y(value));
        }
      }
      for (var index = chart.length - 1; index >= 0; index--) {
        final value = (chart[index]['bollinger_lower'] as num?)?.toDouble();
        if (value != null) fill.lineTo(x(index), y(value));
      }
      fill.close();
      canvas.drawPath(fill, Paint()..color = const Color(0x148B6FC0));
      final bandPaint = Paint()
        ..color = const Color(0xFF8B6FC0)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(upperPath, bandPaint);
      canvas.drawPath(lowerPath, bandPaint);
    }

    final slot = size.width / chart.length;
    final bodyWidth = math.max(2.0, math.min(7.0, slot * .58));
    for (var index = 0; index < chart.length; index++) {
      final item = chart[index];
      final open = (item['open'] as num).toDouble();
      final high = (item['high'] as num).toDouble();
      final low = (item['low'] as num).toDouble();
      final close = (item['close'] as num).toDouble();
      final color =
          close >= open ? const Color(0xFF14966F) : const Color(0xFFD84A54);
      final center = x(index);
      canvas.drawLine(
          Offset(center, y(high)),
          Offset(center, y(low)),
          Paint()
            ..color = color
            ..strokeWidth = 1);
      final bodyTop = math.min(y(open), y(close));
      final bodyHeight = math.max(1.5, (y(open) - y(close)).abs());
      canvas.drawRect(
          Rect.fromLTWH(center - bodyWidth / 2, bodyTop, bodyWidth, bodyHeight),
          Paint()..color = color);
    }

    for (final entry in const [
      ('ema9', Color(0xFFF3B61F), 2.0),
      ('sma20', Color(0xFF2F80B7), 2.0),
    ]) {
      final path = _linePath(entry.$1, x, y);
      if (path != null) {
        canvas.drawPath(
            path,
            Paint()
              ..color = entry.$2
              ..strokeWidth = entry.$3
              ..style = PaintingStyle.stroke);
      }
    }
  }

  Path? _linePath(
      String key, double Function(int) x, double Function(double) y) {
    final path = Path();
    var started = false;
    for (var index = 0; index < chart.length; index++) {
      final value = (chart[index][key] as num?)?.toDouble();
      if (value == null) continue;
      if (!started) {
        path.moveTo(x(index), y(value));
        started = true;
      } else {
        path.lineTo(x(index), y(value));
      }
    }
    return started ? path : null;
  }

  @override
  bool shouldRepaint(covariant _CandlePainter oldDelegate) =>
      oldDelegate.chart != chart;
}
