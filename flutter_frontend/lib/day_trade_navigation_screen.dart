import 'vu_meter.dart';
import 'dart:convert';
import 'win_calendar_screen.dart';
import 'b3_calendar.dart';

import 'api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'day_trade_navigation_report.dart';
import 'day_trade_navigation_share_stub.dart'
    if (dart.library.js_interop) 'day_trade_navigation_share_web.dart';

typedef DayTradeNavigationUriBuilder = Uri Function(String path);

const _navNavy = Color(0xFF061A33);
const _navPanel = Color(0xFF092847);
const _navCyan = Color(0xFF39E7E0);
const _navLine = Color(0xFF2E668A);
const _navYellow = Color(0xFFFFE66B);
const _navigationPositiveCell = Color(0xFF168A57);
const _navigationNegativeCell = Color(0xFFD65C62);

Color? navigationNetResultCellColor(double result) {
  if (result > 0) return _navigationPositiveCell;
  if (result < 0) return _navigationNegativeCell;
  return null;
}

class DayTradeDailyEntry {
  const DayTradeDailyEntry({
    required this.date,
    required this.asset,
    required this.netResult,
  });

  final String date;
  final String asset;
  final double netResult;
}

class DayTradeDailyResult {
  const DayTradeDailyResult({
    required this.date,
    required this.entries,
    required this.total,
  });

  final String date;
  final List<DayTradeDailyEntry> entries;
  final double total;
}

List<DayTradeDailyResult> consolidateDayTradeResults(
    Iterable<DayTradeDailyEntry> entries) {
  final grouped = <String, List<DayTradeDailyEntry>>{};
  for (final entry in entries) {
    grouped.putIfAbsent(entry.date, () => []).add(entry);
  }
  final results = grouped.entries
      .map((group) => DayTradeDailyResult(
            date: group.key,
            entries: List.unmodifiable(group.value),
            total: group.value
                .fold<double>(0, (total, entry) => total + entry.netResult),
          ))
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  return results;
}

