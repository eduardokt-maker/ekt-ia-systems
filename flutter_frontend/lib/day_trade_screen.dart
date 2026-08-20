import 'dart:convert';

import 'api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'day_trade_bi_screen.dart';
import 'day_trade_navigation_screen.dart';
import 'trade_result_format.dart';

typedef TradeApiUriBuilder = Uri Function(String path);

const Color _tradeCanvas = Color(0xFFF4F1EA);
const Color _tradePanel = Color(0xFFFFFFFF);
const Color _tradeNavy = Color(0xFF102A3A);
const Color _tradeInk = Color(0xFF1E2932);
const Color _tradeMuted = Color(0xFF65727C);
const Color _tradeTeal = Color(0xFF0F766E);
const Color _tradeGreen = Color(0xFF16825D);
const Color _tradeRed = Color(0xFFB94747);
const Color _tradeAmber = Color(0xFFD18A25);
const Color _tradeBreakEven = Color(0xFF5266A8);
const Color _tradeLine = Color(0xFFE1DED6);
const Color _tradeField = Color(0xFFF5F4F0);

class DayTradeScreen extends StatefulWidget {
  const DayTradeScreen(
      {required this.apiUriBuilder, required this.sessionToken, super.key});

  final TradeApiUriBuilder apiUriBuilder;
  final String sessionToken;

  @override
  State<DayTradeScreen> createState() => _DayTradeScreenState();
}

class _DayTradeScreenState extends State<DayTradeScreen> {
  final TextEditingController _assetController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _entryPriceController = TextEditingController();
  final TextEditingController _pointValueController = TextEditingController();
  final TextEditingController _stopController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  final TextEditingController _strategyController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _costsController = TextEditingController();

  late DateTime _selectedDate;
  late DateTime _operationDate;
  late TimeOfDay _entryTime;
  String _market = 'Mini índice';
  String _direction = 'Compra';
  bool _loading = true;
  bool _saving = false;
  String? _operationResult;
  bool _operationResultError = false;
  String? _quantityError;
  String? _entryPriceError;
  String? _pointValueError;
  String? _stopPriceError;
  String? _targetPriceError;
  TradeSettings _settings = TradeSettings.empty();
  TradeSummary _summary = TradeSummary.empty();
  List<TradeOperation> _operations = <TradeOperation>[];

  bool get _isMiniIndex => _market == 'Mini índice';
  bool get _isMiniDollar =>
      _market == 'Mini dólar' ||
      _assetController.text.trim().toUpperCase().startsWith('WDO');
  bool get _isAutomaticContract => _isMiniIndex || _isMiniDollar;
  double get _automaticPointValue => _isMiniDollar ? 10.0 : 0.20;
  bool get _isBreakEven => _operationResult == 'BREAK_EVEN';

  int get _formQuantity => int.tryParse(_quantityController.text) ?? 0;

  double get _miniIndexPointTotal => _formQuantity * _automaticPointValue;

  double get _miniIndexExposurePoints =>
      (_parseNumber(_entryPriceController.text) -
              _parseNumber(_stopController.text))
          .abs();

  double get _miniIndexTargetPoints => (_parseNumber(_targetController.text) -
          _parseNumber(_entryPriceController.text))
      .abs();

  double get _miniIndexPlannedRisk =>
      _miniIndexExposurePoints * _miniIndexPointTotal;

  double get _miniIndexPotentialGain =>
      _miniIndexTargetPoints * _miniIndexPointTotal;

  double? get _miniIndexStopResultPoints => calculateOperationPoints(
        direction: _direction,
        entryText: _entryPriceController.text,
        exitText: _stopController.text,
      );

  double? get _miniIndexTargetResultPoints => calculateOperationPoints(
        direction: _direction,
        entryText: _entryPriceController.text,
        exitText: _targetController.text,
      );

  bool get _miniIndexNumbersComplete =>
      _formQuantity > 0 &&
      _parseNumber(_entryPriceController.text) > 0 &&
      _parseNumber(_stopController.text) > 0 &&
      _parseNumber(_targetController.text) > 0;

