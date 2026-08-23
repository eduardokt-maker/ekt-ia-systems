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
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  bool _loading = true;
  String _error = '', _type = 'Todos';
  int _tab = 0;
  int? _category;
  List<Map<String, dynamic>> _items = const [], _categories = const [];
  Map<String, dynamic> _summary = const {};

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
          widget.apiUriBuilder('/api/banking-santander'),
          timeout: const Duration(seconds: 90));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw ApiFailure(body['message'] as String? ??
            'Não foi possível carregar os lançamentos Santander.');
      }
      if (!mounted) return;
      setState(() {
        _items = (body['outflows'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _categories = (body['categories'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _summary = Map<String, dynamic>.from(body['summary'] as Map);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _active(Map<String, dynamic> x) =>
      x['active'] == true || x['active'] == 1;
  List<String> get _types =>
      <String>{'Todos', ..._items.map((x) => '${x['type']}')}.toList();
  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return _items.where((x) {
      final text =
          '${x['destination']} ${x['description']} ${x['document']} ${x['category_name'] ?? ''}'
              .toLowerCase();
      return (_type == 'Todos' || x['type'] == _type) &&
          (_category == null ||
              (_category == -1
                  ? x['category_id'] == null
                  : x['category_id'] == _category)) &&
          (q.isEmpty || text.contains(q));
    }).toList();
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

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
          context: context,
          builder: (c) =>
              AlertDialog(title: Text(title), content: Text(text), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Confirmar'))
              ])) ??
      false;

  Future<void> _saveOutflow([Map<String, dynamic>? current]) async {
    final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _OutflowDialog(
            current: current, categories: _categories.where(_active).toList()));
    if (data == null) return;
    try {
      final id = current?['id'];
      final response = id == null
          ? await apiClient.post(widget.apiUriBuilder('/api/banking-santander'),
              body: data)
          : await apiClient.put(
              widget.apiUriBuilder('/api/banking-santander/outflows/$id'),
              body: data);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 ||
          response.statusCode > 299 ||
          body['ok'] != true) {
        throw ApiFailure(
            body['message'] as String? ?? 'Não foi possível salvar.');
      }
      await _load();
      _message(id == null ? 'Despesa incluída.' : 'Despesa atualizada.');
    } catch (e) {
      _message(e.toString(), error: true);
    }
  }

  Future<void> _deleteOutflow(Map<String, dynamic> item) async {
    if (!await _confirm('Excluir lançamento?',
        '${item['destination']} • ${_money.format(item['amount'])}')) {
      return;
    }
    try {
      final r = await apiClient.delete(widget
          .apiUriBuilder('/api/banking-santander/outflows/${item['id']}'));
      if (r.statusCode != 200) {
        throw const ApiFailure('Não foi possível excluir.');
      }
      await _load();
      _message('Lançamento excluído.');
    } catch (e) {
      _message(e.toString(), error: true);
    }
  }

  Future<void> _saveCategory([Map<String, dynamic>? current]) async {
    final data = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => _CategoryDialog(current: current));
    if (data == null) return;
    try {
      final id = current?['id'];
      final r = id == null
          ? await apiClient.post(
              widget.apiUriBuilder('/api/banking-santander/categories'),
              body: data)
          : await apiClient.put(
              widget.apiUriBuilder('/api/banking-santander/categories/$id'),
              body: data);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode < 200 || r.statusCode > 299 || body['ok'] != true) {
        throw ApiFailure(body['message'] as String? ??
            'Não foi possível salvar a categoria.');
      }
      await _load();
      _message(id == null ? 'Categoria criada.' : 'Categoria atualizada.');
    } catch (e) {
      _message(e.toString(), error: true);
    }
  }

  Future<void> _deleteCategory(Map<String, dynamic> item) async {
    if (!await _confirm('Excluir categoria?',
        'Os lançamentos vinculados ficarão sem categoria.')) {
      return;
    }
    try {
      final r = await apiClient.delete(widget
          .apiUriBuilder('/api/banking-santander/categories/${item['id']}'));
      if (r.statusCode != 200) {
        throw const ApiFailure('Não foi possível excluir.');
      }
      await _load();
      _message('Categoria excluída.');
    } catch (e) {
      _message(e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Despesas Santander',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  Text('CRUD do Extrato Consolidado Inteligente',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w400))
                ]),
            actions: [
              IconButton(
                  tooltip: 'Atualizar',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh))
            ],
            bottom: PreferredSize(
                preferredSize: const Size.fromHeight(66),
                child: NavigationBar(
                    height: 66,
                    selectedIndex: _tab,
                    onDestinationSelected: (v) => setState(() => _tab = v),
                    destinations: const [
                      NavigationDestination(
                          icon: Icon(Icons.receipt_long_outlined),
                          selectedIcon: Icon(Icons.receipt_long),
                          label: 'Lançamentos'),
                      NavigationDestination(
                          icon: Icon(Icons.category_outlined),
                          selectedIcon: Icon(Icons.category),
                          label: 'Categorias')
                    ]))),
        floatingActionButton: _loading
            ? null
            : FloatingActionButton.extended(
                onPressed: _tab == 0 ? _saveOutflow : _saveCategory,
                icon: const Icon(Icons.add),
                label: Text(_tab == 0 ? 'Nova despesa' : 'Nova categoria')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.cloud_off_outlined, size: 48),
                          const SizedBox(height: 12),
                          Text(_error, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tentar novamente'))
                        ])))
                : (_tab == 0 ? _outflowsView() : _categoriesView()),
      );

  Widget _outflowsView() {
    final list = _filtered;
    final total =
        list.fold<double>(0, (sum, x) => sum + (x['amount'] as num).toDouble());
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            child: const ListTile(
                                leading: Icon(Icons.account_balance),
                                title: Text('Estrutura Santander',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w900)),
                                subtitle: Text(
                                    'O PDF original permanece preservado. Cada saída importada vira um registro independente, editável e protegido contra duplicação.'))),
                        const SizedBox(height: 12),
                        Wrap(spacing: 10, runSpacing: 10, children: [
                          _metric(
                              'Total de saídas',
                              _money.format(_summary['total'] ?? 0),
                              Icons.south_east,
                              const Color(0xFFB42332)),
                          _metric('Lançamentos', '${_summary['count'] ?? 0}',
                              Icons.list_alt, const Color(0xFF315F8C)),
                          _metric('Resultado do filtro', _money.format(total),
                              Icons.filter_alt, const Color(0xFF0B766E))
                        ]),
                        const SizedBox(height: 14),
                        LayoutBuilder(builder: (c, box) {
                          final w = box.maxWidth < 720
                              ? box.maxWidth
                              : (box.maxWidth - 20) / 3;
                          return Wrap(spacing: 10, runSpacing: 10, children: [
                            SizedBox(
                                width: w,
                                child: TextField(
                                    controller: _search,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                        prefixIcon: Icon(Icons.search),
                                        labelText:
                                            'Pesquisar recebedor ou descrição',
                                        border: OutlineInputBorder()))),
                            SizedBox(
                                width: w,
                                child: DropdownButtonFormField<String>(
                                    initialValue: _type,
                                    decoration: const InputDecoration(
                                        labelText: 'Tipo de saída',
                                        border: OutlineInputBorder()),
                                    items: _types
                                        .map((v) => DropdownMenuItem(
                                            value: v, child: Text(v)))
                                        .toList(),
                                    onChanged: (v) =>
                                        setState(() => _type = v ?? 'Todos'))),
                            SizedBox(
                                width: w,
                                child: DropdownButtonFormField<int?>(
                                    initialValue: _category,
                                    decoration: const InputDecoration(
                                        labelText: 'Categoria',
                                        border: OutlineInputBorder()),
                                    items: [
                                      const DropdownMenuItem<int?>(
                                          value: null, child: Text('Todas')),
                                      const DropdownMenuItem<int?>(
                                          value: -1,
                                          child: Text('Sem categoria')),
                                      ..._categories.where(_active).map((x) =>
                                          DropdownMenuItem<int?>(
                                              value: x['id'] as int,
                                              child: Text('${x['name']}')))
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _category = v)))
                          ]);
                        }),
                        const SizedBox(height: 16),
                        Text('${list.length} despesa(s)',
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        if (list.isEmpty)
                          const Card(
                              child: Padding(
                                  padding: EdgeInsets.all(26),
                                  child: Text('Nenhuma despesa encontrada.')))
                        else
                          ...list.map(_outflowCard),
                      ])))
        ]);
  }

  Widget _categoriesView() =>
      ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Categorias de despesas',
                          style: TextStyle(
                              fontSize: 23, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 5),
                      const Text(
                          'Cadastre as categorias que poderão ser escolhidas nos lançamentos Santander.'),
                      const SizedBox(height: 14),
                      ..._categories.map((x) => Card(
                          child: ListTile(
                              leading: CircleAvatar(
                                  child: Icon(_active(x)
                                      ? Icons.category_outlined
                                      : Icons.visibility_off_outlined)),
                              title: Text('${x['name']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              subtitle: Text('${x['description']}'.isEmpty
                                  ? (_active(x)
                                      ? 'Categoria ativa'
                                      : 'Categoria inativa')
                                  : '${x['description']}'),
                              onTap: () => _saveCategory(x),
                              trailing: PopupMenuButton<String>(
                                  onSelected: (v) => v == 'edit'
                                      ? _saveCategory(x)
                                      : _deleteCategory(x),
                                  itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Editar')),
                                        PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Excluir'))
                                      ]))))
                    ])))
      ]);

  Widget _metric(String label, String value, IconData icon, Color color) =>
      SizedBox(
          width: 250,
          child: Card(
              child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Row(children: [
                    CircleAvatar(
                        backgroundColor: color.withValues(alpha: .12),
                        foregroundColor: color,
                        child: Icon(icon)),
                    const SizedBox(width: 11),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(label, style: const TextStyle(fontSize: 12)),
                          Text(value,
                              style: const TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w900))
                        ]))
                  ]))));
  Widget _outflowCard(Map<String, dynamic> x) => Card(
      child: ListTile(
          leading: CircleAvatar(child: Icon(_icon('${x['type']}'))),
          title: Text('${x['destination']}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
              '${x['transaction_date']} • ${x['type']} • ${x['category_name'] ?? 'Sem categoria'}\n${x['is_manual'] == true ? 'Lançamento manual' : 'Importado de ${x['filename']}'}'),
          isThreeLine: true,
          onTap: () => _saveOutflow(x),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_money.format(x['amount']),
                style: const TextStyle(
                    color: Color(0xFFB42332), fontWeight: FontWeight.w900)),
            PopupMenuButton<String>(
                onSelected: (v) =>
                    v == 'edit' ? _saveOutflow(x) : _deleteOutflow(x),
                itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'edit', child: Text('Editar e categorizar')),
                      PopupMenuItem(value: 'delete', child: Text('Excluir'))
                    ])
          ])));
  IconData _icon(String t) {
    if (t.contains('Cartão')) return Icons.credit_card;
    if (t.contains('Pix')) return Icons.pix;
    if (t.contains('Boleto')) return Icons.receipt_long;
    if (t.contains('IOF') || t.contains('Juros')) return Icons.percent;
    return Icons.south_east;
  }
}

