import 'dart:convert';

import 'api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'budget_bi_screen.dart';

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
      {required this.apiUriBuilder,
      required this.sessionToken,
      this.initialItems,
      super.key});

  final ApiUriBuilder apiUriBuilder;
  final String sessionToken;
  @visibleForTesting
  final List<BudgetItem>? initialItems;

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _observationController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _receivedAmountController =
      TextEditingController();
  final TextEditingController _dueDateController = TextEditingController();
  final TextEditingController _paymentDateController = TextEditingController();
  final TextEditingController _otherRevenueTypeController =
      TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _entriesScrollController = ScrollController();
  final FocusNode _descriptionFocusNode = FocusNode();
  final FocusNode _amountFocusNode = FocusNode();

  StateSetter? _dialogSetState;

  late String _month;
  late String _formReferenceMonth;
  String _itemType = 'Despesa';
  String? _revenueType;
  int? _expenseNatureId;
  String _expenseNatureFilter = 'Todas';
  String _revenueTypeFilter = 'Todos';
  String _typeFilter = 'Todos';
  String _statusFilter = 'Todos';
  String _dueMonthFilter = 'Todos';
  String _paymentMonthFilter = 'Todos';
  String _sortBy = 'Mês de Referência';
  String _referenceFromFilter = 'Todos';
  String _referenceToFilter = 'Todos';
  final bool _showAdvancedFilters = false;
  bool _showAllPeriods = true;
  bool _settled = false;
  bool _loading = true;
  bool _saving = false;
  bool _printing = false;
  int? _editingId;
  List<BudgetItem> _items = <BudgetItem>[];
  List<String> _availableMonths = <String>[];
  Map<String, String> _monthStatuses = <String, String>{};
  Map<String, Map<String, dynamic>> _monthImports =
      <String, Map<String, dynamic>>{};
  List<String> _expenseDescriptionSuggestions = <String>[];
  List<ExpenseNature> _expenseNatures = <ExpenseNature>[];
  final Set<int> _selectedExpenseIds = <int>{};

  Map<String, String> get _headers => <String, String>{
        'authorization': 'Bearer ${widget.sessionToken}',
        'content-type': 'application/json; charset=utf-8',
      };

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _formReferenceMonth = _month;
    if (widget.initialItems == null) {
      _loadBudget();
    } else {
      _items = List<BudgetItem>.from(widget.initialItems!);
      _availableMonths = _items
          .map((BudgetItem item) => item.referenceMonth)
          .where((String value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      _loading = false;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _observationController.dispose();
    _amountController.dispose();
    _receivedAmountController.dispose();
    _dueDateController.dispose();
    _paymentDateController.dispose();
    _otherRevenueTypeController.dispose();
    _searchController.dispose();
    _entriesScrollController.dispose();
    _descriptionFocusNode.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  void _updateState(VoidCallback change) {
    final StateSetter? dialogState = _dialogSetState;
    if (dialogState != null) {
      dialogState(change);
      return;
    }
    setState(change);
  }

  List<String> get _monthOptions {
    final int year = DateTime.now().year;
    return <String>[
      for (int optionYear = year - 5; optionYear <= year + 5; optionYear++)
        for (int month = 1; month <= 12; month++)
          '$optionYear-${month.toString().padLeft(2, '0')}',
    ];
  }

  List<BudgetItem> get _filteredItems {
    final String query = _searchController.text.trim().toUpperCase();
    final List<BudgetItem> result = _periodItems.where((BudgetItem item) {
      final bool matchesDescription =
          query.isEmpty || item.description.contains(query);
      final bool matchesType =
          _typeFilter == 'Todos' || item.itemType == _typeFilter;
      final bool matchesRevenueType = _revenueTypeFilter == 'Todos' ||
          (item.itemType == 'Receita' &&
              item.revenueType == _revenueTypeFilter);
      final bool matchesStatus = _matchesSelectedStatus(item);
      final bool matchesNature = _expenseNatureFilter == 'Todas' ||
          (_expenseNatureFilter == 'Sem categoria'
              ? !item.hasExpenseNature
              : item.expenseNatureId.toString() == _expenseNatureFilter);
      final bool matchesDueMonth = _dueMonthFilter == 'Todos' ||
          item.dueDate.startsWith(_dueMonthFilter);
      final bool matchesPaymentMonth = _paymentMonthFilter == 'Todos' ||
          (_paymentMonthFilter == 'Não pagas'
              ? item.paymentDate.isEmpty
              : item.paymentDate.startsWith(_paymentMonthFilter));
      return matchesDescription &&
          matchesType &&
          matchesRevenueType &&
          matchesNature &&
          matchesStatus &&
          matchesDueMonth &&
          matchesPaymentMonth;
    }).toList();
    result.sort((BudgetItem a, BudgetItem b) {
      final int comparison = switch (_sortBy) {
        'Data de Vencimento' => a.dueDate.compareTo(b.dueDate),
        'Data de Pagamento' => _nullableDateSort(a.paymentDate, b.paymentDate),
        _ => a.referenceMonth.compareTo(b.referenceMonth),
      };
      return comparison != 0 ? comparison : a.id.compareTo(b.id);
    });
    return result;
  }

  List<BudgetItem> get _periodItems => filterBudgetItemsByPeriod(
        _items,
        _showAllPeriods ? null : _month,
      );

  double get _filteredDisplayedTotal => _filteredItems.fold<double>(
        0,
        (double total, BudgetItem item) => total + budgetDisplayedAmount(item),
      );

  bool get _showFilteredHomogeneousTotal =>
      _typeFilter != 'Todos' && _statusFilter != 'Todos';

  bool _matchesSelectedStatus(BudgetItem item) {
    if (_statusFilter == 'Todos') return true;
    // Para receitas, settled representa "Recebido"; para despesas, "Pago".
    if (_statusFilter == 'Quitado') return item.settled;
    if (_statusFilter == 'Pendente') return !item.settled;
    return true;
  }

  List<String> get _dueMonthOptions =>
      _dateMonthOptions(_periodItems.map((BudgetItem item) => item.dueDate),
          includeUnpaid: false);

  List<String> get _paymentMonthOptions =>
      _dateMonthOptions(_periodItems.map((BudgetItem item) => item.paymentDate),
          includeUnpaid: true);

  double get _revenueTotal => _periodItems
      .where((BudgetItem item) => item.itemType == 'Receita')
      .fold<double>(0, (double total, BudgetItem item) => total + item.amount);

  double get _expenseTotal => _periodItems
      .where((BudgetItem item) => item.itemType == 'Despesa')
      .fold<double>(0, (double total, BudgetItem item) => total + item.amount);

  double get _pendingTotal => _periodItems
      .where((BudgetItem item) => item.itemType == 'Despesa' && !item.settled)
      .fold<double>(0, (double total, BudgetItem item) => total + item.amount);

  double get _paidTotal => _periodItems
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
      final http.Response response = await apiClient.get(
        widget.apiUriBuilder('/api/budget'),
        headers: _headers,
      );
      final Map<String, dynamic> body = await _decode(response);
      if (response.statusCode != 200 || body['ok'] != true) {
        throw BudgetApiException((body['message'] as String?) ??
            'Não foi possível carregar o orçamento.');
      }
      final List<dynamic> rawItems =
          (body['items'] as List<dynamic>?) ?? <dynamic>[];
      final List<dynamic> rawSuggestions =
          (body['expense_description_suggestions'] as List<dynamic>?) ??
              <dynamic>[];
      final List<dynamic> rawNatures =
          (body['expense_natures'] as List<dynamic>?) ?? <dynamic>[];
      if (!mounted) return;
      setState(() {
        _items = rawItems
            .map((dynamic item) =>
                BudgetItem.fromJson(item as Map<String, dynamic>))
            .toList();
        _availableMonths = ((body['months'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic value) => value.toString())
            .where((String value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        _monthStatuses = ((body['month_statuses'] as Map<String, dynamic>?) ??
                <String, dynamic>{})
            .map((String key, dynamic value) =>
                MapEntry<String, String>(key, '$value'));
        _monthImports = ((body['month_imports'] as Map<String, dynamic>?) ??
                <String, dynamic>{})
            .map((String key, dynamic value) =>
                MapEntry(key, Map<String, dynamic>.from(value as Map)));
        _expenseDescriptionSuggestions =
            rawSuggestions.map((dynamic item) => '$item').toList();
        _expenseNatures = rawNatures
            .map((dynamic item) =>
                ExpenseNature.fromJson(item as Map<String, dynamic>))
            .toList();
      });
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadReferenceRange() async {
    final Set<String> candidateSet = <String>{..._availableMonths, _month};
    if (_referenceFromFilter != 'Todos') {
      candidateSet.add(_referenceFromFilter);
    }
    if (_referenceToFilter != 'Todos') {
      candidateSet.add(_referenceToFilter);
    }
    final List<String> candidates = candidateSet.toList()..sort();
    if (candidates.isEmpty) return;
    final String start = _referenceFromFilter == 'Todos'
        ? candidates.first
        : _referenceFromFilter;
    final String end =
        _referenceToFilter == 'Todos' ? candidates.last : _referenceToFilter;
    final String lower = start.compareTo(end) <= 0 ? start : end;
    final String upper = start.compareTo(end) <= 0 ? end : start;
    final List<String> selected = candidates
        .where((String value) =>
            value.compareTo(lower) >= 0 && value.compareTo(upper) <= 0)
        .toList();

    setState(() => _loading = true);
    try {
      final List<http.Response> responses = await Future.wait(
        selected.map((String month) => apiClient.get(
              widget.apiUriBuilder('/api/budget').replace(
                queryParameters: <String, String>{'month': month},
              ),
              headers: _headers,
            )),
      );
      final List<BudgetItem> items = <BudgetItem>[];
      final Set<String> suggestions = <String>{};
      for (final http.Response response in responses) {
        final Map<String, dynamic> body = await _decode(response);
        if (response.statusCode != 200 || body['ok'] != true) {
          throw BudgetApiException((body['message'] as String?) ??
              'Não foi possível carregar o período selecionado.');
        }
        items.addAll(((body['items'] as List<dynamic>?) ?? <dynamic>[]).map(
            (dynamic item) =>
                BudgetItem.fromJson(item as Map<String, dynamic>)));
        suggestions.addAll(
            ((body['expense_description_suggestions'] as List<dynamic>?) ??
                    <dynamic>[])
                .map((dynamic item) => '$item'));
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _expenseDescriptionSuggestions = suggestions.toList()..sort();
      });
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Iterable<String> _descriptionOptions(TextEditingValue value) {
    return rankBudgetDescriptionSuggestions(
      _descriptionSuggestionsForItemType,
      value.text,
    );
  }

  List<String> get _descriptionSuggestionsForItemType => _itemType == 'Despesa'
      ? _expenseDescriptionSuggestions
      : uniqueBudgetDescriptionsForType(_items, 'Receita');

  bool get _descriptionMatchesHistory => isKnownBudgetDescription(
        _descriptionSuggestionsForItemType,
        _descriptionController.text,
      );

  Widget _descriptionField() {
    final bool expense = _itemType == 'Despesa';
    return RawAutocomplete<String>(
      textEditingController: _descriptionController,
      focusNode: _descriptionFocusNode,
      displayStringForOption: (option) => option,
      optionsBuilder: _descriptionOptions,
      onSelected: (String option) {
        _descriptionController.text = option;
        _descriptionController.selection =
            TextSelection.collapsed(offset: option.length);
        _amountFocusNode.requestFocus();
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          TextField(
        controller: controller,
        focusNode: focusNode,
        maxLength: 15,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: <TextInputFormatter>[UpperCaseTextFormatter()],
        onChanged: (_) => _updateState(() {}),
        onSubmitted: (_) {
          onSubmitted();
          _amountFocusNode.requestFocus();
        },
        decoration: _fieldDecoration(
          label: 'Descrição',
          icon: Icons.notes_rounded,
          counterText: '',
          hintText: 'Digite para consultar o histórico',
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) {
        final List<String> visible = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 10,
            color: _budgetPanel,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 280),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                    child: Text(
                        expense ? 'DESPESAS ANTERIORES' : 'RECEITAS ANTERIORES',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _budgetMuted)),
                  ),
                  Flexible(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final int highlighted =
                            AutocompleteHighlightedOption.of(context);
                        final bool selected = index == highlighted;
                        return InkWell(
                          onTap: () => onSelected(visible[index]),
                          child: Container(
                            color: selected ? _budgetSky : Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            child: Row(children: <Widget>[
                              Icon(Icons.history_rounded,
                                  size: 18,
                                  color: selected ? _budgetBlue : _budgetMuted),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(visible[index],
                                    style: TextStyle(
                                      color: _budgetInk,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                    )),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                    child: Text(
                      expense
                          ? 'Ou continue digitando para criar uma nova despesa.'
                          : 'Ou continue digitando para criar uma nova receita.',
                      style: const TextStyle(fontSize: 12, color: _budgetMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
      'reference_month': _formReferenceMonth,
      'item_type': _itemType,
      'tipo_receita': _itemType == 'Receita' ? _revenueType : null,
      'tipo_receita_outros': _itemType == 'Receita' && _revenueType == 'OUTROS'
          ? _otherRevenueTypeController.text.trim()
          : null,
      'expense_nature_id': _itemType == 'Despesa' ? _expenseNatureId : null,
      'description': _descriptionController.text.trim().toUpperCase(),
      'observation': _observationController.text,
      'amount_text': _amountController.text.trim(),
      'received_amount_text': _itemType == 'Receita'
          ? _receivedAmountController.text.trim()
          : '0,00',
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
          ? await apiClient.put(uri,
              headers: _headers, body: jsonEncode(payload))
          : await apiClient.post(uri,
              headers: _headers, body: jsonEncode(payload));
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
      final http.Response response = await apiClient.patch(
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
      final http.Response response = await apiClient.delete(
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
          expenseNatures: _expenseNatures,
          expenseDescriptionSuggestions: _expenseDescriptionSuggestions,
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

  Future<void> _openBudgetBi() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => BudgetBiScreen(
          apiUriBuilder: widget.apiUriBuilder,
          sessionToken: widget.sessionToken,
        ),
      ),
    );
  }

  Future<void> _saveExpenseNature({ExpenseNature? existing}) async {
    final TextEditingController controller =
        TextEditingController(text: existing?.name ?? '');
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(
            existing == null ? 'Nova natureza da despesa' : 'Editar natureza'),
        content: TextField(
          key: const Key('expense-nature-name'),
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textInputAction: TextInputAction.done,
          onSubmitted: (String value) => Navigator.pop(context, value),
          decoration: const InputDecoration(labelText: 'Nome'),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Salvar')),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    final Uri uri = widget.apiUriBuilder(existing == null
        ? '/api/budget/expense-natures'
        : '/api/budget/expense-natures/${existing.id}');
    final http.Response response = existing == null
        ? await apiClient.post(uri,
            headers: _headers,
            body: jsonEncode(<String, dynamic>{'name': name}))
        : await apiClient.put(uri,
            headers: _headers,
            body: jsonEncode(<String, dynamic>{'name': name}));
    final Map<String, dynamic> body = await _decode(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['ok'] != true) {
      throw BudgetApiException((body['message'] as String?) ??
          'Não foi possível salvar a natureza.');
    }
    await _loadBudget();
    if (mounted) {
      _showMessage(existing == null
          ? 'Natureza cadastrada com sucesso.'
          : 'Natureza atualizada com sucesso.');
    }
  }

  Future<void> _showExpenseNaturesDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter refresh) => AlertDialog(
          title: const Text('Naturezas da Despesa'),
          content: SizedBox(
            width: 520,
            child: _expenseNatures.isEmpty
                ? const Text('Nenhuma natureza cadastrada.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _expenseNatures.length,
                    itemBuilder: (_, int index) {
                      final ExpenseNature nature = _expenseNatures[index];
                      return ListTile(
                        title: Text(nature.name),
                        subtitle:
                            Text('${nature.usageCount} despesas vinculadas'),
                        leading: const Icon(Icons.category_outlined),
                        trailing: IconButton(
                            tooltip: 'Alterar nome',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              try {
                                await _saveExpenseNature(existing: nature);
                                refresh(() {});
                              } catch (error) {
                                if (mounted) {
                                  _showMessage(_messageFor(error), error: true);
                                }
                              }
                            }),
                      );
                    }),
          ),
          actions: <Widget>[
            TextButton.icon(
                onPressed: () async {
                  try {
                    await _saveExpenseNature();
                    refresh(() {});
                  } catch (error) {
                    if (mounted) _showMessage(_messageFor(error), error: true);
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Nova natureza')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Concluir')),
          ],
        ),
      ),
    );
  }

  Future<void> _categorizeSelectedExpenses() async {
    int? selectedNature;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (_, StateSetter refresh) => AlertDialog(
          title: const Text('Categorizar despesas em lote'),
          content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text('${_selectedExpenseIds.length} despesas serão modificadas.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              decoration:
                  const InputDecoration(labelText: 'Natureza da Despesa'),
              items: _expenseNatures
                  .where((ExpenseNature n) => n.active)
                  .map((ExpenseNature n) =>
                      DropdownMenuItem(value: n.id, child: Text(n.name)))
                  .toList(),
              onChanged: (int? value) => refresh(() => selectedNature = value),
            ),
          ]),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: selectedNature == null
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('Aplicar')),
          ],
        ),
      ),
    );
    if (confirmed != true || selectedNature == null) return;
    final http.Response response = await apiClient.post(
      widget.apiUriBuilder('/api/budget/categorize-expenses'),
      headers: _headers,
      body: jsonEncode(<String, dynamic>{
        'item_ids': _selectedExpenseIds.toList(),
        'expense_nature_id': selectedNature,
      }),
    );
    final Map<String, dynamic> body = await _decode(response);
    if (response.statusCode != 200 || body['ok'] != true) {
      throw BudgetApiException((body['message'] as String?) ??
          'Não foi possível categorizar as despesas.');
    }
    _selectedExpenseIds.clear();
    await _loadBudget();
    if (mounted) {
      _showMessage((body['message'] as String?) ??
          'Despesas categorizadas com sucesso.');
    }
  }

  void _clearForm() {
    _updateState(() {
      _editingId = null;
      _itemType = 'Despesa';
      _formReferenceMonth = _month;
      _revenueType = null;
      _expenseNatureId = null;
      _otherRevenueTypeController.clear();
      _descriptionController.clear();
      _observationController.clear();
      _amountController.clear();
      _receivedAmountController.clear();
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
    if (_itemType == 'Despesa' &&
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(_formReferenceMonth)) {
      return 'Informe o mês de referência da despesa.';
    }
    if (_itemType == 'Receita' && _revenueType == null) {
      return 'Selecione o tipo de receita.';
    }
    if (_itemType == 'Despesa' &&
        _expenseNatures.any((ExpenseNature item) => item.active) &&
        _expenseNatureId == null) {
      return 'Informe a natureza da despesa.';
    }
    if (_itemType == 'Receita' &&
        _revenueType == 'OUTROS' &&
        _otherRevenueTypeController.text.trim().isEmpty) {
      return 'Especifique o tipo de receita.';
    }
    if (_descriptionController.text.trim().isEmpty) {
      return 'Informe a descrição.';
    }
    if (_parseAmount(_amountController.text) <= 0) {
      return 'Informe um valor maior que zero.';
    }
    if (_itemType == 'Receita' &&
        _parseAmount(_receivedAmountController.text) >
            _parseAmount(_amountController.text)) {
      return 'O valor recebido nÃ£o pode superar o valor total.';
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

  List<String> get _activeReportFilters {
    final List<String> filters = <String>[
      _showAllPeriods
          ? 'Período: todos os meses'
          : 'Período: ${_monthLabel(_month)}',
    ];
    final String search = _searchController.text.trim();
    if (search.isNotEmpty) filters.add('Busca: $search');
    if (_typeFilter != 'Todos') filters.add('Tipo: $_typeFilter');
    if (_statusFilter != 'Todos') filters.add('Situação: $_statusFilter');
    if (_expenseNatureFilter != 'Todas') {
      String natureLabel = _expenseNatureFilter;
      for (final ExpenseNature nature in _expenseNatures) {
        if (nature.id.toString() == _expenseNatureFilter) {
          natureLabel = nature.name;
          break;
        }
      }
      filters.add('Natureza: $natureLabel');
    }
    if (_revenueTypeFilter != 'Todos') {
      filters.add('Tipo de receita: $_revenueTypeFilter');
    }
    if (_referenceFromFilter != 'Todos') {
      filters.add('Competência inicial: ${_monthLabel(_referenceFromFilter)}');
    }
    if (_referenceToFilter != 'Todos') {
      filters.add('Competência final: ${_monthLabel(_referenceToFilter)}');
    }
    if (_dueMonthFilter != 'Todos') {
      filters.add('Vencimento: ${_monthLabel(_dueMonthFilter)}');
    }
    if (_paymentMonthFilter != 'Todos') {
      filters.add(
          'Pagamento: ${_paymentMonthFilter == 'Não pagas' ? _paymentMonthFilter : _monthLabel(_paymentMonthFilter)}');
    }
    filters.add('Ordenação: $_sortBy');
    return filters;
  }

  Future<void> _printCurrentView() async {
    final List<BudgetItem> visibleItems = List<BudgetItem>.from(_filteredItems);
    setState(() => _printing = true);
    try {
      final Uint8List bytes = await buildBudgetListingReportPdf(
        items: visibleItems,
        filters: List<String>.from(_activeReportFilters),
        generatedAt: DateTime.now(),
      );
      await Printing.layoutPdf(
        name: 'Meu-Orcamento-EKT.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (error) {
      if (mounted) {
        _showMessage('Não foi possível preparar o relatório para impressão.',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
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
              key: const Key('print-current-budget-appbar'),
              tooltip: 'Imprimir o que está sendo exibido',
              onPressed: _loading || _printing ? null : _printCurrentView,
              icon: _printing
                  ? const SizedBox.square(
                      dimension: 19,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.print_outlined)),
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
    return ListView(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 18),
      children: <Widget>[
        _buildMonthHeader(compactHeight: true),
        const SizedBox(height: 12),
        _buildMetrics(),
        const SizedBox(height: 12),
        _buildCompactActions(),
        const SizedBox(height: 12),
        SizedBox(
          height: 720,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: 370,
                child: SingleChildScrollView(child: _buildForm()),
              ),
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
    );
  }

  Widget _buildCompactWorkspace(double horizontalPadding) {
    return ListView(
      primary: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 24),
      children: <Widget>[
        _buildMonthHeader(),
        const SizedBox(height: 12),
        _buildMetrics(),
        const SizedBox(height: 12),
        _buildCompactActions(),
        const SizedBox(height: 12),
        _buildFilters(),
        const SizedBox(height: 12),
        _buildEntries(expandList: false),
      ],
    );
  }

  List<String> get _primaryPeriodOptions {
    final List<String> months = <String>{
      _month,
      ..._availableMonths,
      ..._items
          .map((BudgetItem item) => item.referenceMonth)
          .where((String value) => value.isNotEmpty),
    }.toList()
      ..sort((String a, String b) => b.compareTo(a));
    return <String>['Todos', ...months];
  }

  void _selectPrimaryPeriod(String? value) {
    if (value == null) return;
    final bool showAll = value == 'Todos';
    if (showAll == _showAllPeriods && (showAll || value == _month)) return;
    setState(() {
      _showAllPeriods = showAll;
      if (!showAll) _month = value;
      _referenceFromFilter = showAll ? 'Todos' : value;
      _referenceToFilter = showAll ? 'Todos' : value;
      _selectedExpenseIds.clear();
    });
    _clearForm();
  }

  Widget _buildPrimaryPeriodFilter() {
    final String selectedValue = _showAllPeriods ? 'Todos' : _month;
    return Container(
      key: const Key('budget-primary-period-filter'),
      width: 250,
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFFE3A2), Color(0xFFF5BC4C)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFA66519), width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
              color: Color(0x44804C0F), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: ValueKey<String>('budget-primary-period-$selectedValue'),
          value: selectedValue,
          isExpanded: true,
          borderRadius: BorderRadius.circular(14),
          dropdownColor: const Color(0xFFFFF8E8),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF5E3509)),
          selectedItemBuilder: (BuildContext context) => _primaryPeriodOptions
              .map((String value) => Row(
                    children: <Widget>[
                      const Icon(Icons.calendar_month_rounded,
                          color: Color(0xFF5E3509), size: 21),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text('PERÍODO PRINCIPAL',
                                style: TextStyle(
                                    color: Color(0xFF6F4310),
                                    fontSize: 9,
                                    letterSpacing: .7,
                                    fontWeight: FontWeight.w900)),
                            Text(
                              value == 'Todos'
                                  ? 'Todos os meses'
                                  : _monthLabel(value),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Color(0xFF3F2507),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ))
              .toList(),
          items: _primaryPeriodOptions
              .map((String value) => DropdownMenuItem<String>(
                    value: value,
                    child: Text(value == 'Todos'
                        ? 'Todos os meses'
                        : _monthLabel(value)),
                  ))
              .toList(),
          onChanged: _selectPrimaryPeriod,
        ),
      ),
    );
  }

  String get _selectedMonthStatus => _monthStatuses[_month] ?? 'open';

  Future<void> _changeMonthStatus(String? status) async {
    if (status == null || _showAllPeriods || status == _selectedMonthStatus) {
      return;
    }
    final bool closing = status == 'closed';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        icon: Icon(
          closing
              ? Icons.event_available_rounded
              : Icons.pending_actions_rounded,
          color: closing ? _budgetGreen : _budgetAmber,
        ),
        title: Text(closing ? 'Encerrar este mês?' : 'Reabrir este mês?'),
        content: Text(
          closing
              ? '${_monthLabel(_month)} será rotulado como encerrado. Isso não altera despesas pendentes nem impede edições manuais.'
              : '${_monthLabel(_month)} voltará ao status em andamento e não estará elegível para futuras importações.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(closing ? 'Encerrar mês' : 'Reabrir mês'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final http.Response response = await apiClient.patch(
        widget.apiUriBuilder('/api/budget/month-status'),
        headers: _headers,
        body: jsonEncode(<String, String>{
          'reference_month': _month,
          'status': status,
        }),
      );
      final Map<String, dynamic> body = await _decode(response);
      if (response.statusCode != 200 || body['ok'] != true) {
        throw BudgetApiException((body['message'] as String?) ??
            'Não foi possível alterar o status mensal.');
      }
      if (!mounted) return;
      setState(() {
        _monthStatuses = ((body['month_statuses'] as Map<String, dynamic>?) ??
                <String, dynamic>{})
            .map((String key, dynamic value) =>
                MapEntry<String, String>(key, '$value'));
      });
      _showMessage(closing
          ? '${_monthLabel(_month)} foi encerrado.'
          : '${_monthLabel(_month)} está em andamento.');
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildMonthStatusControl() {
    final bool disabled = _showAllPeriods;
    final bool closed = !disabled && _selectedMonthStatus == 'closed';
    final Color accent = closed ? _budgetGreen : _budgetAmber;
    return Container(
      key: const Key('budget-month-status-control'),
      width: 230,
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color:
            disabled ? const Color(0xFFE5E1DA) : accent.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: disabled ? _budgetMuted : accent, width: 1.6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: closed ? 'closed' : 'open',
          isExpanded: true,
          onChanged: disabled || _saving ? null : _changeMonthStatus,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: accent),
          selectedItemBuilder: (BuildContext context) => <String>[
            'open',
            'closed'
          ]
              .map((String value) => Row(
                    children: <Widget>[
                      Icon(
                        value == 'closed'
                            ? Icons.event_available_rounded
                            : Icons.pending_actions_rounded,
                        color: disabled ? _budgetMuted : accent,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text('STATUS DO MÊS',
                                style: TextStyle(
                                    fontSize: 9, fontWeight: FontWeight.w900)),
                            Text(
                              disabled
                                  ? 'Selecione um mês'
                                  : value == 'closed'
                                      ? 'Mês encerrado'
                                      : 'Mês em andamento',
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ))
              .toList(),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem(value: 'open', child: Text('Mês em andamento')),
            DropdownMenuItem(value: 'closed', child: Text('Mês encerrado')),
          ],
        ),
      ),
    );
  }

  String _previousMonth(String month) {
    final List<int> parts = month.split('-').map(int.parse).toList();
    return parts[1] == 1
        ? '${parts[0] - 1}-12'
        : '${parts[0]}-${(parts[1] - 1).toString().padLeft(2, '0')}';
  }

  Future<void> _importPreviousMonth() async {
    if (_showAllPeriods || _selectedMonthStatus == 'closed') return;
    if (_monthImports.containsKey(_month)) {
      _showMessage('Acesso negado: esse mês já teve uma importação.',
          error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final http.Response previewResponse = await apiClient.post(
        widget.apiUriBuilder('/api/budget/import-previous-month-preview'),
        headers: _headers,
        body: jsonEncode(<String, String>{'target_month': _month}),
      );
      final Map<String, dynamic> preview = await _decode(previewResponse);
      if (previewResponse.statusCode != 200 || preview['ok'] != true) {
        throw BudgetApiException((preview['message'] as String?) ??
            'Não foi possível revisar a importação.');
      }
      if (preview['already_imported'] == true) {
        throw const BudgetApiException(
            'Acesso negado: esse mês já teve uma importação.');
      }
      if (preview['target_status'] == 'closed') {
        throw const BudgetApiException(
            'Acesso negado: mês encerrado não permite importação.');
      }
      if (preview['source_status'] != 'closed') {
        throw BudgetApiException(
            'Encerre ${_monthLabel('${preview['source_month']}')} antes de importar.');
      }
      if (!mounted) return;
      bool authorized = false;
      final bool? confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) =>
              AlertDialog(
            icon: const Icon(Icons.fact_check_rounded,
                color: _budgetBlue, size: 34),
            title: const Text('Revisão da importação'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildImportReviewRow('Mês de origem',
                        _monthLabel('${preview['source_month']}')),
                    _buildImportReviewRow('Mês de destino',
                        _monthLabel('${preview['target_month']}')),
                    _buildImportReviewRow('Despesas a copiar',
                        '${preview['expense_count'] ?? 0}'),
                    _buildImportReviewRow('Valor total estimado',
                        '${preview['total_amount_text'] ?? 'R\$ 0,00'}'),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _budgetAmber.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _budgetAmber.withValues(alpha: .55)),
                      ),
                      child: const Text(
                        'Todas as despesas entrarão como pendentes e sem data de pagamento. Esta importação só pode ser realizada uma vez para o mês de destino.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      key: const Key('authorize-budget-import'),
                      value: authorized,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: _budgetGreen,
                      title: const Text(
                        'Conferi os períodos e autorizo a importação',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onChanged: (bool? value) =>
                          setDialogState(() => authorized = value ?? false),
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                key: const Key('confirm-budget-import'),
                onPressed: authorized
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                icon: const Icon(Icons.download_done_rounded),
                label: const Text('Confirmar importação'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      final http.Response response = await apiClient.post(
        widget.apiUriBuilder('/api/budget/import-previous-month'),
        headers: _headers,
        body: jsonEncode(<String, String>{'target_month': _month}),
      );
      final Map<String, dynamic> body = await _decode(response);
      if (response.statusCode != 200 || body['ok'] != true) {
        throw BudgetApiException((body['message'] as String?) ??
            'Não foi possível importar o mês anterior.');
      }
      final int imported = (body['imported_count'] as num?)?.toInt() ?? 0;
      await _loadBudget();
      if (!mounted) return;
      _showMessage(
          '$imported despesa${imported == 1 ? '' : 's'} importada${imported == 1 ? '' : 's'} como pendente${imported == 1 ? '' : 's'}.');
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildImportReviewRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: <Widget>[
            Expanded(
                child:
                    Text(label, style: const TextStyle(color: _budgetMuted))),
            const SizedBox(width: 16),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      );

  Widget _buildImportPreviousMonthButton() {
    final bool enabled = !_showAllPeriods && _selectedMonthStatus == 'open';
    final String sourceMonth = _previousMonth(_month);
    final bool sourceClosed = _monthStatuses[sourceMonth] == 'closed';
    final bool alreadyImported = _monthImports.containsKey(_month);
    return Tooltip(
      message: alreadyImported
          ? 'Acesso negado: esse mês já teve uma importação.'
          : !enabled
              ? (_showAllPeriods
                  ? 'Selecione um mês em andamento'
                  : 'Mês encerrado: importação desabilitada')
              : sourceClosed
                  ? 'Copiar despesas de ${_monthLabel(sourceMonth)}'
                  : 'Encerre ${_monthLabel(sourceMonth)} antes de importar',
      child: OutlinedButton.icon(
        key: const Key('import-previous-budget-month'),
        onPressed: enabled && sourceClosed && !alreadyImported && !_saving
            ? _importPreviousMonth
            : null,
        icon: Icon(
            alreadyImported
                ? Icons.verified_rounded
                : Icons.content_copy_rounded,
            size: 19),
        label: Text(alreadyImported
            ? 'Importação já realizada'
            : 'Importar mês anterior'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          foregroundColor: _budgetNavy,
          side: const BorderSide(color: _budgetNavy, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildImportedMonthBadge() {
    final Map<String, dynamic>? importData = _monthImports[_month];
    if (_showAllPeriods || importData == null) return const SizedBox.shrink();
    final int count = (importData['imported_count'] as num?)?.toInt() ?? 0;
    final String source = '${importData['source_month'] ?? ''}';
    return Container(
      key: const Key('budget-month-imported-badge'),
      constraints: const BoxConstraints(minHeight: 52, maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _budgetGreen.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _budgetGreen.withValues(alpha: .65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.verified_user_rounded, color: _budgetGreen),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('MÊS COM DADOS IMPORTADOS',
                    style:
                        TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                Text(
                  '${_monthLabel(source)} → ${_monthLabel(_month)} • $count despesa${count == 1 ? '' : 's'}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactActions() {
    ButtonStyle accessButtonStyle(Color background, Color foreground) =>
        OutlinedButton.styleFrom(
          foregroundColor: foreground,
          disabledForegroundColor: foreground,
          backgroundColor: background,
          disabledBackgroundColor: background,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: background, width: 1.3),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        );
    return Card(
      key: const Key('budget-primary-actions'),
      margin: EdgeInsets.zero,
      elevation: 4,
      color: _budgetPanel,
      shadowColor: const Color(0x407A5A3A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFD9BE98)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilledButton.icon(
              key: const Key('open-new-budget-entry'),
              onPressed: _showFormDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Novo lançamento'),
              style: FilledButton.styleFrom(
                backgroundColor: _budgetBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
              ),
            ),
            OutlinedButton.icon(
              key: const Key('print-current-budget'),
              onPressed: _loading || _printing ? null : _printCurrentView,
              icon: const Icon(Icons.print_outlined, size: 19),
              label: const Text('Imprimir relatório'),
              style: accessButtonStyle(const Color(0xFF315E7D), Colors.white),
            ),
            OutlinedButton.icon(
              key: const Key('open-cash-report'),
              onPressed: _openCashReport,
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 19),
              label: const Text('Caixa'),
              style: accessButtonStyle(const Color(0xFF3677A8), Colors.white),
            ),
            OutlinedButton.icon(
              key: const Key('open-budget-bi'),
              onPressed: _openBudgetBi,
              icon: const Icon(Icons.insights_rounded, size: 19),
              label: const Text('BI-Orçamento'),
              style: accessButtonStyle(
                  const Color(0xFFE3B341), const Color(0xFF3D2B0C)),
            ),
            OutlinedButton.icon(
              key: const Key('bank-balance-placeholder'),
              onPressed: null,
              icon: const Icon(Icons.account_balance_outlined, size: 19),
              label: const Text('Saldo Bancário'),
              style: accessButtonStyle(const Color(0xFF568166), Colors.white),
            ),
            OutlinedButton.icon(
              key: const Key('open-expense-natures'),
              onPressed: _showExpenseNaturesDialog,
              icon: const Icon(Icons.category_outlined, size: 19),
              label: const Text('Configurar Despesas'),
              style: accessButtonStyle(const Color(0xFF7B5A93), Colors.white),
            ),
            _buildPrimaryPeriodFilter(),
            _buildMonthStatusControl(),
            _buildImportPreviousMonthButton(),
            _buildImportedMonthBadge(),
          ],
        ),
      ),
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
                    Flexible(
                      child: Text('EKT IA SYSTEMS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: _budgetNavy,
                              fontSize: 11,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w800)),
                    ),
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
              Text(_showAllPeriods ? 'Todos os meses' : _monthLabel(_month),
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
            child: illustration,
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
            height: 96,
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
          height: 96,
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
    final Widget chips = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            ...const <String>['Todos', 'Receita', 'Despesa'].map(
              (String value) => FilterChip(
                label: Text(value),
                selected: _typeFilter == value,
                onSelected: (_) {
                  setState(() {
                    _typeFilter = value;
                    if (value == 'Todos') {
                      _revenueTypeFilter = 'Todos';
                      _dueMonthFilter = 'Todos';
                      _paymentMonthFilter = 'Todos';
                      _searchController.clear();
                    }
                  });
                },
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
            ...const <String>['Quitado', 'Pendente'].map(
              (String value) => FilterChip(
                label: Text(value),
                selected: _statusFilter == value,
                onSelected: (bool selected) => setState(() {
                  _statusFilter = selected ? value : 'Todos';
                }),
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
        const SizedBox(height: 12),
        SizedBox(
          width: 245,
          child: Material(
            color: const Color(0xFFEAF5FF),
            elevation: 2,
            shadowColor: const Color(0x3378B7F0),
            borderRadius: BorderRadius.circular(16),
            child: DropdownButtonFormField<String>(
              key: const Key('budget-expense-nature-filter'),
              initialValue: _expenseNatureFilter,
              isExpanded: true,
              borderRadius: BorderRadius.circular(16),
              dropdownColor: const Color(0xFFF5FAFF),
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: _budgetBlue),
              style: const TextStyle(
                color: _budgetInk,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                labelText: 'Natureza da despesa',
                labelStyle: const TextStyle(
                  color: _budgetBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                prefixIcon: const Icon(Icons.category_rounded,
                    color: _budgetBlue, size: 20),
                filled: true,
                fillColor: const Color(0xFFEAF5FF),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: Color(0xFF8CC4F4), width: 1.2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: Color(0xFF8CC4F4), width: 1.2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _budgetBlue, width: 1.8),
                ),
              ),
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem(
                    value: 'Todas', child: Text('Todas as naturezas')),
                const DropdownMenuItem(
                    value: 'Sem categoria', child: Text('Sem categoria')),
                ..._expenseNatures
                    .where((ExpenseNature n) => n.active || n.usageCount > 0)
                    .map((ExpenseNature n) => DropdownMenuItem(
                        value: n.id.toString(),
                        child:
                            Text(n.active ? n.name : '${n.name} (inativa)'))),
              ],
              onChanged: (String? value) =>
                  setState(() => _expenseNatureFilter = value ?? 'Todas'),
            ),
          ),
        ),
      ],
    );
    final Widget revenueTypeFilter = DropdownButtonFormField<String>(
      key: const Key('budget-revenue-type-filter'),
      initialValue: _revenueTypeFilter,
      decoration: _fieldDecoration(
        label: 'Tipo de Receita',
        icon: Icons.category_outlined,
      ),
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem(value: 'Todos', child: Text('Todos')),
        DropdownMenuItem(value: 'ALUGUEL', child: Text('Aluguel')),
        DropdownMenuItem(value: 'DAY_TRADE', child: Text('Day Trade')),
        DropdownMenuItem(value: 'OUTROS', child: Text('Outros')),
      ],
      onChanged: (String? value) =>
          setState(() => _revenueTypeFilter = value ?? 'Todos'),
    );
    final List<String> referenceOptions = <String>{
      _month,
      ..._availableMonths,
      if (_referenceFromFilter != 'Todos') _referenceFromFilter,
      if (_referenceToFilter != 'Todos') _referenceToFilter,
    }.toList()
      ..sort();
    final List<String> referenceFilterOptions = <String>[
      'Todos',
      ...referenceOptions,
    ];
    final Widget referenceFromFilter = DropdownButtonFormField<String>(
      key: ValueKey<String>('budget-reference-from-$_referenceFromFilter'),
      initialValue: _referenceFromFilter,
      decoration: _fieldDecoration(
        label: 'Competência inicial',
        icon: Icons.date_range_outlined,
      ),
      items: referenceFilterOptions
          .map((String value) => DropdownMenuItem<String>(
                value: value,
                child: Text(value == 'Todos' ? value : _monthLabel(value)),
              ))
          .toList(),
      onChanged: (String? value) {
        setState(() => _referenceFromFilter = value ?? 'Todos');
        _loadReferenceRange();
      },
    );
    final Widget referenceToFilter = DropdownButtonFormField<String>(
      key: ValueKey<String>('budget-reference-to-$_referenceToFilter'),
      initialValue: _referenceToFilter,
      decoration: _fieldDecoration(
        label: 'Competência final',
        icon: Icons.event_available_outlined,
      ),
      items: referenceFilterOptions
          .map((String value) => DropdownMenuItem<String>(
                value: value,
                child: Text(value == 'Todos' ? value : _monthLabel(value)),
              ))
          .toList(),
      onChanged: (String? value) {
        setState(() => _referenceToFilter = value ?? 'Todos');
        _loadReferenceRange();
      },
    );
    final Widget dueMonthFilter = DropdownButtonFormField<String>(
      key: ValueKey<String>('budget-due-filter-$_dueMonthFilter'),
      initialValue: _dueMonthFilter,
      decoration: _fieldDecoration(
        label: 'Mês de Vencimento',
        icon: Icons.event_outlined,
      ),
      items: _dueMonthOptions
          .map((String value) => DropdownMenuItem<String>(
                value: value,
                child: Text(value == 'Todos' ? value : _monthLabel(value)),
              ))
          .toList(),
      onChanged: (String? value) =>
          setState(() => _dueMonthFilter = value ?? 'Todos'),
    );
    final Widget paymentMonthFilter = DropdownButtonFormField<String>(
      key: ValueKey<String>('budget-payment-filter-$_paymentMonthFilter'),
      initialValue: _paymentMonthFilter,
      decoration: _fieldDecoration(
        label: 'Mês de Pagamento',
        icon: Icons.price_check_outlined,
      ),
      items: _paymentMonthOptions
          .map((String value) => DropdownMenuItem<String>(
                value: value,
                child: Text(value == 'Todos' || value == 'Não pagas'
                    ? value
                    : _monthLabel(value)),
              ))
          .toList(),
      onChanged: (String? value) =>
          setState(() => _paymentMonthFilter = value ?? 'Todos'),
    );
    final Widget sortField = DropdownButtonFormField<String>(
      key: ValueKey<String>('budget-sort-$_sortBy'),
      initialValue: _sortBy,
      decoration: _fieldDecoration(
        label: 'Ordenar por',
        icon: Icons.sort_rounded,
      ),
      items: const <String>[
        'Mês de Referência',
        'Data de Vencimento',
        'Data de Pagamento'
      ]
          .map((String value) =>
              DropdownMenuItem<String>(value: value, child: Text(value)))
          .toList(),
      onChanged: (String? value) =>
          setState(() => _sortBy = value ?? 'Mês de Referência'),
    );
    return _BudgetPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          header,
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final bool wide = constraints.maxWidth >= 760;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(flex: 2, child: search),
                  const SizedBox(width: 12),
                  Expanded(flex: 3, child: chips),
                ],
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                search,
                const SizedBox(height: 10),
                chips,
              ],
            );
          }),
          if (_showAdvancedFilters) ...<Widget>[
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, constraints) {
              final double fieldWidth = switch (constraints.maxWidth) {
                >= 900 => 205,
                >= 620 => (constraints.maxWidth - 20) / 3,
                >= 420 => (constraints.maxWidth - 10) / 2,
                _ => constraints.maxWidth,
              };
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  SizedBox(width: fieldWidth, child: referenceFromFilter),
                  SizedBox(width: fieldWidth, child: referenceToFilter),
                  SizedBox(width: fieldWidth, child: revenueTypeFilter),
                  SizedBox(width: fieldWidth, child: dueMonthFilter),
                  SizedBox(width: fieldWidth, child: paymentMonthFilter),
                  SizedBox(width: fieldWidth, child: sortField),
                ],
              );
            }),
          ],
        ],
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
            onSelectionChanged: (Set<String> selected) => _updateState(() {
              _itemType = selected.first;
              if (_itemType != 'Receita') {
                _revenueType = null;
                _otherRevenueTypeController.clear();
              }
            }),
          ),
          const SizedBox(height: 10),
          if (_itemType == 'Receita') ...<Widget>[
            DropdownButtonFormField<String>(
              key: const Key('budget-new-revenue-type'),
              initialValue: _revenueType,
              decoration: _fieldDecoration(
                label: 'Tipo de Receita',
                icon: Icons.category_outlined,
              ),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'ALUGUEL', child: Text('Aluguel')),
                DropdownMenuItem(value: 'DAY_TRADE', child: Text('Day Trade')),
                DropdownMenuItem(value: 'OUTROS', child: Text('Outros')),
              ],
              onChanged: (String? value) => _updateState(() {
                _revenueType = value;
                if (value != 'OUTROS') {
                  _otherRevenueTypeController.clear();
                }
              }),
            ),
            if (_revenueType == 'OUTROS') ...<Widget>[
              const SizedBox(height: 10),
              TextField(
                key: const Key('budget-new-revenue-type-other'),
                controller: _otherRevenueTypeController,
                maxLength: 80,
                textInputAction: TextInputAction.next,
                decoration: _fieldDecoration(
                  label: 'Especifique o tipo de receita',
                  icon: Icons.edit_note_rounded,
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: 10),
          ],
          if (_itemType == 'Despesa') ...<Widget>[
            if (_expenseNatures.any((ExpenseNature item) => item.active))
              DropdownMenu<int>(
                key: const Key('budget-new-expense-nature'),
                initialSelection: _expenseNatureId,
                enableFilter: true,
                requestFocusOnTap: true,
                expandedInsets: EdgeInsets.zero,
                label: const Text('Natureza da Despesa'),
                leadingIcon: const Icon(Icons.category_outlined),
                dropdownMenuEntries: _expenseNatures
                    .where((ExpenseNature item) => item.active)
                    .map((ExpenseNature item) => DropdownMenuEntry<int>(
                        value: item.id, label: item.name))
                    .toList(),
                onSelected: (int? value) {
                  _updateState(() => _expenseNatureId = value);
                  _descriptionFocusNode.requestFocus();
                },
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _budgetField,
                    borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Row(children: <Widget>[
                      Icon(Icons.info_outline),
                      SizedBox(width: 8),
                      Expanded(child: Text('Nenhuma natureza cadastrada')),
                    ]),
                    const SizedBox(height: 4),
                    const Text('Cadastre uma natureza antes da nova despesa.'),
                    TextButton(
                      onPressed: _showExpenseNaturesDialog,
                      child: const Text('Cadastrar natureza da despesa'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
          ],
          DropdownButtonFormField<String>(
            key: ValueKey<String>(
                'budget-new-reference-month-$_formReferenceMonth'),
            initialValue: _formReferenceMonth,
            autofocus: true,
            decoration: _fieldDecoration(
              label: 'Mês de Referência',
              icon: Icons.calendar_view_month_rounded,
            ),
            items: _monthOptions
                .map((String value) => DropdownMenuItem<String>(
                    value: value, child: Text(_monthLabel(value))))
                .toList(),
            onChanged: (String? value) => _updateState(
                () => _formReferenceMonth = value ?? _formReferenceMonth),
          ),
          const SizedBox(height: 10),
          _dateField(_dueDateController, 'Data de Vencimento'),
          const SizedBox(height: 10),
          _dateField(
            _paymentDateController,
            'Data de Pagamento',
            isRequired: false,
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _descriptionField(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _amountController,
                  focusNode: _amountFocusNode,
                  onChanged: (_) => _updateState(() {}),
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
          ...<Widget>[
            const SizedBox(height: 6),
            Row(
              key: const Key('budget-description-mode-hint'),
              children: <Widget>[
                Icon(
                  _descriptionMatchesHistory
                      ? Icons.history_rounded
                      : Icons.add_circle_outline_rounded,
                  size: 16,
                  color:
                      _descriptionMatchesHistory ? _budgetBlue : _budgetMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _descriptionController.text.trim().isEmpty
                        ? _itemType == 'Despesa'
                            ? 'Digite as iniciais para buscar despesas anteriores.'
                            : 'Digite as iniciais para buscar receitas anteriores.'
                        : _descriptionMatchesHistory
                            ? 'Descrição anterior selecionada.'
                            : _itemType == 'Despesa'
                                ? 'Nova descrição — será cadastrada ao salvar.'
                                : 'Nova descrição de receita — será cadastrada ao salvar.',
                    style: const TextStyle(fontSize: 12, color: _budgetMuted),
                  ),
                ),
              ],
            ),
          ],
          if (_itemType == 'Receita') ...<Widget>[
            const SizedBox(height: 10),
            TextField(
              key: const Key('budget-new-received-amount'),
              controller: _receivedAmountController,
              onChanged: (_) => _updateState(() {
                _settled = _parseAmount(_amountController.text) > 0 &&
                    _parseAmount(_receivedAmountController.text) >=
                        _parseAmount(_amountController.text);
              }),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
              ],
              decoration: _fieldDecoration(
                  label: 'Valor recebido (parcial)',
                  icon: Icons.account_balance_wallet_outlined,
                  prefixText: 'R\$ ',
                  hintText: '0,00'),
            ),
            const SizedBox(height: 6),
            Text(
              'Saldo a receber: ${_formatCurrency((_parseAmount(_amountController.text) - _parseAmount(_receivedAmountController.text)).clamp(0, double.infinity))}',
              style: const TextStyle(
                  color: _budgetBlue, fontWeight: FontWeight.w800),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            key: const Key('budget-new-observation'),
            controller: _observationController,
            maxLength: 500,
            minLines: 3,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: _fieldDecoration(
              label: 'Observação',
              icon: Icons.chat_bubble_outline_rounded,
              counterText: 'máximo de 500 caracteres',
            ),
          ),
          if (_itemType == 'Receita') ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                    child: _dateField(_dueDateController, 'Vencimento / data')),
                const SizedBox(width: 10),
                Expanded(
                  child: _dateField(
                    _paymentDateController,
                    'Data do recebimento',
                    isRequired: false,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: _settled,
            title: Text(_itemType == 'Receita' ? 'Recebido' : 'Pago'),
            onChanged: (bool? value) => _updateState(() {
              _settled = value ?? false;
              if (!_settled) {
                if (_parseAmount(_receivedAmountController.text) == 0) {
                  _paymentDateController.clear();
                }
              } else if (_paymentDateController.text.isEmpty) {
                if (_itemType == 'Receita') {
                  _receivedAmountController.text = _amountController.text;
                }
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
      key: const Key('budget-entries-panel'),
      child: Column(
        mainAxisSize: expandList ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionHeader(
            icon: Icons.receipt_long_rounded,
            title: 'Lançamentos',
            subtitle:
                _showAllPeriods ? 'Todos os períodos' : _monthLabel(_month),
            trailing: _showFilteredHomogeneousTotal
                ? _ListedTotalPill(value: _filteredDisplayedTotal)
                : null,
          ),
          if (_selectedExpenseIds.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('categorize-selected-expenses'),
              onPressed: () async {
                try {
                  await _categorizeSelectedExpenses();
                } catch (error) {
                  if (mounted) _showMessage(_messageFor(error), error: true);
                }
              },
              icon: const Icon(Icons.category_outlined),
              label: Text(
                  'Aplicar natureza a ${_selectedExpenseIds.length} despesas'),
            ),
          ],
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
      key: ValueKey<String>('budget-entry-${item.id}'),
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
              if (!revenue) ...<Widget>[
                Text(
                  'Referência: ${_monthLabel(item.referenceMonth)}  •  '
                  'Vencimento: ${_dateToDisplay(item.dueDate)}  •  '
                  'Pagamento: ${item.paymentDate.isEmpty ? 'Não pago' : _dateToDisplay(item.paymentDate)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _budgetNavy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
              ],
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
                  if (revenue)
                    _StatusPill(
                      label: item.revenueTypeLabel,
                      icon: Icons.category_outlined,
                      color: _budgetBlue,
                    ),
                  if (!revenue)
                    _ExpenseNatureLabel(
                      itemId: item.id,
                      label: item.expenseNatureLabel,
                      categorized: item.hasExpenseNature,
                    ),
                  _StatusPill(
                    label: statusText,
                    icon: statusIcon,
                    color: statusColor,
                    emphasized: item.settled,
                  ),
                ],
              ),
              if (revenue) ...<Widget>[
                const SizedBox(height: 7),
                Text(
                  'Vencimento: ${_dateToDisplay(item.dueDate)}${item.paymentDate.isEmpty ? '' : ' • Pagamento: ${_dateToDisplay(item.paymentDate)}'}',
                  style: const TextStyle(fontSize: 11, color: _budgetMuted),
                ),
              ],
              if (item.observation.isNotEmpty) ...<Widget>[
                const SizedBox(height: 7),
                Text(
                  item.observation,
                  softWrap: true,
                  style: const TextStyle(fontSize: 12, color: _budgetInk),
                ),
              ],
            ],
          );
          final Widget actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (!revenue)
                Checkbox(
                  key: ValueKey<String>('select-budget-expense-${item.id}'),
                  value: _selectedExpenseIds.contains(item.id),
                  onChanged: (bool? selected) => setState(() {
                    if (selected == true) {
                      _selectedExpenseIds.add(item.id);
                    } else {
                      _selectedExpenseIds.remove(item.id);
                    }
                  }),
                ),
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
                Text(
                    _formatCurrency(revenue && !item.settled
                        ? item.remainingAmount
                        : item.amount),
                    style: TextStyle(
                        color: accent,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: details),
              const SizedBox(width: 8),
              Text(
                  _formatCurrency(revenue && !item.settled
                      ? item.remainingAmount
                      : item.amount),
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
    required this.expenseNatures,
    required this.expenseDescriptionSuggestions,
  });

  final ApiUriBuilder apiUriBuilder;
  final String sessionToken;
  final String referenceMonth;
  final BudgetItem item;
  final List<ExpenseNature> expenseNatures;
  final List<String> expenseDescriptionSuggestions;

  @override
  State<_BudgetEditScreen> createState() => _BudgetEditScreenState();
}

class _BudgetEditScreenState extends State<_BudgetEditScreen> {
  final FocusNode _descriptionFocusNode = FocusNode();
  late final TextEditingController _descriptionController;
  late final TextEditingController _observationController;
  late final TextEditingController _amountController;
  late final TextEditingController _receivedAmountController;
  late final TextEditingController _dueDateController;
  late final TextEditingController _paymentDateController;
  late final TextEditingController _otherRevenueTypeController;
  late String _itemType;
  late String _referenceMonth;
  late String? _revenueType;
  late int? _expenseNatureId;
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
    _observationController = TextEditingController(text: item.observation);
    _amountController = TextEditingController(text: item.amountText);
    _receivedAmountController =
        TextEditingController(text: item.receivedAmountText);
    _dueDateController =
        TextEditingController(text: _dateToDisplay(item.dueDate));
    _paymentDateController = TextEditingController(
        text: item.paymentDate.isEmpty ? '' : _dateToDisplay(item.paymentDate));
    _otherRevenueTypeController =
        TextEditingController(text: item.revenueTypeOther ?? '');
    _itemType = item.itemType;
    _referenceMonth = item.referenceMonth.isNotEmpty
        ? item.referenceMonth
        : widget.referenceMonth;
    _revenueType = item.revenueType;
    _expenseNatureId = item.expenseNatureId;
    _settled = item.settled;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _observationController.dispose();
    _amountController.dispose();
    _receivedAmountController.dispose();
    _dueDateController.dispose();
    _paymentDateController.dispose();
    _otherRevenueTypeController.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  bool get _descriptionMatchesHistory => isKnownBudgetDescription(
        widget.expenseDescriptionSuggestions,
        _descriptionController.text,
      );

  Widget _editDescriptionField() {
    if (_itemType != 'Despesa') {
      return TextField(
        key: const Key('budget-edit-description'),
        controller: _descriptionController,
        focusNode: _descriptionFocusNode,
        maxLength: 15,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: <TextInputFormatter>[UpperCaseTextFormatter()],
        decoration: _fieldDecoration(
            label: 'Descrição', icon: Icons.notes_rounded, counterText: ''),
      );
    }
    return RawAutocomplete<String>(
      textEditingController: _descriptionController,
      focusNode: _descriptionFocusNode,
      displayStringForOption: (String option) => option,
      optionsBuilder: (TextEditingValue value) =>
          rankBudgetDescriptionSuggestions(
        widget.expenseDescriptionSuggestions,
        value.text,
      ),
      onSelected: (String option) {
        _descriptionController.text = option;
        _descriptionController.selection =
            TextSelection.collapsed(offset: option.length);
        setState(() {});
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          TextField(
        key: const Key('budget-edit-description'),
        controller: controller,
        focusNode: focusNode,
        maxLength: 15,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: <TextInputFormatter>[UpperCaseTextFormatter()],
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => onSubmitted(),
        decoration: _fieldDecoration(
          label: 'Descrição',
          icon: Icons.notes_rounded,
          counterText: '',
          hintText: 'Digite para consultar o histórico',
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) {
        final List<String> visible = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 10,
            color: _budgetPanel,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 280),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
                    child: Text('DESPESAS ANTERIORES',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _budgetMuted)),
                  ),
                  Flexible(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final int highlighted =
                            AutocompleteHighlightedOption.of(context);
                        final bool selected = index == highlighted;
                        return InkWell(
                          onTap: () => onSelected(visible[index]),
                          child: Container(
                            color: selected ? _budgetSky : Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            child: Row(children: <Widget>[
                              Icon(Icons.history_rounded,
                                  size: 18,
                                  color: selected ? _budgetBlue : _budgetMuted),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(visible[index],
                                    style: TextStyle(
                                      color: _budgetInk,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                    )),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 6, 14, 10),
                    child: Text(
                      'Ou continue digitando para usar uma nova descrição.',
                      style: TextStyle(fontSize: 12, color: _budgetMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
    if (_itemType == 'Despesa' &&
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(_referenceMonth)) {
      return 'Informe o mês de referência da despesa.';
    }
    if (_itemType == 'Receita' && _revenueType == null) {
      return 'Selecione o tipo de receita.';
    }
    if (_itemType == 'Despesa' &&
        widget.expenseNatures.any((ExpenseNature item) => item.active) &&
        _expenseNatureId == null) {
      return 'Informe a natureza da despesa.';
    }
    if (_itemType == 'Receita' &&
        _revenueType == 'OUTROS' &&
        _otherRevenueTypeController.text.trim().isEmpty) {
      return 'Especifique o tipo de receita.';
    }
    if (_descriptionController.text.trim().isEmpty) {
      return 'Informe a descrição.';
    }
    if (_parseAmount(_amountController.text) <= 0) {
      return 'Informe um valor maior que zero.';
    }
    if (_itemType == 'Receita' &&
        _parseAmount(_receivedAmountController.text) >
            _parseAmount(_amountController.text)) {
      return 'O valor recebido nÃ£o pode superar o valor total.';
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
      'reference_month': _referenceMonth,
      'item_type': _itemType,
      'tipo_receita': _itemType == 'Receita' ? _revenueType : null,
      'tipo_receita_outros': _itemType == 'Receita' && _revenueType == 'OUTROS'
          ? _otherRevenueTypeController.text.trim()
          : null,
      'expense_nature_id': _itemType == 'Despesa' ? _expenseNatureId : null,
      'description': _descriptionController.text.trim().toUpperCase(),
      'observation': _observationController.text,
      'amount_text': _amountController.text.trim(),
      'received_amount_text': _itemType == 'Receita'
          ? _receivedAmountController.text.trim()
          : '0,00',
      'due_date': _dateToIso(_dueDateController.text),
      'payment_date': _paymentDateController.text.isEmpty
          ? null
          : _dateToIso(_paymentDateController.text),
      'settled': _settled,
    };
    try {
      final http.Response response = await apiClient.put(
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
                      onSelectionChanged: (Set<String> value) => setState(() {
                        _itemType = value.first;
                        if (_itemType != 'Receita') {
                          _revenueType = null;
                          _otherRevenueTypeController.clear();
                        }
                      }),
                    ),
                    const SizedBox(height: 14),
                    if (revenue == false) ...<Widget>[
                      DropdownMenu<int>(
                        key: const Key('budget-edit-expense-nature'),
                        initialSelection: _expenseNatureId,
                        enableFilter: true,
                        requestFocusOnTap: true,
                        expandedInsets: EdgeInsets.zero,
                        label: const Text('Natureza da Despesa'),
                        dropdownMenuEntries: widget.expenseNatures
                            .where((ExpenseNature nature) =>
                                nature.active || nature.id == _expenseNatureId)
                            .map((ExpenseNature nature) =>
                                DropdownMenuEntry<int>(
                                    value: nature.id,
                                    label: nature.active
                                        ? nature.name
                                        : '${nature.name} (inativa)'))
                            .toList(),
                        onSelected: (int? value) =>
                            setState(() => _expenseNatureId = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>(
                            'budget-edit-reference-month-$_referenceMonth'),
                        initialValue: _referenceMonth,
                        autofocus: true,
                        decoration: _fieldDecoration(
                          label: 'Mês de Referência',
                          icon: Icons.calendar_view_month_rounded,
                        ),
                        items: _budgetMonthOptions()
                            .map((String value) => DropdownMenuItem<String>(
                                value: value, child: Text(_monthLabel(value))))
                            .toList(),
                        onChanged: (String? value) => setState(
                            () => _referenceMonth = value ?? _referenceMonth),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('budget-edit-due-date'),
                        controller: _dueDateController,
                        readOnly: true,
                        onTap: () => _pickDate(_dueDateController),
                        decoration: _dateDecoration('Data de Vencimento'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('budget-edit-payment-date'),
                        controller: _paymentDateController,
                        readOnly: true,
                        onTap: () => _pickDate(_paymentDateController),
                        decoration: _dateDecoration('Data de Pagamento'),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (revenue) ...<Widget>[
                      DropdownButtonFormField<String>(
                        key: const Key('budget-edit-revenue-type'),
                        initialValue: _revenueType,
                        decoration: _fieldDecoration(
                          label: 'Tipo de Receita',
                          icon: Icons.category_outlined,
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(
                              value: 'ALUGUEL', child: Text('Aluguel')),
                          DropdownMenuItem(
                              value: 'DAY_TRADE', child: Text('Day Trade')),
                          DropdownMenuItem(
                              value: 'OUTROS', child: Text('Outros')),
                        ],
                        onChanged: (String? value) => setState(() {
                          _revenueType = value;
                          if (value != 'OUTROS') {
                            _otherRevenueTypeController.clear();
                          }
                        }),
                      ),
                      if (_revenueType == 'OUTROS') ...<Widget>[
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('budget-edit-revenue-type-other'),
                          controller: _otherRevenueTypeController,
                          maxLength: 80,
                          textInputAction: TextInputAction.next,
                          decoration: _fieldDecoration(
                            label: 'Especifique o tipo de receita',
                            icon: Icons.edit_note_rounded,
                            counterText: '',
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                    ],
                    _editDescriptionField(),
                    if (!revenue) ...<Widget>[
                      const SizedBox(height: 6),
                      Row(
                        key: const Key('budget-edit-description-mode-hint'),
                        children: <Widget>[
                          Icon(
                            _descriptionMatchesHistory
                                ? Icons.history_rounded
                                : Icons.add_circle_outline_rounded,
                            size: 16,
                            color: _descriptionMatchesHistory
                                ? _budgetBlue
                                : _budgetMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _descriptionMatchesHistory
                                  ? 'Descrição anterior selecionada.'
                                  : 'Nova descrição — será usada ao salvar.',
                              style: const TextStyle(
                                  fontSize: 12, color: _budgetMuted),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('budget-edit-observation'),
                      controller: _observationController,
                      maxLength: 500,
                      minLines: 3,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: _fieldDecoration(
                        label: 'Observação',
                        icon: Icons.chat_bubble_outline_rounded,
                        counterText: 'máximo de 500 caracteres',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('budget-edit-amount'),
                      controller: _amountController,
                      onChanged: (_) => setState(() {}),
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
                    if (revenue) ...<Widget>[
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('budget-edit-received-amount'),
                        controller: _receivedAmountController,
                        onChanged: (_) => setState(() {
                          _settled = _parseAmount(_amountController.text) > 0 &&
                              _parseAmount(_receivedAmountController.text) >=
                                  _parseAmount(_amountController.text);
                        }),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                        ],
                        decoration: _fieldDecoration(
                            label: 'Valor recebido (parcial)',
                            icon: Icons.account_balance_wallet_outlined,
                            prefixText: 'R\$ ',
                            hintText: '0,00'),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Saldo a receber: ${_formatCurrency((_parseAmount(_amountController.text) - _parseAmount(_receivedAmountController.text)).clamp(0, double.infinity))}',
                        style: const TextStyle(
                            color: _budgetBlue, fontWeight: FontWeight.w800),
                      ),
                    ],
                    if (revenue) ...<Widget>[
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
                        decoration: _dateDecoration('Data do recebimento'),
                      ),
                    ],
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
                          if (_parseAmount(_receivedAmountController.text) ==
                              0) {
                            _paymentDateController.clear();
                          }
                        } else if (_paymentDateController.text.isEmpty) {
                          if (revenue) {
                            _receivedAmountController.text =
                                _amountController.text;
                          }
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
      final http.Response response = await apiClient.get(
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
                'Observacao',
                'Valor'
              ],
              data: _entries
                  .map((_CashEntry entry) => <String>[
                        _dateToDisplay(entry.paymentDate),
                        _monthLabel(entry.referenceMonth),
                        entry.description,
                        entry.observation,
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
                3: const pw.FlexColumnWidth(1.5),
                4: const pw.FixedColumnWidth(85),
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
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minWidth: constraints.maxWidth < 780
                        ? 780
                        : constraints.maxWidth),
                child: Table(
                  key: const Key('cash-report-grid'),
                  border: TableBorder.all(
                    color: const Color(0xFFB9B1A6),
                    width: 1,
                  ),
                  columnWidths: const <int, TableColumnWidth>{
                    0: FixedColumnWidth(48),
                    1: FixedColumnWidth(125),
                    2: FixedColumnWidth(145),
                    3: FlexColumnWidth(1.5),
                    4: FlexColumnWidth(2.4),
                    5: FixedColumnWidth(135),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: <TableRow>[
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFE3E7EA)),
                      children: <Widget>[
                        _cashGridCell('#',
                            header: true, alignment: TextAlign.center),
                        _cashGridCell('Recebimento', header: true),
                        _cashGridCell('Competência', header: true),
                        _cashGridCell('Descrição', header: true),
                        _cashGridCell('Observação', header: true),
                        _cashGridCell('Valor',
                            header: true, alignment: TextAlign.right),
                      ],
                    ),
                    for (int index = 0; index < _entries.length; index++)
                      TableRow(
                        decoration: BoxDecoration(
                          color: index.isEven
                              ? Colors.white
                              : const Color(0xFFF7F7F4),
                        ),
                        children: <Widget>[
                          _cashGridCell('${index + 1}',
                              alignment: TextAlign.center),
                          _cashGridCell(
                              _dateToDisplay(_entries[index].paymentDate)),
                          _cashGridCell(
                              _monthLabel(_entries[index].referenceMonth)),
                          _cashGridCell(_entries[index].description,
                              emphasized: true),
                          _cashGridCell(_entries[index].observation),
                          _cashGridCell(_formatCurrency(_entries[index].amount),
                              alignment: TextAlign.right,
                              emphasized: true,
                              color: _budgetGreen),
                        ],
                      ),
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFEDF5E9)),
                      children: <Widget>[
                        _cashGridCell(''),
                        _cashGridCell(''),
                        _cashGridCell(''),
                        _cashGridCell(''),
                        _cashGridCell('TOTAL RECEBIDO', emphasized: true),
                        _cashGridCell(_formatCurrency(_total),
                            alignment: TextAlign.right,
                            emphasized: true,
                            color: _budgetGreen),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _cashGridCell(
    String value, {
    bool header = false,
    bool emphasized = false,
    TextAlign alignment = TextAlign.left,
    Color? color,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      alignment: alignment == TextAlign.right
          ? Alignment.centerRight
          : alignment == TextAlign.center
              ? Alignment.center
              : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Text(
        value,
        textAlign: alignment,
        style: TextStyle(
          color: color ?? _budgetInk,
          fontSize: header ? 12 : 12.5,
          fontWeight: header || emphasized ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
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
    required this.observation,
    required this.amountText,
    required this.paymentDate,
  });

  factory _CashEntry.fromJson(Map<String, dynamic> json) => _CashEntry(
        referenceMonth: (json['reference_month'] as String?) ?? '',
        description: ((json['description'] as String?) ?? '').toUpperCase(),
        observation: (json['observation'] as String?) ?? '',
        amountText: (json['amount_text'] as String?) ?? '0,00',
        paymentDate: (json['payment_date'] as String?) ?? '',
      );

  final String referenceMonth;
  final String description;
  final String observation;
  final String amountText;
  final String paymentDate;

  double get amount => _parseAmount(amountText);
}

class _BudgetPanel extends StatelessWidget {
  const _BudgetPanel(
      {required this.child,
      this.padding = const EdgeInsets.all(18),
      super.key});

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
      child: Material(
        color: Colors.transparent,
        child: child,
      ),
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
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.trailing});

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

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
        if (trailing != null) ...<Widget>[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}

class _ListedTotalPill extends StatelessWidget {
  const _ListedTotalPill({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('budget-filtered-total'),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF246AA5), Color(0xFF174C7D)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF7FC3F4), width: 1.2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
              color: Color(0x3D174C7D), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          const Text('TOTAL LISTADO',
              style: TextStyle(
                  color: Color(0xFFD8EEFF),
                  fontSize: 9,
                  letterSpacing: .65,
                  fontWeight: FontWeight.w800)),
          Text(_formatCurrency(value),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900)),
        ],
      ),
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
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    letterSpacing: emphasized ? 0.35 : 0,
                    fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _ExpenseNatureLabel extends StatelessWidget {
  const _ExpenseNatureLabel({
    required this.itemId,
    required this.label,
    required this.categorized,
  });

  final int itemId;
  final String label;
  final bool categorized;

  @override
  Widget build(BuildContext context) {
    final Color surface =
        categorized ? const Color(0xFFD9FF57) : const Color(0xFFFFE66B);
    final Color foreground =
        categorized ? const Color(0xFF234B16) : const Color(0xFF684600);
    final Color border =
        categorized ? const Color(0xFF76C800) : const Color(0xFFE0A600);
    return Semantics(
      label: 'Natureza da despesa: $label',
      child: Container(
        key: ValueKey<String>('expense-nature-label-$itemId'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border, width: 1.25),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: surface.withValues(alpha: 0.48),
              blurRadius: 9,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.sell_rounded, size: 14, color: foreground),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                'NATUREZA • ${label.toUpperCase()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 10,
                  letterSpacing: .35,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
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

@visibleForTesting
Future<Uint8List> buildBudgetListingReportPdf({
  required List<BudgetItem> items,
  required List<String> filters,
  required DateTime generatedAt,
}) async {
  final double revenues = items
      .where((BudgetItem item) => item.itemType == 'Receita')
      .fold<double>(
          0,
          (double total, BudgetItem item) =>
              total + budgetDisplayedAmount(item));
  final double expenses = items
      .where((BudgetItem item) => item.itemType == 'Despesa')
      .fold<double>(
          0,
          (double total, BudgetItem item) =>
              total + budgetDisplayedAmount(item));
  final double balance = revenues - expenses;
  final String generatedLabel = '${generatedAt.day.toString().padLeft(2, '0')}/'
      '${generatedAt.month.toString().padLeft(2, '0')}/${generatedAt.year} '
      '${generatedAt.hour.toString().padLeft(2, '0')}:'
      '${generatedAt.minute.toString().padLeft(2, '0')}';
  final pw.Document document = pw.Document(
    title: 'Meu Orçamento - Relatório da visualização atual',
    author: 'EKT IA Systems',
    creator: 'EKT IA Systems',
  );

  pw.Widget metric(String label, String value, PdfColor accent) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border(left: pw.BorderSide(color: accent, width: 3)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(label,
                  style: const pw.TextStyle(
                      fontSize: 7.5, color: PdfColors.grey700)),
              pw.SizedBox(height: 3),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: accent)),
            ],
          ),
        ),
      );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 28),
      header: (pw.Context context) => pw.Column(
        children: <pw.Widget>[
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFF153B5B)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: <pw.Widget>[
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text('EKT IA SYSTEMS',
                        style: const pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 15,
                            fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 2),
                    pw.Text('GESTÃO FINANCEIRA E INTELIGÊNCIA APLICADA',
                        style: const pw.TextStyle(
                            color: PdfColor.fromInt(0xFFD7E7F2),
                            fontSize: 7.5,
                            letterSpacing: .7)),
                  ],
                ),
                pw.Text('MEU ORÇAMENTO',
                    style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.Container(height: 3, color: const PdfColor.fromInt(0xFFD3A95D)),
        ],
      ),
      footer: (pw.Context context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text('Relatório emitido em $generatedLabel',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
          pw.Text('Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
        ],
      ),
      build: (pw.Context context) => <pw.Widget>[
        pw.SizedBox(height: 14),
        pw.Text('RELATÓRIO DA VISUALIZAÇÃO ATUAL',
            style: const pw.TextStyle(
                color: PdfColor.fromInt(0xFF153B5B),
                fontSize: 18,
                fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(
          'Este relatório reproduz os lançamentos apresentados na tela no momento da impressão.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 11),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(9),
          decoration: pw.BoxDecoration(
            color: PdfColors.blueGrey50,
            border: pw.Border.all(color: PdfColors.blueGrey200, width: .6),
          ),
          child: pw.Text('FILTROS APLICADOS  |  ${filters.join('  |  ')}',
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.blueGrey800)),
        ),
        pw.SizedBox(height: 11),
        pw.Row(children: <pw.Widget>[
          metric(
              'LANÇAMENTOS EXIBIDOS', '${items.length}', PdfColors.blueGrey700),
          pw.SizedBox(width: 8),
          metric('RECEITAS EXIBIDAS', _formatCurrency(revenues),
              PdfColors.green700),
          pw.SizedBox(width: 8),
          metric(
              'DESPESAS EXIBIDAS', _formatCurrency(expenses), PdfColors.red700),
          pw.SizedBox(width: 8),
          metric('SALDO DA SELEÇÃO', _formatCurrency(balance),
              balance >= 0 ? PdfColors.green800 : PdfColors.red800),
        ]),
        pw.SizedBox(height: 15),
        if (items.isEmpty)
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(22),
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Text(
                'Nenhum lançamento corresponde aos filtros aplicados.',
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          )
        else
          pw.TableHelper.fromTextArray(
            headers: const <String>[
              'Referência',
              'Tipo',
              'Descrição',
              'Categoria',
              'Vencimento',
              'Pagamento',
              'Situação',
              'Valor exibido',
            ],
            data: items
                .map((BudgetItem item) => <String>[
                      _monthLabel(item.referenceMonth),
                      item.itemType,
                      item.description,
                      item.itemType == 'Receita'
                          ? item.revenueTypeLabel
                          : item.expenseNatureLabel,
                      _dateToDisplay(item.dueDate),
                      item.paymentDate.isEmpty
                          ? '-'
                          : _dateToDisplay(item.paymentDate),
                      item.statusLabel,
                      _formatCurrency(budgetDisplayedAmount(item)),
                    ])
                .toList(),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFF285A7D)),
            headerStyle: const pw.TextStyle(
                color: PdfColors.white,
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 7.2),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: const <int, pw.Alignment>{
              7: pw.Alignment.centerRight,
            },
            columnWidths: const <int, pw.TableColumnWidth>{
              0: pw.FlexColumnWidth(1.05),
              1: pw.FlexColumnWidth(.72),
              2: pw.FlexColumnWidth(1.7),
              3: pw.FlexColumnWidth(1.25),
              4: pw.FlexColumnWidth(.9),
              5: pw.FlexColumnWidth(.9),
              6: pw.FlexColumnWidth(1.05),
              7: pw.FlexColumnWidth(1.05),
            },
            border: pw.TableBorder.all(color: PdfColors.grey400, width: .45),
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4.5),
          ),
      ],
    ),
  );
  return document.save();
}

class BudgetItem {
  BudgetItem(
      {required this.id,
      required this.referenceMonth,
      required this.itemType,
      required this.revenueType,
      required this.revenueTypeOther,
      required this.expenseNatureId,
      required this.expenseNatureName,
      required this.expenseNatureActive,
      required this.description,
      required this.observation,
      required this.amountText,
      required this.receivedAmountText,
      required this.dueDate,
      required this.paymentDate,
      required this.settled});

  factory BudgetItem.fromJson(Map<String, dynamic> json) => BudgetItem(
        id: (json['id'] as num).toInt(),
        referenceMonth: (json['reference_month'] as String?) ?? '',
        itemType: (json['item_type'] as String?) ?? 'Despesa',
        revenueType: json['tipo_receita'] as String?,
        revenueTypeOther: json['tipo_receita_outros'] as String?,
        expenseNatureId: (json['expense_nature_id'] as num?)?.toInt(),
        expenseNatureName: json['expense_nature_name'] as String?,
        expenseNatureActive: json['expense_nature_active'] as bool?,
        description: ((json['description'] as String?) ?? '').toUpperCase(),
        observation: (json['observation'] as String?) ?? '',
        amountText: (json['amount_text'] as String?) ?? '0,00',
        receivedAmountText: (json['received_amount_text'] as String?) ?? '0,00',
        dueDate: (json['due_date'] as String?) ?? '',
        paymentDate: (json['payment_date'] as String?) ?? '',
        settled: (json['settled'] as bool?) ?? false,
      );

  final int id;
  final String referenceMonth;
  final String itemType;
  final String? revenueType;
  final String? revenueTypeOther;
  final int? expenseNatureId;
  final String? expenseNatureName;
  final bool? expenseNatureActive;
  final String description;
  final String observation;
  final String amountText;
  final String receivedAmountText;
  final String dueDate;
  final String paymentDate;
  final bool settled;

  double get amount => _parseAmount(amountText);
  double get receivedAmount => _parseAmount(receivedAmountText);
  double get remainingAmount =>
      (amount - receivedAmount).clamp(0, double.infinity);
  bool get partiallyReceived =>
      itemType == 'Receita' && receivedAmount > 0 && remainingAmount > 0;
  bool get hasExpenseNature =>
      expenseNatureId != null && expenseNatureName?.trim().isNotEmpty == true;
  String get expenseNatureLabel =>
      hasExpenseNature ? expenseNatureName!.trim() : 'Sem categoria';

  String get revenueTypeLabel {
    if (revenueType == 'OUTROS') {
      return revenueTypeOther?.trim().isNotEmpty == true
          ? revenueTypeOther!.trim()
          : 'Outros';
    }
    if (revenueType == 'ALUGUEL') return 'Aluguel';
    if (revenueType == 'DAY_TRADE') return 'Day Trade';
    return 'Não informado';
  }

  String get statusLabel {
    if (itemType == 'Receita') {
      if (settled) return 'Recebido';
      if (partiallyReceived) return 'Recebido parcial';
      return 'Não recebido';
    }
    return settled ? 'Pago' : 'Falta pagar';
  }
}

class ExpenseNature {
  const ExpenseNature(
      {required this.id,
      required this.name,
      required this.active,
      required this.usageCount});

  factory ExpenseNature.fromJson(Map<String, dynamic> json) => ExpenseNature(
        id: (json['id'] as num).toInt(),
        name: (json['name'] as String?) ?? '',
        active: (json['active'] as bool?) ?? false,
        usageCount: (json['usage_count'] as num?)?.toInt() ?? 0,
      );

  final int id;
  final String name;
  final bool active;
  final int usageCount;
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

List<String> _budgetMonthOptions() {
  final int currentYear = DateTime.now().year;
  return <String>[
    for (int year = currentYear - 5; year <= currentYear + 5; year++)
      for (int month = 1; month <= 12; month++)
        '$year-${month.toString().padLeft(2, '0')}',
  ];
}

List<String> _dateMonthOptions(Iterable<String> dates,
    {required bool includeUnpaid}) {
  final List<String> months = dates
      .where((String value) => value.length >= 7)
      .map((String value) => value.substring(0, 7))
      .toSet()
      .toList()
    ..sort();
  return <String>[
    'Todos',
    ...months,
    if (includeUnpaid) 'Não pagas',
  ];
}

int _nullableDateSort(String first, String second) {
  if (first.isEmpty && second.isEmpty) return 0;
  if (first.isEmpty) return 1;
  if (second.isEmpty) return -1;
  return first.compareTo(second);
}

double _parseAmount(String value) {
  String cleaned = value.replaceAll('R\$', '').replaceAll(' ', '');
  if (cleaned.contains(',')) {
    cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(cleaned) ?? 0;
}

String _normalizeSuggestion(String value) {
  const String accented = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
  const String plain = 'AAAAAEEEEIIIIOOOOOUUUUCN';
  final String upper = value.toUpperCase();
  final StringBuffer normalized = StringBuffer();
  for (final int rune in upper.runes) {
    final String character = String.fromCharCode(rune);
    final int index = accented.indexOf(character);
    normalized.write(index < 0 ? character : plain[index]);
  }
  return normalized.toString();
}

List<String> rankBudgetDescriptionSuggestions(
    List<String> suggestions, String typed) {
  final String query = _normalizeSuggestion(typed.trim());
  if (query.isEmpty) return const <String>[];
  final List<(String, int, int)> matches = <(String, int, int)>[];
  for (int index = 0; index < suggestions.length; index++) {
    final String description = suggestions[index];
    final String normalized = _normalizeSuggestion(description);
    final int position = normalized.indexOf(query);
    if (position >= 0) matches.add((description, position, index));
  }
  matches.sort((a, b) {
    final int relevance = a.$2.compareTo(b.$2);
    return relevance != 0 ? relevance : a.$3.compareTo(b.$3);
  });
  return matches.take(10).map((item) => item.$1).toList();
}

List<BudgetItem> filterBudgetItemsByPeriod(
    List<BudgetItem> items, String? referenceMonth) {
  if (referenceMonth == null || referenceMonth.isEmpty) {
    return List<BudgetItem>.from(items);
  }
  return items
      .where((BudgetItem item) => item.referenceMonth == referenceMonth)
      .toList();
}

double budgetDisplayedAmount(BudgetItem item) =>
    item.itemType == 'Receita' && !item.settled
        ? item.remainingAmount
        : item.amount;

List<String> uniqueBudgetDescriptionsForType(
    List<BudgetItem> items, String itemType) {
  final List<String> descriptions = <String>[];
  final Set<String> seen = <String>{};
  for (final BudgetItem item in items) {
    if (item.itemType != itemType || item.description.trim().isEmpty) continue;
    final String normalized = _normalizeSuggestion(item.description.trim());
    if (seen.add(normalized)) descriptions.add(item.description.trim());
  }
  return descriptions;
}

bool isKnownBudgetDescription(List<String> suggestions, String typed) {
  final String candidate = _normalizeSuggestion(typed.trim());
  if (candidate.isEmpty) return false;
  return suggestions.any(
    (String description) =>
        _normalizeSuggestion(description.trim()) == candidate,
  );
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
  if (value.trim().isEmpty) return 'Sem referência';
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
