import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  Map<String, dynamic> model = const {};
  List<Map<String, dynamic>> quotes = const [];

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(
        const Duration(seconds: 30), (_) => _load(background: true));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool background = false}) async {
    if (!background) setState(() => loading = true);
    try {
      final hostedBySites = kIsWeb && Uri.base.host.endsWith('.chatgpt.site');
      final endpoint = hostedBySites
          ? Uri.base.resolve('/api/market-global/status')
          : widget.apiUriBuilder('/api/market-global/status');
      final response = await apiClient.get(
        endpoint,
        timeout: marketApiTimeout,
      );
      if (!(response.headers['content-type'] ?? '')
          .toLowerCase()
          .contains('application/json')) {
        throw const ApiFailure(
            'A integração externa ainda não está disponível no servidor.');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw const ApiFailure('Não foi possível consultar a fonte externa.');
      }
      if (!mounted) return;
      setState(() {
        diagnostics =
            Map<String, dynamic>.from(body['diagnostics'] as Map? ?? const {});
        model = Map<String, dynamic>.from(body['model'] as Map? ?? const {});
        quotes = ((body['quotes'] as List?) ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        error = body['ok'] == true
            ? ''
            : '${diagnostics['message'] ?? 'Fonte externa indisponível.'}';
      });
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Não foi possível comunicar com a fonte externa neste momento.');
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
                tooltip: 'Atualizar agora',
                icon: const Icon(Icons.refresh))
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusPanel(diagnostics: diagnostics, loading: loading),
              const SizedBox(height: 16),
              const Text('Pulso internacional',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const Text('EWZ • E-mini S&P 500 • VIX',
                  style: TextStyle(color: Color(0xFF667085))),
              const SizedBox(height: 14),
              if (model.isNotEmpty) _BiasPanel(model: model),
              if (model.isNotEmpty) const SizedBox(height: 14),
              if (loading && quotes.isEmpty)
                const Center(child: CircularProgressIndicator()),
              if (error.isNotEmpty) _MessageCard(message: error),
              LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth >= 850
                    ? 3
                    : constraints.maxWidth >= 520
                        ? 2
                        : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: quotes.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 205,
                  ),
                  itemBuilder: (_, index) => _QuoteCard(data: quotes[index]),
                );
              }),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.sync),
                  label: const Text('Atualizar indicadores')),
              const SizedBox(height: 10),
              Text(
                '${diagnostics['delay_notice'] ?? 'Cotações externas podem ter atraso.'} '
                'Modelo informativo: não envia ordens nem constitui recomendação.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Color(0xFF667085)),
              ),
            ],
          ),
        ),
      );
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.diagnostics, required this.loading});
  final Map<String, dynamic> diagnostics;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final online = diagnostics['provider_online'] == true;
    final active = diagnostics['active_assets'] ?? 0;
    final requested = diagnostics['requested_assets'] ?? 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          color: const Color(0xFF0E2841),
          borderRadius: BorderRadius.circular(18)),
      child: Wrap(spacing: 18, runSpacing: 8, children: [
        _Status(label: 'Fonte externa', ok: online),
        _Status(
            label: '$active/$requested indicadores', ok: active == requested),
        Text(
          loading
              ? 'Atualizando…'
              : '${diagnostics['message'] ?? 'Aguardando primeira leitura…'}',
          style: const TextStyle(color: Colors.white),
        ),
      ]),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.label, required this.ok});
  final String label;
  final bool ok;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle,
              size: 9,
              color: ok ? const Color(0xFF52D3A2) : const Color(0xFFFFB4AB)),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      );
}

class _BiasPanel extends StatelessWidget {
  const _BiasPanel({required this.model});
  final Map<String, dynamic> model;

  @override
  Widget build(BuildContext context) {
    final bias = '${model['bias'] ?? 'neutro'}';
    final color = bias == 'favorável'
        ? const Color(0xFF087A55)
        : bias == 'defensivo'
            ? const Color(0xFFC83E44)
            : const Color(0xFF9A6700);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        border: Border.all(color: color.withValues(alpha: .28)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Text('${model['score'] ?? 0}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Viés $bias',
                style: TextStyle(
                    color: color, fontSize: 18, fontWeight: FontWeight.w900)),
            Text('${model['summary'] ?? ''}'),
            Text('${model['methodology'] ?? ''}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF667085))),
          ]),
        ),
      ]),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.data});
  final Map<String, dynamic> data;

  String number(String key, {int decimals = 2}) {
    final value = data[key] as num?;
    if (value == null) return '—';
    return NumberFormat.decimalPatternDigits(
            locale: 'pt_BR', decimalDigits: decimals)
        .format(value);
  }

  @override
  Widget build(BuildContext context) {
    final change = (data['change_percent'] as num?)?.toDouble();
    final color = change == null
        ? const Color(0xFF667085)
        : change >= 0
            ? const Color(0xFF087A55)
            : const Color(0xFFC83E44);
    final prefix = change == null || change == 0
        ? ''
        : change > 0
            ? '+'
            : '';
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFD9E2EC)),
          borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${data['ticker']}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900)),
            ),
            Text('${data['market'] ?? ''}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF667085))),
          ]),
          Text('${data['name'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF667085))),
          const SizedBox(height: 14),
          Text(number('price'),
              style:
                  const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
          Text('$prefix${number('change_percent')}%',
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          const Spacer(),
          Row(children: [
            const Icon(Icons.schedule, size: 13, color: Color(0xFF667085)),
            const SizedBox(width: 5),
            Expanded(
              child: Text('${data['message'] ?? ''} • ${data['source'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 10, color: Color(0xFF667085))),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFFFFF4E5),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(message, textAlign: TextAlign.center),
        ),
      );
}
