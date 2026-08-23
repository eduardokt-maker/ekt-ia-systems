import 'dart:convert';

import 'package:flutter/material.dart';
import 'api_client.dart';
import 'banking_file_picker.dart';
import 'banking_import_history_screen.dart';

typedef BankingApiUriBuilder = Uri Function(String path);

class BankingControlScreen extends StatefulWidget {
  const BankingControlScreen({required this.apiUriBuilder, super.key});
  final BankingApiUriBuilder apiUriBuilder;

  @override
  State<BankingControlScreen> createState() => _BankingControlScreenState();
}

class _BankingControlScreenState extends State<BankingControlScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  late String _month;
  int? _selectedAccountId;
  int? _importAccountId;
  bool _loading = true;
  String _error = '';
  Map<String, dynamic> _data = <String, dynamic>{};

  List<dynamic> get _accounts =>
      _data['accounts'] as List<dynamic>? ?? const [];
  List<dynamic> get _cards => _data['cards'] as List<dynamic>? ?? const [];
  List<dynamic> get _categories =>
      _data['categories'] as List<dynamic>? ?? const [];
  List<dynamic> get _transactions =>
      _data['transactions'] as List<dynamic>? ?? const [];
  Map<String, dynamic> get _summary =>
      _data['summary'] as Map<String, dynamic>? ?? const {};
  List<dynamic> get _accountSummaries =>
      _data['account_summaries'] as List<dynamic>? ?? const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    final now = DateTime.now();
    _month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = widget.apiUriBuilder('/api/banking').replace(
        queryParameters: <String, String>{
          'month': _month,
          if (_selectedAccountId != null) 'account_id': '$_selectedAccountId',
          if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
        },
      );
      var response = await apiClient.get(uri);
      if (response.body.trim().isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        response = await apiClient.get(uri);
      }
      final body = _jsonObject(response.body,
          fallback: 'O servidor não concluiu a consulta. Tente novamente.');
      if (response.statusCode != 200 || body['ok'] != true) {
        throw ApiFailure(body['message'] as String? ??
            'Não foi possível carregar os dados.');
      }
      if (mounted) setState(() => _data = body);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(String resource, Map<String, dynamic> payload,
      {int? id}) async {
    final path = '/api/banking/$resource${id == null ? '' : '/$id'}';
    final response = id == null
        ? await apiClient.post(widget.apiUriBuilder(path), body: payload)
        : await apiClient.put(widget.apiUriBuilder(path), body: payload);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = _jsonObject(response.body,
          fallback: 'O servidor não confirmou a gravação.');
      throw ApiFailure(
          body['message'] as String? ?? 'Não foi possível salvar.');
    }
    await _load();
  }

  Map<String, dynamic> _jsonObject(String raw, {required String fallback}) {
    if (raw.trim().isEmpty) throw ApiFailure(fallback);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Converted below into a stable, user-facing error.
    }
    throw ApiFailure(fallback);
  }

  Future<void> _delete(String resource, Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar exclusão'),
        content: const Text('Esta ação remove o registro selecionado.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final response = await apiClient
          .delete(widget.apiUriBuilder('/api/banking/$resource/${item['id']}'));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw ApiFailure(
            body['message'] as String? ?? 'Não foi possível excluir.');
      }
      await _load();
    } catch (error) {
      _message(error.toString(), error: true);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(text),
          backgroundColor:
              error ? const Color(0xFFB42332) : const Color(0xFF167A4B)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Controle bancário e cartões',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              Text('Entradas, gastos, contas e cartões',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
            ],
          ),
          actions: <Widget>[
            IconButton(
                tooltip: 'Atualizar',
                onPressed: _load,
                icon: const Icon(Icons.refresh)),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: const <Widget>[
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Visão geral'),
              Tab(icon: Icon(Icons.swap_horiz), text: 'Movimentações'),
              Tab(icon: Icon(Icons.account_balance_outlined), text: 'Contas'),
              Tab(icon: Icon(Icons.credit_card_outlined), text: 'Cartões'),
              Tab(icon: Icon(Icons.category_outlined), text: 'Categorias'),
              Tab(
                  icon: Icon(Icons.document_scanner_outlined),
                  text: 'Importações'),
            ],
          ),
        ),
        body: Column(
          children: <Widget>[
            _filters(),
            if (_error.isNotEmpty)
              MaterialBanner(
                content: Text(_error),
                actions: <Widget>[
                  TextButton(
                      onPressed: _load, child: const Text('Tentar novamente'))
                ],
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabs,
                      children: <Widget>[
                        _overview(),
                        _transactionsView(),
                        _accountsView(),
                        _cardsView(),
                        _categoriesView(),
                        _importsView(),
                      ],
                    ),
            ),
          ],
        ),
      );

  Widget _importsView() => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text('Importação automática',
                      style:
                          TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text(
                      'Selecione obrigatoriamente o banco e a conta de destino. O sistema fará a leitura e abrirá uma revisão antes de salvar.'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    key: ValueKey<String>(
                        'import-account-${_importAccountId ?? 'none'}'),
                    initialValue: _importAccountId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Banco e conta de destino da importação',
                        border: OutlineInputBorder()),
                    items: <DropdownMenuItem<int?>>[
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Selecione uma conta')),
                      ..._accounts.map((account) => DropdownMenuItem<int?>(
                            value: account['id'] as int,
                            child: Text(
                                '${account['bank_name']} → ${account['description']}',
                                overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (value) =>
                        setState(() => _importAccountId = value),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => BankingImportHistoryScreen(
                          apiUriBuilder: widget.apiUriBuilder,
                          onEdit: (item) => _transactionDialog(existing: item),
                          onDelete: (item) => _delete('transactions', item),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Visualizar movimentações importadas'),
                  ),
                  const SizedBox(height: 18),
                  Wrap(spacing: 12, runSpacing: 12, children: <Widget>[
                    _importCard(
                        'Ler extrato bancário',
                        'PDF, CSV, XLSX, TXT ou OFX com várias movimentações.',
                        Icons.receipt_long_outlined,
                        () => _pickAndPreview('statement')),
                    _importCard(
                        'Ler comprovante bancário',
                        'Identifica automaticamente entrada ou saída, data, valor e favorecido.',
                        Icons.document_scanner_outlined,
                        () => _pickAndPreview('receipt')),
                  ]),
                  const SizedBox(height: 16),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                          'Segurança: a leitura automática apenas sugere os campos. Nada é salvo sem sua confirmação. Possíveis duplicidades são ignoradas na gravação.'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _importCard(String title, String description, IconData icon,
          VoidCallback action) =>
      SizedBox(
        width: 475,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CircleAvatar(child: Icon(icon)),
                const SizedBox(height: 12),
                Text(title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(description),
                const SizedBox(height: 14),
                FilledButton.icon(
                    onPressed: action,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Escolher arquivo')),
              ],
            ),
          ),
        ),
      );

  Future<void> _pickAndPreview(String kind) async {
    final accountId = _importAccountId;
    if (accountId == null) {
      _message('Selecione primeiro o banco e a conta de destino.', error: true);
      return;
    }
    try {
      final file = await pickBankingFile();
      if (file == null) return;
      final bytes = file.bytes;
      setState(() => _loading = true);
      final response = await apiClient.post(
        widget.apiUriBuilder('/api/banking/import/preview'),
        body: <String, dynamic>{
          'filename': file.name,
          'content_base64': base64Encode(bytes),
          'document_kind': kind,
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw ApiFailure(body['message'] as String? ??
            'Não foi possível interpretar o arquivo.');
      }
      if (mounted) await _reviewImport(accountId, body);
    } catch (error) {
      _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reviewImport(
      int accountId, Map<String, dynamic> preview) async {
    final items = (preview['items'] as List<dynamic>)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final account = _accounts.firstWhere((item) => item['id'] == accountId);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(
              'Revisar ${preview['document_kind'] == 'receipt' ? 'comprovante' : 'extrato'} importado'),
          content: SizedBox(
            width: 850,
            height: 540,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                    'Destino: ${account['bank_name']} → ${account['description']}'),
                if ('${preview['detected_bank'] ?? ''}'.isNotEmpty)
                  Text('Banco identificado: ${preview['detected_bank']}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(preview['notice'] as String? ?? ''),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(children: <Widget>[
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: item['selected'] != false,
                              title: Text('Movimentação ${index + 1}'),
                              subtitle:
                                  Text(item['source_line'] as String? ?? ''),
                              onChanged: (value) => setLocal(
                                  () => item['selected'] = value ?? false),
                            ),
                            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                              SizedBox(
                                width: 150,
                                child: TextFormField(
                                  initialValue:
                                      item['transaction_date'] as String?,
                                  decoration: const InputDecoration(
                                      labelText: 'Data',
                                      border: OutlineInputBorder()),
                                  onChanged: (value) =>
                                      item['transaction_date'] = value,
                                ),
                              ),
                              SizedBox(
                                width: 155,
                                child: DropdownButtonFormField<String>(
                                  initialValue:
                                      item['transaction_type'] as String?,
                                  decoration: const InputDecoration(
                                      labelText: 'Tipo',
                                      border: OutlineInputBorder()),
                                  items: const <DropdownMenuItem<String>>[
                                    DropdownMenuItem(
                                        value: 'INCOME',
                                        child: Text('Entrada')),
                                    DropdownMenuItem(
                                        value: 'EXPENSE', child: Text('Saída')),
                                  ],
                                  onChanged: (value) =>
                                      item['transaction_type'] = value,
                                ),
                              ),
                              SizedBox(
                                width: 130,
                                child: TextFormField(
                                  initialValue: item['amount'] as String?,
                                  decoration: const InputDecoration(
                                      labelText: 'Valor',
                                      border: OutlineInputBorder()),
                                  onChanged: (value) => item['amount'] = value,
                                ),
                              ),
                              SizedBox(
                                width: 330,
                                child: TextFormField(
                                  initialValue: item['description'] as String?,
                                  decoration: const InputDecoration(
                                      labelText: 'Descrição/favorecido',
                                      border: OutlineInputBorder()),
                                  onChanged: (value) {
                                    item['description'] = value;
                                    item['counterparty'] = value;
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 260,
                                child: TextFormField(
                                  initialValue:
                                      item['category_hint'] as String?,
                                  decoration: const InputDecoration(
                                      labelText: 'Categoria sugerida',
                                      border: OutlineInputBorder()),
                                  onChanged: (value) =>
                                      item['category_hint'] = value,
                                ),
                              ),
                            ]),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar')),
            FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.check),
                label: const Text('Confirmar e salvar')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final response = await apiClient.post(
      widget.apiUriBuilder('/api/banking/import/confirm'),
      body: <String, dynamic>{
        'account_id': accountId,
        'filename': preview['filename'],
        'document_kind': preview['document_kind'],
        'detected_bank': preview['detected_bank'],
        'items': items,
      },
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 201 || body['ok'] != true) {
      throw ApiFailure(
          body['message'] as String? ?? 'Não foi possível salvar.');
    }
    await _load();
    _message(
        '${body['saved']} movimentação(ões) salva(s). ${body['duplicates_skipped']} duplicidade(s) ignorada(s).');
  }

  Widget _filters() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 300,
                  child: DropdownButtonFormField<int?>(
                    key: ValueKey<String>(
                        'bank-account-filter-${_selectedAccountId ?? 'all'}'),
                    initialValue: _selectedAccountId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Banco/Conta',
                        border: OutlineInputBorder(),
                        isDense: true),
                    items: <DropdownMenuItem<int?>>[
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Todos os bancos')),
                      ..._accounts.map((account) => DropdownMenuItem<int?>(
                            value: account['id'] as int,
                            child: Text(
                                '${account['bank_name']}  →  ${account['description']}',
                                overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedAccountId = value);
                      _load();
                    },
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    initialValue: _month,
                    decoration: const InputDecoration(
                        labelText: 'Mês',
                        border: OutlineInputBorder(),
                        isDense: true),
                    onFieldSubmitted: (value) {
                      if (RegExp(r'^\d{4}-\d{2}$').hasMatch(value)) {
                        _month = value;
                        _load();
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 330,
                  child: TextField(
                    controller: _search,
                    onSubmitted: (_) => _load(),
                    decoration: InputDecoration(
                      labelText: 'Pesquisar movimentações',
                      hintText: 'Descrição, estabelecimento ou categoria',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                          onPressed: _load,
                          icon: const Icon(Icons.arrow_forward)),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                FilledButton.icon(
                  key: const Key('new-bank-transaction'),
                  onPressed: () => _transactionDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Nova movimentação'),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _overview() => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                      _selectedAccountId == null
                          ? 'Visão consolidada • Todos os bancos'
                          : 'Visão individual • ${_data['selected_account']?['bank_name']} → ${_data['selected_account']?['description']}',
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      _metric(
                          'Entradas do mês',
                          'R\$ ${_summary['income_text'] ?? '0,00'}',
                          Icons.south_west,
                          const Color(0xFF167A4B)),
                      _metric(
                          'Saídas do mês',
                          'R\$ ${_summary['expenses_text'] ?? '0,00'}',
                          Icons.north_east,
                          const Color(0xFFB42332)),
                      _metric(
                          'Saldo do período',
                          'R\$ ${_selectedAccountId == null ? _summary['result_text'] : _summary['account_period_result_text'] ?? '0,00'}',
                          Icons.balance,
                          const Color(0xFF1F4E79)),
                      if (_selectedAccountId != null)
                        _metric(
                            'Transferências recebidas',
                            'R\$ ${_summary['transfer_in_text'] ?? '0,00'}',
                            Icons.call_received,
                            const Color(0xFF167A4B)),
                      if (_selectedAccountId != null)
                        _metric(
                            'Transferências enviadas',
                            'R\$ ${_summary['transfer_out_text'] ?? '0,00'}',
                            Icons.call_made,
                            const Color(0xFFB42332)),
                      _metric(
                          'Saldo disponível estimado',
                          'R\$ ${_summary['available_balance_text'] ?? '0,00'}',
                          Icons.savings_outlined,
                          const Color(0xFF0F766E)),
                      _metric(
                          'Renda consumida',
                          '${(_summary['commitment_percent'] as num? ?? 0).toStringAsFixed(1)}%',
                          Icons.donut_large,
                          const Color(0xFFC76A00)),
                      _metric(
                          'Quanto sobrou?',
                          '${(_summary['remaining_percent'] as num? ?? 0).toStringAsFixed(1)}%',
                          Icons.volunteer_activism_outlined,
                          const Color(0xFF7252A3)),
                    ],
                  ),
                  if (_selectedAccountId == null &&
                      _accountSummaries.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 20),
                    const Text('Saldo por banco e conta',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _accountSummaries
                          .map((item) => SizedBox(
                                width: 260,
                                child: Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.account_balance),
                                    title: Text(item['bank_name'] as String,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                    subtitle:
                                        Text(item['account_name'] as String),
                                    trailing: Text(
                                        'R\$ ${item['available_balance_text']}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900)),
                                    onTap: () {
                                      setState(() => _selectedAccountId =
                                          item['account_id'] as int);
                                      _load();
                                    },
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text('Movimentações recentes',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  if (_transactions.isEmpty)
                    const _EmptyCard('Nenhuma movimentação neste período.')
                  else
                    ..._transactions
                        .take(8)
                        .map((item) => _transactionTile(item)),
                  const SizedBox(height: 12),
                  const Text(
                    'Transferências entre contas próprias não entram como receita nem despesa. Saldo bancário e resultado do mês são indicadores distintos.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF5F6873)),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _metric(String label, dynamic value, IconData icon, Color color) =>
      SizedBox(
        width: 245,
        child: Card(
          margin: EdgeInsets.zero,
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
                    Text(label,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF5F6873))),
                    Text(value == null ? 'R\$ 0,00' : '$value',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w900)),
                  ])),
            ]),
          ),
        ),
      );

  Widget _transactionsView() => _list(
        title: 'Movimentações de $_month',
        count: _transactions.length,
        empty: 'Nenhuma movimentação encontrada.',
        children: _transactions.map(_transactionTile).toList(),
      );

  Widget _transactionTile(dynamic raw) {
    final item = Map<String, dynamic>.from(raw as Map);
    final type = item['transaction_type'];
    final color = type == 'INCOME'
        ? const Color(0xFF167A4B)
        : type == 'EXPENSE'
            ? const Color(0xFFB42332)
            : const Color(0xFF1F4E79);
    final label = type == 'INCOME'
        ? 'Entrada'
        : type == 'EXPENSE'
            ? 'Saída'
            : 'Transferência';
    final transferDirection = item['transfer_direction'] as String?;
    final transferLabel = type == 'TRANSFER'
        ? '${item['bank_name']} → ${item['destination_bank_name']} • ${item['transfer_identifier']}'
        : '${item['bank_name']} • ${item['account_name']}';
    final signedAmount = type == 'TRANSFER' && transferDirection == 'OUT'
        ? '- R\$ ${item['amount_text']}'
        : type == 'TRANSFER' && transferDirection == 'IN'
            ? '+ R\$ ${item['amount_text']}'
            : 'R\$ ${item['amount_text']}';
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: .12),
            foregroundColor: color,
            child: Icon(type == 'INCOME'
                ? Icons.add
                : type == 'EXPENSE'
                    ? Icons.remove
                    : Icons.swap_horiz)),
        title: Text(item['description'] as String? ?? '',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
            '${item['transaction_date']} • $label • ${item['category_name'] ?? 'Sem categoria'}\n$transferLabel'),
        isThreeLine: true,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(signedAmount,
              style: TextStyle(color: color, fontWeight: FontWeight.w900)),
          PopupMenuButton<String>(
            tooltip: 'Ações',
            onSelected: (value) => value == 'edit'
                ? _transactionDialog(existing: item)
                : _delete('transactions', item),
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'edit', child: Text('Editar')),
              PopupMenuItem(value: 'delete', child: Text('Excluir')),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _accountsView() => _list(
        title: 'Minhas contas',
        count: _accounts.length,
        action: FilledButton.icon(
            key: const Key('new-bank-account'),
            onPressed: () => _accountDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Nova conta')),
        empty: 'Cadastre sua primeira conta bancária.',
        children: _accounts.map((raw) {
          final item = Map<String, dynamic>.from(raw as Map);
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.account_balance)),
              title: Text('${item['bank_name']} • ${item['description']}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                  '${item['account_type']} • ${item['holder']}\nSaldo inicial: R\$ ${item['opening_balance_text']}'),
              isThreeLine: true,
              trailing: _rowActions(() => _accountDialog(existing: item),
                  () => _delete('accounts', item)),
            ),
          );
        }).toList(),
      );

  Widget _cardsView() => _list(
        title: 'Meus cartões',
        count: _cards.length,
        action: FilledButton.icon(
            key: const Key('new-bank-card'),
            onPressed: () => _cardDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Novo cartão')),
        empty: 'Cadastre um cartão usando somente os quatro últimos dígitos.',
        children: _cards.map((raw) {
          final item = Map<String, dynamic>.from(raw as Map);
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.credit_card)),
              title: Text('${item['card_name']} •••• ${item['last_four']}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                  '${item['issuer']} • ${item['brand']}\nLimite: R\$ ${item['credit_limit_text']} • Fecha ${item['closing_day']} • Vence ${item['due_day']}'),
              isThreeLine: true,
              trailing: _rowActions(() => _cardDialog(existing: item),
                  () => _delete('cards', item)),
            ),
          );
        }).toList(),
      );

  Widget _categoriesView() => _list(
        title: 'Categorias e subcategorias',
        count: _categories.length,
        action: FilledButton.icon(
            onPressed: () => _categoryDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Nova categoria')),
        empty: 'Nenhuma categoria cadastrada.',
        children: _categories.map((raw) {
          final item = Map<String, dynamic>.from(raw as Map);
          return Card(
            child: ListTile(
              leading: Icon(item['category_type'] == 'INCOME'
                  ? Icons.south_west
                  : Icons.north_east),
              title: Text(item['name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle:
                  Text(item['category_type'] == 'INCOME' ? 'Entrada' : 'Saída'),
              trailing: _rowActions(() => _categoryDialog(existing: item),
                  () => _delete('categories', item)),
            ),
          );
        }).toList(),
      );

  Widget _list(
          {required String title,
          required int count,
          required String empty,
          required List<Widget> children,
          Widget? action}) =>
      ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Text('$title ($count)',
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w900)),
                          if (action != null) action,
                        ]),
                    const SizedBox(height: 10),
                    if (children.isEmpty) _EmptyCard(empty) else ...children,
                  ]),
            ),
          ),
        ],
      );

  Widget _rowActions(VoidCallback edit, VoidCallback delete) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
              tooltip: 'Editar',
              onPressed: edit,
              icon: const Icon(Icons.edit_outlined)),
          IconButton(
              tooltip: 'Excluir',
              onPressed: delete,
              icon: const Icon(Icons.delete_outline)),
        ],
      );

  Future<void> _accountDialog({Map<String, dynamic>? existing}) async {
    final bank = TextEditingController(text: existing?['bank_name'] as String?);
    final description =
        TextEditingController(text: existing?['description'] as String?);
    final type = TextEditingController(
        text: existing?['account_type'] as String? ?? 'Conta corrente');
    final holder = TextEditingController(text: existing?['holder'] as String?);
    final agency = TextEditingController(text: existing?['agency'] as String?);
    final digits = TextEditingController(
        text: existing?['account_last_digits'] as String?);
    final balance = TextEditingController(
        text: existing?['opening_balance_text'] as String? ?? '0,00');
    final opening = TextEditingController(
        text: existing?['opening_date']?.toString() ??
            DateTime.now().toIso8601String().substring(0, 10));
    await _formDialog(
      title: existing == null ? 'Nova conta bancária' : 'Editar conta',
      fields: <Widget>[
        _field(bank, 'Banco'),
        _field(description, 'Descrição da conta'),
        _field(type, 'Tipo da conta'),
        _field(holder, 'Titular'),
        _field(agency, 'Agência (opcional)'),
        _field(digits, 'Identificação parcial da conta'),
        _field(balance, 'Saldo inicial', number: true),
        _field(opening, 'Data do saldo inicial (AAAA-MM-DD)'),
      ],
      save: () => _save(
          'accounts',
          <String, dynamic>{
            'bank_name': bank.text,
            'description': description.text,
            'account_type': type.text,
            'holder': holder.text,
            'agency': agency.text,
            'account_last_digits': digits.text,
            'opening_balance': balance.text,
            'opening_date': opening.text,
            'active': true,
          },
          id: existing?['id'] as int?),
    );
  }

  Future<void> _cardDialog({Map<String, dynamic>? existing}) async {
    final issuer = TextEditingController(text: existing?['issuer'] as String?);
    final name = TextEditingController(text: existing?['card_name'] as String?);
    final brand = TextEditingController(text: existing?['brand'] as String?);
    final digits =
        TextEditingController(text: existing?['last_four'] as String?);
    final holder = TextEditingController(text: existing?['holder'] as String?);
    final limit = TextEditingController(
        text: existing?['credit_limit_text'] as String? ?? '0,00');
    final closing =
        TextEditingController(text: '${existing?['closing_day'] ?? ''}');
    final due = TextEditingController(text: '${existing?['due_day'] ?? ''}');
    int? accountId = existing?['payment_account_id'] as int?;
    await _formDialog(
      title: existing == null ? 'Novo cartão' : 'Editar cartão',
      fields: <Widget>[
        const Text('Por segurança, não informe número completo, CVV ou senha.',
            style: TextStyle(
                color: Color(0xFFB42332), fontWeight: FontWeight.w700)),
        _field(issuer, 'Banco/emissor'),
        _field(name, 'Nome do cartão'),
        _field(brand, 'Bandeira'),
        _field(digits, 'Quatro últimos dígitos', number: true),
        _field(holder, 'Titular'),
        _field(limit, 'Limite', number: true),
        _field(closing, 'Dia de fechamento', number: true),
        _field(due, 'Dia de vencimento', number: true),
        DropdownButtonFormField<int?>(
          initialValue: accountId,
          decoration: const InputDecoration(
              labelText: 'Conta para pagamento', border: OutlineInputBorder()),
          items: <DropdownMenuItem<int?>>[
            const DropdownMenuItem<int?>(
                value: null, child: Text('Não vinculada')),
            ..._accounts.map((a) => DropdownMenuItem<int?>(
                value: a['id'] as int,
                child: Text('${a['bank_name']} • ${a['description']}'))),
          ],
          onChanged: (value) => accountId = value,
        ),
      ],
      save: () => _save(
          'cards',
          <String, dynamic>{
            'issuer': issuer.text,
            'card_name': name.text,
            'brand': brand.text,
            'last_four': digits.text,
            'holder': holder.text,
            'credit_limit': limit.text,
            'closing_day': closing.text,
            'due_day': due.text,
            'payment_account_id': accountId,
            'active': true,
          },
          id: existing?['id'] as int?),
    );
  }

  Future<void> _categoryDialog({Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: existing?['name'] as String?);
    var type = existing?['category_type'] as String? ?? 'EXPENSE';
    int? parentId = existing?['parent_id'] as int?;
    await _formDialog(
      title: existing == null ? 'Nova categoria' : 'Editar categoria',
      fields: <Widget>[
        StatefulBuilder(
            builder: (context, setLocal) => Column(children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                        labelText: 'Tipo', border: OutlineInputBorder()),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'INCOME', child: Text('Entrada')),
                      DropdownMenuItem(value: 'EXPENSE', child: Text('Saída')),
                    ],
                    onChanged: (value) => setLocal(() {
                      type = value!;
                      parentId = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    initialValue: parentId,
                    decoration: const InputDecoration(
                        labelText: 'Categoria principal (opcional)',
                        border: OutlineInputBorder()),
                    items: <DropdownMenuItem<int?>>[
                      const DropdownMenuItem(
                          value: null, child: Text('Categoria principal')),
                      ..._categories
                          .where((c) =>
                              c['category_type'] == type &&
                              c['id'] != existing?['id'])
                          .map((c) => DropdownMenuItem(
                              value: c['id'] as int,
                              child: Text(c['name'] as String))),
                    ],
                    onChanged: (value) => parentId = value,
                  ),
                ])),
        _field(name, 'Nome'),
      ],
      save: () => _save(
          'categories',
          <String, dynamic>{
            'category_type': type,
            'name': name.text,
            'parent_id': parentId,
          },
          id: existing?['id'] as int?),
    );
  }

  Future<void> _transactionDialog({Map<String, dynamic>? existing}) async {
    var type = existing?['transaction_type'] as String? ?? 'EXPENSE';
    final description =
        TextEditingController(text: existing?['description'] as String?);
    final counterparty =
        TextEditingController(text: existing?['counterparty'] as String?);
    final amount =
        TextEditingController(text: existing?['amount_text'] as String?);
    final txDate = TextEditingController(
        text: existing?['transaction_date']?.toString() ??
            DateTime.now().toIso8601String().substring(0, 10));
    final reference = TextEditingController(
        text: existing?['reference_month'] as String? ?? _month);
    final payment = TextEditingController(
        text: existing?['payment_method'] as String? ?? 'PIX');
    final notes = TextEditingController(text: existing?['notes'] as String?);
    int? accountId = existing?['account_id'] as int?;
    int? destinationId = existing?['destination_account_id'] as int?;
    int? cardId = existing?['card_id'] as int?;
    int? categoryId = existing?['category_id'] as int?;
    await _formDialog(
      title: existing == null ? 'Nova movimentação' : 'Editar movimentação',
      fields: <Widget>[
        StatefulBuilder(
            builder: (context, setLocal) => Column(children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                        labelText: 'Entrada, saída ou transferência?',
                        border: OutlineInputBorder()),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'INCOME', child: Text('Entrada')),
                      DropdownMenuItem(value: 'EXPENSE', child: Text('Saída')),
                      DropdownMenuItem(
                          value: 'TRANSFER',
                          child: Text('Transferência entre contas próprias')),
                    ],
                    onChanged: (value) => setLocal(() {
                      type = value!;
                      categoryId = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  _selector(
                      'Conta',
                      accountId,
                      _accounts,
                      (item) => '${item['bank_name']} • ${item['description']}',
                      (value) => accountId = value),
                  if (type == 'TRANSFER') ...<Widget>[
                    const SizedBox(height: 10),
                    _selector(
                        'Conta de destino',
                        destinationId,
                        _accounts,
                        (item) =>
                            '${item['bank_name']} • ${item['description']}',
                        (value) => destinationId = value),
                  ],
                  if (type != 'TRANSFER') ...<Widget>[
                    const SizedBox(height: 10),
                    _selector(
                        'Categoria',
                        categoryId,
                        _categories
                            .where((c) => c['category_type'] == type)
                            .toList(),
                        (item) => item['name'] as String,
                        (value) => categoryId = value),
                  ],
                  if (type == 'EXPENSE') ...<Widget>[
                    const SizedBox(height: 10),
                    _selector(
                        'Cartão (opcional)',
                        cardId,
                        _cards,
                        (item) =>
                            '${item['card_name']} •••• ${item['last_four']}',
                        (value) => cardId = value),
                  ],
                ])),
        _field(txDate, 'Data (AAAA-MM-DD)'),
        _field(reference, 'Mês de referência (AAAA-MM)'),
        _field(description, 'Descrição'),
        _field(counterparty, 'Estabelecimento/origem'),
        _field(amount, 'Valor', number: true),
        _field(payment, 'Forma de pagamento'),
        _field(notes, 'Observação', lines: 2),
      ],
      save: () => _save(
          'transactions',
          <String, dynamic>{
            'transaction_type': type,
            'transaction_date': txDate.text,
            'reference_month': reference.text,
            'description': description.text,
            'counterparty': counterparty.text,
            'amount': amount.text,
            'payment_method': payment.text,
            'account_id': accountId,
            'destination_account_id': destinationId,
            'card_id': cardId,
            'category_id': categoryId,
            'notes': notes.text,
          },
          id: existing?['id'] as int?),
      saveAndContinue: existing != null
          ? null
          : () async {
              await _save('transactions', <String, dynamic>{
                'transaction_type': type,
                'transaction_date': txDate.text,
                'reference_month': reference.text,
                'description': description.text,
                'counterparty': counterparty.text,
                'amount': amount.text,
                'payment_method': payment.text,
                'account_id': accountId,
                'destination_account_id': destinationId,
                'card_id': cardId,
                'category_id': categoryId,
                'notes': notes.text,
              });
              description.clear();
              counterparty.clear();
              amount.clear();
              notes.clear();
            },
    );
  }

  Widget _selector(String label, int? value, List<dynamic> items,
          String Function(dynamic) labeler, ValueChanged<int?> changed) =>
      DropdownButtonFormField<int?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        items: <DropdownMenuItem<int?>>[
          DropdownMenuItem(value: null, child: Text('Selecione $label')),
          ...items.map((item) => DropdownMenuItem(
              value: item['id'] as int,
              child: Text(labeler(item), overflow: TextOverflow.ellipsis))),
        ],
        onChanged: changed,
      );

  Widget _field(TextEditingController controller, String label,
          {bool number = false, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: controller,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          maxLines: lines,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
      );

  Future<void> _formDialog(
      {required String title,
      required List<Widget> fields,
      required Future<void> Function() save,
      Future<void> Function()? saveAndContinue}) async {
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: fields.separatedBy(const SizedBox(height: 10))),
            ),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancelar')),
            if (saveAndContinue != null)
              OutlinedButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        setLocal(() => saving = true);
                        try {
                          await saveAndContinue();
                          _message('Salvo. Informe o próximo lançamento.');
                        } catch (error) {
                          _message(error.toString(), error: true);
                        } finally {
                          if (dialogContext.mounted) {
                            setLocal(() => saving = false);
                          }
                        }
                      },
                icon: const Icon(Icons.playlist_add),
                label: const Text('Salvar e lançar próximo'),
              ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      setLocal(() => saving = true);
                      try {
                        await save();
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        _message('Registro salvo com sucesso.');
                      } catch (error) {
                        _message(error.toString(), error: true);
                        if (dialogContext.mounted) {
                          setLocal(() => saving = false);
                        }
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(saving ? 'Salvando...' : 'Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
              child:
                  Text(text, style: const TextStyle(color: Color(0xFF5F6873)))),
        ),
      );
}

extension _SeparatedWidgets on List<Widget> {
  List<Widget> separatedBy(Widget separator) {
    if (length < 2) return this;
    return <Widget>[
      for (var index = 0; index < length; index++) ...<Widget>[
        if (index > 0) separator,
        this[index],
      ],
    ];
  }
}