  Map<String, String> get _headers => <String, String>{
        'authorization': 'Bearer ${widget.sessionToken}',
        'content-type': 'application/json; charset=utf-8',
      };

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _operationDate = _selectedDate;
    _entryTime = TimeOfDay.now();
    _load();
  }

  @override
  void dispose() {
    _assetController.dispose();
    _quantityController.dispose();
    _entryPriceController.dispose();
    _pointValueController.dispose();
    _stopController.dispose();
    _targetController.dispose();
    _strategyController.dispose();
    _notesController.dispose();
    _costsController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw const TradeApiException(
          'O backend retornou uma resposta inválida.');
    }
  }

  void _applyPayload(Map<String, dynamic> body) {
    setState(() {
      _settings = TradeSettings.fromJson(
          (body['settings'] as Map<String, dynamic>?) ?? <String, dynamic>{});
      _summary = TradeSummary.fromJson(
          (body['summary'] as Map<String, dynamic>?) ?? <String, dynamic>{});
      _operations = ((body['items'] as List<dynamic>?) ?? <dynamic>[])
          .map((dynamic item) =>
              TradeOperation.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final Uri uri = widget.apiUriBuilder('/api/day-trade').replace(
          queryParameters: <String, String>{'date': _dateIso(_selectedDate)});
      final http.Response response =
          await apiClient.get(uri, headers: _headers);
      final Map<String, dynamic> body = await _decode(response);
      if (response.statusCode != 200 || body['ok'] != true) {
        throw TradeApiException((body['message'] as String?) ??
            'Não foi possível carregar as operações.');
      }
      if (!mounted) return;
      _applyPayload(body);
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveOperation() async {
    FocusScope.of(context).unfocus();
    final bool numbersValid = _validateOperationNumbers();
    final bool outcomeValid = _validateOperationOutcome();
    if (!numbersValid || !outcomeValid) return;
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        'trade_date': _dateIso(_operationDate),
        'trade_weekday': _weekdayDisplay(_operationDate),
        'entry_time': _timeText(_entryTime),
        'asset': _assetController.text.trim().toUpperCase(),
        'market': _market,
        'direction': _direction,
        'quantity': int.tryParse(_quantityController.text.trim()) ?? 0,
        'entry_price_text': _entryPriceController.text.trim(),
        'point_value_text': _isMiniDollar
            ? '10'
            : _isMiniIndex
                ? '0.20'
                : _pointValueController.text.trim(),
        'stop_price_text': _stopController.text.trim(),
        'target_price_text': _targetController.text.trim(),
        'strategy': _strategyController.text.trim(),
        'operation_result': _operationResult,
        'costs_text': _costsController.text.trim(),
        'notes': _notesController.text.trim(),
      };
      final http.Response response = await apiClient.post(
        widget.apiUriBuilder('/api/day-trade'),
        headers: _headers,
        body: jsonEncode(payload),
      );
      final Map<String, dynamic> body = await _decode(response);
      if (response.statusCode != 201 || body['ok'] != true) {
        throw TradeApiException(
            (body['message'] as String?) ?? 'Não foi possível salvar.');
      }
      if (!mounted) return;
      final bool savedAsBreakEven = _isBreakEven;
      _applyPayload(body);
      _clearForm();
      _showMessage(savedAsBreakEven
          ? 'Operação registrada como Break Even.'
          : 'Operação real registrada e confirmada no banco.');
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _requiredNumberError(TextEditingController controller) {
    if (controller.text.trim().isEmpty) return 'Campo obrigatório';
    if (_parseNumber(controller.text) <= 0) {
      return 'Informe um valor maior que zero';
    }
    return null;
  }

  bool _validateOperationNumbers() {
    final String? quantityError = _requiredNumberError(_quantityController);
    final String? entryError = _isBreakEven
        ? (_entryPriceController.text.trim().isNotEmpty &&
                _parseNumber(_entryPriceController.text) <= 0
            ? 'Informe um valor maior que zero'
            : null)
        : _requiredNumberError(_entryPriceController);
    final String? stopError =
        _isBreakEven ? null : _requiredNumberError(_stopController);
    final String? targetError =
        _isBreakEven ? null : _requiredNumberError(_targetController);
    final String? pointError = _isBreakEven || _isAutomaticContract
        ? null
        : _requiredNumberError(_pointValueController);
    setState(() {
      _quantityError = quantityError;
      _entryPriceError = entryError;
      _stopPriceError = stopError;
      _targetPriceError = targetError;
      _pointValueError = pointError;
    });
    final bool valid = quantityError == null &&
        entryError == null &&
        stopError == null &&
        targetError == null &&
        pointError == null;
    if (!valid) {
      _showMessage('Preencha todos os campos numéricos obrigatórios.',
          error: true);
    }
    return valid;
  }

  bool _validateOperationOutcome() {
    final bool valid = _operationResult == 'stop loss' ||
        _operationResult == 'Gain' ||
        _operationResult == 'BREAK_EVEN';
    setState(() => _operationResultError = !valid);
    if (!valid) {
      _showMessage('Selecione Gain, Stop loss ou Break Even.', error: true);
    }
    return valid;
  }

  void _selectOperationResult(String result) {
    setState(() {
      _operationResult = result;
      _operationResultError = false;
    });
  }

  void _selectLaunchType(String value) {
    setState(() {
      _operationResult = value == 'BREAK_EVEN' ? 'BREAK_EVEN' : null;
      _operationResultError = false;
      _entryPriceError = null;
      _pointValueError = null;
      _stopPriceError = null;
      _targetPriceError = null;
    });
  }

  Future<void> _closeOperation(TradeOperation operation) async {
    final TextEditingController exitPrice = TextEditingController();
    final TextEditingController costs = TextEditingController(text: '0,00');
    TimeOfDay exitTime = TimeOfDay.now();
    String reason = 'Alvo atingido';
    final bool? submitted = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
          title: Row(
            children: <Widget>[
              const CircleAvatar(
                backgroundColor: Color(0xFFE5F3EF),
                child: Icon(Icons.flag_rounded, color: _tradeTeal),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Encerrar ${operation.asset}')),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: exitPrice,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                    ],
                    onChanged: (_) => setDialogState(() {}),
                    decoration: _inputDecoration(
                        'Preço de saída', Icons.price_change_outlined),
                  ),
                  if (calculateOperationPoints(
                    direction: operation.direction,
                    entryText: operation.entryPrice,
                    exitText: exitPrice.text,
                  )
                      case final double points) ...<Widget>[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Resultado: ${formatOperationPoints(points)}',
                        style: TextStyle(
                          color: points > 0
                              ? _tradeGreen
                              : points < 0
                                  ? _tradeRed
                                  : _tradeBreakEven,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const Icon(Icons.schedule_rounded),
                    title: const Text('Horário de saída'),
                    subtitle: Text(_timeText(exitTime)),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: () async {
                      final TimeOfDay? picked = await showTimePicker(
                          context: context, initialTime: exitTime);
                      if (picked != null) {
                        setDialogState(() => exitTime = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: costs,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _inputDecoration(
                        'Custos operacionais', Icons.receipt_long_outlined,
                        prefixText: 'R\$ '),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: reason,
                    decoration: _inputDecoration(
                        'Motivo da saída', Icons.route_outlined),
                    items: const <String>[
                      'Alvo atingido',
                      'Stop acionado',
                      'Saída manual',
                      'Erro operacional',
                      'Encerramento do dia'
                    ]
                        .map((String value) => DropdownMenuItem<String>(
                            value: value, child: Text(value)))
                        .toList(),
                    onChanged: (String? value) {
                      if (value != null) reason = value;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Encerrar operação'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted) {
      exitPrice.dispose();
      costs.dispose();
      return;
    }
    try {
      final http.Response response = await apiClient.patch(
        widget.apiUriBuilder('/api/day-trade/${operation.id}/close'),
        headers: _headers,
        body: jsonEncode(<String, dynamic>{
          'exit_price_text': exitPrice.text.trim(),
          'exit_time': _timeText(exitTime),
          'costs_text': costs.text.trim(),
          'exit_reason': reason,
        }),
      );
      final Map<String, dynamic> body = await _decode(response);
      if (response.statusCode != 200 || body['ok'] != true) {
        throw TradeApiException((body['message'] as String?) ??
            'Não foi possível encerrar a operação.');
      }
      _showMessage('Operação encerrada e resultado calculado.');
      await _load();
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error), error: true);
    } finally {
      exitPrice.dispose();
      costs.dispose();
    }
  }

  Future<void> _editOperation(TradeOperation operation) async {
    final TextEditingController asset =
        TextEditingController(text: operation.asset);
    final TextEditingController quantity =
        TextEditingController(text: operation.quantity.toString());
    final TextEditingController entry =
        TextEditingController(text: _displayDecimal(operation.entryPrice));
    final TextEditingController pointValue =
        TextEditingController(text: _displayDecimal(operation.pointValue));
    final TextEditingController stop =
        TextEditingController(text: _displayDecimal(operation.stopPrice));
    final TextEditingController target =
        TextEditingController(text: _displayDecimal(operation.targetPrice));
    final TextEditingController strategy =
        TextEditingController(text: operation.strategy);
    final TextEditingController notes =
        TextEditingController(text: operation.notes);
    final TextEditingController costs = TextEditingController(
        text: _displayDecimal(operation.costs.toString()));
    String market = operation.market;
    String direction = operation.direction;
    DateTime operationDate =
        DateTime.tryParse(operation.tradeDate) ?? DateTime.now();
    String? result =
        operation.operationResult.isEmpty ? null : operation.operationResult;
    bool breakEven = operation.isBreakEven;
    String? formError;

    final bool? submitted = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          final bool miniIndex = market == 'Mini índice';
          bool requiredNumber(TextEditingController controller) =>
              controller.text.trim().isNotEmpty &&
              _parseNumber(controller.text) > 0;
          return AlertDialog(
            title: Row(children: <Widget>[
              const CircleAvatar(
                  backgroundColor: Color(0xFFE5F3EF),
                  child: Icon(Icons.edit_rounded, color: _tradeTeal)),
              const SizedBox(width: 12),
              Expanded(child: Text('Editar ${operation.asset}')),
            ]),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment<String>(
                            value: 'Compra', label: Text('Compra')),
                        ButtonSegment<String>(
                            value: 'Venda', label: Text('Venda')),
                      ],
                      selected: <String>{direction},
                      showSelectedIcon: false,
                      onSelectionChanged: (Set<String> values) =>
                          setDialogState(() => direction = values.first),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment<String>(
                            value: 'NORMAL', label: Text('Operação normal')),
                        ButtonSegment<String>(
                            value: 'BREAK_EVEN',
                            label: Text('Break Even'),
                            icon: Icon(Icons.balance_rounded)),
                      ],
                      selected: <String>{breakEven ? 'BREAK_EVEN' : 'NORMAL'},
                      showSelectedIcon: false,
                      onSelectionChanged: (Set<String> values) async {
                        final bool wantsBreakEven =
                            values.first == 'BREAK_EVEN';
                        if (wantsBreakEven &&
                            !breakEven &&
                            (stop.text.trim().isNotEmpty ||
                                target.text.trim().isNotEmpty)) {
                          final bool? confirmed = await showDialog<bool>(
                            context: dialogContext,
                            builder: (BuildContext confirmContext) =>
                                AlertDialog(
                              title: const Text('Alterar para Break Even?'),
                              content: const Text(
                                  'Stop e alvo preenchidos deixarão de participar do cálculo. O resultado operacional será zero.'),
                              actions: <Widget>[
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(confirmContext, false),
                                    child: const Text('Cancelar')),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(confirmContext, true),
                                    child: const Text('Confirmar')),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                        }
                        setDialogState(() {
                          breakEven = wantsBreakEven;
                          result = wantsBreakEven ? 'BREAK_EVEN' : null;
                          formError = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: _tradeLine),
                      ),
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: const Text('Data da operação'),
                      subtitle: Text(
                        '${_weekdayDisplay(operationDate)} • ${_dateDisplay(operationDate)}',
                      ),
                      trailing: const Icon(Icons.edit_calendar_outlined),
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: operationDate,
                          firstDate: DateTime(2020),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                          helpText: 'Selecione a data da operação',
                        );
                        if (picked != null) {
                          setDialogState(() {
                            operationDate = picked;
                            formError = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: asset,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: <TextInputFormatter>[
                        UpperCaseTradeFormatter()
                      ],
                      decoration: _inputDecoration(
                          'Ativo', Icons.candlestick_chart_rounded),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: market,
                      decoration: _inputDecoration(
                          'Mercado', Icons.storefront_outlined),
                      items: const <String>[
                        'Mini índice',
                        'Mini dólar',
                        'Ações',
                        'Outro'
                      ]
                          .map((String value) => DropdownMenuItem<String>(
                              value: value, child: Text(value)))
                          .toList(),
                      onChanged: (String? value) {
                        if (value != null) {
                          setDialogState(() {
                            market = value;
                            if (market == 'Mini índice') {
                              pointValue.text = '0,20';
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: quantity,
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: _inputDecoration(
                              'Quantidade', Icons.numbers_rounded),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: entry,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'))
                          ],
                          decoration: _inputDecoration(
                              'Preço de entrada', Icons.login_rounded),
                        ),
                      ),
                    ]),
                    if (!breakEven) ...<Widget>[
                      const SizedBox(height: 12),
                      Row(children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: stop,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]'))
                            ],
                            decoration: _inputDecoration(
                                'Preço de stop loss', Icons.gpp_bad_outlined),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: target,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]'))
                            ],
                            decoration: _inputDecoration(
                                'Preço alvo', Icons.flag_outlined),
                          ),
                        ),
                      ]),
                    ],
                    if (!breakEven && !miniIndex) ...<Widget>[
                      const SizedBox(height: 12),
                      TextField(
                        controller: pointValue,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                        ],
                        decoration: _inputDecoration(
                            'R\$ por ponto/unid.', Icons.paid_outlined),
                      ),
                    ],
                    if (breakEven) ...<Widget>[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _tradeBreakEven.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _tradeBreakEven.withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'Break Even • Resultado operacional: R\$ 0,00',
                          style: TextStyle(
                              color: _tradeBreakEven,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: costs,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                      ],
                      decoration: _inputDecoration(
                          'Custos operacionais', Icons.receipt_long_outlined,
                          prefixText: 'R\$ '),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: strategy,
                      decoration: _inputDecoration(
                          'Estratégia', Icons.psychology_outlined),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notes,
                      maxLines: 2,
                      decoration: _inputDecoration(
                          'Observações', Icons.sticky_note_2_outlined),
                    ),
                    const SizedBox(height: 12),
                    if (!breakEven)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: _tradeField,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: formError == null
                                    ? _tradeLine
                                    : _tradeRed)),
                        child: Row(children: <Widget>[
                          Expanded(
                            child: CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: result == 'stop loss',
                              activeColor: _tradeRed,
                              title: const Text('Stop loss'),
                              onChanged: (_) => setDialogState(() {
                                result = 'stop loss';
                                formError = null;
                              }),
                            ),
                          ),
                          Expanded(
                            child: CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: result == 'Gain',
                              activeColor: _tradeGreen,
                              title: const Text('Gain'),
                              onChanged: (_) => setDialogState(() {
                                result = 'Gain';
                                formError = null;
                              }),
                            ),
                          ),
                        ]),
                      ),
                    if (formError != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(formError!,
                          style: const TextStyle(
                              color: _tradeRed,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar')),
              FilledButton.icon(
                onPressed: () {
                  final bool valid = asset.text.trim().isNotEmpty &&
                      strategy.text.trim().isNotEmpty &&
                      requiredNumber(quantity) &&
                      (entry.text.trim().isEmpty || requiredNumber(entry)) &&
                      (breakEven || requiredNumber(entry)) &&
                      (breakEven || requiredNumber(stop)) &&
                      (breakEven || requiredNumber(target)) &&
                      (breakEven || miniIndex || requiredNumber(pointValue)) &&
                      (result == 'Gain' ||
                          result == 'stop loss' ||
                          result == 'BREAK_EVEN');
                  if (!valid) {
                    setDialogState(() => formError =
                        'Preencha os campos obrigatórios e selecione o resultado.');
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar alterações'),
              ),
            ],
          );
        },
      ),
    );

    if (submitted == true && mounted) {
      try {
        final http.Response response = await apiClient.patch(
          widget.apiUriBuilder('/api/day-trade/${operation.id}'),
          headers: _headers,
          body: jsonEncode(<String, dynamic>{
            'trade_date': _dateIso(operationDate),
            'entry_time': operation.entryTime,
            'asset': asset.text.trim().toUpperCase(),
            'market': market,
            'direction': direction,
            'quantity': int.tryParse(quantity.text.trim()) ?? 0,
            'entry_price_text': entry.text.trim(),
            'point_value_text':
                market == 'Mini índice' ? '0.20' : pointValue.text.trim(),
            'stop_price_text': stop.text.trim(),
            'target_price_text': target.text.trim(),
            'strategy': strategy.text.trim(),
            'operation_result': result,
            'costs_text': costs.text.trim(),
            'notes': notes.text.trim(),
          }),
        );
        final Map<String, dynamic> body = await _decode(response);
        if (response.statusCode != 200 || body['ok'] != true) {
          throw TradeApiException((body['message'] as String?) ??
              'Não foi possível editar a operação.');
        }
        _showMessage('Operação atualizada e resultado recalculado.');
        await _load();
      } catch (error) {
        if (mounted) _showMessage(_errorMessage(error), error: true);
      }
    }

    asset.dispose();
    quantity.dispose();
    entry.dispose();
    pointValue.dispose();
    stop.dispose();
    target.dispose();
    strategy.dispose();
    notes.dispose();
    costs.dispose();
  }

  Future<void> _deleteOperation(TradeOperation operation) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Excluir operação?'),
        content: Text(
            '${operation.asset} • ${operation.direction} será removida permanentemente.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: _tradeRed),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final http.Response response = await apiClient.delete(
          widget.apiUriBuilder('/api/day-trade/${operation.id}'),
          headers: _headers);
      final Map<String, dynamic> body = await _decode(response);
      if (response.statusCode != 200 || body['ok'] != true) {
        throw TradeApiException(
            (body['message'] as String?) ?? 'Não foi possível excluir.');
      }
      _showMessage('Operação excluída.');
      await _load();
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error), error: true);
    }
  }

  Future<void> _showRiskSettings() async {
    final TextEditingController capital = TextEditingController(
        text: _displayDecimal(_settings.initialCapitalText));
    final TextEditingController loss = TextEditingController(
        text: _displayDecimal(_settings.dailyLossLimitText));
    final TextEditingController target =
        TextEditingController(text: _displayDecimal(_settings.dailyTargetText));
    final TextEditingController maxOperations =
        TextEditingController(text: _settings.maxOperations.toString());
    final TextEditingController risk = TextEditingController(
        text: _displayDecimal(_settings.riskPerTradeText));
    final bool? submitted = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Plano diário de risco'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const _RealAccountNotice(),
                const SizedBox(height: 16),
                _moneyField(
                    capital, 'Capital disponível', Icons.savings_outlined),
                const SizedBox(height: 12),
                _moneyField(loss, 'Perda máxima diária', Icons.shield_outlined),
                const SizedBox(height: 12),
                _moneyField(target, 'Meta diária', Icons.flag_outlined),
                const SizedBox(height: 12),
                TextField(
                  controller: maxOperations,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  decoration: _inputDecoration('Máximo de operações',
                      Icons.format_list_numbered_rounded),
                ),
                const SizedBox(height: 12),
                _moneyField(risk, 'Risco por operação', Icons.speed_rounded),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar plano')),
        ],
      ),
    );
    if (submitted == true && mounted) {
      try {
        final http.Response response = await apiClient.put(
          widget.apiUriBuilder('/api/day-trade/settings'),
          headers: _headers,
          body: jsonEncode(<String, dynamic>{
            'capital_text': capital.text,
            'daily_loss_limit_text': loss.text,
            'daily_target_text': target.text,
            'max_operations': int.tryParse(maxOperations.text) ?? 0,
            'risk_per_trade_text': risk.text,
          }),
        );
        final Map<String, dynamic> body = await _decode(response);
        if (response.statusCode != 200 || body['ok'] != true) {
          throw TradeApiException((body['message'] as String?) ??
              'Não foi possível salvar o plano.');
        }
        _showMessage('Plano de risco atualizado.');
        await _load();
      } catch (error) {
        if (mounted) _showMessage(_errorMessage(error), error: true);
      }
    }
    capital.dispose();
    loss.dispose();
    target.dispose();
    maxOperations.dispose();
    risk.dispose();
  }

  Widget _moneyField(
      TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
      ],
      decoration: _inputDecoration(label, icon, prefixText: 'R\$ '),
    );
  }

  void _clearForm() {
    setState(() {
      _assetController.clear();
      _quantityController.clear();
      _entryPriceController.clear();
      _pointValueController.clear();
      _stopController.clear();
      _targetController.clear();
      _strategyController.clear();
      _notesController.clear();
      _costsController.clear();
      _entryTime = TimeOfDay.now();
      _operationDate = _selectedDate;
      _market = 'Mini índice';
      _direction = 'Compra';
      _operationResult = null;
      _operationResultError = false;
      _quantityError = null;
      _entryPriceError = null;
      _pointValueError = null;
      _stopPriceError = null;
      _targetPriceError = null;
    });
  }

  Future<void> _pickTradeDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _operationDate = picked;
      });
      await _load();
    }
  }

  Future<void> _pickOperationDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _operationDate,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('pt', 'BR'),
      initialEntryMode: DatePickerEntryMode.calendar,
      helpText: 'Data da nova operação',
      cancelText: 'Cancelar',
      confirmText: 'Escolher data',
      builder: (BuildContext context, Widget? child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: _tradeTeal,
            brightness: Brightness.light,
          ),
          datePickerTheme: DatePickerThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            headerBackgroundColor: _tradeNavy,
            headerForegroundColor: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _operationDate = picked);
    if (!DateUtils.isSameDay(_operationDate, _selectedDate) && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text(
            'DATA ESCOLHIDA DIFERENTE DA DATA A SER LANÇADA',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          backgroundColor: _tradeAmber,
        ));
    }
  }

  Future<void> _pickEntryTime() async {
    final TimeOfDay? picked =
        await showTimePicker(context: context, initialTime: _entryTime);
    if (picked != null) setState(() => _entryTime = picked);
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? _tradeRed : _tradeGreen,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _tradeCanvas,
      appBar: AppBar(
        backgroundColor: _tradeNavy,
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Controle de Day Trade',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            Text('Conta real • Diário operacional',
                style: TextStyle(fontSize: 11, color: Color(0xFFB9CDD8))),
          ],
        ),
        actions: <Widget>[
          _DayTradeBiAccessButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DayTradeBiScreen(
                  apiUriBuilder: widget.apiUriBuilder,
                  sessionToken: widget.sessionToken,
                ),
              ),
            ),
          ),
          _DayTradeNavigationAccessButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DayTradeNavigationScreen(
                  apiUriBuilder: widget.apiUriBuilder,
                  sessionToken: widget.sessionToken,
                ),
              ),
            ),
          ),
          IconButton(
              tooltip: 'Plano de risco',
              onPressed: _showRiskSettings,
              icon: const Icon(Icons.shield_outlined)),
          IconButton(
              tooltip: 'Atualizar',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.sync_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      body: Theme(
        data: ThemeData.light(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(
              seedColor: _tradeTeal, brightness: Brightness.light),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double padding = constraints.maxWidth < 620 ? 12 : 22;
              return CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: <Widget>[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(padding, 16, padding, 0),
                    sliver: SliverToBoxAdapter(child: _buildHero()),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(padding, 14, padding, 0),
                    sliver: SliverToBoxAdapter(child: _buildMetrics()),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(padding, 14, padding, 26),
                    sliver: SliverToBoxAdapter(
                      child: constraints.maxWidth >= 980
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                SizedBox(width: 380, child: _buildForm()),
                                const SizedBox(width: 16),
                                Expanded(child: _buildOperations()),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                _buildForm(),
                                const SizedBox(height: 14),
                                _buildOperations(),
                              ],
                            ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    final double lossLimit = _parseNumber(_settings.dailyLossLimitText);
    final double target = _parseNumber(_settings.dailyTargetText);
    final bool lossReached = lossLimit > 0 && _summary.netResult <= -lossLimit;
    final bool targetReached = target > 0 && _summary.netResult >= target;
    final Color statusColor = lossReached
        ? _tradeRed
        : targetReached
            ? _tradeGreen
            : _tradeTeal;
    final String title = lossReached
        ? 'Limite diário de perda atingido'
        : targetReached
            ? 'Meta diária atingida'
            : _settings.configured
                ? 'Plano de risco ativo'
                : 'Configure seu plano de risco';
    final String subtitle = lossReached
        ? 'Considere encerrar o operacional de hoje e preservar o capital.'
        : targetReached
            ? 'Objetivo alcançado. Proteja o resultado construído.'
            : _settings.configured
                ? '${_summary.operationsRemaining} operações disponíveis no limite definido.'
                : 'Defina capital, limite de perda, meta e risco por operação.';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1240),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: <Color>[Color(0xFF102A3A), Color(0xFF174A50)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const <BoxShadow>[
            BoxShadow(
                color: Color(0x28102A3A), blurRadius: 24, offset: Offset(0, 12))
          ],
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget status = Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(15)),
                  child: Icon(
                      lossReached
                          ? Icons.gpp_bad_outlined
                          : targetReached
                              ? Icons.emoji_events_outlined
                              : Icons.shield_outlined,
                      color: Colors.white),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Color(0xFFC6D7DE), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            );
            final Widget controls = Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _pickTradeDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(_dateDisplay(_selectedDate)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF6F9298)),
                    backgroundColor: const Color(0x25FFFFFF),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _showRiskSettings,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Plano de risco'),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _tradeNavy),
                ),
              ],
            );
            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  status,
                  const SizedBox(height: 16),
                  controls
                ],
              );
            }
            return Row(children: <Widget>[
              Expanded(child: status),
              const SizedBox(width: 24),
              controls,
            ]);
          },
        ),
      ),
    );
  }

  Widget _buildMetrics() {
    final List<_TradeMetric> cards = <_TradeMetric>[
      _TradeMetric(
          title: 'Resultado líquido',
          value: _currency(_summary.netResult),
          icon: Icons.account_balance_wallet_outlined,
          color: _summary.netResult >= 0 ? _tradeGreen : _tradeRed),
      _TradeMetric(
          title: 'Taxa de acerto',
          value: '${_summary.winRate.toStringAsFixed(0)}%',
          icon: Icons.track_changes_rounded,
          color: _tradeTeal),
      _TradeMetric(
          title: 'Gain / Loss',
          value: '${_summary.gains} / ${_summary.losses}',
          icon: Icons.balance_rounded,
          color: _tradeAmber),
      _TradeMetric(
          title: 'Custos',
          value: _currency(_summary.costs),
          icon: Icons.receipt_long_outlined,
          color: _tradeMuted),
      _TradeMetric(
          title: 'Operações abertas',
          value: _summary.openOperations.toString(),
          icon: Icons.pending_actions_outlined,
          color: _tradeAmber),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 1040
            ? 5
            : constraints.maxWidth >= 650
                ? 3
                : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 92,
          ),
          itemBuilder: (BuildContext context, int index) => cards[index],
        );
      },
    );
  }

  Widget _buildForm() {
    return _TradePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _TradeSectionTitle(
              icon: Icons.add_chart_rounded,
              title: 'Nova operação real',
              subtitle: 'Planeje a entrada antes de executar'),
          const SizedBox(height: 16),
          const _RealAccountNotice(),
          const SizedBox(height: 14),
          InkWell(
            key: const Key('new-operation-date-picker'),
            onTap: _pickOperationDate,
            borderRadius: BorderRadius.circular(14),
            child: InputDecorator(
              decoration: _inputDecoration(
                'Data da operação',
                Icons.calendar_month_rounded,
                hintText: 'Escolha no calendário',
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _dateDisplay(_operationDate),
                          style: const TextStyle(
                            color: _tradeInk,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _weekdayDisplay(_operationDate),
                          style: const TextStyle(
                            color: _tradeMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.edit_calendar_outlined, color: _tradeTeal),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(
                  value: 'Compra',
                  label: Text('Compra'),
                  icon: Icon(Icons.trending_up_rounded)),
              ButtonSegment<String>(
                  value: 'Venda',
                  label: Text('Venda'),
                  icon: Icon(Icons.trending_down_rounded)),
            ],
            selected: <String>{_direction},
            showSelectedIcon: false,
            onSelectionChanged: (Set<String> value) =>
                setState(() => _direction = value.first),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: 'NORMAL',
                label: Text('Operação normal'),
                icon: Icon(Icons.swap_vert_rounded),
              ),
              ButtonSegment<String>(
                value: 'BREAK_EVEN',
                label: Text('Break Even'),
                icon: Icon(Icons.balance_rounded),
              ),
            ],
            selected: <String>{_isBreakEven ? 'BREAK_EVEN' : 'NORMAL'},
            showSelectedIcon: false,
            onSelectionChanged: (Set<String> value) =>
                _selectLaunchType(value.first),
          ),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            Expanded(
              child: TextField(
                controller: _assetController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: <TextInputFormatter>[
                  UpperCaseTradeFormatter()
                ],
                onChanged: (_) => setState(() => _pointValueError = null),
                decoration: _inputDecoration(
                    'Ativo', Icons.candlestick_chart_rounded,
                    hintText: 'WIN, WDO...'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 112,
              child: TextField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly
                ],
                onChanged: (_) => setState(() => _quantityError = null),
                decoration: _inputDecoration(
                    'Quantidade', Icons.numbers_rounded,
                    errorText: _quantityError),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey<String>(_market),
            initialValue: _market,
            decoration: _inputDecoration('Mercado', Icons.storefront_outlined),
            items: const <String>['Mini índice', 'Mini dólar', 'Ações', 'Outro']
                .map((String value) =>
                    DropdownMenuItem<String>(value: value, child: Text(value)))
                .toList(),
            onChanged: (String? value) {
              if (value != null) {
                setState(() {
                  _market = value;
                  _pointValueController.text = value == 'Mini índice'
                      ? '0,20'
                      : value == 'Mini dólar'
                          ? '10,00'
                          : '';
                  _stopController.clear();
                  _targetController.clear();
                  if (!_isBreakEven) _operationResult = null;
                  _operationResultError = false;
                  _pointValueError = null;
                  _stopPriceError = null;
                  _targetPriceError = null;
                });
              }
            },
          ),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            Expanded(
                child: _decimalField(_entryPriceController, 'Preço de entrada',
                    Icons.login_rounded,
                    errorText: _entryPriceError,
                    onChanged: (_) => setState(() => _entryPriceError = null))),
            const SizedBox(width: 10),
            if (!_isBreakEven)
              Expanded(
                child: _isAutomaticContract
                    ? InputDecorator(
                        decoration: _inputDecoration(
                            'Valor por ponto', Icons.calculate_outlined),
                        child: Text(
                          _miniIndexNumbersComplete
                              ? '${_currency(_miniIndexPointTotal)} total'
                              : '',
                          style: const TextStyle(
                              color: _tradeTeal, fontWeight: FontWeight.w900),
                        ),
                      )
                    : _decimalField(_pointValueController,
                        'R\$ por ponto/unid.', Icons.paid_outlined,
                        errorText: _pointValueError,
                        onChanged: (_) =>
                            setState(() => _pointValueError = null)),
              ),
          ]),
          if (!_isBreakEven) ...<Widget>[
            const SizedBox(height: 12),
            Row(children: <Widget>[
              Expanded(
                  child: _decimalField(
                      _stopController,
                      _isMiniIndex ? 'Preço de stop loss' : 'Preço do stop',
                      Icons.gpp_bad_outlined,
                      errorText: _stopPriceError,
                      onChanged: (_) =>
                          setState(() => _stopPriceError = null))),
              const SizedBox(width: 10),
              Expanded(
                  child: _decimalField(
                      _targetController,
                      _isMiniIndex ? 'Preço alvo' : 'Preço do alvo',
                      Icons.flag_outlined,
                      errorText: _targetPriceError,
                      onChanged: (_) =>
                          setState(() => _targetPriceError = null))),
            ]),
          ],
          if (_isBreakEven) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: _tradeBreakEven.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: _tradeBreakEven.withValues(alpha: 0.42)),
              ),
              child: const Row(children: <Widget>[
                Icon(Icons.balance_rounded, color: _tradeBreakEven),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Break Even • Empate',
                          style: TextStyle(
                              color: _tradeBreakEven,
                              fontWeight: FontWeight.w900)),
                      Text('Resultado operacional: R\$ 0,00',
                          style: TextStyle(color: _tradeMuted, fontSize: 11)),
                    ],
                  ),
                ),
              ]),
            ),
          ] else if (_isAutomaticContract) ...<Widget>[
            const SizedBox(height: 12),
            InputDecorator(
              decoration: _inputDecoration(
                  'Exposição em pontos', Icons.straighten_rounded),
              child: Text(
                _miniIndexNumbersComplete
                    ? '${_plainNumber(_miniIndexExposurePoints)} pontos'
                    : '',
                style: const TextStyle(
                    color: _tradeRed, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            _buildMiniIndexCalculator(),
          ] else ...<Widget>[
            const SizedBox(height: 12),
            _buildSimpleOutcomeSelector(),
          ],
          const SizedBox(height: 12),
          _decimalField(_costsController, 'Custos operacionais',
              Icons.receipt_long_outlined),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickEntryTime,
            borderRadius: BorderRadius.circular(14),
            child: InputDecorator(
              decoration: _inputDecoration(
                  'Horário da entrada', Icons.schedule_rounded),
              child: Text(_timeText(_entryTime)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _strategyController,
            decoration: _inputDecoration(
                'Estratégia', Icons.psychology_outlined,
                hintText: 'Rompimento, pullback...'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: _inputDecoration(
                'Observações', Icons.sticky_note_2_outlined,
                hintText: 'Contexto e disciplina'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _saveOperation,
            icon: _saving
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Salvando...' : 'Registrar operação'),
            style: FilledButton.styleFrom(
              backgroundColor: _tradeTeal,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _decimalField(
      TextEditingController controller, String label, IconData icon,
      {ValueChanged<String>? onChanged, String? errorText}) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
      ],
      onChanged: onChanged,
      decoration: _inputDecoration(label, icon, errorText: errorText),
    );
  }

  Widget _buildMiniIndexCalculator() {
    final int quantity = _formQuantity;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F4F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB8DCD4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(children: <Widget>[
            const Icon(Icons.auto_graph_rounded, color: _tradeTeal, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _miniIndexNumbersComplete
                    ? '$quantity contrato${quantity == 1 ? '' : 's'} × ${_currency(_automaticPointValue)} = ${_currency(_miniIndexPointTotal)} por ponto'
                    : 'Preencha quantidade, entrada, stop e alvo.',
                style: const TextStyle(
                    color: _tradeNavy,
                    fontSize: 11,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: <Widget>[
            Expanded(
              child: _TradeCalculation(
                  label: 'LOSS NO STOP',
                  value: _miniIndexNumbersComplete
                      ? '${_currency(-_miniIndexPlannedRisk)} | '
                          '${formatOperationPoints(_miniIndexStopResultPoints)}'
                      : '',
                  color: _tradeRed,
                  selected: _operationResult == 'stop loss',
                  showError: _operationResultError,
                  onChanged: (_) => _selectOperationResult('stop loss')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TradeCalculation(
                  label: 'GANHO NO ALVO',
                  value: _miniIndexNumbersComplete
                      ? '${_currency(_miniIndexPotentialGain)} | '
                          '${formatOperationPoints(_miniIndexTargetResultPoints)}'
                      : '',
                  color: _tradeGreen,
                  selected: _operationResult == 'Gain',
                  showError: _operationResultError,
                  onChanged: (_) => _selectOperationResult('Gain')),
            ),
          ]),
          if (_operationResultError) ...<Widget>[
            const SizedBox(height: 8),
            const Text(
              'Selecione obrigatoriamente Stop loss ou Gain.',
              style: TextStyle(
                  color: _tradeRed, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSimpleOutcomeSelector() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _tradeField,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: _operationResultError ? _tradeRed : _tradeLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('Status da op • seleção obrigatória',
              style: TextStyle(
                  color: _tradeMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          Row(children: <Widget>[
            Expanded(
              child: CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _operationResult == 'stop loss',
                activeColor: _tradeRed,
                title: const Text('Stop loss'),
                onChanged: (_) => _selectOperationResult('stop loss'),
              ),
            ),
            Expanded(
              child: CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _operationResult == 'Gain',
                activeColor: _tradeGreen,
                title: const Text('Gain'),
                onChanged: (_) => _selectOperationResult('Gain'),
              ),
            ),
          ]),
          if (_operationResultError)
            const Text('Selecione Stop loss ou Gain.',
                style: TextStyle(
                    color: _tradeRed,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildOperations() {
    return _TradePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TradeSectionTitle(
            icon: Icons.timeline_rounded,
            title: 'Operações do dia',
            subtitle:
                '${_operations.length} registros • ${_dateDisplay(_selectedDate)}',
          ),
          const SizedBox(height: 16),
          if (_loading)
            const SizedBox(
                height: 240, child: Center(child: CircularProgressIndicator()))
          else if (_operations.isEmpty)
            const _EmptyTrades()
          else
            for (final TradeOperation operation in _operations)
              _buildOperationCard(operation),
        ],
      ),
    );
  }

  Widget _buildOperationCard(TradeOperation operation) {
    final bool open = operation.status == 'ABERTA';
    final bool breakEven = operation.isBreakEven;
    final bool gain = !breakEven &&
        (operation.operationResult == 'Gain' || operation.netResult > 0);
    final bool loss = !breakEven &&
        (operation.operationResult == 'stop loss' || operation.netResult < 0);
    final Color resultColor = open
        ? _tradeAmber
        : breakEven
            ? _tradeBreakEven
            : gain
                ? _tradeGreen
                : loss
                    ? _tradeRed
                    : _tradeMuted;
    final double riskLimit = _parseNumber(_settings.riskPerTradeText);
    final bool riskExceeded =
        riskLimit > 0 && operation.plannedRisk > riskLimit;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: resultColor.withValues(alpha: 0.48)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
              color: Color(0x0D102A3A), blurRadius: 12, offset: Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                    color: resultColor.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(
                    operation.direction == 'Compra'
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    color: resultColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(operation.asset,
                            style: const TextStyle(
                                color: _tradeInk,
                                fontSize: 17,
                                fontWeight: FontWeight.w900)),
                        _TradePill(
                            label: operation.direction,
                            color: operation.direction == 'Compra'
                                ? _tradeTeal
                                : _tradeRed),
                        _TradePill(
                            label: open
                                ? 'ABERTA'
                                : breakEven
                                    ? 'BREAK EVEN'
                                    : gain
                                        ? 'GAIN'
                                        : loss
                                            ? 'LOSS'
                                            : 'ZERO A ZERO',
                            color: resultColor),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                        '${operation.market} • ${operation.quantity} un.\n${_capitalizeFirst(operation.tradeWeekday)} • ${_dateDisplayFromIso(operation.tradeDate)} • ${operation.entryTime}${operation.exitTime.isEmpty ? '' : ' → ${operation.exitTime}'}',
                        style:
                            const TextStyle(color: _tradeMuted, fontSize: 11)),
                  ],
                ),
              ),
              if (!open)
                Flexible(
                  child: Text(
                    '${breakEven ? 'Break-even' : gain ? 'Ganho' : 'Perda'}: '
                    '${_currency(operation.netResult)} | '
                    '${formatOperationPoints(operation.pointsResult)}',
                    textAlign: TextAlign.end,
                    softWrap: true,
                    style: TextStyle(
                        color: resultColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w900),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _TradeFact(
                  label: 'Entrada',
                  value: _displayDecimal(operation.entryPrice)),
              if (!open)
                _TradeFact(
                    label: 'Saída',
                    value: _displayDecimal(operation.exitPrice)),
              if (!open && operation.pointsResult != null)
                _TradeFact(
                    label: 'Resultado em pontos',
                    value: formatOperationPoints(operation.pointsResult),
                    color: resultColor),
              if (!breakEven && operation.market == 'Mini índice') ...<Widget>[
                _TradeFact(
                    label: 'Preço de stop loss',
                    value: _displayDecimal(operation.stopPrice)),
                _TradeFact(
                    label: 'Preço alvo',
                    value: _displayDecimal(operation.targetPrice)),
                _TradeFact(
                    label: 'Exposição',
                    value: '${_plainNumber(operation.stopPoints)} pts'),
                _TradeFact(
                    label: 'Valor por ponto',
                    value: _currency(operation.totalPointValue)),
              ] else if (!breakEven) ...<Widget>[
                _TradeFact(
                    label: 'Stop', value: _displayDecimal(operation.stopPrice)),
                _TradeFact(
                    label: 'Alvo',
                    value: _displayDecimal(operation.targetPrice)),
              ],
              if (!breakEven)
                _TradeFact(
                    label: 'Risco planejado',
                    value: _currency(operation.plannedRisk),
                    color: riskExceeded ? _tradeRed : null),
              if (operation.operationResult.isNotEmpty)
                _TradeFact(
                    label: 'Status da op',
                    value: operation.operationResult,
                    color: breakEven
                        ? _tradeBreakEven
                        : operation.operationResult == 'Gain'
                            ? _tradeGreen
                            : _tradeRed),
              if (breakEven) ...<Widget>[
                const _TradeFact(
                    label: 'Resultado operacional',
                    value: 'R\$ 0,00',
                    color: _tradeBreakEven),
                _TradeFact(label: 'Custos', value: _currency(operation.costs)),
              ] else
                _TradeFact(
                    label: 'Risco/retorno',
                    value: '1 : ${operation.riskReward.toStringAsFixed(1)}'),
              _TradeFact(label: 'Estratégia', value: operation.strategy),
            ],
          ),
          if (riskExceeded) ...<Widget>[
            const SizedBox(height: 10),
            const Row(children: <Widget>[
              Icon(Icons.warning_amber_rounded, size: 17, color: _tradeRed),
              SizedBox(width: 6),
              Expanded(
                child: Text('Risco planejado acima do limite por operação.',
                    style: TextStyle(
                        color: _tradeRed,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ],
          if (!open && operation.exitReason.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text('Saída: ${operation.exitReason}',
                style: const TextStyle(color: _tradeMuted, fontSize: 11)),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              if (open)
                FilledButton.icon(
                  onPressed: () => _closeOperation(operation),
                  icon: const Icon(Icons.flag_rounded, size: 18),
                  label: const Text('Encerrar'),
                  style: FilledButton.styleFrom(
                      backgroundColor: _tradeTeal,
                      foregroundColor: Colors.white),
                ),
              const SizedBox(width: 6),
              IconButton(
                  tooltip: 'Editar',
                  onPressed: () => _editOperation(operation),
                  color: _tradeTeal,
                  icon: const Icon(Icons.edit_outlined)),
              const SizedBox(width: 2),
              IconButton(
                  tooltip: 'Excluir',
                  onPressed: () => _deleteOperation(operation),
                  color: _tradeRed,
                  icon: const Icon(Icons.delete_outline_rounded)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayTradeBiAccessButton extends StatelessWidget {
  const _DayTradeBiAccessButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bool showDescription = MediaQuery.sizeOf(context).width >= 760;
    const Color accent = Color(0xFF52D6B5);

    return Semantics(
      button: true,
      label: 'Abrir Business Intelligence',
      child: Tooltip(
        message: 'Abrir Business Intelligence',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
          child: FilledButton(
            onPressed: onPressed,
            style: ButtonStyle(
              foregroundColor:
                  const WidgetStatePropertyAll<Color>(Colors.white),
              backgroundColor:
                  const WidgetStatePropertyAll<Color>(Color(0xFF173E58)),
              overlayColor:
                  WidgetStatePropertyAll<Color>(accent.withValues(alpha: 0.14)),
              side: const WidgetStatePropertyAll<BorderSide>(
                BorderSide(color: accent, width: 1.2),
              ),
              elevation: const WidgetStatePropertyAll<double>(2),
              padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
                EdgeInsets.symmetric(
                  horizontal: showDescription ? 12 : 10,
                  vertical: 7,
                ),
              ),
              shape: WidgetStatePropertyAll<RoundedRectangleBorder>(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              minimumSize: const WidgetStatePropertyAll<Size>(Size(64, 44)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.analytics_rounded, size: 22, color: accent),
                const SizedBox(width: 7),
                if (showDescription)
                  const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('BI',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800)),
                      Text('Análise e desempenho',
                          style: TextStyle(
                              color: Color(0xFFC7DCE5), fontSize: 9.5)),
                    ],
                  )
                else
                  const Text('BI',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayTradeNavigationAccessButton extends StatelessWidget {
  const _DayTradeNavigationAccessButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final showDescription = MediaQuery.sizeOf(context).width >= 900;
    const accent = Color(0xFF6DD5FA);
    return Semantics(
      button: true,
      label: 'Abrir navegação de operações',
      child: Tooltip(
        message: 'Navegar e editar todas as operações',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xFF173E58),
              side: const BorderSide(color: accent, width: 1.2),
              elevation: 2,
              minimumSize: const Size(64, 44),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.table_rows_rounded, size: 21, color: accent),
                const SizedBox(width: 7),
                if (showDescription)
                  const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NAVEGAÇÃO',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800)),
                      Text('Todos os registros',
                          style: TextStyle(
                              color: Color(0xFFC7DCE5), fontSize: 9.5)),
                    ],
                  )
                else
                  const Text('NAV',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TradePanel extends StatelessWidget {
  const _TradePanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _tradePanel,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _tradeLine),
          boxShadow: const <BoxShadow>[
            BoxShadow(
                color: Color(0x10102A3A), blurRadius: 20, offset: Offset(0, 8))
          ],
        ),
        child: child,
      );
}

class _TradeMetric extends StatelessWidget {
  const _TradeMetric(
      {required this.title,
      required this.value,
      required this.icon,
      required this.color});
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _tradeLine)),
        child: Row(children: <Widget>[
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: color, size: 21)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _tradeMuted, fontSize: 10)),
                const SizedBox(height: 3),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ]),
      );
}

class _TradeSectionTitle extends StatelessWidget {
  const _TradeSectionTitle(
      {required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
        Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: const Color(0xFFE5F3EF),
                borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: _tradeTeal, size: 21)),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title,
                  style: const TextStyle(
                      color: _tradeInk,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              Text(subtitle,
                  style: const TextStyle(color: _tradeMuted, fontSize: 11)),
            ],
          ),
        ),
      ]);
}

class _RealAccountNotice extends StatelessWidget {
  const _RealAccountNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
            color: const Color(0xFFEAF2F5),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFFC9D9DF))),
        child: const Row(children: <Widget>[
          Icon(Icons.verified_user_outlined, color: _tradeNavy, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text('CONTA REAL • valores financeiros efetivos',
                style: TextStyle(
                    color: _tradeNavy,
                    fontSize: 10,
                    letterSpacing: 0.35,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}

class _TradePill extends StatelessWidget {
  const _TradePill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.28))),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 9, fontWeight: FontWeight.w900)),
      );
}

class _TradeFact extends StatelessWidget {
  const _TradeFact({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: _tradeField, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label,
                style: const TextStyle(color: _tradeMuted, fontSize: 8)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    color: color ?? _tradeInk,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

class _TradeCalculation extends StatelessWidget {
  const _TradeCalculation(
      {required this.label,
      required this.value,
      required this.color,
      required this.selected,
      required this.showError,
      required this.onChanged});

  final String label;
  final String value;
  final Color color;
  final bool selected;
  final bool showError;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: () => onChanged(!selected),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected
                    ? color
                    : showError
                        ? _tradeRed
                        : Colors.transparent)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: _tradeMuted,
                        fontSize: 8,
                        fontWeight: FontWeight.w700)),
              ),
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                    value: selected,
                    activeColor: color,
                    side: BorderSide(color: showError ? _tradeRed : color),
                    onChanged: onChanged),
              ),
            ]),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w900)),
          ],
        ),
      ));
}

