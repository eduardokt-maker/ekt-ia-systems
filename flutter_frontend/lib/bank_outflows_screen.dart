import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api_client.dart';

class BankOutflowsScreen extends StatefulWidget {
  const BankOutflowsScreen({super.key, required this.apiUriBuilder});
  final Uri Function(String path) apiUriBuilder;

  @override
  State<BankOutflowsScreen> createState() => _BankOutflowsScreenState();
}

class _BankOutflowsScreenState extends State<BankOutflowsScreen> {
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _summary = const {};
  int _totalFound = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final response = await apiClient.get(
          widget.apiUriBuilder('/api/banking-lab/outflows'),
          timeout: const Duration(seconds: 90));
      if (response.body.trim().isEmpty) {
        throw const ApiFailure(
            'O servidor não concluiu a leitura do extrato. Tente novamente.');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw ApiFailure(body['message'] as String? ??
            'Não foi possível ler as despesas do extrato.');
      }
      if (!mounted) return;
      setState(() {
        _items = (body['outflows'] as List<dynamic>)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _summary = Map<String, dynamic>.from(body['summary'] as Map);
        _totalFound = (body['total_found'] as num?)?.toInt() ?? _items.length;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Extrato de despesas',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              Text('Débitos reconhecidos no arquivo enviado',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
            ],
          ),
          actions: <Widget>[
            IconButton(
                tooltip: 'Ler novamente',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _loading
            ? const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Lendo as despesas do extrato...'),
                ]),
              )
            : _error.isNotEmpty
                ? _errorView()
                : _content(),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Icon(Icons.receipt_long_outlined, size: 48),
            const SizedBox(height: 12),
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente')),
          ]),
        ),
      );

  Widget _content() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 20,
                        runSpacing: 12,
                        children: <Widget>[
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text('Conferência de despesas',
                                  style: TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900)),
                              SizedBox(height: 4),
                              Text(
                                  'Primeiros 50 débitos, na ordem apresentada pelo extrato.'),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              const Text('Total dos itens apresentados'),
                              Text(_money.format(_summary['total'] ?? 0),
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFB42332))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${_items.length} de $_totalFound despesas encontradas',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if (_items.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(26),
                        child: Text(
                            'Nenhuma saída foi reconhecida no extrato enviado.'),
                      ),
                    )
                  else
                    ..._items.asMap().entries.map(
                        (entry) => _expenseRow(entry.key + 1, entry.value)),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _expenseRow(int number, Map<String, dynamic> item) => Card(
        margin: const EdgeInsets.only(bottom: 7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 38,
                child: Text('$number',
                    style: const TextStyle(
                        color: Color(0xFF687582), fontWeight: FontWeight.w700)),
              ),
              CircleAvatar(
                  radius: 19,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(_icon('${item['type']}'), size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('${item['destination']}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text('${item['transaction_date']} • ${item['type']}',
                        style: const TextStyle(color: Color(0xFF5F6873))),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(_money.format(item['amount']),
                  style: const TextStyle(
                      color: Color(0xFFB42332), fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      );

  IconData _icon(String type) {
    if (type.contains('Pix')) return Icons.pix;
    if (type.contains('Cartão')) return Icons.credit_card;
    if (type.contains('Boleto')) return Icons.receipt_long;
    if (type.contains('Débito automático')) return Icons.sync_alt;
    if (type.contains('IOF') || type.contains('Juros')) return Icons.percent;
    return Icons.south_east;
  }
}
