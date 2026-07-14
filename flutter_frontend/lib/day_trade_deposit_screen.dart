import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

typedef DayTradeDepositApiUriBuilder = Uri Function(String path);

class DayTradeDepositScreen extends StatefulWidget {
  const DayTradeDepositScreen({
    required this.apiUriBuilder,
    required this.sessionToken,
    super.key,
  });

  final DayTradeDepositApiUriBuilder apiUriBuilder;
  final String sessionToken;

  @override
  State<DayTradeDepositScreen> createState() => _DayTradeDepositScreenState();
}

class _DayTradeDepositScreenState extends State<DayTradeDepositScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _sourceController = TextEditingController();
  DateTime _depositDate = DateTime.now();
  String _movementType = 'Entrada';
  String _sourceType = 'Capital extra';
  bool _loading = true;
  bool _saving = false;
  String? _amountError;
  String? _sourceError;
  double _initialCapital = 0;
  double _currentCapital = 0;
  double _depositedTotal = 0;
  double _externalNet = 0;
  double _dayTradeResult = 0;
  double _automaticDayTradeResult = 0;
  double _manualDayTradeAdjustment = 0;
  double _contributedCapital = 0;
  double _growthPercent = 0;
  double _operationalReturnPercent = 0;
  double _dayTradeShareGlobalPercent = 0;
  List<_CapitalDeposit> _deposits = <_CapitalDeposit>[];

  Map<String, String> get _headers => <String, String>{
        'authorization': 'Bearer ${widget.sessionToken}',
        'content-type': 'application/json; charset=utf-8',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw const _DepositException(
          'O servidor retornou uma resposta inválida.');
    }
  }

  void _applySummary(Map<String, dynamic> body) {
    _initialCapital = _parseNumber('${body['initial_capital_text'] ?? '0'}');
    _currentCapital = _parseNumber('${body['capital_text'] ?? '0'}');
    _depositedTotal = _parseNumber('${body['deposited_total_text'] ?? '0'}');
    _externalNet = _parseNumber('${body['external_net_text'] ?? '0'}');
    _dayTradeResult = _parseNumber('${body['day_trade_result_text'] ?? '0'}');
    _automaticDayTradeResult =
        _parseNumber('${body['automatic_day_trade_result_text'] ?? '0'}');
    _manualDayTradeAdjustment =
        _parseNumber('${body['manual_day_trade_adjustment_text'] ?? '0'}');
    _contributedCapital =
        _parseNumber('${body['contributed_capital_text'] ?? '0'}');
    _growthPercent = (body['growth_percent'] as num?)?.toDouble() ?? 0;
    _operationalReturnPercent =
        (body['operational_return_percent'] as num?)?.toDouble() ?? 0;
    _dayTradeShareGlobalPercent =
        (body['day_trade_share_global_percent'] as num?)?.toDouble() ?? 0;
    _deposits = ((body['deposits'] as List<dynamic>?) ?? <dynamic>[])
        .map((dynamic item) =>
            _CapitalDeposit.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final http.Response response = await http.get(
        widget.apiUriBuilder('/api/day-trade/capital/deposits'),
        headers: _headers,
      );
      final Map<String, dynamic> body = await _decode(response);
      if (response.statusCode != 200 || body['ok'] != true) {
        throw _DepositException((body['message'] as String?) ??
            'Não foi possível carregar os depósitos.');
      }
      if (!mounted) return;
      setState(() => _applySummary(body));
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final bool amountValid = _parseNumber(_amountController.text) > 0;
    final bool sourceValid =
        _sourceType == 'Day Trade' || _sourceController.text.trim().isNotEmpty;
    setState(() {
      _amountError = amountValid ? null : 'Informe um valor maior que zero';
      _sourceError = sourceValid ? null : 'Informe a origem do capital extra';
    });
    if (!amountValid || !sourceValid) {
      _showMessage('Preencha o valor e a origem do depósito.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final http.Response response = await http.post(
        widget.apiUriBuilder('/api/day-trade/capital/deposits'),
        headers: _headers,
        body: jsonEncode(<String, String>{
          'deposit_date': _dateIso(_depositDate),
          'movement_type': _movementType,
          'source_type': _sourceType,
          'source_description': _sourceType == 'Capital extra'
              ? _sourceController.text.trim()
              : 'Resultado Day Trade',
          'amount_text': _amountController.text.trim(),
        }),
      );
      final Map<String, dynamic> body = await _decode(response);
      if (response.statusCode != 201 || body['ok'] != true) {
        throw _DepositException((body['message'] as String?) ??
            'Não foi possível depositar o capital.');
      }
      if (!mounted) return;
      setState(() {
        _applySummary(body);
        _amountController.clear();
        _sourceController.clear();
        _depositDate = DateTime.now();
      });
      _showMessage(_movementType == 'Entrada'
          ? 'Entrada somada ao capital Day Trade.'
          : 'Subtração aplicada ao capital Day Trade.');
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _depositDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) setState(() => _depositDate = picked);
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor:
            error ? const Color(0xFFB42332) : const Color(0xFF167A4B),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F3E8),
      appBar: AppBar(
        title: const Text('Depositar capital',
            style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: const Color(0xFF102A35),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _GrowthHeader(
                        initialCapital: _initialCapital,
                        currentCapital: _currentCapital,
                        depositedTotal: _depositedTotal,
                        externalNet: _externalNet,
                        dayTradeResult: _dayTradeResult,
                        automaticDayTradeResult: _automaticDayTradeResult,
                        manualDayTradeAdjustment: _manualDayTradeAdjustment,
                        contributedCapital: _contributedCapital,
                        growthPercent: _growthPercent,
                        operationalReturnPercent: _operationalReturnPercent,
                        dayTradeShareGlobalPercent: _dayTradeShareGlobalPercent,
                      ),
                      const SizedBox(height: 16),
                      _buildForm(),
                      const SizedBox(height: 16),
                      _buildHistory(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildForm() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE4DCC8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('Nova movimentação',
                style: TextStyle(
                    color: Color(0xFF17333C),
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(
                    value: 'Entrada',
                    label: Text('Entrada'),
                    icon: Icon(Icons.add_circle_outline_rounded)),
                ButtonSegment<String>(
                    value: 'Subtracao',
                    label: Text('Subtração'),
                    icon: Icon(Icons.remove_circle_outline_rounded)),
              ],
              selected: <String>{_movementType},
              showSelectedIcon: false,
              onSelectionChanged: (Set<String> value) =>
                  setState(() => _movementType = value.first),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _sourceType,
              decoration:
                  _decoration('Origem do capital', Icons.source_outlined),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                    value: 'Capital extra', child: Text('Capital extra')),
                DropdownMenuItem<String>(
                    value: 'Day Trade', child: Text('Ajuste manual Day Trade')),
              ],
              onChanged: (String? value) {
                if (value != null) {
                  setState(() {
                    _sourceType = value;
                    _sourceError = null;
                    if (value == 'Day Trade') _sourceController.clear();
                  });
                }
              },
            ),
            if (_sourceType == 'Capital extra') ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                controller: _sourceController,
                onChanged: (_) => setState(() => _sourceError = null),
                decoration: _decoration(
                  'De onde veio o capital extra?',
                  Icons.edit_note_rounded,
                  hintText: 'Salário, reserva, aporte externo...',
                  errorText: _sourceError,
                ),
              ),
            ] else ...<Widget>[
              const SizedBox(height: 10),
              const Text(
                'Ganhos e perdas das operações registradas já entram automaticamente. Use o ajuste manual apenas para conciliação.',
                style: TextStyle(
                    color: Color(0xFF9A6B00),
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (_) => setState(() => _amountError = null),
              decoration: _decoration(
                  _movementType == 'Entrada'
                      ? 'Valor da entrada'
                      : 'Valor da subtração',
                  _movementType == 'Entrada'
                      ? Icons.add_card_rounded
                      : Icons.money_off_csred_outlined,
                  prefixText: 'R\$ ',
                  errorText: _amountError),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: _decoration(
                    'Data da inclusão', Icons.calendar_month_outlined),
                child: Text(_dateDisplay(_depositDate),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 16),
            if (_initialCapital <= 0) ...<Widget>[
              const Text(
                'Cadastre o capital inicial antes de fazer o primeiro depósito.',
                style: TextStyle(
                    color: Color(0xFFB42332),
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              onPressed: _saving || _initialCapital <= 0 ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_circle_outline_rounded),
              label: Text(_saving
                  ? 'Salvando...'
                  : _movementType == 'Entrada'
                      ? 'Registrar entrada'
                      : 'Registrar subtração'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF167A4B),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistory() {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('Histórico de movimentações',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            if (_deposits.isEmpty)
              const Text('Nenhuma movimentação registrada.',
                  style: TextStyle(color: Color(0xFF65747A)))
            else
              for (final _CapitalDeposit deposit in _deposits)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: deposit.movementType == 'Subtracao'
                        ? const Color(0xFFFFECEE)
                        : deposit.sourceType == 'Day Trade'
                            ? const Color(0xFFE5F3EF)
                            : const Color(0xFFFFF1D5),
                    child: Icon(
                      deposit.movementType == 'Subtracao'
                          ? Icons.remove_rounded
                          : deposit.sourceType == 'Day Trade'
                              ? Icons.candlestick_chart_rounded
                              : Icons.savings_outlined,
                      color: deposit.movementType == 'Subtracao'
                          ? const Color(0xFFB42332)
                          : deposit.sourceType == 'Day Trade'
                              ? const Color(0xFF167A4B)
                              : const Color(0xFFA66A00),
                    ),
                  ),
                  title: Text(deposit.sourceDescription,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                      '${deposit.movementType == 'Subtracao' ? 'Subtração' : 'Entrada'} • ${deposit.sourceType} • ${_dateDisplayFromIso(deposit.depositDate)}'),
                  trailing: Text(
                      '${deposit.movementType == 'Subtracao' ? '-' : '+'}${_currency(deposit.amount)}',
                      style: TextStyle(
                          color: deposit.movementType == 'Subtracao'
                              ? const Color(0xFFB42332)
                              : const Color(0xFF167A4B),
                          fontWeight: FontWeight.w900)),
                ),
          ],
        ),
      ),
    );
  }
}

