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
  String period = '5m';
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
        widget.apiUriBuilder('/api/analysis-engine/status?period=$period'),
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
          Row(children: [
            const Expanded(
                child: Text('Período gráfico',
                    style: TextStyle(fontWeight: FontWeight.w800))),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '5m', label: Text('5m')),
                ButtonSegment(value: '15m', label: Text('15m')),
                ButtonSegment(value: '1h', label: Text('1h')),
                ButtonSegment(value: '1d', label: Text('1D'))
              ],
              selected: {period},
              showSelectedIcon: false,
              onSelectionChanged: (value) {
                setState(() => period = value.first);
                _load();
              },
            ),
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
    final values =
        Map<String, dynamic>.from(technical['values'] as Map? ?? const {});
    final signal =
        Map<String, dynamic>.from(data['signal'] as Map? ?? const {});
    final candles = (data['candles'] as List? ?? const [])
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
            SizedBox(height: 120, child: _PriceChart(candles: candles)),
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
            Wrap(spacing: 8, runSpacing: 8, children: [
              _Metric('EMA 9', fmt(values['ema9'])),
              _Metric('EMA 21', fmt(values['ema21'])),
              _Metric('EMA 80', fmt(values['ema80'])),
              _Metric('EMA 200', fmt(values['ema200'])),
              _Metric('RSI 14', fmt(values['rsi'])),
              _Metric('ADX 14', fmt(values['adx'])),
              _Metric('MACD', fmt(values['macd_hist'])),
              _Metric('ATR 14', fmt(values['atr'])),
              _Metric('VWAP', fmt(values['vwap'])),
              _Metric('MFI', fmt(values['mfi'])),
            ]),
            const SizedBox(height: 12),
            Text(
                '${technical['engine']} • ${technical['quality']} • ${data['source']}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF667085))),
          ])),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
      width: 94,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE1E8EF)),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF667085))),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800))
      ]));
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

class _PriceChart extends StatelessWidget {
  const _PriceChart({required this.candles});
  final List<Map<String, dynamic>> candles;
  @override
  Widget build(BuildContext context) => CustomPaint(
      size: const Size(double.infinity, 120),
      painter: _PricePainter(candles
          .map((c) => (c['close'] as num?)?.toDouble())
          .whereType<double>()
          .toList()));
}

class _PricePainter extends CustomPainter {
  const _PricePainter(this.values);
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minValue = values.reduce(math.min),
        maxValue = values.reduce(math.max),
        spread = math.max(0.0001, maxValue - minValue);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
          i / (values.length - 1) * size.width,
          size.height -
              ((values[i] - minValue) / spread * (size.height - 8)) -
              4);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF2F80B7)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _PricePainter oldDelegate) =>
      oldDelegate.values != values;
}
