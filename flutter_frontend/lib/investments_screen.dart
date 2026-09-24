import 'vu_meter.dart';
import 'dart:convert';

import 'api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'investment_statement_screen.dart';

typedef InvestmentsApiUriBuilder = Uri Function(String path);
typedef DayTradeCapitalLauncher = Future<void> Function();

class InvestmentsScreen extends StatefulWidget {
  const InvestmentsScreen({
    required this.apiUriBuilder,
    required this.sessionToken,
    required this.onOpenDayTradeCapital,
    required this.onOpenDayTradeDeposit,
    super.key,
  });

  final InvestmentsApiUriBuilder apiUriBuilder;
  final String sessionToken;
  final DayTradeCapitalLauncher onOpenDayTradeCapital;
  final DayTradeCapitalLauncher onOpenDayTradeDeposit;

  @override
  State<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends State<InvestmentsScreen> {
  final Map<int, TextEditingController> _amountControllers =
      <int, TextEditingController>{};
  List<InvestmentItem> _items = <InvestmentItem>[];
  List<InvestmentOption> _options = <InvestmentOption>[];
  bool _loading = true;
  bool _savingAmounts = false;

  Map<String, String> get _headers => <String, String>{
        'authorization': 'Bearer ${widget.sessionToken}',
        'content-type': 'application/json; charset=utf-8',
      };

  double get _total => _items.fold<double>(
        0,
        (double total, InvestmentItem item) => total + item.amount,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _amountControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw const InvestmentsApiException(
        'O backend retornou uma resposta inválida.',
      );
    }
  }

  Future<void> _load() async {
    return VuTasks.run(
        owner: this,
        key: '_load',
        message: 'Carregando dados…',
        alive: () => mounted,
        silent: false,
        blocking: false,
        action: () async {
          setState(() => _loading = true);
          try {
            final http.Response response = await apiClient.get(
              widget.apiUriBuilder('/api/investments'),
              headers: _headers,
            );
            final Map<String, dynamic> body = await _decode(response);
            if (response.statusCode != 200 || body['ok'] != true) {
              throw InvestmentsApiException(
                (body['message'] as String?) ??
                    'Não foi possível carregar os investimentos.',
              );
            }
            final List<InvestmentItem> items =
                ((body['items'] as List<dynamic>?) ?? <dynamic>[])
                    .map(
                      (dynamic item) => InvestmentItem.fromJson(
                        item as Map<String, dynamic>,
                      ),
                    )
                    .toList();
            final List<InvestmentOption> options =
                ((body['options'] as List<dynamic>?) ?? <dynamic>[])
                    .map(
                      (dynamic item) => InvestmentOption.fromJson(
                        item as Map<String, dynamic>,
                      ),
                    )
                    .toList();
            if (!mounted) {
              return;
            }
            _syncAmountControllers(items);
            setState(() {
              _items = items;
              _options = options;
            });
          } catch (error) {
            VuTasks.fail(error);
            if (mounted) {
              _showMessage(_messageFor(error), error: true);
            }
          } finally {
            if (mounted) {
              setState(() => _loading = false);
            }
          }
        });
  }

  void _syncAmountControllers(List<InvestmentItem> items) {
    final Set<int> currentIds =
        items.map((InvestmentItem item) => item.id).toSet();
    for (final int id in _amountControllers.keys.toList()) {
      if (!currentIds.contains(id)) {
        _amountControllers.remove(id)?.dispose();
      }
    }
    for (final InvestmentItem item in items) {
      final TextEditingController controller = _amountControllers.putIfAbsent(
        item.id,
        TextEditingController.new,
      );
      controller.text = item.amount == 0 ? '' : item.amountText;
    }
  }

  Future<void> _addInvestment(InvestmentOption option) async {
    return VuTasks.run(
        owner: this,
        key: '_addInvestment',
        message: 'Salvando…',
        alive: () => mounted,
        silent: false,
        blocking: false,
        action: () async {
          try {
            final http.Response response = await apiClient.post(
              widget.apiUriBuilder('/api/investments'),
              headers: _headers,
              body: jsonEncode(option.toJson()),
            );
            final Map<String, dynamic> body = await _decode(response);
            if (response.statusCode < 200 ||
                response.statusCode >= 300 ||
                body['ok'] != true) {
              throw InvestmentsApiException(
                (body['message'] as String?) ??
                    'Não foi possível cadastrar o investimento.',
              );
            }
            if (!mounted) {
              return;
            }
            _showMessage('${option.name} cadastrado.');
            await _load();
          } catch (error) {
            VuTasks.fail(error);
            if (mounted) {
              _showMessage(_messageFor(error), error: true);
            }
          }
        });
  }