class _OutflowDialog extends StatefulWidget {
  const _OutflowDialog({required this.current, required this.categories});
  final Map<String, dynamic>? current;
  final List<Map<String, dynamic>> categories;
  @override
  State<_OutflowDialog> createState() => _OutflowDialogState();
}

class _OutflowDialogState extends State<_OutflowDialog> {
  static const types = [
    'Cartão de débito',
    'Pix enviado',
    'Boleto',
    'Débito automático',
    'Tarifa',
    'Juros',
    'IOF',
    'Seguro',
    'Outras saídas'
  ];
  late final TextEditingController date,
      destination,
      amount,
      description,
      document;
  late String type;
  int? category;
  @override
  void initState() {
    super.initState();
    final x = widget.current;
    date = TextEditingController(text: '${x?['transaction_date'] ?? ''}');
    destination = TextEditingController(text: '${x?['destination'] ?? ''}');
    amount = TextEditingController(text: '${x?['amount'] ?? ''}');
    description = TextEditingController(text: '${x?['description'] ?? ''}');
    document = TextEditingController(text: '${x?['document'] ?? ''}');
    type = '${x?['type'] ?? 'Cartão de débito'}';
    if (!types.contains(type)) type = 'Outras saídas';
    category = x?['category_id'] as int?;
  }