class _EmptyTrades extends StatelessWidget {
  const _EmptyTrades();

  @override
  Widget build(BuildContext context) => Container(
        height: 240,
        decoration: BoxDecoration(
            color: _tradeField, borderRadius: BorderRadius.circular(18)),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xFFE5F3EF),
                child: Icon(Icons.candlestick_chart_outlined,
                    color: _tradeTeal, size: 28)),
            SizedBox(height: 13),
            Text('Nenhuma operação registrada',
                style:
                    TextStyle(color: _tradeInk, fontWeight: FontWeight.w800)),
            SizedBox(height: 4),
            Text('Planeje sua primeira entrada real ao lado.',
                style: TextStyle(color: _tradeMuted, fontSize: 11)),
          ],
        ),
      );
}

class TradeSettings {
  TradeSettings(
      {required this.capitalText,
      required this.initialCapitalText,
      required this.dailyLossLimitText,
      required this.dailyTargetText,
      required this.maxOperations,
      required this.riskPerTradeText});

  factory TradeSettings.empty() => TradeSettings(
      capitalText: '0',
      initialCapitalText: '0',
      dailyLossLimitText: '0',
      dailyTargetText: '0',
      maxOperations: 5,
      riskPerTradeText: '0');

  factory TradeSettings.fromJson(Map<String, dynamic> json) => TradeSettings(
      capitalText: '${json['capital_text'] ?? '0'}',
      initialCapitalText:
          '${json['initial_capital_text'] ?? json['capital_text'] ?? '0'}',
      dailyLossLimitText: '${json['daily_loss_limit_text'] ?? '0'}',
      dailyTargetText: '${json['daily_target_text'] ?? '0'}',
      maxOperations: (json['max_operations'] as num?)?.toInt() ?? 5,
      riskPerTradeText: '${json['risk_per_trade_text'] ?? '0'}');

