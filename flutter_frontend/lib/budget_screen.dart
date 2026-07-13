import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

typedef ApiUriBuilder = Uri Function(String path);

class BudgetScreen extends StatefulWidget {
  const BudgetScreen(
      {required this.apiUriBuilder, required this.sessionToken, super.key});

  final ApiUriBuilder apiUriBuilder;
  final String sessionToken;

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _dueDateController = TextEditingController();
  final TextEditingController _paymentDateController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  late String _month;
  String _itemType = 'Despesa';
  String _typeFilter = 'Todos';
  String _statusFilter = 'Todos';
  bool _settled = false;
  bool _loading = true;
  bool _saving = false;
  int? _editingId;
  List<BudgetItem> _items = <BudgetItem>[];

  Map<String, String> get _headers => <String, String>{
        'authorization': 'Bearer ${widget.sessionToken}',
        'content-type': 'application/json; charset=utf-8',
      };

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _loadBudget();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _dueDateController.dispose();
    _paymentDateController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _monthOptions {
    final int year = DateTime.now().year;
    return List<String>.generate(
        12, (int index) => '$year-${(index + 1).toString().padLeft(2, '0')}');
  }

  List<BudgetItem> get _filteredItems {
    final String query = _searchController.text.trim().toUpperCase();
    return _items.where((BudgetItem item) {
      final bool matchesDescription =
          query.isEmpty || item.description.contains(query);
      final bool matchesType =
          _typeFilter == 'Todos' || item.itemType == _typeFilter;
      final bool matchesStatus = _statusFilter == 'Todos' ||
          (_statusFilter == 'Quitado' && item.settled) ||
          (_statusFilter == 'Pendente' && !item.settled);
      return matchesDescription && matchesType && matchesStatus;
    }).toList();
  }

  double get _revenueTotal => _items
      .where((BudgetItem item) => item.itemType == 'Receita')
      .fold<double>(0, (double total, BudgetItem item) => total + item.amount);

  double get _expenseTotal => _items
      .where((BudgetItem item) => item.itemType == 'Despesa')
      .fold<double>(0, (double total, BudgetItem item) => total + item.amount);

