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
  final _search = TextEditingController();
  bool _loading = true;
  String _error = '';
  String _type = 'Todos';
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _summary = const {};

  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw ApiFailure(body['message'] as String? ??
            'Não foi possível carregar as saídas.');
      }
      if (mounted) {
        setState(() {
          _items = (body['outflows'] as List<dynamic>)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
          _summary = Map<String, dynamic>.from(body['summary'] as Map);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _types => <String>{
        'Todos',
        ..._items.map((item) => item['type'] as String),
      }.toList();

  List<Map<String, dynamic>> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _items.where((item) {
      final matchesType = _type == 'Todos' || item['type'] == _type;
      final haystack =
          '${item['destination']} ${item['description']} ${item['document']}'
              .toLowerCase();
      return matchesType && (query.isEmpty || haystack.contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Saídas financeiras',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              Text('Débito, Pix, boletos, tarifas e demais despesas',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
            ],
          ),
          actions: <Widget>[
            IconButton(
                tooltip: 'Atualizar',
                onPressed: _load,
                icon: const Icon(Icons.refresh))
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
                ? Center(child: Text(_error))
                : _content(),
      );

  Widget _content() {
    final filtered = _filtered;
    final filteredTotal = filtered.fold<double>(
        0, (total, item) => total + (item['amount'] as num).toDouble());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1150),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
                  _metric(
                      'Total de saídas',
                      _currency.format(_summary['total'] ?? 0),
                      Icons.trending_down,
                      const Color(0xFFB42332)),
                  _metric('Movimentações', '${_summary['count'] ?? 0}',
                      Icons.receipt_long, const Color(0xFF315F8C)),
                  _metric(
                      'Resultado do filtro',
                      _currency.format(filteredTotal),
                      Icons.filter_alt,
                      const Color(0xFF0B766E)),
                ]),
                const SizedBox(height: 14),
                const Text('Como o dinheiro saiu',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: (_summary['by_type'] as List<dynamic>? ?? const [])
                      .map((raw) {
                    final row = Map<String, dynamic>.from(raw as Map);
                    return ActionChip(
                      avatar: Icon(_icon(row['name'] as String), size: 18),
                      label: Text(
                          '${row['name']} • ${row['count']} • ${_currency.format(row['amount'])}'),
                      onPressed: () =>
                          setState(() => _type = row['name'] as String),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Principais destinos das despesas',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  subtitle: const Text(
                      'Valores agrupados por favorecido ou estabelecimento'),
                  children:
                      (_summary['by_destination'] as List<dynamic>? ?? const [])
                          .take(10)
                          .map((raw) {
                    final row = Map<String, dynamic>.from(raw as Map);
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(row['name'] as String),
                      subtitle: Text('${row['count']} movimentação(ões)'),
                      trailing: Text(_currency.format(row['amount'])),
                      onTap: () {
                        _search.text = row['name'] as String;
                        setState(() {});
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Pesquisar destino, descrição ou documento',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _types
                        .map((type) => Padding(
                              padding: const EdgeInsets.only(right: 7),
                              child: FilterChip(
                                label: Text(type),
                                selected: _type == type,
                                onSelected: (_) => setState(() => _type = type),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 16),
                Text('${filtered.length} saída(s) encontrada(s)',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                ...filtered.map(_transactionCard),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _metric(String label, String value, IconData icon, Color color) =>
      SizedBox(
        width: 250,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(children: <Widget>[
              CircleAvatar(
                  backgroundColor: color.withValues(alpha: .12),
                  foregroundColor: color,
                  child: Icon(icon)),
              const SizedBox(width: 11),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                    Text(label, style: const TextStyle(fontSize: 12)),
                    Text(value,
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w900)),
                  ])),
            ]),
          ),
        ),
      );

  Widget _transactionCard(Map<String, dynamic> item) => Card(
        child: ListTile(
          leading: CircleAvatar(child: Icon(_icon(item['type'] as String))),
          title: Text(item['destination'] as String,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
              '${item['transaction_date']} • ${item['type']}\nLançamento: ${item['posting_date']} • Página ${item['page']} • ${item['filename']}'),
          isThreeLine: true,
          trailing: Text(_currency.format(item['amount']),
              style: const TextStyle(
                  color: Color(0xFFB42332), fontWeight: FontWeight.w900)),
        ),
      );

  IconData _icon(String type) {
    if (type.contains('Cartão')) return Icons.credit_card;
    if (type.contains('Pix')) return Icons.pix;
    if (type.contains('Boleto')) return Icons.receipt_long;
    if (type.contains('IOF') || type.contains('Juros')) return Icons.percent;
    return Icons.south_east;
  }
}