  final String capitalText;
  final String initialCapitalText;
  final String dailyLossLimitText;
  final String dailyTargetText;
  final int maxOperations;
  final String riskPerTradeText;

  bool get configured =>
      _parseNumber(capitalText) > 0 &&
      _parseNumber(dailyLossLimitText) > 0 &&
      _parseNumber(dailyTargetText) > 0 &&
      _parseNumber(riskPerTradeText) > 0;
}

class TradeSummary {
  TradeSummary(
      {required this.netResult,
      required this.costs,
      required this.gains,
      required this.losses,
      required this.openOperations,
      required this.operationsRemaining,
      required this.winRate});

  factory TradeSummary.empty() => TradeSummary(
      netResult: 0,
      costs: 0,
      gains: 0,
      losses: 0,
      openOperations: 0,
      operationsRemaining: 0,
      winRate: 0);

  factory TradeSummary.fromJson(Map<String, dynamic> json) => TradeSummary(
      netResult: (json['net_result'] as num?)?.toDouble() ?? 0,
      costs: (json['costs'] as num?)?.toDouble() ?? 0,
      gains: (json['gains'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      openOperations: (json['open_operations'] as num?)?.toInt() ?? 0,
      operationsRemaining: (json['operations_remaining'] as num?)?.toInt() ?? 0,
      winRate: (json['win_rate'] as num?)?.toDouble() ?? 0);

  final double netResult;
  final double costs;
  final int gains;
  final int losses;
  final int openOperations;
  final int operationsRemaining;
  final double winRate;
}

class TradeOperation {
  TradeOperation(
      {required this.id,
      required this.tradeDate,
      required this.tradeWeekday,
      required this.asset,
      required this.market,
      required this.direction,
      required this.quantity,
      required this.entryTime,
      required this.exitTime,
      required this.entryPrice,
      required this.exitPrice,
      required this.pointValue,
      required this.stopPrice,
      required this.targetPrice,
      required this.stopPoints,
      required this.targetPoints,
      required this.totalPointValue,
      required this.strategy,
      required this.notes,
      required this.exitReason,
      required this.operationResult,
      required this.backendResultType,
      required this.status,
      required this.plannedRisk,
      required this.riskReward,
      required this.costs,
      required this.netResult,
      required this.pointsResult});

  factory TradeOperation.fromJson(Map<String, dynamic> json) => TradeOperation(
      id: (json['id'] as num).toInt(),
      tradeDate: '${json['trade_date'] ?? ''}',
      tradeWeekday: '${json['trade_weekday'] ?? ''}',
      asset: '${json['asset'] ?? ''}',
      market: '${json['market'] ?? ''}',
      direction: '${json['direction'] ?? ''}',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      entryTime: '${json['entry_time'] ?? ''}',
      exitTime: '${json['exit_time'] ?? ''}',
      entryPrice: '${json['entry_price_text'] ?? ''}',
      exitPrice: '${json['exit_price_text'] ?? ''}',
      pointValue: '${json['point_value_text'] ?? ''}',
      stopPrice: '${json['stop_price_text'] ?? ''}',
      targetPrice: '${json['target_price_text'] ?? ''}',
      stopPoints: (json['stop_points'] as num?)?.toDouble() ?? 0,
      targetPoints: (json['target_points'] as num?)?.toDouble() ?? 0,
      totalPointValue: (json['total_point_value'] as num?)?.toDouble() ?? 0,
      strategy: '${json['strategy'] ?? ''}',
      notes: '${json['notes'] ?? ''}',
      exitReason: '${json['exit_reason'] ?? ''}',
      operationResult: '${json['operation_result'] ?? ''}',
      backendResultType: '${json['result_type'] ?? ''}',
      status: '${json['status'] ?? 'ABERTA'}',
      plannedRisk: (json['planned_risk'] as num?)?.toDouble() ?? 0,
      riskReward: (json['risk_reward'] as num?)?.toDouble() ?? 0,
      costs: _parseNumber('${json['costs_text'] ?? '0'}'),
      netResult: (json['net_result'] as num?)?.toDouble() ?? 0,
      pointsResult: (json['points_result'] as num?)?.toDouble());

  final int id;
  final String tradeDate;
  final String tradeWeekday;
  final String asset;
  final String market;
  final String direction;
  final int quantity;
  final String entryTime;
  final String exitTime;
  final String entryPrice;
  final String exitPrice;
  final String pointValue;
  final String stopPrice;
  final String targetPrice;
  final double stopPoints;
  final double targetPoints;
  final double totalPointValue;
  final String strategy;
  final String notes;
  final String exitReason;
  final String operationResult;
  final String backendResultType;
  final String status;
  final double plannedRisk;
  final double riskReward;
  final double costs;
  final double netResult;
  final double? pointsResult;

  bool get isBreakEven => resultType == 'BREAK_EVEN';

  String get resultType => backendResultType.isNotEmpty
      ? backendResultType
      : operationResult == 'BREAK_EVEN' || netResult.abs() < 0.01
          ? 'BREAK_EVEN'
          : netResult > 0
              ? 'WIN'
              : netResult < 0
                  ? 'LOSS'
                  : 'BREAK_EVEN';
}

class TradeApiException implements Exception {
  const TradeApiException(this.message);
  final String message;
}

class UpperCaseTradeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(
          text: newValue.text.toUpperCase(), selection: newValue.selection);
}

InputDecoration _inputDecoration(String label, IconData icon,
    {String? hintText, String? prefixText, String? errorText}) {
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    prefixText: prefixText,
    errorText: errorText,
    prefixIcon: Icon(icon),
    isDense: true,
    filled: true,
    fillColor: _tradeField,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _tradeLine)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _tradeTeal, width: 1.5)),
  );
}

