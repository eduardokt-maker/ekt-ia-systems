import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

typedef DayTradeNavigationUriBuilder = Uri Function(String path);

const _navNavy = Color(0xFF061A33);
const _navPanel = Color(0xFF092847);
const _navCyan = Color(0xFF39E7E0);
const _navLine = Color(0xFF2E668A);
const _navYellow = Color(0xFFFFE66B);

class DayTradeNavigationScreen extends StatefulWidget {
  const DayTradeNavigationScreen({
    required this.apiUriBuilder,
    required this.sessionToken,
    super.key,
  });

  final DayTradeNavigationUriBuilder apiUriBuilder;
  final String sessionToken;

  @override
  State<DayTradeNavigationScreen> createState() =>
      _DayTradeNavigationScreenState();
}

class _DayTradeNavigationScreenState extends State<DayTradeNavigationScreen> {
  final FocusNode _focus = FocusNode();
  final ScrollController _vertical = ScrollController();
  List<_NavigationOperation> _items = [];
  int _selected = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  Map<String, String> get _headers => {
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
    _focus.dispose();
    _vertical.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        widget.apiUriBuilder('/api/day-trade/navigation'),
        headers: _headers,
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw Exception(body['message'] ?? 'Consulta indisponível.');
      }
      final items = ((body['items'] as List<dynamic>?) ?? [])
          .map((item) =>
              _NavigationOperation.fromJson(item as Map<String, dynamic>))
          .toList()
        ..sort(_NavigationOperation.compareNewestFirst);
      if (!mounted) return;
      setState(() {
        _items = items;
        _selected = items.isEmpty ? 0 : _selected.clamp(0, items.length - 1);
      });
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _items.isEmpty) {
      return KeyEventResult.ignored;
    }
    var next = _selected;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      next = (_selected + 1).clamp(0, _items.length - 1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      next = (_selected - 1).clamp(0, _items.length - 1);
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      _editSelected();
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    _select(next);
    return KeyEventResult.handled;
  }

  void _select(int index) {
    setState(() => _selected = index);
    final target = index * 39.0;
    if (_vertical.hasClients) {
      _vertical.animateTo(
        target.clamp(0, _vertical.position.maxScrollExtent),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _editSelected() async {
    if (_items.isEmpty || _saving) return;
    final operation = _items[_selected];
    final date = TextEditingController(text: _dateBr(operation.tradeDate));
    final time = TextEditingController(text: operation.entryTime);
    final exitTime = TextEditingController(text: operation.exitTime);
    final asset = TextEditingController(text: operation.asset);
    final quantity = TextEditingController(text: '${operation.quantity}');
    final entry = TextEditingController(text: operation.entryPrice);
    final stop = TextEditingController(text: operation.stopPrice);
    final target = TextEditingController(text: operation.targetPrice);
    final pointValue = TextEditingController(text: operation.pointValue);
    final costs = TextEditingController(text: operation.costsText);
    final strategy = TextEditingController(text: operation.strategy);
    final notes = TextEditingController(text: operation.notes);
    var market = operation.market;
    var direction = operation.direction;
    var result = operation.operationResult.isEmpty
        ? operation.resultType == 'WIN'
            ? 'Gain'
            : operation.resultType == 'LOSS'
                ? 'stop loss'
                : 'BREAK_EVEN'
        : operation.operationResult;
    String? dialogError;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Editar registro #${operation.id}'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Expanded(child: _field(date, 'Data (dd/mm/aaaa)')),
                    const SizedBox(width: 10),
                    Expanded(child: _field(time, 'Hora entrada')),
                    const SizedBox(width: 10),
                    Expanded(child: _field(exitTime, 'Hora saída')),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _field(asset, 'Ativo')),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: market,
                        decoration: const InputDecoration(
                            labelText: 'Mercado', border: OutlineInputBorder()),
                        items: const [
                          'Mini índice',
                          'Mini dólar',
                          'Ações',
                          'Outro'
                        ]
                            .map((value) => DropdownMenuItem(
                                value: value, child: Text(value)))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => market = value);
                          }
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Compra', label: Text('Compra')),
                      ButtonSegment(value: 'Venda', label: Text('Venda')),
                    ],
                    selected: {direction},
                    onSelectionChanged: (value) =>
                        setDialogState(() => direction = value.first),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _field(quantity, 'Quantidade')),
                    const SizedBox(width: 8),
                    Expanded(child: _field(entry, 'Entrada')),
                    const SizedBox(width: 8),
                    Expanded(child: _field(stop, 'Stop')),
                    const SizedBox(width: 8),
                    Expanded(child: _field(target, 'Alvo')),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _field(pointValue, 'Valor por ponto')),
                    const SizedBox(width: 10),
                    Expanded(child: _field(costs, 'Custos')),
                  ]),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: result,
                    decoration: const InputDecoration(
                        labelText: 'Resultado', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'Gain', child: Text('Gain')),
                      DropdownMenuItem(
                          value: 'stop loss', child: Text('Stop loss')),
                      DropdownMenuItem(
                          value: 'BREAK_EVEN', child: Text('Break Even')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => result = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  _field(strategy, 'Estratégia'),
                  const SizedBox(height: 10),
                  _field(notes, 'Observações', maxLines: 2),
                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Text(dialogError!,
                        style: const TextStyle(
                            color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar')),
            FilledButton.icon(
              onPressed: () {
                if (_isoDate(date.text) == null ||
                    !RegExp(r'^\d{2}:\d{2}$').hasMatch(time.text.trim()) ||
                    !RegExp(r'^\d{2}:\d{2}$').hasMatch(exitTime.text.trim()) ||
                    asset.text.trim().isEmpty ||
                    strategy.text.trim().isEmpty) {
                  setDialogState(() =>
                      dialogError = 'Revise data, hora e campos obrigatórios.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar alterações'),
            ),
          ],
        ),
      ),
    );

    if (submitted == true && mounted) {
      setState(() => _saving = true);
      try {
        final response = await http.patch(
          widget.apiUriBuilder('/api/day-trade/${operation.id}'),
          headers: _headers,
          body: jsonEncode({
            'trade_date': _isoDate(date.text),
            'entry_time': time.text.trim(),
            'exit_time': exitTime.text.trim(),
            'asset': asset.text.trim().toUpperCase(),
            'market': market,
            'direction': direction,
            'quantity': int.tryParse(quantity.text.trim()) ?? 0,
            'entry_price_text': entry.text.trim(),
            'point_value_text': pointValue.text.trim(),
            'stop_price_text': stop.text.trim(),
            'target_price_text': target.text.trim(),
            'costs_text': costs.text.trim(),
            'strategy': strategy.text.trim(),
            'operation_result': result,
            'notes': notes.text.trim(),
          }),
        );
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (response.statusCode != 200 || body['ok'] != true) {
          throw Exception(body['message'] ?? 'Não foi possível salvar.');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Operação atualizada no banco de dados.')));
        }
        await _load();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: Colors.red,
              content: Text(error.toString().replaceFirst('Exception: ', ''))));
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }

    for (final controller in [
      date,
      time,
      exitTime,
      asset,
      quantity,
      entry,
      stop,
      target,
      pointValue,
      costs,
      strategy,
      notes,
    ]) {
      controller.dispose();
    }
  }

  Widget _field(TextEditingController controller, String label,
          {int maxLines = 1}) =>
      TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _navNavy,
        appBar: AppBar(
          backgroundColor: _navNavy,
          foregroundColor: Colors.white,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NAVEGAÇÃO DE OPERAÇÕES',
                  style: TextStyle(
                      fontFamily: 'monospace', fontWeight: FontWeight.bold)),
              Text('DAY TRADE • EDIÇÃO SEM EXCLUSÃO',
                  style: TextStyle(
                      fontFamily: 'monospace', fontSize: 10, color: _navCyan)),
            ],
          ),
          actions: [
            IconButton(
                tooltip: 'Atualizar listagem',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.sync)),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  color: _navPanel,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${_items.length} REGISTROS • MAIS RECENTE PRIMEIRO',
                          style: const TextStyle(
                              color: _navYellow,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold)),
                      FilledButton.icon(
                        onPressed:
                            _items.isEmpty || _saving ? null : _editSelected,
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(_saving
                            ? 'SALVANDO...'
                            : 'EDITAR REGISTRO SELECIONADO'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: _navCyan))
                      : _error != null
                          ? Center(
                              child: Text(_error!,
                                  style:
                                      const TextStyle(color: Colors.redAccent)))
                          : _items.isEmpty
                              ? const Center(
                                  child: Text('NENHUMA OPERAÇÃO CADASTRADA',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'monospace')))
                              : Focus(
                                  focusNode: _focus,
                                  autofocus: true,
                                  onKeyEvent: _onKey,
                                  child: _table(),
                                ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _table() => Container(
        decoration: BoxDecoration(
            color: _navPanel, border: Border.all(color: _navCyan, width: 2)),
        child: Scrollbar(
          controller: _vertical,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _minimumTableWidth,
                child: Column(
                  children: [
                    _row(-1, const [
                      'DATA',
                      'HORA',
                      'ATIVO',
                      'MERCADO',
                      'TIPO',
                      'QTD',
                      'ENTRADA',
                      'STOP',
                      'ALVO',
                      'SAÍDA',
                      'R\$ LÍQUIDO',
                      'PONTOS',
                      'STATUS',
                      'ESTRATÉGIA',
                    ]),
                    for (var index = 0; index < _items.length; index++)
                      _row(index, _items[index].cells),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _row(int index, List<String> values) {
    final header = index < 0;
    final selected = index == _selected;
    return InkWell(
      onTap: header ? null : () => _select(index),
      onDoubleTap: header
          ? null
          : () {
              _select(index);
              _editSelected();
            },
      child: Container(
        height: 39,
        color: header
            ? _navCyan
            : selected
                ? _navYellow
                : index.isEven
                    ? const Color(0xFF0D3150)
                    : _navPanel,
        child: Row(
          children: [
            for (var column = 0; column < values.length; column++)
              Container(
                width: _columnWidths[column],
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(
                    border: Border(
                        right: BorderSide(color: _navLine),
                        bottom: BorderSide(color: _navLine))),
                child: Text(
                  values[column],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: header
                        ? _navNavy
                        : selected
                            ? _navNavy
                            : const Color(0xFFD7EAF3),
                    fontFamily: 'monospace',
                    fontSize: header ? 11 : 10.5,
                    fontWeight: header || selected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const _columnWidths = <double>[
  84,
  76,
  72,
  96,
  66,
  48,
  86,
  82,
  82,
  82,
  96,
  68,
  88,
  150,
];
const _minimumTableWidth = 1176.0;

class _NavigationOperation {
  const _NavigationOperation({
    required this.id,
    required this.tradeDate,
    required this.entryTime,
    required this.exitTime,
    required this.asset,
    required this.market,
    required this.direction,
    required this.quantity,
    required this.entryPrice,
    required this.exitPrice,
    required this.stopPrice,
    required this.targetPrice,
    required this.pointValue,
    required this.costsText,
    required this.netResult,
    required this.pointsResult,
    required this.strategy,
    required this.notes,
    required this.operationResult,
    required this.resultType,
    required this.status,
  });

  factory _NavigationOperation.fromJson(Map<String, dynamic> json) =>
      _NavigationOperation(
        id: (json['id'] as num).toInt(),
        tradeDate: '${json['trade_date'] ?? ''}',
        entryTime: '${json['entry_time'] ?? ''}',
        exitTime: '${json['exit_time'] ?? json['entry_time'] ?? ''}',
        asset: '${json['asset'] ?? ''}',
        market: '${json['market'] ?? ''}',
        direction: '${json['direction'] ?? ''}',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        entryPrice: '${json['entry_price_text'] ?? ''}',
        exitPrice: '${json['exit_price_text'] ?? ''}',
        stopPrice: '${json['stop_price_text'] ?? ''}',
        targetPrice: '${json['target_price_text'] ?? ''}',
        pointValue: '${json['point_value_text'] ?? ''}',
        costsText: '${json['costs_text'] ?? '0'}',
        netResult: (json['net_result'] as num?)?.toDouble() ?? 0,
        pointsResult: (json['points_result'] as num?)?.toDouble(),
        strategy: '${json['strategy'] ?? ''}',
        notes: '${json['notes'] ?? ''}',
        operationResult: '${json['operation_result'] ?? ''}',
        resultType: '${json['result_type'] ?? ''}',
        status: '${json['status'] ?? ''}',
      );

  static int compareNewestFirst(
      _NavigationOperation a, _NavigationOperation b) {
    final date = b.tradeDate.compareTo(a.tradeDate);
    if (date != 0) return date;
    final time = b.entryTime.compareTo(a.entryTime);
    if (time != 0) return time;
    return b.id.compareTo(a.id);
  }

  bool get isBreakEven => resultType == 'BREAK_EVEN';

  List<String> get cells => [
        _dateBr(tradeDate),
        exitTime == entryTime ? entryTime : '$entryTime→$exitTime',
        asset,
        market,
        direction,
        '$quantity',
        isBreakEven ? 'BREAK EVEN' : entryPrice,
        isBreakEven ? 'BREAK EVEN' : stopPrice,
        isBreakEven ? 'BREAK EVEN' : targetPrice,
        isBreakEven ? 'BREAK EVEN' : exitPrice,
        netResult.toStringAsFixed(2).replaceAll('.', ','),
        pointsResult?.toStringAsFixed(0) ?? '',
        status,
        strategy,
      ];

  final int id;
  final String tradeDate;
  final String entryTime;
  final String exitTime;
  final String asset;
  final String market;
  final String direction;
  final int quantity;
  final String entryPrice;
  final String exitPrice;
  final String stopPrice;
  final String targetPrice;
  final String pointValue;
  final String costsText;
  final double netResult;
  final double? pointsResult;
  final String strategy;
  final String notes;
  final String operationResult;
  final String resultType;
  final String status;
}

String _dateBr(String iso) {
  final parts = iso.split('-');
  return parts.length == 3 ? '${parts[2]}/${parts[1]}/${parts[0]}' : iso;
}

String? _isoDate(String br) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(br.trim());
  if (match == null) return null;
  final parsed = DateTime.tryParse(
      '${match.group(3)}-${match.group(2)}-${match.group(1)}');
  return parsed == null
      ? null
      : '${parsed.year.toString().padLeft(4, '0')}-'
          '${parsed.month.toString().padLeft(2, '0')}-'
          '${parsed.day.toString().padLeft(2, '0')}';
}
