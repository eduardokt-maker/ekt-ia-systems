import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_client.dart';

class BankingImportHistoryScreen extends StatefulWidget {
  const BankingImportHistoryScreen({
    super.key,
    required this.apiUriBuilder,
    required this.onEdit,
    required this.onDelete,
  });

  final Uri Function(String path) apiUriBuilder;
  final Future<void> Function(Map<String, dynamic> item) onEdit;
  final Future<void> Function(Map<String, dynamic> item) onDelete;

  @override
  State<BankingImportHistoryScreen> createState() =>
      _BankingImportHistoryScreenState();
}

class _BankingImportHistoryScreenState
    extends State<BankingImportHistoryScreen> {
  bool _loading = true;
  String _error = '';
  List<dynamic> _batches = const [];
  Map<String, dynamic>? _selectedBatch;
  List<dynamic> _items = const [];

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await apiClient.get(widget.apiUriBuilder(path));
    if (response.body.trim().isEmpty) {
      throw const ApiFailure('O servidor não concluiu a consulta.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || body['ok'] != true) {
      throw ApiFailure(
          body['message'] as String? ?? 'Não foi possível carregar.');
    }
    return body;
  }

  Future<void> _loadBatches() async {
    setState(() {
      _loading = true;
      _error = '';
      _selectedBatch = null;
      _items = const [];
    });
    try {
      final body = await _get('/api/banking/imports');
      if (mounted) setState(() => _batches = body['batches'] as List<dynamic>);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openBatch(Map<String, dynamic> batch) async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final body = await _get('/api/banking/imports/${batch['id']}');
      if (mounted) {
        setState(() {
          _selectedBatch = Map<String, dynamic>.from(body['batch'] as Map);
          _items = body['items'] as List<dynamic>;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_selectedBatch == null
              ? 'Movimentações importadas'
              : _selectedBatch!['filename'] as String),
          leading: IconButton(
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back),
            onPressed: _selectedBatch == null
                ? () => Navigator.pop(context)
                : _loadBatches,
          ),
          actions: <Widget>[
            IconButton(
                tooltip: 'Atualizar',
                onPressed: _selectedBatch == null
                    ? _loadBatches
                    : () => _openBatch(_selectedBatch!),
                icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _selectedBatch == null
                                ? _loadBatches
                                : () => _openBatch(_selectedBatch!),
                            child: const Text('Tentar novamente')),
                      ]),
                    ),
                  )
                : _selectedBatch == null
                    ? _batchList()
                    : _transactionList(),
      );

  Widget _batchList() => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1050),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text('Arquivos e lotes enviados',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  const Text(
                      'Abra um lote para conferir, editar ou excluir as movimentações lançadas.'),
                  const SizedBox(height: 14),
                  if (_batches.isEmpty)
                    const Card(
                        child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Nenhuma importação encontrada.')))
                  else
                    ..._batches.map((raw) {
                      final batch = Map<String, dynamic>.from(raw as Map);
                      final kind = batch['document_kind'] == 'receipt'
                          ? 'Comprovante'
                          : batch['document_kind'] == 'legacy'
                              ? 'Histórico'
                              : 'Extrato';
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                              child: Icon(batch['document_kind'] == 'receipt'
                                  ? Icons.description_outlined
                                  : Icons.receipt_long_outlined)),
                          title: Text(batch['filename'] as String,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(
                              '$kind • ${batch['bank_name']} → ${batch['account_name']}\nEnviado em ${_displayDate(batch['created_at'])}'),
                          isThreeLine: true,
                          trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Chip(
                                    label:
                                        Text('${batch['item_count']} itens')),
                                const Icon(Icons.chevron_right),
                              ]),
                          onTap: () => _openBatch(batch),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _transactionList() => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1050),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                      '${_selectedBatch!['bank_name']} → ${_selectedBatch!['account_name']}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('${_items.length} movimentação(ões) neste lote'),
                  const SizedBox(height: 12),
                  if (_items.isEmpty)
                    const Card(
                        child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                                'Este envio não possui movimentações ativas.')))
                  else
                    ..._items.map((raw) => _transactionCard(
                        Map<String, dynamic>.from(raw as Map))),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _transactionCard(Map<String, dynamic> item) {
    final income = item['transaction_type'] == 'INCOME';
    final color = income ? const Color(0xFF167A4B) : const Color(0xFFB42332);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: .12),
            foregroundColor: color,
            child: Icon(income ? Icons.add : Icons.remove)),
        title: Text(item['description'] as String,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
            '${item['transaction_date']} • ${item['category_name'] ?? 'Sem categoria'}\n${item['bank_name']} → ${item['account_name']} • ${item['counterparty'] ?? ''}'),
        isThreeLine: true,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text('${income ? '+' : '-'} R\$ ${item['amount_text']}',
              style: TextStyle(color: color, fontWeight: FontWeight.w900)),
          PopupMenuButton<String>(
            tooltip: 'Ações da movimentação',
            onSelected: (action) async {
              if (action == 'edit') {
                await widget.onEdit(item);
              } else {
                await widget.onDelete(item);
              }
              if (mounted) await _openBatch(_selectedBatch!);
            },
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'edit', child: Text('Editar')),
              PopupMenuItem(value: 'delete', child: Text('Excluir')),
            ],
          ),
        ]),
      ),
    );
  }

  String _displayDate(dynamic raw) {
    final value = '${raw ?? ''}';
    if (value.length < 10) return 'data não informada';
    final date = value.substring(0, 10).split('-');
    return date.length == 3 ? '${date[2]}/${date[1]}/${date[0]}' : value;
  }
}