String _errorMessage(Object error) => error is TradeApiException
    ? error.message
    : 'Não foi possível conectar ao backend Python.';

String _dateIso(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _dateDisplay(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _dateDisplayFromIso(String value) {
  final DateTime? date = DateTime.tryParse(value);
  return date == null ? value : _dateDisplay(date);
}

String _weekdayDisplay(DateTime date) => const <String>[
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado',
      'Domingo',
    ][date.weekday - 1];

String _capitalizeFirst(String value) => value.isEmpty
    ? value
    : '${value.substring(0, 1).toUpperCase()}${value.substring(1)}';

String _timeText(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

double _parseNumber(String value) {
  String cleaned = value.replaceAll('R\$', '').replaceAll(' ', '');
  if (cleaned.contains(',')) {
    cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^[+-]?\d{1,3}(\.\d{3})+$').hasMatch(cleaned)) {
    cleaned = cleaned.replaceAll('.', '');
  }
  return double.tryParse(cleaned) ?? 0;
}

String _displayDecimal(String value) {
  if (value.isEmpty) return '—';
  final double number = _parseNumber(value);
  final String fixed = number.toStringAsFixed(number % 1 == 0 ? 2 : 4);
  return fixed.replaceAll('.', ',');
}

String _plainNumber(double value) {
  final int decimals = value == value.roundToDouble() ? 0 : 2;
  return value.toStringAsFixed(decimals).replaceAll('.', ',');
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