  Future<void> _saveAllAmounts() async {
    return VuTasks.run(
        owner: this,
        key: '_saveAllAmounts',
        message: 'Salvando…',
        alive: () => mounted,
        silent: false,
        blocking: false,
        action: () async {
          setState(() => _savingAmounts = true);
          try {
            for (final InvestmentItem item in _items) {
              if (item.isDayTradeCapital) continue;
              final String amountText =
                  _amountControllers[item.id]?.text.trim() ?? '0';
              if (_parseAmount(amountText) < 0) {
                throw InvestmentsApiException(
                  'Revise o valor informado para ${item.name}.',
                );
              }
              final http.Response response = await apiClient.put(
                widget.apiUriBuilder('/api/investments/${item.id}'),
                headers: _headers,
                body: jsonEncode(<String, String>{'amount_text': amountText}),
              );
              final Map<String, dynamic> body = await _decode(response);
              if (response.statusCode != 200 || body['ok'] != true) {
                throw InvestmentsApiException(
                  (body['message'] as String?) ??
                      'Não foi possível salvar o valor de ${item.name}.',
                );
              }
            }
            if (!mounted) {
              return;
            }
            _showMessage('Valores aplicados salvos.');
            await _load();
          } catch (error) {
            VuTasks.fail(error);
            if (mounted) {
              _showMessage(_messageFor(error), error: true);
            }
          } finally {
            if (mounted) {
              setState(() => _savingAmounts = false);
            }
          }
        });
  }

