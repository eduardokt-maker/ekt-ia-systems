import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_client.dart';

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

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
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
          if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
        },
      );
      final response = await apiClient.get(uri);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
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
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiFailure(
          body['message'] as String? ?? 'Não foi possível salvar.');
    }
    await _load();
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
                      ],
                    ),
            ),
          ],
        ),
      );

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
                  const Text('Resumo financeiro do período',
                      style:
                          TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
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
                          'R\$ ${_summary['result_text'] ?? '0,00'}',
                          Icons.balance,
                          const Color(0xFF1F4E79)),
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
            '${item['transaction_date']} • $label • ${item['category_name'] ?? 'Sem categoria'}\n${item['account_name'] ?? item['card_name'] ?? ''}'),
        isThreeLine: true,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text('R\$ ${item['amount_text']}',
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
