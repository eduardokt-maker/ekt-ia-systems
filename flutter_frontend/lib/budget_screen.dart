import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
  final ScrollController _entriesScrollController = ScrollController();

  StateSetter? _dialogSetState;

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
    _entriesScrollController.dispose();
    super.dispose();
  }

  void _updateState(VoidCallback change) {
    setState(change);
    _dialogSetState?.call(() {});
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

  double get _paidTotal => _items
      .where((BudgetItem item) => item.itemType == 'Despesa' && item.settled)
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
    _updateState(() => _saving = true);
    final bool closeDialogAfterSave = _dialogSetState != null;
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
      if (closeDialogAfterSave && mounted) {
        _dialogSetState = null;
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error), error: true);
    } finally {
      if (mounted) _updateState(() => _saving = false);
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
      if (item.itemType == 'Receita') {
        _showMessage(settled
            ? 'Receita recebida e enviada ao Caixa.'
            : 'Receita reaberta e removida do Caixa.');
      } else {
        _showMessage(
            settled ? 'Despesa marcada como paga.' : 'Despesa reaberta.');
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

  Future<void> _startEditing(BudgetItem item) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => _BudgetEditScreen(
          apiUriBuilder: widget.apiUriBuilder,
          sessionToken: widget.sessionToken,
          referenceMonth: _month,
          item: item,
        ),
      ),
    );
    if (saved == true && mounted) {
      _showMessage(item.itemType == 'Receita'
          ? 'Receita alterada e Caixa atualizado.'
          : 'Lançamento alterado.');
      await _loadBudget();
    }
  }

  Future<void> _openCashReport() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => _CashReportScreen(
          apiUriBuilder: widget.apiUriBuilder,
          sessionToken: widget.sessionToken,
        ),
      ),
    );
  }

  void _clearForm() {
    _updateState(() {
      _editingId = null;
      _itemType = 'Despesa';
      _descriptionController.clear();
      _amountController.clear();
      _dueDateController.clear();
      _paymentDateController.clear();
      _settled = false;
    });
  }

  Future<void> _showFormDialog() async {
    if (_dialogSetState != null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          _dialogSetState = setDialogState;
          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 430,
                maxHeight: MediaQuery.sizeOf(dialogContext).height - 48,
              ),
              child: SingleChildScrollView(child: _buildForm()),
            ),
          );
        },
      ),
    );
    _dialogSetState = null;
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
      _dialogSetState?.call(() {});
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
              final double horizontalPadding =
                  constraints.maxWidth < 600 ? 12 : 24;
              final bool desktop =
                  constraints.maxWidth >= 980 && constraints.maxHeight >= 700;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: desktop
                      ? _buildDesktopWorkspace(horizontalPadding)
                      : _buildCompactWorkspace(horizontalPadding),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopWorkspace(double horizontalPadding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildMonthHeader(compactHeight: true),
          const SizedBox(height: 12),
          _buildMetrics(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(width: 370, child: _buildForm()),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildFilters(),
                      const SizedBox(height: 12),
                      Expanded(child: _buildEntries()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactWorkspace(double horizontalPadding) {
    return CustomScrollView(
      primary: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: <Widget>[
        SliverPadding(
          padding:
              EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 0),
          sliver: SliverToBoxAdapter(child: _buildMonthHeader()),
        ),
        SliverPadding(
          padding:
              EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 0),
          sliver: SliverToBoxAdapter(child: _buildMetrics()),
        ),
        SliverPadding(
          padding:
              EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 0),
          sliver: SliverToBoxAdapter(child: _buildFilters()),
        ),
        SliverPadding(
          padding:
              EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 0),
          sliver: SliverToBoxAdapter(child: _buildCompactActions()),
        ),
        SliverPadding(
          padding:
              EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 24),
          sliver: SliverToBoxAdapter(child: _buildEntries(expandList: false)),
        ),
      ],
    );
  }

  Widget _buildCompactActions() {
    return Row(
      children: <Widget>[
        Flexible(
          child: FilledButton.icon(
            onPressed: _showFormDialog,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Novo lançamento'),
            style: FilledButton.styleFrom(
              backgroundColor: _budgetBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          key: const Key('open-cash-report'),
          onPressed: _openCashReport,
          icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
          label: const Text('Caixa'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _budgetNavy,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            visualDensity: VisualDensity.compact,
            side: const BorderSide(color: _budgetBlue),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthHeader({bool compactHeight = false}) {
    final double balance = _revenueTotal - _expenseTotal;
    final double useRatio = _revenueTotal <= 0
        ? 0
        : (_expenseTotal / _revenueTotal).clamp(0.0, 1.0);
    return Container(
      padding: EdgeInsets.all(compactHeight ? 16 : 20),
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
              SizedBox(height: compactHeight ? 8 : 14),
              Text(
                  compactHeight
                      ? 'PLANEJAMENTO MENSAL'
                      : 'PLANEJAMENTO\nMENSAL',
                  style: TextStyle(
                      color: _budgetInk,
                      fontSize: compactHeight ? 25 : 31,
                      height: 1.02,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4)),
              SizedBox(height: compactHeight ? 5 : 10),
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
              SizedBox(height: compactHeight ? 9 : 18),
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
            height: compactHeight ? 102 : (compact ? 135 : 155),
            child: Image.asset(
              'assets/images/budget_3d.png',
              fit: BoxFit.contain,
              semanticLabel:
                  'Ilustração 3D de carteira, calculadora, moedas e calendário',
            ),
          );
          final Widget visual = SizedBox(
            width: compact ? double.infinity : (compactHeight ? 390 : 420),
            child: Row(
              children: <Widget>[
                Expanded(child: illustration),
                const SizedBox(width: 12),
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
      _MetricCard(
          title: 'Despesas pagas',
          value: _formatCurrency(_paidTotal),
          icon: Icons.check_circle_outline_rounded,
          accent: _budgetGreen,
          surface: const Color(0xFFE3EBDD)),
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
        return SizedBox(
          height: 88,
          child: Row(
            children: <Widget>[
              for (int index = 0; index < cards.length; index++) ...<Widget>[
                if (index > 0) const SizedBox(width: 12),
                Expanded(child: cards[index]),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilters() {
    final Widget header = _SectionHeader(
      icon: Icons.tune_rounded,
      title: 'Encontre o que precisa',
      subtitle: '${_filteredItems.length} lançamentos encontrados',
    );
    final Widget search = TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: _fieldDecoration(
        label: 'Buscar descrição',
        icon: Icons.search_rounded,
      ),
    );
    final Widget chips = Wrap(
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
            onSelected: (bool selected) =>
                setState(() => _statusFilter = selected ? value : 'Todos'),
            avatar: Icon(
              value == 'Quitado'
                  ? Icons.check_circle_outline_rounded
                  : Icons.schedule_rounded,
              size: 17,
            ),
          ),
        ),
      ],
    );
    return _BudgetPanel(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (constraints.maxWidth >= 900) {
            return Row(
              children: <Widget>[
                SizedBox(width: 230, child: header),
                const SizedBox(width: 14),
                SizedBox(width: 250, child: search),
                const SizedBox(width: 14),
                Expanded(child: chips),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              header,
              const SizedBox(height: 12),
              search,
              const SizedBox(height: 10),
              chips,
            ],
          );
        },
      ),
    );
  }

  Widget _buildForm() {
    return _BudgetPanel(
      padding: const EdgeInsets.all(14),
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
          const SizedBox(height: 12),
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
                _updateState(() => _itemType = selected.first),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _descriptionController,
                  maxLength: 15,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: <TextInputFormatter>[
                    UpperCaseTextFormatter()
                  ],
                  decoration: _fieldDecoration(
                      label: 'Descrição',
                      icon: Icons.notes_rounded,
                      counterText: ''),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                  ],
                  decoration: _fieldDecoration(
                      label: 'Valor',
                      icon: Icons.payments_outlined,
                      prefixText: 'R\$ ',
                      hintText: '0,00'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                  child: _dateField(_dueDateController, 'Vencimento / data')),
              const SizedBox(width: 10),
              Expanded(
                child: _dateField(
                  _paymentDateController,
                  _itemType == 'Receita'
                      ? 'Data do recebimento'
                      : 'Data do pagamento',
                  isRequired: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: _settled,
            title: Text(_itemType == 'Receita' ? 'Recebido' : 'Pago'),
            onChanged: (bool? value) => _updateState(() {
              _settled = value ?? false;
              if (!_settled) {
                _paymentDateController.clear();
              } else if (_paymentDateController.text.isEmpty) {
                final DateTime today = DateTime.now();
                _paymentDateController.text =
                    '${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}';
              }
            }),
          ),
          const SizedBox(height: 4),
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
        isDense: true,
        filled: true,
        fillColor: _budgetField,
        suffixIcon: !isRequired && controller.text.isNotEmpty
            ? IconButton(
                tooltip: 'Limpar data',
                onPressed: () => _updateState(controller.clear),
                icon: const Icon(Icons.close_rounded),
              )
            : const Icon(Icons.calendar_month_rounded),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildEntries({bool expandList = true}) {
    final Widget content;
    if (_loading) {
      content = const SizedBox(
          height: 180, child: Center(child: CircularProgressIndicator()));
    } else if (_filteredItems.isEmpty) {
      content = _buildEmptyState();
    } else if (expandList) {
      content = Scrollbar(
        controller: _entriesScrollController,
        thumbVisibility: true,
        child: RefreshIndicator(
          onRefresh: _loadBudget,
          child: ListView.builder(
            controller: _entriesScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(right: 10),
            itemCount: _filteredItems.length,
            itemBuilder: (BuildContext context, int index) =>
                _buildEntry(_filteredItems[index]),
          ),
        ),
      );
    } else {
      content = Column(
        children: <Widget>[
          for (final BudgetItem item in _filteredItems) _buildEntry(item),
        ],
      );
    }

    return _BudgetPanel(
      child: Column(
        mainAxisSize: expandList ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionHeader(
            icon: Icons.receipt_long_rounded,
            title: 'Lançamentos do mês',
            subtitle: _monthLabel(_month),
          ),
          const SizedBox(height: 16),
          if (expandList) Expanded(child: content) else content,
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
          color: _budgetField, borderRadius: BorderRadius.circular(18)),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CircleAvatar(
            radius: 28,
            backgroundColor: _budgetSky,
            child:
                Icon(Icons.receipt_long_outlined, size: 28, color: _budgetBlue),
          ),
          SizedBox(height: 14),
          Text('Nenhum lançamento encontrado',
              style: TextStyle(color: _budgetInk, fontWeight: FontWeight.w700)),
          SizedBox(height: 5),
          Text('Ajuste os filtros ou inclua um novo item.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _budgetMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildEntry(BudgetItem item) {
    final bool revenue = item.itemType == 'Receita';
    final Color accent = revenue ? _budgetGreen : _budgetRed;
    final Color statusColor = item.settled ? _budgetGreen : _budgetAmber;
    final Color cardColor = revenue
        ? (item.settled ? const Color(0xFFEDF5E9) : const Color(0xFFF4EEE4))
        : Colors.white;
    final String statusText = revenue
        ? (item.settled ? 'RECEBIDO' : 'A RECEBER')
        : (item.settled ? 'PAGO' : 'FALTA PAGAR');
    final IconData statusIcon =
        item.settled ? Icons.check_circle_rounded : Icons.hourglass_top_rounded;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
            color: statusColor.withValues(alpha: item.settled ? 0.68 : 0.52),
            width: item.settled ? 1.6 : 1.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: statusColor.withValues(alpha: item.settled ? 0.13 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
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
                  _StatusPill(
                    label: statusText,
                    icon: statusIcon,
                    color: statusColor,
                    emphasized: item.settled,
                  ),
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
                message: item.settled
                    ? (revenue
                        ? 'Marcar como não recebido'
                        : 'Marcar como falta pagar')
                    : (revenue ? 'Marcar como recebido' : 'Marcar como pago'),
                child: IconButton(
                  onPressed: () => _changeStatus(item, !item.settled),
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    backgroundColor: item.settled
                        ? _budgetGreen
                        : _budgetAmber.withValues(alpha: 0.16),
                    foregroundColor: item.settled ? Colors.white : _budgetAmber,
                    side: BorderSide(
                      color: item.settled
                          ? _budgetGreen
                          : _budgetAmber.withValues(alpha: 0.42),
                    ),
                  ),
                  icon: Icon(item.settled
                      ? Icons.check_rounded
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

class _BudgetEditScreen extends StatefulWidget {
  const _BudgetEditScreen({
    required this.apiUriBuilder,
    required this.sessionToken,
    required this.referenceMonth,
    required this.item,
  });

  final ApiUriBuilder apiUriBuilder;
  final String sessionToken;
  final String referenceMonth;
  final BudgetItem item;

  @override
  State<_BudgetEditScreen> createState() => _BudgetEditScreenState();
}

class _BudgetEditScreenState extends State<_BudgetEditScreen> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _amountController;
  late final TextEditingController _dueDateController;
  late final TextEditingController _paymentDateController;
  late String _itemType;
  late bool _settled;
  bool _saving = false;

  Map<String, String> get _headers => <String, String>{
        'authorization': 'Bearer ${widget.sessionToken}',
        'content-type': 'application/json; charset=utf-8',
      };

  @override
  void initState() {
    super.initState();
    final BudgetItem item = widget.item;
    _descriptionController = TextEditingController(text: item.description);
    _amountController = TextEditingController(text: item.amountText);
    _dueDateController =
        TextEditingController(text: _dateToDisplay(item.dueDate));
    _paymentDateController = TextEditingController(
        text: item.paymentDate.isEmpty ? '' : _dateToDisplay(item.paymentDate));
    _itemType = item.itemType;
    _settled = item.settled;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _dueDateController.dispose();
    _paymentDateController.dispose();
    super.dispose();
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
      setState(() => controller.text =
          '${selected.day.toString().padLeft(2, '0')}/${selected.month.toString().padLeft(2, '0')}/${selected.year}');
    }
  }

  String? _validate() {
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
      return 'Informe uma data de recebimento válida.';
    }
    return null;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(message), backgroundColor: const Color(0xFFB42332)));
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final String? validation = _validate();
    if (validation != null) {
      _showError(validation);
      return;
    }
    setState(() => _saving = true);
    final Map<String, dynamic> payload = <String, dynamic>{
      'reference_month': widget.referenceMonth,
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
      final http.Response response = await http.put(
        widget.apiUriBuilder('/api/budget/${widget.item.id}'),
        headers: _headers,
        body: jsonEncode(payload),
      );
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          body['ok'] != true) {
        throw BudgetApiException((body['message'] as String?) ??
            'Não foi possível gravar a alteração.');
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) _showError(_messageFor(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dateDecoration(String label) => _fieldDecoration(
        label: label,
        icon: Icons.calendar_month_outlined,
        hintText: 'dd/mm/aaaa',
      ).copyWith(suffixIcon: const Icon(Icons.arrow_drop_down_rounded));

  @override
  Widget build(BuildContext context) {
    final bool revenue = _itemType == 'Receita';
    return Scaffold(
      backgroundColor: _budgetCanvas,
      appBar: AppBar(
        backgroundColor: _budgetPanel,
        foregroundColor: _budgetInk,
        automaticallyImplyLeading: false,
        title: const Text('Alterar lançamento'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _BudgetPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _SectionHeader(
                      icon: Icons.edit_note_rounded,
                      title: revenue ? 'Alterar receita' : 'Alterar despesa',
                      subtitle:
                          'Edite os dados e confirme para voltar aos lançamentos',
                    ),
                    const SizedBox(height: 18),
                    SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment<String>(
                            value: 'Receita', label: Text('Receita')),
                        ButtonSegment<String>(
                            value: 'Despesa', label: Text('Despesa')),
                      ],
                      selected: <String>{_itemType},
                      onSelectionChanged: (Set<String> value) =>
                          setState(() => _itemType = value.first),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('budget-edit-description'),
                      controller: _descriptionController,
                      maxLength: 15,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: <TextInputFormatter>[
                        UpperCaseTextFormatter()
                      ],
                      decoration: _fieldDecoration(
                          label: 'Descrição',
                          icon: Icons.notes_rounded,
                          counterText: ''),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('budget-edit-amount'),
                      controller: _amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                      ],
                      decoration: _fieldDecoration(
                          label: 'Valor',
                          icon: Icons.payments_outlined,
                          prefixText: 'R\$ '),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _dueDateController,
                      readOnly: true,
                      onTap: () => _pickDate(_dueDateController),
                      decoration: _dateDecoration('Vencimento / data'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _paymentDateController,
                      readOnly: true,
                      onTap: () => _pickDate(_paymentDateController),
                      decoration: _dateDecoration(revenue
                          ? 'Data do recebimento'
                          : 'Data do pagamento'),
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      value: _settled,
                      title: Text(revenue ? 'Recebida' : 'Paga'),
                      subtitle: revenue && _settled
                          ? const Text(
                              'Ao gravar, esta receita será registrada no Caixa.')
                          : null,
                      onChanged: (bool value) => setState(() {
                        _settled = value;
                        if (!value) {
                          _paymentDateController.clear();
                        } else if (_paymentDateController.text.isEmpty) {
                          final DateTime today = DateTime.now();
                          _paymentDateController.text =
                              '${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}';
                        }
                      }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('budget-edit-cancel'),
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).pop(false),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Cancelar'),
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            key: const Key('budget-edit-save'),
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.save_outlined),
                            label: const Text('Gravar alteração'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _budgetBlue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(50),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CashReportScreen extends StatefulWidget {
  const _CashReportScreen({
    required this.apiUriBuilder,
    required this.sessionToken,
  });

  final ApiUriBuilder apiUriBuilder;
  final String sessionToken;

  @override
  State<_CashReportScreen> createState() => _CashReportScreenState();
}

class _CashReportScreenState extends State<_CashReportScreen> {
  bool _loading = true;
  bool _processing = false;
  String? _error;
  List<_CashEntry> _entries = <_CashEntry>[];

  double get _total => _entries.fold<double>(
      0, (double total, _CashEntry entry) => total + entry.amount);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final http.Response response = await http.get(
        widget.apiUriBuilder('/api/cash'),
        headers: <String, String>{
          'authorization': 'Bearer ${widget.sessionToken}',
          'content-type': 'application/json; charset=utf-8',
        },
      );
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw BudgetApiException((body['message'] as String?) ??
            'Não foi possível carregar o Caixa.');
      }
      final List<dynamic> items =
          (body['items'] as List<dynamic>?) ?? <dynamic>[];
      if (!mounted) return;
      setState(() => _entries = items
          .map((dynamic item) =>
              _CashEntry.fromJson(item as Map<String, dynamic>))
          .toList());
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Uint8List> _buildPdf() async {
    final pw.Document document = pw.Document(
      title: 'Relatorio Caixa - EKT IA Systems',
      author: 'EKT IA Systems',
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: const pw.BoxDecoration(
            border:
                pw.Border(bottom: pw.BorderSide(color: PdfColors.blueGrey700)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text('EKT IA SYSTEMS',
                  style: const pw.TextStyle(
                      fontSize: 15, fontWeight: pw.FontWeight.bold)),
              pw.Text('RELATORIO CAIXA',
                  style: const pw.TextStyle(fontSize: 11)),
            ],
          ),
        ),
        footer: (pw.Context context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
              'Pagina ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ),
        build: (pw.Context context) => <pw.Widget>[
          pw.SizedBox(height: 18),
          pw.Text('Receitas recebidas',
              style: const pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          pw.Text('Documento somente leitura',
              style:
                  const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: <pw.Widget>[
                pw.Text('${_entries.length} recebimento(s)'),
                pw.Text(_formatCurrency(_total),
                    style: const pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          if (_entries.isEmpty)
            pw.Text('Nenhuma receita recebida foi registrada no Caixa.')
          else
            pw.TableHelper.fromTextArray(
              headers: const <String>[
                'Recebimento',
                'Competencia',
                'Descricao',
                'Valor'
              ],
              data: _entries
                  .map((_CashEntry entry) => <String>[
                        _dateToDisplay(entry.paymentDate),
                        _monthLabel(entry.referenceMonth),
                        entry.description,
                        _formatCurrency(entry.amount),
                      ])
                  .toList(),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.blueGrey800),
              headerStyle: const pw.TextStyle(
                  color: PdfColors.white, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellPadding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
              columnWidths: <int, pw.TableColumnWidth>{
                0: const pw.FixedColumnWidth(78),
                1: const pw.FixedColumnWidth(82),
                2: const pw.FlexColumnWidth(),
                3: const pw.FixedColumnWidth(85),
              },
            ),
        ],
      ),
    );
    return Uint8List.fromList(await document.save());
  }

  Future<void> _print() async {
    setState(() => _processing = true);
    try {
      final Uint8List bytes = await _buildPdf();
      await Printing.layoutPdf(
        name: 'Relatorio-Caixa-EKT.pdf',
        onLayout: (PdfPageFormat format) async => bytes,
      );
    } catch (error) {
      if (mounted) _showError('Não foi possível imprimir o relatório.');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _share() async {
    setState(() => _processing = true);
    try {
      await Printing.sharePdf(
        bytes: await _buildPdf(),
        filename: 'Relatorio-Caixa-EKT.pdf',
      );
    } catch (error) {
      if (mounted) _showError('Não foi possível compartilhar o relatório.');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(message), backgroundColor: const Color(0xFFB42332)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _budgetCanvas,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: _budgetPanel,
        foregroundColor: _budgetInk,
        title: const Text('Caixa'),
        actions: <Widget>[
          IconButton(
              tooltip: 'Atualizar',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: _BudgetPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildReportHeader(),
                    const SizedBox(height: 18),
                    Expanded(child: _buildReportBody()),
                    const SizedBox(height: 14),
                    _buildReportActions(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReportHeader() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 620;
        final Widget title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('EKT IA SYSTEMS',
                style: TextStyle(
                    color: _budgetNavy,
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('RELATÓRIO CAIXA',
                style: TextStyle(
                    color: _budgetInk,
                    fontSize: 24,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('${_entries.length} receita(s) recebida(s) • Somente leitura',
                style: const TextStyle(color: _budgetMuted, fontSize: 12)),
          ],
        );
        final Widget total = Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEDF5E9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _budgetGreen),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('TOTAL RECEBIDO',
                  style: TextStyle(
                      color: _budgetGreen,
                      fontSize: 10,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(_formatCurrency(_total),
                  style: const TextStyle(
                      color: _budgetInk,
                      fontSize: 20,
                      fontWeight: FontWeight.w900)),
            ],
          ),
        );
        return compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[title, const SizedBox(height: 14), total])
            : Row(children: <Widget>[Expanded(child: title), total]);
      },
    );
  }

  Widget _buildReportBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente')),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(
        child: Text('Nenhuma receita recebida foi registrada no Caixa.',
            textAlign: TextAlign.center, style: TextStyle(color: _budgetMuted)),
      );
    }
    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final _CashEntry entry = _entries[index];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFEDF5E9),
            child: Icon(Icons.south_west_rounded, color: _budgetGreen),
          ),
          title: Text(entry.description,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
              'Recebido em ${_dateToDisplay(entry.paymentDate)} • ${_monthLabel(entry.referenceMonth)}'),
          trailing: Text(_formatCurrency(entry.amount),
              style: const TextStyle(
                  color: _budgetGreen, fontWeight: FontWeight.w900)),
        );
      },
    );
  }

  Widget _buildReportActions() {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        OutlinedButton.icon(
          key: const Key('cash-report-share'),
          onPressed: _loading || _processing ? null : _share,
          icon: const Icon(Icons.share_outlined),
          label: const Text('Compartilhar'),
        ),
        OutlinedButton.icon(
          key: const Key('cash-report-print'),
          onPressed: _loading || _processing ? null : _print,
          icon: const Icon(Icons.print_outlined),
          label: const Text('Imprimir relatório'),
        ),
        FilledButton.icon(
          key: const Key('cash-report-exit'),
          onPressed: _processing ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sair'),
          style: FilledButton.styleFrom(
              backgroundColor: _budgetNavy, foregroundColor: Colors.white),
        ),
      ],
    );
  }
}

class _CashEntry {
  const _CashEntry({
    required this.referenceMonth,
    required this.description,
    required this.amountText,
    required this.paymentDate,
  });

  factory _CashEntry.fromJson(Map<String, dynamic> json) => _CashEntry(
        referenceMonth: (json['reference_month'] as String?) ?? '',
        description: ((json['description'] as String?) ?? '').toUpperCase(),
        amountText: (json['amount_text'] as String?) ?? '0,00',
        paymentDate: (json['payment_date'] as String?) ?? '',
      );

  final String referenceMonth;
  final String description;
  final String amountText;
  final String paymentDate;

  double get amount => _parseAmount(amountText);
}

class _BudgetPanel extends StatelessWidget {
  const _BudgetPanel(
      {required this.child, this.padding = const EdgeInsets.all(18)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
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
      {required this.label,
      required this.icon,
      required this.color,
      this.emphasized = false});

  final String label;
  final IconData icon;
  final Color color;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: emphasized ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: color.withValues(alpha: emphasized ? 0.58 : 0.22))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  letterSpacing: emphasized ? 0.35 : 0,
                  fontWeight: FontWeight.w900)),
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
    isDense: true,
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