  Future<void> _deleteInvestment(InvestmentItem item) async {
    return VuTasks.run(
        owner: this,
        key: '_deleteInvestment',
        message: 'Excluindo…',
        alive: () => mounted,
        silent: false,
        blocking: false,
        action: () async {
          final bool? confirmed =
              await VuTasks.awaitUser(() => showDialog<bool>(
                    context: context,
                    builder: (BuildContext context) => AlertDialog(
                      title: const Text('Excluir investimento?'),
                      content:
                          Text('“${item.name}” será removido da carteira.'),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Excluir'),
                        ),
                      ],
                    ),
                  ));
          if (confirmed != true || !mounted) {
            return;
          }
          try {
            final http.Response response = await apiClient.delete(
              widget.apiUriBuilder('/api/investments/${item.id}'),
              headers: _headers,
            );
            final Map<String, dynamic> body = await _decode(response);
            if (response.statusCode != 200 || body['ok'] != true) {
              throw InvestmentsApiException(
                (body['message'] as String?) ??
                    'Não foi possível excluir o investimento.',
              );
            }
            if (!mounted) {
              return;
            }
            _showMessage('Investimento excluído.');
            await _load();
          } catch (error) {
            VuTasks.fail(error);
            if (mounted) {
              _showMessage(_messageFor(error), error: true);
            }
          }
        });
  }

  Future<void> _showManualForm() async {
    return VuTasks.run(
        owner: this,
        key: '_showManualForm',
        message: 'Salvando…',
        alive: () => mounted,
        silent: false,
        blocking: false,
        action: () async {
          final TextEditingController nameController = VuTasks.draftController(
              'investments_screen.dart:nameController:10041',
              () => TextEditingController());
          final TextEditingController issuerController =
              VuTasks.draftController(
                  'investments_screen.dart:issuerController:10121',
                  () => TextEditingController());
          final TextEditingController categoryController =
              VuTasks.draftController(
                  'investments_screen.dart:categoryController:10217',
                  () => TextEditingController());
          final TextEditingController indexerController =
              VuTasks.draftController(
                  'investments_screen.dart:indexerController:10315',
                  () => TextEditingController());
          final TextEditingController maturityController =
              VuTasks.draftController(
                  'investments_screen.dart:maturityController:10412',
                  () => TextEditingController());
          final InvestmentOption? result =
              await VuTasks.awaitUser(() => showDialog<InvestmentOption>(
                    context: context,
                    builder: (BuildContext context) => AlertDialog(
                      title: const Text('Adicionar investimento'),
                      content: SizedBox(
                        width: 480,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              _dialogField(
                                  nameController, 'Nome do investimento'),
                              _dialogField(issuerController, 'Instituição'),
                              _dialogField(categoryController, 'Categoria'),
                              _dialogField(indexerController, 'Indexador'),
                              _dialogField(
                                  maturityController, 'Vencimento ou liquidez'),
                            ],
                          ),
                        ),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton.icon(
                          onPressed: () {
                            if (nameController.text.trim().isEmpty) {
                              return;
                            }
                            Navigator.pop(
                              context,
                              InvestmentOption(
                                name: nameController.text.trim(),
                                issuer: issuerController.text.trim().isEmpty
                                    ? 'Não informado'
                                    : issuerController.text.trim(),
                                category: categoryController.text.trim().isEmpty
                                    ? 'Investimento'
                                    : categoryController.text.trim(),
                                indexer: indexerController.text.trim().isEmpty
                                    ? 'Não informado'
                                    : indexerController.text.trim(),
                                maturity: maturityController.text.trim().isEmpty
                                    ? 'Não informado'
                                    : maturityController.text.trim(),
                                source: 'Cadastro manual',
                              ),
                            );
                          },
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ));
          VuTasks.disposeController(nameController);
          VuTasks.disposeController(issuerController);
          VuTasks.disposeController(categoryController);
          VuTasks.disposeController(indexerController);
          VuTasks.disposeController(maturityController);
          if (result != null) {
            await _addInvestment(result);
          }
        });
  }

  Future<void> _openDayTradeCapital() async {
    await widget.onOpenDayTradeCapital();
    if (mounted) await _load();
  }

  Future<void> _openDayTradeDeposit() async {
    await widget.onOpenDayTradeDeposit();
    if (mounted) await _load();
  }

  Widget _dialogField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  void _showDetails(InvestmentOption option) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(option.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _detailLine('Instituição', option.issuer),
            _detailLine('Categoria', option.category),
            _detailLine('Indexador', option.indexer),
            _detailLine('Vencimento', option.maturity),
            _detailLine('Fonte', option.source),
            const SizedBox(height: 8),
            const Text(
              'Taxas e disponibilidade devem ser confirmadas na instituição.',
              style: TextStyle(fontSize: 11, color: Color(0xFF5F6873)),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Meus investimentos',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                'Carteira e valores aplicados',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
              ),
            ],
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  text: 'Minha carteira'),
              Tab(
                  icon: Icon(Icons.add_circle_outline),
                  text: 'Adicionar ativos'),
            ],
          ),
        ),
        body: _loading
            ? const Center(
                child: VuLoading(message: 'Carregando dados…', compact: false))
            : TabBarView(
                children: <Widget>[
                  _buildPortfolio(),
                  _buildCatalog(),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showManualForm,
          icon: const Icon(Icons.add),
          label: const Text('Adicionar'),
        ),
      ),
    );
  }

  Widget _buildPortfolio() {
    return RefreshIndicator.noSpinner(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                      final bool compact = constraints.maxWidth < 560;
                      final List<Widget> metrics = <Widget>[
                        _InvestmentMetric(
                          label: 'Total aplicado',
                          value: _formatCurrency(_total),
                          icon: Icons.paid_outlined,
                          accent: const Color(0xFF167A4B),
                          onTap: _openInvestmentStatement,
                        ),
                        _InvestmentMetric(
                          label: 'Ativos cadastrados',
                          value: '${_items.length}',
                          icon: Icons.inventory_2_outlined,
                          accent: const Color(0xFF4F8CFF),
                        ),
                      ];
                      return compact
                          ? Column(
                              children: metrics
                                  .map(
                                    (Widget item) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: item,
                                    ),
                                  )
                                  .toList(),
                            )
                          : Row(
                              children: metrics
                                  .map((Widget item) => Expanded(child: item))
                                  .toList()
                                  .separatedBy(const SizedBox(width: 8)),
                            );
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_items.isEmpty)
                    const _EmptyInvestments()
                  else
                    ..._items.map(_buildPortfolioCard),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _items.isEmpty || _savingAmounts
                        ? null
                        : _saveAllAmounts,
                    icon: _savingAmounts
                        ? const SizedBox(
                            width: 58,
                            height: 30,
                            child:
                                VuLoading(message: 'Salvando…', compact: true),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _savingAmounts
                          ? 'Salvando...'
                          : 'Salvar valores aplicados',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioCard(InvestmentItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget information = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(item.name,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  '${item.category} • ${item.issuer}',
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF5F6873)),
                ),
                Text(
                  '${item.indexer} • ${item.maturity}',
                  style:
                      const TextStyle(fontSize: 10, color: Color(0xFF5F6873)),
                ),
                if (item.isDayTradeCapital) ...<Widget>[
                  const SizedBox(height: 7),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: item.growthPercent >= 0
                          ? const Color(0xFFE8F5EE)
                          : const Color(0xFFFFECEE),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '${item.growthPercent >= 0 ? '+' : ''}${item.growthPercent.toStringAsFixed(2).replaceAll('.', ',')}% desde o capital inicial • ${_formatCurrency(item.growthAmount)}',
                      style: TextStyle(
                        color: item.growthPercent >= 0
                            ? const Color(0xFF167A4B)
                            : const Color(0xFFB42332),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: item.dayTradeResult >= 0
                          ? const Color(0xFFEAF4FF)
                          : const Color(0xFFFFECEE),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      'Resultado Day Trade: ${_formatCurrency(item.dayTradeResult)} • Operações automáticas: ${_formatCurrency(item.automaticDayTradeResult)} • Ajustes manuais: ${_formatCurrency(item.manualDayTradeAdjustment)} • ${item.operationalReturnPercent.toStringAsFixed(2).replaceAll('.', ',')}% sobre o patrimônio aportado • ${item.dayTradeShareGlobalPercent.toStringAsFixed(2).replaceAll('.', ',')}% do saldo global',
                      style: TextStyle(
                        color: item.dayTradeResult >= 0
                            ? const Color(0xFF1F4E79)
                            : const Color(0xFFB42332),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            );
            final Widget amount = SizedBox(
              width: 190,
              child: TextField(
                controller: _amountControllers[item.id],
                readOnly: item.isDayTradeCapital,
                onTap: item.isDayTradeCapital ? _openDayTradeCapital : null,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: item.isDayTradeCapital
                      ? 'Capital alocado'
                      : 'Valor aplicado',
                  prefixText: 'R\$ ',
                  hintText: '0,00',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            );
            final Widget deleteButton = IconButton(
              tooltip: 'Excluir',
              onPressed: () => _deleteInvestment(item),
              color: const Color(0xFFB42332),
              icon: const Icon(Icons.delete_outline),
            );
            final Widget actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (item.isDayTradeCapital)
                  IconButton(
                    tooltip: 'Depositar capital',
                    onPressed: _openDayTradeDeposit,
                    color: const Color(0xFFB77900),
                    icon: const Icon(Icons.add_card_outlined),
                  ),
                if (item.isDayTradeCapital)
                  IconButton(
                    tooltip: 'Editar capital',
                    onPressed: _openDayTradeCapital,
                    color: const Color(0xFF167A4B),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                deleteButton,
              ],
            );
            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(children: <Widget>[
                    Expanded(child: information),
                    actions
                  ]),
                  const SizedBox(height: 10),
                  amount,
                ],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(child: information),
                const SizedBox(width: 12),
                amount,
                actions,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCatalog() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'Ativos disponíveis',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Escolha uma modalidade para incluir na carteira.',
                  style: TextStyle(color: Color(0xFF5F6873), fontSize: 12),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Renda fixa Santander',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Confirme taxas e disponibilidade diretamente na instituição.',
                  style: TextStyle(color: Color(0xFF5F6873), fontSize: 11),
                ),
                const SizedBox(height: 10),
                ..._options.map(_buildOptionCard),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionCard(InvestmentOption option) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.savings_outlined)),
        title: Text(option.name,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          '${option.category} • ${option.indexer} • ${option.maturity}\n${option.issuer}',
        ),
        isThreeLine: true,
        onTap: () => _showDetails(option),
        trailing: FilledButton.icon(
          onPressed: () => _addInvestment(option),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Adicionar'),
        ),
      ),
    );
  }

  Future<void> _openInvestmentStatement() async {
    await VuTasks.awaitUser(() => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => InvestmentStatementScreen(
              apiUriBuilder: widget.apiUriBuilder,
              sessionToken: widget.sessionToken,
            ),
          ),
        ));
    if (mounted) await _load();
  }
}