class _GrowthHeader extends StatelessWidget {
  const _GrowthHeader({
    required this.initialCapital,
    required this.currentCapital,
    required this.depositedTotal,
    required this.externalNet,
    required this.dayTradeResult,
    required this.automaticDayTradeResult,
    required this.manualDayTradeAdjustment,
    required this.contributedCapital,
    required this.growthPercent,
    required this.operationalReturnPercent,
    required this.dayTradeShareGlobalPercent,
  });

  final double initialCapital;
  final double currentCapital;
  final double depositedTotal;
  final double externalNet;
  final double dayTradeResult;
  final double automaticDayTradeResult;
  final double manualDayTradeAdjustment;
  final double contributedCapital;
  final double growthPercent;
  final double operationalReturnPercent;
  final double dayTradeShareGlobalPercent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF102A35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Saldo global Day Trade',
              style: TextStyle(color: Color(0xFFC8D8DC), fontSize: 12)),
          const SizedBox(height: 4),
          Text(_currency(currentCapital),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: <Widget>[
              _HeaderValue(label: 'Inicial', value: _currency(initialCapital)),
              _HeaderValue(
                  label: 'Patrimônio aportado',
                  value: _currency(contributedCapital)),
              _HeaderValue(
                  label: 'Aportes externos líquidos',
                  value: _currency(externalNet)),
              _HeaderValue(
                  label: 'Resultado Day Trade total',
                  value: _currency(dayTradeResult)),
              _HeaderValue(
                  label: 'Operações automáticas',
                  value: _currency(automaticDayTradeResult)),
              _HeaderValue(
                  label: 'Ajustes manuais',
                  value: _currency(manualDayTradeAdjustment)),
              _HeaderValue(
                  label: 'Rentabilidade operacional',
                  value:
                      '${operationalReturnPercent.toStringAsFixed(2).replaceAll('.', ',')}%'),
              _HeaderValue(
                  label: 'DT no saldo global',
                  value:
                      '${dayTradeShareGlobalPercent.toStringAsFixed(2).replaceAll('.', ',')}%'),
              _HeaderValue(
                  label: 'Crescimento patrimonial',
                  value:
                      '${_currency(depositedTotal)} • ${growthPercent.toStringAsFixed(2).replaceAll('.', ',')}%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderValue extends StatelessWidget {
  const _HeaderValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: const TextStyle(color: Color(0xFF9FB6BC), fontSize: 10)),
          Text(value,
              style: const TextStyle(
                  color: Color(0xFFFFD98B), fontWeight: FontWeight.w800)),
        ],
      );
}