const _navigationEditTextStyle = TextStyle(
  fontSize: 15.5,
  fontWeight: FontWeight.w600,
  color: Color(0xFF17324D),
);

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
  bool _processingReport = false;
  String? _error;

  _NavigationSummary get _summary => _NavigationSummary.from(_items);

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
    return VuTasks.run(
        owner: this,
        key: '_load',
        message: 'Carregando dados…',
        alive: () => mounted,
        silent: false,
        blocking: false,
        action: () async {
          setState(() {
            _loading = true;
            _error = null;
          });
          try {
            final response = await apiClient.get(
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
              _selected =
                  items.isEmpty ? 0 : _selected.clamp(0, items.length - 1);
            });
          } catch (error) {
            VuTasks.fail(error);
            if (mounted) {
              setState(() =>
                  _error = error.toString().replaceFirst('Exception: ', ''));
            }
          } finally {
            if (mounted) setState(() => _loading = false);
          }
        });
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
    return VuTasks.run(
        owner: this,
        key: '_editSelected',
        message: 'Salvando…',
        alive: () => mounted,
        silent: false,
        blocking: false,
        action: () async {
          if (_items.isEmpty || _saving) return;
          final operation = _items[_selected];
          final date = VuTasks.draftController(
              'day_trade_navigation_screen.dart:date:6159',
              () => TextEditingController(text: _dateBr(operation.tradeDate)));
          final time = VuTasks.draftController(
              'day_trade_navigation_screen.dart:time:6255',
              () => TextEditingController(text: operation.entryTime));
          final exitTime = VuTasks.draftController(
              'day_trade_navigation_screen.dart:exitTime:6328',
              () => TextEditingController(text: operation.exitTime));
          final asset = VuTasks.draftController(
              'day_trade_navigation_screen.dart:asset:6404',
              () => TextEditingController(text: operation.asset));
          final quantity = VuTasks.draftController(
              'day_trade_navigation_screen.dart:quantity:6474',
              () => TextEditingController(text: '${operation.quantity}'));
          final entry = VuTasks.draftController(
              'day_trade_navigation_screen.dart:entry:6555',
              () => TextEditingController(text: operation.entryPrice));
          final stop = VuTasks.draftController(
              'day_trade_navigation_screen.dart:stop:6630',
              () => TextEditingController(text: operation.stopPrice));
          final target = VuTasks.draftController(
              'day_trade_navigation_screen.dart:target:6703',
              () => TextEditingController(text: operation.targetPrice));
          final pointValue = VuTasks.draftController(
              'day_trade_navigation_screen.dart:pointValue:6780',
              () => TextEditingController(text: operation.pointValue));
          final costs = VuTasks.draftController(
              'day_trade_navigation_screen.dart:costs:6860',
              () => TextEditingController(text: operation.costsText));
          final strategy = VuTasks.draftController(
              'day_trade_navigation_screen.dart:strategy:6934',
              () => TextEditingController(text: operation.strategy));
          final notes = VuTasks.draftController(
              'day_trade_navigation_screen.dart:notes:7010',
              () => TextEditingController(text: operation.notes));
          var market = operation.asset.toUpperCase().startsWith('WDO')
              ? 'Mini dólar'
              : operation.asset.toUpperCase().startsWith('WIN')
                  ? 'Mini índice'
                  : operation.market;
          var direction = operation.direction;
          var result = operation.operationResult.isEmpty
              ? operation.resultType == 'WIN'
                  ? 'Gain'
                  : operation.resultType == 'LOSS'
                      ? 'stop loss'
                      : 'BREAK_EVEN'
              : operation.operationResult;
          String? dialogError;

          final submitted = await VuTasks.awaitUser(() => showDialog<bool>(
                context: context,
                builder: (dialogContext) => StatefulBuilder(
                  builder: (context, setDialogState) => AlertDialog(
                    insetPadding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 1180),
                    backgroundColor: const Color(0xFFF7FAFE),
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                    title: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3F2FD),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.edit_note_rounded,
                              color: Color(0xFF1565C0), size: 27),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Editar registro #${operation.id}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 21,
                                  color: Color(0xFF17324D),
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Dados da operação e resultado consolidado em uma única tela',
                                style: TextStyle(
                                    fontSize: 14, color: Color(0xFF607D8B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
                    content: SizedBox(
                      width: 1136,
                      height: ((MediaQuery.sizeOf(context).height - 176)
                              .clamp(520.0, 620.0))
                          .toDouble(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _NavigationReadOnlyFacts(
                            operationId: operation.id,
                            status: operation.status,
                            weekday: operation.tradeWeekday,
                            points:
                                operation.pointsResult?.toStringAsFixed(0) ??
                                    '—',
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            SizedBox(
                                width: 168,
                                child: _field(date, 'Data (dd/mm/aaaa)')),
                            const SizedBox(width: 8),
                            SizedBox(
                                width: 132,
                                child: _field(time, 'Hora entrada')),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: _compactEditWidth(asset.text,
                                  min: 145, max: 170),
                              child: _field(
                                asset,
                                'Ativo',
                                onChanged: (value) => setDialogState(() {
                                  if (value.toUpperCase().startsWith('WDO'))
                                    market = 'Mini dólar';
                                  if (value.toUpperCase().startsWith('WIN'))
                                    market = 'Mini índice';
                                }),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 174,
                              child: DropdownButtonFormField<String>(
                                key: ValueKey('navigation-$market'),
                                initialValue: market,
                                style: _navigationEditTextStyle,
                                decoration:
                                    _navigationEditDecoration('Mercado'),
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
                                    setDialogState(() {
                                      market = value;
                                      if (market == 'Mini índice') {
                                        pointValue.text = '0,20';
                                        asset.text =
                                            currentWinContract(b3Today())
                                                .symbol;
                                      } else if (market == 'Mini dólar') {
                                        pointValue.text = '10,00';
                                        asset.text =
                                            currentWdoContract(b3Today())
                                                .symbol;
                                      } else if (asset.text
                                              .toUpperCase()
                                              .startsWith('WIN') ||
                                          asset.text
                                              .toUpperCase()
                                              .startsWith('WDO')) {
                                        asset.clear();
                                      }
                                      dialogError = null;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 220,
                              child: SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(
                                      value: 'Compra',
                                      label: Text('Compra',
                                          style: _navigationEditTextStyle)),
                                  ButtonSegment(
                                      value: 'Venda',
                                      label: Text('Venda',
                                          style: _navigationEditTextStyle)),
                                ],
                                selected: {direction},
                                selectedIcon: Icon(
                                  direction == 'Compra'
                                      ? Icons.trending_up_rounded
                                      : Icons.trending_down_rounded,
                                  size: 18,
                                  color: direction == 'Compra'
                                      ? const Color(0xFF16825D)
                                      : const Color(0xFFB42332),
                                ),
                                onSelectionChanged: (value) => setDialogState(
                                    () => direction = value.first),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 210,
                              child: DropdownButtonFormField<String>(
                                initialValue: result,
                                style: _navigationEditTextStyle,
                                decoration:
                                    _navigationEditDecoration('Resultado'),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'Gain', child: Text('Gain')),
                                  DropdownMenuItem(
                                      value: 'stop loss',
                                      child: Text('Stop loss')),
                                  DropdownMenuItem(
                                      value: 'BREAK_EVEN',
                                      child: Text('Break Even')),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setDialogState(() {
                                      result = value;
                                      dialogError = null;
                                    });
                                  }
                                },
                              ),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            SizedBox(
                                width: _compactEditWidth(quantity.text,
                                    min: 132, max: 180),
                                child: _field(quantity, 'Quantidade',
                                    onChanged: (_) => setDialogState(() {
                                          dialogError = null;
                                        }))),
                            const SizedBox(width: 8),
                            SizedBox(
                                width: _compactEditWidth(entry.text,
                                    min: 150, max: 170),
                                child: _field(entry, 'Entrada',
                                    onChanged: (_) => setDialogState(() {
                                          dialogError = null;
                                        }))),
                            const SizedBox(width: 8),
                            SizedBox(
                                width: _compactEditWidth(stop.text,
                                    min: 150, max: 170),
                                child: _field(stop, 'Stop',
                                    onChanged: (_) => setDialogState(() {
                                          dialogError = null;
                                        }))),
                            const SizedBox(width: 8),
                            SizedBox(
                                width: _compactEditWidth(target.text,
                                    min: 150, max: 170),
                                child: _field(target, 'Alvo',
                                    onChanged: (_) => setDialogState(() {
                                          dialogError = null;
                                        }))),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: _compactEditWidth(pointValue.text,
                                  min: 160, max: 175),
                              child: market == 'Mini índice' ||
                                      market == 'Mini dólar'
                                  ? _NavigationInfoLabel(
                                      label: 'Valor por ponto',
                                      value: market == 'Mini dólar'
                                          ? 'R\$ 10,00'
                                          : 'R\$ 0,20',
                                      icon: Icons.lock_outline_rounded,
                                      emphasized: true,
                                    )
                                  : _field(pointValue, 'Valor por ponto',
                                      onChanged: (_) => setDialogState(() {
                                            dialogError = null;
                                          })),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                                width: _compactEditWidth(costs.text,
                                    min: 135, max: 150),
                                child: _field(costs, 'Custos',
                                    onChanged: (_) => setDialogState(() {
                                          dialogError = null;
                                        }))),
                          ]),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _NavigationNetResultCard(
                                value: calculateNavigationNetResult(
                                  direction: direction,
                                  market: market,
                                  quantityText: quantity.text,
                                  entryText: entry.text,
                                  stopText: stop.text,
                                  targetText: target.text,
                                  pointValueText: pointValue.text,
                                  costsText: costs.text,
                                  operationResult: result,
                                ),
                                exitPrice: navigationDerivedExitPrice(
                                  entryText: entry.text,
                                  stopText: stop.text,
                                  targetText: target.text,
                                  operationResult: result,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _field(
                                  strategy,
                                  'Estratégia',
                                  minLines: 3,
                                  maxLines: 4,
                                  textAlign: TextAlign.justify,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: _field(
                                  notes,
                                  'Observações',
                                  minLines: 3,
                                  maxLines: 4,
                                  textAlign: TextAlign.justify,
                                ),
                              ),
                            ],
                          ),
                          if (dialogError != null) ...[
                            const SizedBox(height: 8),
                            Text(dialogError!,
                                style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ],
                      ),
                    ),
                    actionsPadding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancelar')),
                      FilledButton.icon(
                        onPressed: () {
                          if (_isoDate(date.text) == null ||
                              !RegExp(r'^\d{2}:\d{2}$')
                                  .hasMatch(time.text.trim()) ||
                              !RegExp(r'^\d{2}:\d{2}$')
                                  .hasMatch(exitTime.text.trim()) ||
                              asset.text.trim().isEmpty ||
                              strategy.text.trim().isEmpty) {
                            setDialogState(() => dialogError =
                                'Revise data, hora e campos obrigatórios.');
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
              ));

          if (submitted == true && mounted) {
            setState(() => _saving = true);
            try {
              final response = await apiClient.patch(
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
                  'point_value_text': market == 'Mini índice'
                      ? '0.20'
                      : market == 'Mini dólar'
                          ? '10'
                          : pointValue.text.trim(),
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
              VuTasks.fail(error);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: Colors.red,
                    content: Text(
                        error.toString().replaceFirst('Exception: ', ''))));
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
        });
  }

  Widget _field(TextEditingController controller, String label,
          {int minLines = 1,
          int maxLines = 1,
          TextAlign textAlign = TextAlign.start,
          ValueChanged<String>? onChanged}) =>
      TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        textAlign: textAlign,
        onChanged: onChanged,
        style: _navigationEditTextStyle,
        decoration: _navigationEditDecoration(label),
      );

  double _compactEditWidth(String text,
      {required double min, required double max}) {
    final extraCharacters = (text.trim().length - 5).clamp(0, 20);
    return (min + extraCharacters * 8).clamp(min, max).toDouble();
  }

  InputDecoration _navigationEditDecoration(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF546E7A),
        ),
        floatingLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1565C0),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCFDCE8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCFDCE8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1E88E5), width: 1.6),
        ),
      );

  Future<Uint8List> _reportBytes({bool printOptimized = false}) =>
      buildDayTradeNavigationReport(
        period: _summary.dayCount == 0
            ? 'Sem registros'
            : '${_summary.firstDate} a ${_summary.lastDate}',
        generatedAt: _dateTimeBr(DateTime.now()),
        metrics: <NavigationReportMetric>[
          NavigationReportMetric('Registros', '${_items.length}'),
          NavigationReportMetric(
              'Resultados positivos', _currencyBr(_summary.positiveTotal)),
          NavigationReportMetric(
              'Resultados negativos', _currencyBr(_summary.negativeTotal)),
          NavigationReportMetric(
              'Saldo líquido', _currencyBr(_summary.balance)),
        ],
        rows: _items.map((item) => item.reportCells).toList(),
        printOptimized: printOptimized,
      );

  Future<void> _printReport() async {
    return VuTasks.run(
        owner: this,
        key: '_printReport',
        message: 'Gerando relatório…',
        alive: () => mounted,
        silent: false,
        blocking: false,
        action: () async {
          if (_items.isEmpty || _processingReport) return;
          setState(() => _processingReport = true);
          try {
            final bytes = await _reportBytes(printOptimized: true);
            await Printing.layoutPdf(
              name: 'Relatorio-Navegacao-Operacoes-EKT.pdf',
              format: PdfPageFormat.a4.landscape,
              onLayout: (_) async => bytes,
            );
          } catch (_) {
            VuTasks.fail('Não foi possível concluir. Tente novamente.');
            if (mounted) {
              _showReportMessage(
                  'Não foi possível gerar o relatório para impressão.',
                  error: true);
            }
          } finally {
            if (mounted) setState(() => _processingReport = false);
          }
        });
  }

  Future<void> _shareReport() async {
    return VuTasks.run(
        owner: this,
        key: '_shareReport',
        message: 'Gerando relatório…',
        alive: () => mounted,
        silent: false,
        blocking: false,
        action: () async {
          if (_items.isEmpty || _processingReport) return;
          setState(() => _processingReport = true);
          try {
            const filename = 'Relatorio-Navegacao-Operacoes-EKT.pdf';
            final bytes = await _reportBytes();
            final shared = await shareNavigationReportPdf(bytes, filename);
            if (!shared) {
              await Printing.sharePdf(bytes: bytes, filename: filename);
            }
            if (mounted) {
              _showReportMessage(shared
                  ? 'PDF preparado. Selecione o WhatsApp para compartilhar.'
                  : 'PDF baixado. Anexe o arquivo em uma conversa do WhatsApp.');
            }
          } catch (_) {
            VuTasks.fail('Não foi possível concluir. Tente novamente.');
            if (mounted) {
              _showReportMessage('Não foi possível compartilhar o relatório.',
                  error: true);
            }
          } finally {
            if (mounted) setState(() => _processingReport = false);
          }
        });
  }

  void _showReportMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : const Color(0xFF167A4B),
      ));
  }

  void _openDailyConsolidated() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DayTradeDailyConsolidatedScreen(
          entries: _items
              .map((item) => DayTradeDailyEntry(
                  date: item.tradeDate,
                  asset: item.asset,
                  netResult: item.netResult))
              .toList()),
    ));
  }

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
                _NavigationSummaryCard(summary: _summary),
                const SizedBox(height: 8),
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
                      OutlinedButton.icon(
                        key: const Key('navigation-daily-consolidated'),
                        onPressed:
                            _items.isEmpty ? null : _openDailyConsolidated,
                        icon: const Icon(Icons.calendar_view_day_outlined),
                        label: const Text('CONSOLIDADO POR DIA'),
                        style: _reportActionStyle(),
                      ),
                      OutlinedButton.icon(
                        key: const Key('navigation-share-whatsapp-pdf'),
                        onPressed: _items.isEmpty || _processingReport
                            ? null
                            : _shareReport,
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('COMPARTILHAR VIA WHATSAPP'),
                        style: _reportActionStyle(),
                      ),
                      OutlinedButton.icon(
                        key: const Key('navigation-print-report'),
                        onPressed: _items.isEmpty || _processingReport
                            ? null
                            : _printReport,
                        icon: const Icon(Icons.print_outlined),
                        label: Text(_processingReport
                            ? 'GERANDO RELATÓRIO...'
                            : 'IMPRIMIR RELATÓRIO'),
                        style: _reportActionStyle(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: VuLoading(
                              message: 'Carregando dados…', compact: false))
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

  ButtonStyle _reportActionStyle() => OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: const Color(0xFF7890A2),
        side: const BorderSide(color: _navCyan, width: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .2,
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
                decoration: BoxDecoration(
                    color: !header && column == 10
                        ? navigationNetResultCellColor(_items[index].netResult)
                        : null,
                    border: const Border(
                        right: BorderSide(color: _navLine),
                        bottom: BorderSide(color: _navLine))),
                child: Text(
                  values[column],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: !header &&
                            column == 10 &&
                            navigationNetResultCellColor(
                                    _items[index].netResult) !=
                                null
                        ? Colors.white
                        : header
                            ? _navNavy
                            : selected
                                ? _navNavy
                                : const Color(0xFFD7EAF3),
                    fontFamily: 'monospace',
                    fontSize: header ? 11 : 10.5,
                    fontWeight: header ||
                            selected ||
                            (!header &&
                                column == 10 &&
                                navigationNetResultCellColor(
                                        _items[index].netResult) !=
                                    null)
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

class _NavigationReadOnlyFacts extends StatelessWidget {
  const _NavigationReadOnlyFacts({
    required this.operationId,
    required this.status,
    required this.weekday,
    required this.points,
  });

  final int operationId;
  final String status;
  final String weekday;
  final String points;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F6FA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFBCD1DF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.info_outline_rounded,
                    color: Color(0xFF28658A), size: 18),
                SizedBox(width: 7),
                Text(
                  'DADOS INFORMATIVOS • SOMENTE LEITURA',
                  style: TextStyle(
                    color: Color(0xFF28658A),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .35,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: <Widget>[
                Expanded(
                  child: _NavigationInfoLabel(
                    label: 'Registro',
                    value: '#$operationId',
                    icon: Icons.tag_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NavigationInfoLabel(
                    label: 'Status',
                    value: status.isEmpty ? 'Não informado' : status,
                    icon: Icons.verified_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NavigationInfoLabel(
                    label: 'Dia da semana',
                    value: weekday.isEmpty ? 'Não informado' : weekday,
                    icon: Icons.event_available_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NavigationInfoLabel(
                    label: 'Pontos',
                    value: points,
                    icon: Icons.straighten_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _NavigationInfoLabel extends StatelessWidget {
  const _NavigationInfoLabel({
    required this.label,
    required this.value,
    required this.icon,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 132, minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: emphasized ? const Color(0xFFE7F3FC) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                emphasized ? const Color(0xFF80B7DA) : const Color(0xFFD0DEE7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: const Color(0xFF28658A), size: 18),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF6A7F8D),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF17384D),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _NavigationNetResultCard extends StatelessWidget {
  const _NavigationNetResultCard({
    required this.value,
    required this.exitPrice,
  });

  final double value;
  final String exitPrice;

  @override
  Widget build(BuildContext context) {
    final color = value > 0
        ? const Color(0xFF16825D)
        : value < 0
            ? const Color(0xFFB42332)
            : const Color(0xFF526878);
    final background = value > 0
        ? const Color(0xFFE8F5EE)
        : value < 0
            ? const Color(0xFFFDECEE)
            : const Color(0xFFF1F5F7);
    return Container(
      key: const Key('navigation-edit-net-result'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .55), width: 1.4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            value >= 0
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'RESULTADO LÍQUIDO',
                style: TextStyle(
                  color: Color(0xFF526878),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .45,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _currencyBr(value),
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Saída considerada: ${exitPrice.isEmpty ? '—' : exitPrice}',
                style: const TextStyle(
                  color: Color(0xFF526878),
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ],
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

class DayTradeDailyConsolidatedScreen extends StatefulWidget {
  const DayTradeDailyConsolidatedScreen({super.key, required this.entries});
  final List<DayTradeDailyEntry> entries;

  @override
  State<DayTradeDailyConsolidatedScreen> createState() =>
      _DailyConsolidatedState();
}

class _DailyConsolidatedState extends State<DayTradeDailyConsolidatedScreen> {
  final _startText = TextEditingController();
  final _endText = TextEditingController();
  DateTime? _start, _end;
  String? _filterError;

  @override
  void dispose() {
    _startText.dispose();
    _endText.dispose();
    super.dispose();
  }

  DateTime? _parseDate(String text) {
    final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(text.trim());
    if (match == null) return null;
    final day = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final year = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    return year >= 1900 &&
            year <= 2100 &&
            date.year == year &&
            date.month == month &&
            date.day == day
        ? date
        : null;
  }

  void _apply() {
    final start = _parseDate(_startText.text);
    final end = _parseDate(_endText.text);
    setState(() {
      if (start == null || end == null) {
        _filterError = 'Informe as duas datas válidas no formato dd/mm/aaaa.';
      } else if (start.isAfter(end)) {
        _filterError =
            'A data final deve ser igual ou posterior à data inicial.';
      } else {
        _start = start;
        _end = end;
        _filterError = null;
      }
    });
  }

  void _clear() => setState(() {
        _start = _end = null;
        _startText.clear();
        _endText.clear();
        _filterError = null;
      });

  Future<void> _pickDate(TextEditingController controller) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _parseDate(controller.text) ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      helpText: controller == _startText ? 'DATA INICIAL' : 'DATA FINAL',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
    );
    if (selected != null && mounted) {
      controller.text =
          '${selected.day.toString().padLeft(2, '0')}/${selected.month.toString().padLeft(2, '0')}/${selected.year}';
    }
  }

  Widget _dateField(
          String label, TextEditingController controller, String key) =>
      SizedBox(
        width: MediaQuery.sizeOf(context).width < 600
            ? (MediaQuery.sizeOf(context).width - 44) / 2
            : 190,
        child: TextField(
          key: Key(key),
          controller: controller,
          keyboardType: TextInputType.datetime,
          style: const TextStyle(color: Color(0xFF27313D)),
          onSubmitted: (_) => _apply(),
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            hintText: 'dd/mm/aaaa',
            labelStyle: const TextStyle(color: Color(0xFF596673)),
            hintStyle: const TextStyle(color: Color(0xFF7B8792)),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            suffixIcon: IconButton(
                tooltip: 'Escolher $label',
                onPressed: () => _pickDate(controller),
                icon: const Icon(Icons.calendar_month_rounded,
                    color: Color(0xFF476578))),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final allDays = consolidateDayTradeResults(widget.entries);
    final days = allDays.where((day) {
      if (_start == null) return true;
      final date = DateTime.tryParse(day.date);
      return date != null && !date.isBefore(_start!) && !date.isAfter(_end!);
    }).toList();
    final gainDays = days.where((day) => day.total > 0).toList();
    final lossDays = days.where((day) => day.total < 0).toList();
    final gains = gainDays.fold<double>(0, (sum, day) => sum + day.total);
    final losses = lossDays.fold<double>(0, (sum, day) => sum + day.total);
    final period = _start == null
        ? 'Todos os dias'
        : '${_dateBr(_start!.toIso8601String().substring(0, 10))} a ${_dateBr(_end!.toIso8601String().substring(0, 10))}';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F4F6),
        foregroundColor: const Color(0xFF27313D),
        title: const Text('CONSOLIDADO POR DIA',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
          child: LayoutBuilder(
              builder: (context, constraints) => ListView(
                    padding: EdgeInsets.symmetric(
                        horizontal: constraints.maxWidth > 1152
                            ? (constraints.maxWidth - 1120) / 2
                            : 16,
                        vertical: 12),
                    children: [
                      _DailyFinancialSummary(
                          gains: gains,
                          losses: losses,
                          gainDays: gainDays.length,
                          lossDays: lossDays.length,
                          totalDays: days.length,
                          period: period),
                      const SizedBox(height: 16),
                      const Text('Filtrar por intervalo de dias',
                          style: TextStyle(
                              color: Color(0xFF27313D),
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _dateField(
                                'Data inicial', _startText, 'daily-start-date'),
                            _dateField(
                                'Data final', _endText, 'daily-end-date'),
                            FilledButton.icon(
                                key: const Key('daily-apply-filter'),
                                onPressed: _apply,
                                style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF476578),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 14)),
                                icon: const Icon(Icons.filter_alt_outlined),
                                label: const Text('Aplicar filtro')),
                            TextButton.icon(
                                onPressed: _clear,
                                icon: const Icon(Icons.filter_alt_off_outlined),
                                label: const Text('Mostrar todos os dias'),
                                style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF476578))),
                          ]),
                      if (_filterError != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(_filterError!,
                                style:
                                    const TextStyle(color: Color(0xFFB43F4B)))),
                      const SizedBox(height: 20),
                      if (days.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18)),
                          child: const Column(children: [
                            Icon(Icons.event_busy_rounded,
                                color: Color(0xFF476578), size: 32),
                            SizedBox(height: 12),
                            Text('Nenhum lançamento no período selecionado.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF27313D)))
                          ]),
                        ),
                      ...days.map(_DailyResultCard.new),
                    ],
                  ))),
    );
  }
}

class _DailyFinancialSummary extends StatelessWidget {
  const _DailyFinancialSummary(
      {required this.gains,
      required this.losses,
      required this.gainDays,
      required this.lossDays,
      required this.totalDays,
      required this.period});
  final double gains, losses;
  final int gainDays, lossDays, totalDays;
  final String period;

  @override
  Widget build(BuildContext context) {
    final net = gains + losses;
    final color = net < 0 ? const Color(0xFFAC3E4A) : const Color(0xFF24775D);
    Widget metric(String label, double value, Color tint, String key,
            {bool primary = false}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF66717D),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(_currencyBr(value),
                  key: Key(key),
                  style: TextStyle(
                      color: tint,
                      fontSize: primary ? 30 : 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5))),
        ]);
    return Container(
      key: const Key('daily-summary'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          gradient:
              const LinearGradient(colors: [Colors.white, Color(0xFFF0F2F4)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFDCE1E6)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x08000000), blurRadius: 14, offset: Offset(0, 4))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 4, children: [
          const Text('RESUMO FINANCEIRO',
              style: TextStyle(
                  color: Color(0xFF354452),
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800)),
          Text(period,
              key: const Key('daily-active-period'),
              style: const TextStyle(color: Color(0xFF66717D), fontSize: 11)),
        ]),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, constraints) {
          final balance = Row(children: [
            Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(
                    net < 0
                        ? Icons.trending_down_rounded
                        : Icons.trending_up_rounded,
                    color: color,
                    size: 24)),
            const SizedBox(width: 12),
            Expanded(
                child: metric('Saldo líquido', net, color, 'daily-net-total',
                    primary: true)),
          ]);
          final totals = Row(children: [
            Expanded(
                child: metric('$gainDays dias de Gain', gains,
                    const Color(0xFF24775D), 'daily-gain-total')),
            const SizedBox(width: 16),
            Expanded(
                child: metric('$lossDays dias de Loss', losses,
                    const Color(0xFFAC3E4A), 'daily-loss-total')),
          ]);
          return constraints.maxWidth >= 650
              ? Row(children: [
                  Expanded(child: balance),
                  const SizedBox(width: 32),
                  Expanded(child: totals)
                ])
              : Column(children: [balance, const SizedBox(height: 14), totals]);
        }),
        const SizedBox(height: 12),
        const Divider(height: 1, color: Color(0xFFDCE1E6)),
        const SizedBox(height: 10),
        Text(
            '$totalDays dias analisados • ${totalDays - gainDays - lossDays} dias zerados',
            style: const TextStyle(color: Color(0xFF66717D), fontSize: 11)),
      ]),
    );
  }
}

