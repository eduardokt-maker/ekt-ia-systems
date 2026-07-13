import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

typedef ApiUriBuilder = Uri Function(String path);

const Color _budgetNavy = Color(0xFF6E553B);
const Color _budgetBlue = Color(0xFFB96F38);
const Color _budgetSky = Color(0xFFF2E2CA);
const Color _budgetCanvas = Color(0xFFF6F0E5);
const Color _budgetPanel = Color(0xFFFFFAF2);
const Color _budgetField = Color(0xFFF1E6D6);
const Color _budgetInk = Color(0xFF342A20);
const Color _budgetMuted = Color(0xFF776B5D);
const Color _budgetGreen = Color(0xFF6F8A67);
const Color _budgetRed = Color(0xFFB15F57);
const Color _budgetAmber = Color(0xFFC9923E);

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
      backgroundColor: _budgetCanvas,
      appBar: AppBar(
        backgroundColor: _budgetCanvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _budgetInk,
        iconTheme: const IconThemeData(color: _budgetInk),
        title: const Text('Meu orçamento',
            style: TextStyle(
                color: _budgetInk, fontWeight: FontWeight.w800, fontSize: 20)),
        actions: <Widget>[
          IconButton(
              tooltip: 'Atualizar',
              onPressed: _loading ? null : _loadBudget,
              icon: const Icon(Icons.sync_rounded)),
          const SizedBox(width: 12),
        ],
      ),
      body: Theme(
        data: ThemeData.light(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(
              seedColor: _budgetBlue, brightness: Brightness.light),
          textSelectionTheme:
              const TextSelectionThemeData(cursorColor: _budgetBlue),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool wide = constraints.maxWidth >= 980;
              final double horizontalPadding =
                  constraints.maxWidth < 600 ? 12 : 24;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            horizontalPadding, 8, horizontalPadding, 0),
                        child: _buildMonthHeader(),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: horizontalPadding),
                        child: _buildMetrics(),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _loadBudget,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                                horizontalPadding, 4, horizontalPadding, 32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                _buildFilters(),
                                const SizedBox(height: 18),
                                if (wide)
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      SizedBox(width: 370, child: _buildForm()),
                                      const SizedBox(width: 18),
                                      Expanded(child: _buildEntries()),
                                    ],
                                  )
                                else ...<Widget>[
                                  _buildForm(),
                                  const SizedBox(height: 18),
                                  _buildEntries(),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMonthHeader() {
    final double balance = _revenueTotal - _expenseTotal;
    final double useRatio = _revenueTotal <= 0
        ? 0
        : (_expenseTotal / _revenueTotal).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFFFAF1), Color(0xFFE9D7BB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
              color: Color(0x307A5A3A), blurRadius: 28, offset: Offset(0, 14))
        ],
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < 680;
          final Widget introduction = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: const Color(0xFFE7D3B5),
                    borderRadius: BorderRadius.circular(999)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.account_balance_wallet_rounded,
                        size: 16, color: _budgetNavy),
                    SizedBox(width: 6),
                    Text('EKT IA SYSTEMS',
                        style: TextStyle(
                            color: _budgetNavy,
                            fontSize: 11,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text('PLANEJAMENTO\nMENSAL',
                  style: TextStyle(
                      color: _budgetInk,
                      fontSize: 31,
                      height: 1.02,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4)),
              const SizedBox(height: 10),
              Text(_monthLabel(_month),
                  style: const TextStyle(
                      color: _budgetMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                balance >= 0
                    ? 'Seu orçamento está com saldo previsto positivo.'
                    : 'As despesas previstas ultrapassam as receitas.',
                style: const TextStyle(
                    color: _budgetNavy, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: useRatio,
                  minHeight: 7,
                  backgroundColor: const Color(0xFFD8C3A4),
                  valueColor: AlwaysStoppedAnimation<Color>(
                      useRatio > 0.85 ? _budgetRed : _budgetGreen),
                ),
              ),
              const SizedBox(height: 7),
              Text('${(useRatio * 100).round()}% das receitas comprometidas',
                  style: const TextStyle(color: _budgetMuted, fontSize: 11)),
            ],
          );
          final Widget monthPicker = Container(
            width: compact ? double.infinity : 205,
            padding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
            decoration: BoxDecoration(
                color: const Color(0xFFFFFBF5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD6BE9A)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Color(0x1F6E553B), blurRadius: 16)
                ]),
            child: DropdownButtonFormField<String>(
              key: ValueKey<String>(_month),
              initialValue: _month,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              decoration: const InputDecoration(
                  labelText: 'Período',
                  prefixIcon:
                      Icon(Icons.calendar_month_rounded, color: _budgetBlue),
                  border: InputBorder.none),
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
          );
          final Widget illustration = SizedBox(
            height: compact ? 135 : 205,
            child: Image.asset(
              'assets/images/budget_3d.png',
              fit: BoxFit.contain,
              semanticLabel:
                  'Ilustração 3D de carteira, calculadora, moedas e calendário',
            ),
          );
          final Widget visual = SizedBox(
            width: compact ? double.infinity : 330,
            child: Column(
              children: <Widget>[
                illustration,
                const SizedBox(height: 4),
                monthPicker,
              ],
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(child: introduction),
                    const SizedBox(width: 8),
                    SizedBox(width: 132, child: illustration),
                  ],
                ),
                const SizedBox(height: 12),
                monthPicker,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(child: introduction),
              const SizedBox(width: 24),
              visual,
            ],
          );
        },
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
          accent: _budgetGreen,
          surface: const Color(0xFFE3EBDD)),
      _MetricCard(
          title: 'Despesas',
          value: _formatCurrency(_expenseTotal),
          icon: Icons.trending_down,
          accent: _budgetRed,
          surface: const Color(0xFFF4DEDA)),
      _MetricCard(
        title: 'Saldo previsto',
        value: _formatCurrency(balance),
        icon: Icons.account_balance_wallet_outlined,
        accent: balance >= 0 ? _budgetBlue : _budgetRed,
        surface: balance >= 0 ? _budgetSky : const Color(0xFFF4DEDA),
      ),
      _MetricCard(
          title: 'Falta pagar',
          value: _formatCurrency(_pendingTotal),
          icon: Icons.event_available_outlined,
          accent: _budgetAmber,
          surface: const Color(0xFFF7E7C9)),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 900) {
          return SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (BuildContext context, int index) =>
                  SizedBox(width: 210, child: cards[index]),
            ),
          );
        }
        return GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.15,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cards,
        );
      },
    );
  }

  Widget _buildFilters() {
    return _BudgetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionHeader(
            icon: Icons.tune_rounded,
            title: 'Encontre o que precisa',
            subtitle: '${_filteredItems.length} lançamentos encontrados',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: _fieldDecoration(
              label: 'Buscar descrição',
              icon: Icons.search_rounded,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ...const <String>['Todos', 'Receita', 'Despesa'].map(
                (String value) => FilterChip(
                  label: Text(value),
                  selected: _typeFilter == value,
                  onSelected: (_) => setState(() => _typeFilter = value),
                  avatar: Icon(
                    value == 'Receita'
                        ? Icons.arrow_downward_rounded
                        : value == 'Despesa'
                            ? Icons.arrow_upward_rounded
                            : Icons.swap_vert_rounded,
                    size: 17,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              ...const <String>['Quitado', 'Pendente'].map(
                (String value) => FilterChip(
                  label: Text(value),
                  selected: _statusFilter == value,
                  onSelected: (bool selected) => setState(
                      () => _statusFilter = selected ? value : 'Todos'),
                  avatar: Icon(
                    value == 'Quitado'
                        ? Icons.check_circle_outline_rounded
                        : Icons.schedule_rounded,
                    size: 17,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return _BudgetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionHeader(
            icon: _editingId == null ? Icons.add_rounded : Icons.edit_rounded,
            title: _editingId == null ? 'Novo lançamento' : 'Editar lançamento',
            subtitle: _editingId == null
                ? 'Inclua uma receita ou despesa'
                : 'Atualize os dados selecionados',
          ),
          const SizedBox(height: 18),
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(
                  value: 'Receita',
                  label: Text('Receita'),
                  icon: Icon(Icons.south_west_rounded)),
              ButtonSegment<String>(
                  value: 'Despesa',
                  label: Text('Despesa'),
                  icon: Icon(Icons.north_east_rounded)),
            ],
            selected: <String>{_itemType},
            showSelectedIcon: false,
            onSelectionChanged: (Set<String> selected) =>
                setState(() => _itemType = selected.first),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descriptionController,
            maxLength: 15,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: <TextInputFormatter>[UpperCaseTextFormatter()],
            decoration: _fieldDecoration(
                label: 'Descrição', icon: Icons.notes_rounded, counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
            decoration: _fieldDecoration(
                label: 'Valor',
                icon: Icons.payments_outlined,
                prefixText: 'R\$ ',
                hintText: '0,00'),
          ),
          const SizedBox(height: 12),
          _dateField(_dueDateController, 'Vencimento / data'),
          const SizedBox(height: 12),
          _dateField(_paymentDateController, 'Data do pagamento',
              isRequired: false),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: _settled,
            title: Text(_itemType == 'Receita' ? 'Recebido' : 'Pago'),
            subtitle: const Text('Marque quando o valor for confirmado',
                style: TextStyle(fontSize: 11)),
            onChanged: (bool? value) =>
                setState(() => _settled = value ?? false),
          ),
          const SizedBox(height: 8),
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
                      backgroundColor: _budgetBlue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
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
        filled: true,
        fillColor: _budgetField,
        prefixIcon: const Icon(Icons.event_outlined),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!isRequired && controller.text.isNotEmpty)
              IconButton(
                  onPressed: () => setState(controller.clear),
                  icon: const Icon(Icons.close)),
            const Icon(Icons.calendar_month_rounded),
            const SizedBox(width: 14),
          ],
        ),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildEntries() {
    return _BudgetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionHeader(
            icon: Icons.receipt_long_rounded,
            title: 'Lançamentos do mês',
            subtitle: _monthLabel(_month),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(44),
                child: Center(child: CircularProgressIndicator()))
          else if (_filteredItems.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
              decoration: BoxDecoration(
                  color: _budgetField, borderRadius: BorderRadius.circular(18)),
              child: const Column(
                children: <Widget>[
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: _budgetSky,
                    child: Icon(Icons.receipt_long_outlined,
                        size: 28, color: _budgetBlue),
                  ),
                  SizedBox(height: 14),
                  Text('Nenhum lançamento encontrado',
                      style: TextStyle(
                          color: _budgetInk, fontWeight: FontWeight.w700)),
                  SizedBox(height: 5),
                  Text('Ajuste os filtros ou inclua um novo item.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _budgetMuted, fontSize: 12)),
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
    final Color accent = revenue ? _budgetGreen : _budgetRed;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
      decoration: BoxDecoration(
        color: item.settled ? const Color(0xFFF4EEE4) : _budgetField,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
            color: item.settled
                ? const Color(0xFFD8CBB9)
                : accent.withValues(alpha: 0.42)),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(item.description,
                      style: const TextStyle(
                          color: _budgetInk,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                  _StatusPill(
                      label: item.itemType,
                      icon: revenue
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
                      color: accent),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                'Vencimento: ${_dateToDisplay(item.dueDate)}${item.paymentDate.isEmpty ? '' : ' • Pagamento: ${_dateToDisplay(item.paymentDate)}'}',
                style: const TextStyle(fontSize: 11, color: _budgetMuted),
              ),
            ],
          );
          final Widget actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Tooltip(
                message: item.settled ? 'Marcar como pendente' : 'Confirmar',
                child: IconButton.filledTonal(
                  onPressed: () => _changeStatus(item, !item.settled),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(item.settled
                      ? Icons.check_circle_rounded
                      : Icons.schedule_rounded),
                ),
              ),
              IconButton(
                  tooltip: 'Editar',
                  onPressed: () => _startEditing(item),
                  icon: const Icon(Icons.edit_outlined, size: 19)),
              IconButton(
                  tooltip: 'Excluir',
                  onPressed: () => _deleteItem(item),
                  color: _budgetRed,
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
                            color: accent,
                            fontSize: 16,
                            fontWeight: FontWeight.w900)),
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
                  style: TextStyle(
                      color: accent,
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
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
  const _BudgetPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _budgetPanel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4D6C3)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
              color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 10))
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
      required this.accent,
      required this.surface});

  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _budgetPanel,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: const Color(0xFFE4D6C3)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
                color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 7))
          ]),
      child: Row(
        children: <Widget>[
          Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: surface, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: accent, size: 23)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: const TextStyle(
                        color: _budgetMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _budgetInk,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.25)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: _budgetSky, borderRadius: BorderRadius.circular(13)),
          child: Icon(icon, color: _budgetBlue, size: 21),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title,
                  style: const TextStyle(
                      color: _budgetInk,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      color: _budgetMuted, fontSize: 11, height: 1.2)),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(
      {required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration({
  required String label,
  required IconData icon,
  String? hintText,
  String? prefixText,
  String? counterText,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    prefixText: prefixText,
    counterText: counterText,
    prefixIcon: Icon(icon),
    filled: true,
    fillColor: _budgetField,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _budgetBlue, width: 1.5)),
  );
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