class _CapitalDeposit {
  const _CapitalDeposit({
    required this.depositDate,
    required this.movementType,
    required this.sourceType,
    required this.sourceDescription,
    required this.amount,
  });

  factory _CapitalDeposit.fromJson(Map<String, dynamic> json) =>
      _CapitalDeposit(
        depositDate: '${json['deposit_date'] ?? ''}',
        movementType: '${json['movement_type'] ?? 'Entrada'}',
        sourceType: '${json['source_type'] ?? ''}',
        sourceDescription: '${json['source_description'] ?? ''}',
        amount: _parseNumber('${json['amount_text'] ?? '0'}'),
      );

  final String depositDate;
  final String movementType;
  final String sourceType;
  final String sourceDescription;
  final double amount;
}

class _DepositException implements Exception {
  const _DepositException(this.message);
  final String message;
}

InputDecoration _decoration(String label, IconData icon,
        {String? hintText, String? prefixText, String? errorText}) =>
    InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixText: prefixText,
      errorText: errorText,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFFAF8F2),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );

String _messageFor(Object error) => error is _DepositException
    ? error.message
    : 'Não foi possível conectar ao backend Python.';

double _parseNumber(String value) {
  String cleaned = value.replaceAll('R\$', '').replaceAll(' ', '');
  if (cleaned.contains(',')) {
    cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(cleaned) ?? 0;
}

String _currency(double value) {
  final bool negative = value < 0;
  final List<String> parts = value.abs().toStringAsFixed(2).split('.');
  final StringBuffer whole = StringBuffer();
  for (int index = 0; index < parts[0].length; index++) {
    if (index > 0 && (parts[0].length - index) % 3 == 0) whole.write('.');
    whole.write(parts[0][index]);
  }
  return '${negative ? '-' : ''}R\$ $whole,${parts[1]}';
}

String _dateIso(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _dateDisplay(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _dateDisplayFromIso(String value) {
  final DateTime? date = DateTime.tryParse(value);
  return date == null ? value : _dateDisplay(date);
}