class _InvestmentMetric extends StatelessWidget {
  const _InvestmentMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(width: 4, color: accent)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF5F6873))),
              Text(value,
                  style: TextStyle(
                      fontSize: 19,
                      color: accent,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          if (onTap != null) ...<Widget>[
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: accent),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: 'Abrir memorial do total aplicado',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

class _EmptyInvestments extends StatelessWidget {
  const _EmptyInvestments();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(30),
        child: Column(
          children: <Widget>[
            Icon(Icons.inbox_outlined, size: 38, color: Color(0xFF5F6873)),
            SizedBox(height: 8),
            Text('Nenhum investimento cadastrado.'),
            Text(
              'Use a aba “Adicionar ativos” ou o botão Adicionar.',
              style: TextStyle(fontSize: 11, color: Color(0xFF5F6873)),
            ),
          ],
        ),
      ),
    );
  }
}

class InvestmentItem {
  InvestmentItem({
    required this.id,
    required this.name,
    required this.issuer,
    required this.category,
    required this.indexer,
    required this.maturity,
    required this.source,
    required this.amountText,
    required this.createdAt,
    required this.initialCapitalText,
    required this.growthAmountText,
    required this.growthPercent,
    required this.contributedCapitalText,
    required this.externalNetText,
    required this.dayTradeResultText,
    required this.automaticDayTradeResultText,
    required this.manualDayTradeAdjustmentText,
    required this.operationalReturnPercent,
    required this.dayTradeShareGlobalPercent,
  });