  double get _pendingTotal => _items
      .where((BudgetItem item) => item.itemType == 'Despesa' && !item.settled)
      .fold<double>(0, (double total, BudgetItem item) => total + item.amount);

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw const BudgetApiException(
          'O backend retornou uma resposta inválida.');
    }
  }

  Future<void> _loadBudget() async {
    setState(() => _loading = true);
    try {
      final Uri uri = widget
          .apiUriBuilder('/api/budget')
          .replace(queryParameters: <String, String>{'month': _month});
      final http.Response response = await http.get(uri, headers: _headers);
      final Map<String, dynamic> body = await _decode(response);
      if (response.statusCode != 200 || body['ok'] != true) {
        throw BudgetApiException((body['message'] as String?) ??
            'Não foi possível carregar o orçamento.');
      }
      final List<dynamic> rawItems =
          (body['items'] as List<dynamic>?) ?? <dynamic>[];
      if (!mounted) return;
      setState(() {
        _items = rawItems
            .map((dynamic item) =>
                BudgetItem.fromJson(item as Map<String, dynamic>))
            .toList();
      });
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveItem() async {
    FocusScope.of(context).unfocus();
    final String? validationMessage = _validateForm();
    if (validationMessage != null) {
      _showMessage(validationMessage, error: true);
      return;
    }
    setState(() => _saving = true);
    final Map<String, dynamic> payload = <String, dynamic>{
      'reference_month': _month,
      'item_type': _itemType,
      'description': _descriptionController.text.trim().toUpperCase(),
      'amount_text': _amountController.text.trim(),
      'due_date': _dateToIso(_dueDateController.text),
      'payment_date': _paymentDateController.text.isEmpty
          ? null
          : _dateToIso(_paymentDateController.text),
      'settled': _settled,
    };
    try {
      final bool editing = _editingId != null;
      final Uri uri = widget
          .apiUriBuilder(editing ? '/api/budget/$_editingId' : '/api/budget');
      final http.Response response = editing
          ? await http.put(uri, headers: _headers, body: jsonEncode(payload))
          : await http.post(uri, headers: _headers, body: jsonEncode(payload));
      final Map<String, dynamic> body = await _decode(response);
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          body['ok'] != true) {
        throw BudgetApiException((body['message'] as String?) ??
            'Não foi possível salvar o lançamento.');
      }
      if (!mounted) return;
      _clearForm();
      _showMessage(editing ? 'Lançamento alterado.' : 'Lançamento salvo.');
      await _loadBudget();
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeStatus(BudgetItem item, bool settled) async {
    try {
      final http.Response response = await http.patch(
        widget.apiUriBuilder('/api/budget/${item.id}/status'),
        headers: _headers,
        body: jsonEncode(<String, bool>{'settled': settled}),
      );
      final Map<String, dynamic> body = await _decode(response);
      if (response.statusCode != 200 || body['ok'] != true) {
        throw BudgetApiException((body['message'] as String?) ??
            'Não foi possível alterar o status.');
      }
      await _loadBudget();
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error), error: true);
    }
  }

  Future<void> _deleteItem(BudgetItem item) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: Text('“${item.description}” será removido permanentemente.'),
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
    if (confirmed != true || !mounted) return;
    try {
      final http.Response response = await http.delete(
        widget.apiUriBuilder('/api/budget/${item.id}'),
        headers: _headers,
      );
      final Map<String, dynamic> body = await _decode(response);
      if (response.statusCode != 200 || body['ok'] != true) {
        throw BudgetApiException((body['message'] as String?) ??
            'Não foi possível excluir o lançamento.');
      }
      if (_editingId == item.id) _clearForm();
      _showMessage('Lançamento excluído.');
      await _loadBudget();
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error), error: true);
    }
  }

  void _startEditing(BudgetItem item) {
    setState(() {
      _editingId = item.id;
      _itemType = item.itemType;
      _descriptionController.text = item.description;
      _amountController.text = item.amountText;
      _dueDateController.text = _dateToDisplay(item.dueDate);
      _paymentDateController.text =
          item.paymentDate.isEmpty ? '' : _dateToDisplay(item.paymentDate);
      _settled = item.settled;
    });
  }

  void _clearForm() {
    setState(() {
      _editingId = null;
      _itemType = 'Despesa';
      _descriptionController.clear();
      _amountController.clear();
      _dueDateController.clear();
      _paymentDateController.clear();
      _settled = false;
    });
  }

  String? _validateForm() {
    if (_descriptionController.text.trim().isEmpty) {
      return 'Informe a descrição.';
    }
    if (_parseAmount(_amountController.text) <= 0) {
      return 'Informe um valor maior que zero.';
    }
    if (_dateToIso(_dueDateController.text) == null) {
      return 'Informe uma data de vencimento válida.';
    }
    if (_paymentDateController.text.isNotEmpty &&
        _dateToIso(_paymentDateController.text) == null) {
      return 'Informe uma data de pagamento válida.';
    }
    if (_itemType == 'Despesa' &&
        _settled &&
        _paymentDateController.text.isEmpty) {
      return 'Informe a data do pagamento.';
    }
    return null;
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final DateTime now = DateTime.now();
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _displayToDate(controller.text) ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
      locale: const Locale('pt', 'BR'),
    );
    if (selected != null) {
      controller.text =
          '${selected.day.toString().padLeft(2, '0')}/${selected.month.toString().padLeft(2, '0')}/${selected.year}';
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              error ? const Color(0xFFB42332) : const Color(0xFF167A4B),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Meu orçamento',
                style: TextStyle(fontWeight: FontWeight.w800)),
            Text('Receitas, despesas e vencimentos',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: <Widget>[
          IconButton(
              tooltip: 'Atualizar',
              onPressed: _loading ? null : _loadBudget,
              icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 920;
            return RefreshIndicator(
              onRefresh: _loadBudget,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1240),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildMonthHeader(),
                        const SizedBox(height: 12),
                        _buildMetrics(),
                        const SizedBox(height: 12),
                        _buildFilters(),
                        const SizedBox(height: 12),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              SizedBox(width: 340, child: _buildForm()),
                              const SizedBox(width: 12),
                              Expanded(child: _buildEntries()),
                            ],
                          )
                        else ...<Widget>[
                          _buildForm(),
                          const SizedBox(height: 12),
                          _buildEntries(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMonthHeader() {
    return _BudgetPanel(
      accent: const Color(0xFFD97706),
      child: Row(
        children: <Widget>[
          const Icon(Icons.calendar_month_outlined, color: Color(0xFFD97706)),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Planejamento mensal',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text('Os dados permanecem salvos no backend Python.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF5F6873))),
              ],
            ),
          ),
          SizedBox(
            width: 175,
            child: DropdownButtonFormField<String>(
              key: ValueKey<String>(_month),
              initialValue: _month,
              decoration: const InputDecoration(
                  labelText: 'Mês',
                  isDense: true,
                  border: OutlineInputBorder()),
              items: _monthOptions
                  .map((String value) => DropdownMenuItem<String>(
                      value: value, child: Text(_monthLabel(value))))
                  .toList(),
              onChanged: (String? value) {
                if (value == null || value == _month) return;
                setState(() => _month = value);
                _clearForm();
                _loadBudget();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics() {
    final double balance = _revenueTotal - _expenseTotal;
    final List<Widget> cards = <Widget>[
      _MetricCard(
          title: 'Receitas',
          value: _formatCurrency(_revenueTotal),
          icon: Icons.trending_up,
          accent: const Color(0xFF167A4B)),
      _MetricCard(
          title: 'Despesas',
          value: _formatCurrency(_expenseTotal),
          icon: Icons.trending_down,
          accent: const Color(0xFFB42332)),
      _MetricCard(
        title: 'Saldo previsto',
        value: _formatCurrency(balance),
        icon: Icons.account_balance_wallet_outlined,
        accent:
            balance >= 0 ? const Color(0xFF167A4B) : const Color(0xFFB42332),
      ),
      _MetricCard(
          title: 'Falta pagar',
          value: _formatCurrency(_pendingTotal),
          icon: Icons.event_available_outlined,
          accent: const Color(0xFFD97706)),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        return GridView.count(
          crossAxisCount: columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: columns == 1 ? 4.2 : 2.4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cards,
        );
      },
    );
  }

  Widget _buildFilters() {
    return _BudgetPanel(
      accent: const Color(0xFF4F8CFF),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.filter_alt_outlined,
                  size: 19, color: Color(0xFF4F8CFF)),
              SizedBox(width: 5),
              Text('Filtros', style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          SizedBox(
            width: 210,
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Descrição',
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder()),
            ),
          ),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              initialValue: _typeFilter,
              decoration: const InputDecoration(
                  labelText: 'Tipo',
                  isDense: true,
                  border: OutlineInputBorder()),
              items: const <String>['Todos', 'Receita', 'Despesa']
                  .map((String value) => DropdownMenuItem<String>(
                      value: value, child: Text(value)))
                  .toList(),
              onChanged: (String? value) =>
                  setState(() => _typeFilter = value ?? 'Todos'),
            ),
          ),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              initialValue: _statusFilter,
              decoration: const InputDecoration(
                  labelText: 'Status',
                  isDense: true,
                  border: OutlineInputBorder()),
              items: const <String>['Todos', 'Quitado', 'Pendente']
                  .map((String value) => DropdownMenuItem<String>(
                      value: value, child: Text(value)))
                  .toList(),
              onChanged: (String? value) =>
                  setState(() => _statusFilter = value ?? 'Todos'),
            ),
          ),
          Text('${_filteredItems.length} lançamento(s)',
              style: const TextStyle(color: Color(0xFF5F6873), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return _BudgetPanel(
      accent: const Color(0xFFD97706),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(_editingId == null ? 'Novo lançamento' : 'Alterar lançamento',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey<String>(_itemType),
            initialValue: _itemType,
            decoration: const InputDecoration(
                labelText: 'Tipo', border: OutlineInputBorder()),
            items: const <String>['Receita', 'Despesa']
                .map((String value) =>
                    DropdownMenuItem<String>(value: value, child: Text(value)))
                .toList(),
            onChanged: (String? value) =>
                setState(() => _itemType = value ?? 'Despesa'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descriptionController,
            maxLength: 15,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: <TextInputFormatter>[UpperCaseTextFormatter()],
            decoration: const InputDecoration(
                labelText: 'Descrição',
                border: OutlineInputBorder(),
                counterText: ''),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
            decoration: const InputDecoration(
                labelText: 'Valor',
                prefixText: 'R\$ ',
                hintText: '0,00',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          _dateField(_dueDateController, 'Vencimento / data'),
          const SizedBox(height: 10),
          _dateField(_paymentDateController, 'Data do pagamento',
              isRequired: false),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _settled,
            title: Text(_itemType == 'Receita' ? 'Recebido' : 'Pago'),
            onChanged: (bool? value) =>
                setState(() => _settled = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          Row(
            children: <Widget>[
              if (_editingId != null) ...<Widget>[
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _saving ? null : _clearForm,
                        icon: const Icon(Icons.close),
                        label: const Text('Cancelar'))),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveItem,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_editingId == null
                          ? Icons.save_outlined
                          : Icons.check),
                  label:
                      Text(_editingId == null ? 'Salvar' : 'Salvar alterações'),
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateField(TextEditingController controller, String label,
      {bool isRequired = true}) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: () => _pickDate(controller),
      decoration: InputDecoration(
        labelText: label,
        hintText: isRequired ? 'dd/mm/aaaa' : 'Opcional',
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!isRequired && controller.text.isNotEmpty)
              IconButton(
                  onPressed: () => setState(controller.clear),
                  icon: const Icon(Icons.close)),
            const Icon(Icons.calendar_today_outlined),
            const SizedBox(width: 12),
          ],
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildEntries() {
    return _BudgetPanel(
      accent: const Color(0xFF1F4E79),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                  child: Text('Lançamentos do mês',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800))),
              Text(_monthLabel(_month),
                  style:
                      const TextStyle(color: Color(0xFF5F6873), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()))
          else if (_filteredItems.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                children: <Widget>[
                  Icon(Icons.inbox_outlined,
                      size: 38, color: Color(0xFF8A8175)),
                  SizedBox(height: 8),
                  Text('Nenhum lançamento encontrado.',
                      style: TextStyle(color: Color(0xFF5F6873))),
                ],
              ),
            )
          else
            ..._filteredItems.map(_buildEntry),
        ],
      ),
    );
  }

  Widget _buildEntry(BudgetItem item) {
    final bool revenue = item.itemType == 'Receita';
    final Color accent =
        revenue ? const Color(0xFF167A4B) : const Color(0xFFB42332);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border(
            left: BorderSide(
                width: 4,
                color: item.settled ? const Color(0xFF667085) : accent),
            top: const BorderSide(color: Color(0xFFD8DEE6)),
            right: const BorderSide(color: Color(0xFFD8DEE6)),
            bottom: const BorderSide(color: Color(0xFFD8DEE6))),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(item.description,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(item.itemType,
                      style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'Vencimento: ${_dateToDisplay(item.dueDate)}${item.paymentDate.isEmpty ? '' : ' • Pagamento: ${_dateToDisplay(item.paymentDate)}'}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF5F6873)),
              ),
            ],
          );
          final Widget actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Checkbox(
                  value: item.settled,
                  onChanged: (bool? value) =>
                      _changeStatus(item, value ?? false),
                  visualDensity: VisualDensity.compact),
              Text(item.statusLabel, style: const TextStyle(fontSize: 10)),
              IconButton(
                  tooltip: 'Editar',
                  onPressed: () => _startEditing(item),
                  icon: const Icon(Icons.edit_outlined, size: 19)),
              IconButton(
                  tooltip: 'Excluir',
                  onPressed: () => _deleteItem(item),
                  color: const Color(0xFFB42332),
                  icon: const Icon(Icons.delete_outline, size: 19)),
            ],
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                details,
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Text(_formatCurrency(item.amount),
                        style: TextStyle(
                            color: accent, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    actions,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: details),
              const SizedBox(width: 8),
              Text(_formatCurrency(item.amount),
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _BudgetPanel extends StatelessWidget {
  const _BudgetPanel({required this.child, required this.accent});

  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(
            left: BorderSide(width: 3, color: accent),
            top: const BorderSide(color: Color(0xFFD8DEE6)),
            right: const BorderSide(color: Color(0xFFD8DEE6)),
            bottom: const BorderSide(color: Color(0xFFD8DEE6))),
        boxShadow: const <BoxShadow>[
          BoxShadow(
              color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 5))
        ],
      ),
      child: child,
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.title,
      required this.value,
      required this.icon,
      required this.accent});

  final String title;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFD8DEE6))),
      child: Row(
        children: <Widget>[
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: accent, size: 21)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: const TextStyle(
                        color: Color(0xFF5F6873), fontSize: 11)),
                Text(value,
                    style: TextStyle(
                        color: accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BudgetItem {
  BudgetItem(
      {required this.id,
      required this.itemType,
      required this.description,
      required this.amountText,
      required this.dueDate,
      required this.paymentDate,
      required this.settled});

  factory BudgetItem.fromJson(Map<String, dynamic> json) => BudgetItem(
        id: (json['id'] as num).toInt(),
        itemType: (json['item_type'] as String?) ?? 'Despesa',
        description: ((json['description'] as String?) ?? '').toUpperCase(),
        amountText: (json['amount_text'] as String?) ?? '0,00',
        dueDate: (json['due_date'] as String?) ?? '',
        paymentDate: (json['payment_date'] as String?) ?? '',
        settled: (json['settled'] as bool?) ?? false,
      );

  final int id;
  final String itemType;
  final String description;
  final String amountText;
  final String dueDate;
  final String paymentDate;
  final bool settled;

  double get amount => _parseAmount(amountText);

  String get statusLabel {
    if (itemType == 'Receita') return settled ? 'Recebido' : 'Não recebido';
    return settled ? 'Pago' : 'Falta pagar';
  }
}

class BudgetApiException implements Exception {
  const BudgetApiException(this.message);
  final String message;
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(
          text: newValue.text.toUpperCase(), selection: newValue.selection);
}

const List<String> _monthNames = <String>[
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro'
];

String _messageFor(Object error) => error is BudgetApiException
    ? error.message
    : 'Não foi possível conectar ao backend Python.';

double _parseAmount(String value) {
  String cleaned = value.replaceAll('R\$', '').replaceAll(' ', '');
  if (cleaned.contains(',')) {
    cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(cleaned) ?? 0;
}

String _formatCurrency(double value) {
  final bool negative = value < 0;
  final String fixed = value.abs().toStringAsFixed(2);
  final List<String> parts = fixed.split('.');
  final StringBuffer whole = StringBuffer();
  for (int index = 0; index < parts[0].length; index++) {
    if (index > 0 && (parts[0].length - index) % 3 == 0) whole.write('.');
    whole.write(parts[0][index]);
  }
  return '${negative ? '-' : ''}R\$ $whole,${parts[1]}';
}

String _monthLabel(String value) {
  final List<String> parts = value.split('-');
  final int month = parts.length == 2 ? int.tryParse(parts[1]) ?? 0 : 0;
  return month >= 1 && month <= 12
      ? '${_monthNames[month - 1]} ${parts[0]}'
      : value;
}

DateTime? _displayToDate(String value) {
  final List<String> parts = value.split('/');
  if (parts.length != 3) return null;
  final int? day = int.tryParse(parts[0]);
  final int? month = int.tryParse(parts[1]);
  final int? year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  final DateTime parsed = DateTime(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day
      ? parsed
      : null;
}

String? _dateToIso(String value) {
  final DateTime? parsed = _displayToDate(value);
  if (parsed == null) return null;
  return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
}

String _dateToDisplay(String value) {
  final List<String> parts = value.split('-');
  return parts.length == 3 ? '${parts[2]}/${parts[1]}/${parts[0]}' : value;
}