class _DailyResultCard extends StatelessWidget {
  const _DailyResultCard(this.day);
  final DayTradeDailyResult day;

  @override
  Widget build(BuildContext context) {
    final color = day.total > 0
        ? const Color(0xFF24775D)
        : day.total < 0
            ? const Color(0xFFAC3E4A)
            : const Color(0xFF66717D);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDCE1E6))),
      child: Column(children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            color: const Color(0xFFEAEDF0),
            child: Row(children: [
              const Icon(Icons.event_outlined,
                  size: 18, color: Color(0xFF66717D)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_dateBr(day.date),
                      style: const TextStyle(
                          color: Color(0xFF354452),
                          fontWeight: FontWeight.w700))),
              Text(
                  day.total > 0
                      ? 'GAIN'
                      : day.total < 0
                          ? 'LOSS'
                          : 'ZERO',
                  style: TextStyle(
                      color: color, fontSize: 10, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Flexible(
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_currencyBr(day.total),
                          style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                              fontSize: 16)))),
            ])),
        for (final entry in day.entries)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Expanded(
                    child: Text(entry.asset,
                        style: const TextStyle(
                            color: Color(0xFF53616E), fontSize: 13))),
                const SizedBox(width: 12),
                Flexible(
                    child: Text(_currencyBr(entry.netResult),
                        style: const TextStyle(
                            color: Color(0xFF354452),
                            fontSize: 13,
                            fontWeight: FontWeight.w600))),
              ])),
      ]),
    );
  }
}