  @override
  void dispose() {
    date.dispose();
    destination.dispose();
    amount.dispose();
    description.dispose();
    document.dispose();
    super.dispose();
  }

  InputDecoration field(String label, [String? hint]) => InputDecoration(
      labelText: label, hintText: hint, border: const OutlineInputBorder());
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.current == null
              ? 'Nova despesa Santander'
              : 'Editar despesa Santander'),
          content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: date,
                    decoration: field('Data', 'DD/MM ou AAAA-MM-DD')),
                const SizedBox(height: 12),
                TextField(
                    controller: destination, decoration: field('Quem recebeu')),
                const SizedBox(height: 12),
                TextField(
                    controller: amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: field('Valor')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: field('Tipo'),
                    items: types
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => setState(() => type = v ?? type)),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                    initialValue: category,
                    decoration: field('Categoria'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Sem categoria')),
                      ...widget.categories.map((x) => DropdownMenuItem<int?>(
                          value: x['id'] as int, child: Text('${x['name']}')))
                    ],
                    onChanged: (v) => setState(() => category = v)),
                const SizedBox(height: 12),
                TextField(
                    controller: description, decoration: field('Descrição')),
                const SizedBox(height: 12),
                TextField(controller: document, decoration: field('Documento'))
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton.icon(
                onPressed: () => Navigator.pop(context, {
                      'transaction_date': date.text.trim(),
                      'posting_date': date.text.trim(),
                      'destination': destination.text.trim(),
                      'amount': amount.text.trim(),
                      'transaction_type': type,
                      'category_id': category,
                      'description': description.text.trim(),
                      'document': document.text.trim()
                    }),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar'))
          ]);
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.current});
  final Map<String, dynamic>? current;
  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController name, description;
  late bool active;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: '${widget.current?['name'] ?? ''}');
    description =
        TextEditingController(text: '${widget.current?['description'] ?? ''}');
    active = widget.current == null ||
        widget.current?['active'] == true ||
        widget.current?['active'] == 1;
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(
              widget.current == null ? 'Nova categoria' : 'Editar categoria'),
          content: SizedBox(
              width: 480,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'Nome da categoria',
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                    controller: description,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Descrição', border: OutlineInputBorder())),
                SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Categoria ativa'),
                    value: active,
                    onChanged: (v) => setState(() => active = v))
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(context, {
                      'name': name.text.trim(),
                      'description': description.text.trim(),
                      'active': active
                    }),
                child: const Text('Salvar'))
          ]);
}