  factory InvestmentItem.fromJson(Map<String, dynamic> json) => InvestmentItem(
        id: (json['id'] as num).toInt(),
        name: (json['name'] as String?) ?? '',
        issuer: (json['issuer'] as String?) ?? 'Não informado',
        category: (json['category'] as String?) ?? 'Investimento',
        indexer: (json['indexer'] as String?) ?? 'Não informado',
        maturity: (json['maturity'] as String?) ?? 'Não informado',
        source: (json['source'] as String?) ?? '',
        amountText: (json['amount_text'] as String?) ?? '0,00',
        createdAt: (json['created_at'] as String?) ?? '',
        initialCapitalText: '${json['initial_capital_text'] ?? '0'}',
        growthAmountText: '${json['growth_amount_text'] ?? '0'}',
        growthPercent: (json['growth_percent'] as num?)?.toDouble() ?? 0,
        contributedCapitalText: '${json['contributed_capital_text'] ?? '0'}',
        externalNetText: '${json['external_net_text'] ?? '0'}',
        dayTradeResultText: '${json['day_trade_result_text'] ?? '0'}',
        automaticDayTradeResultText:
            '${json['automatic_day_trade_result_text'] ?? '0'}',
        manualDayTradeAdjustmentText:
            '${json['manual_day_trade_adjustment_text'] ?? '0'}',
        operationalReturnPercent:
            (json['operational_return_percent'] as num?)?.toDouble() ?? 0,
        dayTradeShareGlobalPercent:
            (json['day_trade_share_global_percent'] as num?)?.toDouble() ?? 0,
      );

  final int id;
  final String name;
  final String issuer;
  final String category;
  final String indexer;
  final String maturity;
  final String source;
  final String amountText;
  final String createdAt;
  final String initialCapitalText;
  final String growthAmountText;
  final double growthPercent;
  final String contributedCapitalText;
  final String externalNetText;
  final String dayTradeResultText;
  final String automaticDayTradeResultText;
  final String manualDayTradeAdjustmentText;
  final double operationalReturnPercent;
  final double dayTradeShareGlobalPercent;

  double get amount => _parseAmount(amountText);
  double get growthAmount => _parseAmount(growthAmountText);
  double get dayTradeResult => _parseAmount(dayTradeResultText);
  double get automaticDayTradeResult =>
      _parseAmount(automaticDayTradeResultText);
  double get manualDayTradeAdjustment =>
      _parseAmount(manualDayTradeAdjustmentText);

  bool get isDayTradeCapital =>
      name == 'Capital alocado Day Trade' && source == 'Controle Day Trade';
}

class InvestmentOption {
  InvestmentOption({
    required this.name,
    required this.issuer,
    required this.category,
    required this.indexer,
    required this.maturity,
    required this.source,
  });

  factory InvestmentOption.fromJson(Map<String, dynamic> json) =>
      InvestmentOption(
        name: (json['name'] as String?) ?? '',
        issuer: (json['issuer'] as String?) ?? 'Não informado',
        category: (json['category'] as String?) ?? 'Investimento',
        indexer: (json['indexer'] as String?) ?? 'Não informado',
        maturity: (json['maturity'] as String?) ?? 'Não informado',
        source: (json['source'] as String?) ?? '',
      );

  final String name;
  final String issuer;
  final String category;
  final String indexer;
  final String maturity;
  final String source;

  Map<String, String> toJson() => <String, String>{
        'name': name,
        'issuer': issuer,
        'category': category,
        'indexer': indexer,
        'maturity': maturity,
        'source': source,
      };
}

class InvestmentsApiException implements Exception {
  const InvestmentsApiException(this.message);
  final String message;
}

extension _SeparatedWidgets on List<Widget> {
  List<Widget> separatedBy(Widget separator) {
    if (length < 2) {
      return this;
    }
    return <Widget>[
      for (int index = 0; index < length; index++) ...<Widget>[
        if (index > 0) separator,
        this[index],
      ],
    ];
  }
}

String _messageFor(Object error) => error is InvestmentsApiException
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
    if (index > 0 && (parts[0].length - index) % 3 == 0) {
      whole.write('.');
    }
    whole.write(parts[0][index]);
  }
  return '${negative ? '-' : ''}R\$ $whole,${parts[1]}';
}