class _NavigationOperation {
  const _NavigationOperation({
    required this.id,
    required this.tradeDate,
    required this.tradeWeekday,
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
        tradeWeekday: '${json['trade_weekday'] ?? ''}',
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

  List<String> get reportCells => <String>[
        _dateBr(tradeDate),
        exitTime == entryTime ? entryTime : '$entryTime - $exitTime',
        asset,
        market,
        direction,
        '$quantity',
        isBreakEven ? 'Break even' : entryPrice,
        isBreakEven ? 'Break even' : stopPrice,
        isBreakEven ? 'Break even' : targetPrice,
        isBreakEven ? 'Break even' : exitPrice,
        _currencyBr(netResult),
        pointsResult?.toStringAsFixed(0) ?? '',
        status,
        strategy,
      ];

  final int id;
  final String tradeDate;
  final String tradeWeekday;
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

class _NavigationSummary {
  const _NavigationSummary({
    required this.firstDate,
    required this.lastDate,
    required this.dayCount,
    required this.positiveTotal,
    required this.negativeTotal,
    required this.balance,
  });

  factory _NavigationSummary.from(List<_NavigationOperation> items) {
    if (items.isEmpty) {
      return const _NavigationSummary(
        firstDate: '',
        lastDate: '',
        dayCount: 0,
        positiveTotal: 0,
        negativeTotal: 0,
        balance: 0,
      );
    }
    final dates = items
        .map((item) => DateTime.tryParse(item.tradeDate))
        .whereType<DateTime>()
        .toList()
      ..sort();
    final positive = items
        .where((item) => item.netResult > 0)
        .fold<double>(0, (total, item) => total + item.netResult);
    final negative = items
        .where((item) => item.netResult < 0)
        .fold<double>(0, (total, item) => total + item.netResult);
    return _NavigationSummary(
      firstDate: dates.isEmpty ? '' : _dateBr(_isoDateValue(dates.first)),
      lastDate: dates.isEmpty ? '' : _dateBr(_isoDateValue(dates.last)),
      dayCount:
          dates.isEmpty ? 0 : dates.last.difference(dates.first).inDays + 1,
      positiveTotal: positive,
      negativeTotal: negative,
      balance: positive + negative,
    );
  }

  final String firstDate;
  final String lastDate;
  final int dayCount;
  final double positiveTotal;
  final double negativeTotal;
  final double balance;
}

class _NavigationSummaryCard extends StatelessWidget {
  const _NavigationSummaryCard({required this.summary});

  final _NavigationSummary summary;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        elevation: 5,
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF3589C9)),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF123E64), Color(0xFF082743)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.analytics_outlined, color: _navCyan, size: 19),
                  SizedBox(width: 7),
                  Text(
                    'RESUMO DO PERÍODO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .7,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SummaryMetric(
                    label: 'PERÍODO DOS REGISTROS',
                    value: summary.dayCount == 0
                        ? 'Sem registros'
                        : '${summary.firstDate} até ${summary.lastDate}',
                    detail: '${summary.dayCount} dias corridos',
                    icon: Icons.date_range_outlined,
                    color: const Color(0xFF7DD3FC),
                    wide: true,
                  ),
                  _SummaryMetric(
                    label: 'RESULTADOS POSITIVOS',
                    value: _currencyBr(summary.positiveTotal),
                    icon: Icons.trending_up_rounded,
                    color: const Color(0xFF4ADE80),
                  ),
                  _SummaryMetric(
                    label: 'RESULTADOS NEGATIVOS',
                    value: _currencyBr(summary.negativeTotal),
                    icon: Icons.trending_down_rounded,
                    color: const Color(0xFFFF6B6B),
                  ),
                  _SummaryMetric(
                    label: 'SALDO LÍQUIDO',
                    value: _currencyBr(summary.balance),
                    icon: Icons.account_balance_wallet_outlined,
                    color: summary.balance < 0
                        ? const Color(0xFFFF6B6B)
                        : const Color(0xFF4ADE80),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.detail,
    this.wide = false,
  });

  final String label;
  final String value;
  final String? detail;
  final IconData icon;
  final Color color;
  final bool wide;

  @override
  Widget build(BuildContext context) => Container(
        width: wide ? 260 : 205,
        constraints: const BoxConstraints(minHeight: 67),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF061D33).withValues(alpha: .72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .55)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFFAFC8DA),
                          fontSize: 9,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                  if (detail != null)
                    Text(detail!,
                        style: const TextStyle(
                            color: Color(0xFFC9D9E4), fontSize: 9.5)),
                ],
              ),
            ),
          ],
        ),
      );
}

