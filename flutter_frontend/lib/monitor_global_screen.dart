import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_client.dart';

class MonitorGlobalScreen extends StatefulWidget {
  const MonitorGlobalScreen({required this.apiUriBuilder, super.key});
  final Uri Function(String path) apiUriBuilder;

  @override
  State<MonitorGlobalScreen> createState() => _MonitorGlobalScreenState();
}

class _MonitorGlobalScreenState extends State<MonitorGlobalScreen> {
  Timer? timer;
  bool loading = true;
  String error = '';
  Map<String, dynamic> diagnostics = const {};
  List<Map<String, dynamic>> quotes = const [];

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(
        const Duration(seconds: 5), (_) => _load(background: true));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool background = false}) async {
    if (!background) {
      setState(() => loading = true);
    }
    try {
      final response = await apiClient
          .get(widget.apiUriBuilder('/api/market-global/status'));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw Exception('Integração indisponível.');
      }
      if (!mounted) return;
      setState(() {
        diagnostics =
            Map<String, dynamic>.from(body['diagnostics'] as Map? ?? const {});
        quotes = ((body['quotes'] as List?) ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        error = '';
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Monitor Global',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
                onPressed: _load,
                tooltip: 'Atualizar',
                icon: const Icon(Icons.refresh))
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusPanel(diagnostics: diagnostics),
              const SizedBox(height: 16),
              const Text('Prova de conceito RTD',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const Text('WIN, WDO, IBOV, PETR4 e VALE3',
                  style: TextStyle(color: Color(0xFF667085))),
              const SizedBox(height: 12),
              if (loading && quotes.isEmpty)
                const Center(child: CircularProgressIndicator()),
              if (error.isNotEmpty) _MessageCard(message: error, warning: true),
              if (!loading && quotes.isEmpty && error.isEmpty)
                _MessageCard(
                    message:
                        '${diagnostics['message'] ?? 'Nenhuma cotação RTD disponível.'}',
                    warning: true),
              LayoutBuilder(builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 1100
                    ? 5
                    : width >= 720
                        ? 3
                        : width >= 460
                            ? 2
                            : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: quotes.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      mainAxisExtent: 190),
                  itemBuilder: (_, index) => _QuoteCard(data: quotes[index]),
                );
              }),
              const SizedBox(height: 16),
              FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Verificar integração Profit')),
              const SizedBox(height: 10),
              const Text(
                  'Módulo informativo. Não envia ordens e não constitui recomendação de compra ou venda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Color(0xFF667085))),
            ],
          ),
        ),
      );
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.diagnostics});
  final Map<String, dynamic> diagnostics;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xFF0E2841),
            borderRadius: BorderRadius.circular(18)),
        child: Wrap(spacing: 18, runSpacing: 10, children: [
          _Status(label: 'Profit', ok: diagnostics['profit_running'] == true),
          _Status(label: 'Excel', ok: diagnostics['excel_running'] == true),
          _Status(label: 'Arquivo', ok: diagnostics['workbook_found'] == true),
          Text('${diagnostics['message'] ?? 'Verificando integração...'}',
              style: const TextStyle(color: Colors.white)),
        ]),
      );
}

class _Status extends StatelessWidget {
  const _Status({required this.label, required this.ok});
  final String label;
  final bool ok;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle,
            size: 9,
            color: ok ? const Color(0xFF52D3A2) : const Color(0xFFFFB4AB)),
        const SizedBox(width: 6),
        Text('$label: ${ok ? 'detectado' : 'indisponível'}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
      ]);
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.data});
  final Map<String, dynamic> data;
  String value(String key, {String suffix = ''}) =>
      data[key] == null ? '—' : '${data[key]}$suffix';
  @override
  Widget build(BuildContext context) {
    final change = (data['change_percent'] as num?)?.toDouble();
    final color = change == null
        ? const Color(0xFF667085)
        : change >= 0
            ? const Color(0xFF087A55)
            : const Color(0xFFC83E44);
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('${data['ticker']}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900))),
            Text('${data['source'] ?? ''}', style: const TextStyle(fontSize: 9))
          ]),
          Text('${data['name'] ?? ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          Text(value('price'),
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          Text(value('change_percent', suffix: '%'),
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('${data['message'] ?? ''}',
              maxLines: 2,
              style: TextStyle(
                  fontSize: 10,
                  color: data['data_status'] == 'updated'
                      ? const Color(0xFF087A55)
                      : const Color(0xFF9A6700))),
        ]),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, this.warning = false});
  final String message;
  final bool warning;
  @override
  Widget build(BuildContext context) => Card(
      color: warning ? const Color(0xFFFFF4E5) : null,
      child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(message, textAlign: TextAlign.center)));
}