String _isoDateValue(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _dateTimeBr(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/'
    '${date.year.toString().padLeft(4, '0')} '
    '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';

String _currencyBr(double value) {
  final negative = value < 0;
  final parts = value.abs().toStringAsFixed(2).split('.');
  final digits = parts.first;
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write('.');
    grouped.write(digits[index]);
  }
  return '${negative ? '-' : ''}R\$ ${grouped.toString()},${parts.last}';
}

double calculateNavigationNetResult({
  required String direction,
  required String market,
  required String quantityText,
  required String entryText,
  required String stopText,
  required String targetText,
  required String pointValueText,
  required String costsText,
  required String? operationResult,
}) {
  final quantity = int.tryParse(quantityText.trim()) ?? 0;
  final entry = _navigationNumber(entryText);
  final costs = _navigationNumber(costsText);
  if (operationResult == 'BREAK_EVEN') return -costs;
  final exit =
      _navigationNumber(operationResult == 'Gain' ? targetText : stopText);
  final pointValue = market == 'Mini índice'
      ? .20
      : market == 'Mini dólar'
          ? 10.0
          : _navigationNumber(pointValueText);
  final difference = direction == 'Compra' ? exit - entry : entry - exit;
  return difference * quantity * pointValue - costs;
}

String navigationDerivedExitPrice({
  required String entryText,
  required String stopText,
  required String targetText,
  required String? operationResult,
}) =>
    operationResult == 'BREAK_EVEN'
        ? entryText
        : operationResult == 'Gain'
            ? targetText
            : stopText;

double _navigationNumber(String value) {
  var cleaned = value.replaceAll('R\$', '').replaceAll(' ', '');
  if (cleaned.contains(',')) {
    cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^[+-]?\d{1,3}(\.\d{3})+$').hasMatch(cleaned)) {
    cleaned = cleaned.replaceAll('.', '');
  }
  return double.tryParse(cleaned) ?? 0;
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
