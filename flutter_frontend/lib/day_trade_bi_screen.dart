import 'dart:convert';
import 'dart:math' as math;

import 'api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';

import 'day_trade_bi_report.dart';

typedef DayTradeBiApiUriBuilder = Uri Function(String path);

const _navy = Color(0xFF102A3A);
const _teal = Color(0xFF0F766E);
const _green = Color(0xFF16825D);
const _red = Color(0xFFB94747);
const _amber = Color(0xFFD18A25);
const _breakEven = Color(0xFF64748B);
const _muted = Color(0xFF65727C);
const _canvas = Color(0xFFF4F1EA);
const _line = Color(0xFFE1DED6);

enum BiPeriod { day, week, month, year }

class DayTradeBiScreen extends StatefulWidget {
  const DayTradeBiScreen({
    required this.apiUriBuilder,
    required this.sessionToken,
    super.key,
  });

  final DayTradeBiApiUriBuilder apiUriBuilder;
  final String sessionToken;

  @override
  State<DayTradeBiScreen> createState() => _DayTradeBiScreenState();
}

class _DayTradeBiScreenState extends State<DayTradeBiScreen> {
  BiPeriod _period = BiPeriod.month;
  DateTime _reference = DateTime.now();
  DateTimeRange? _freeRange;
  late final TextEditingController _freeStartController;
  late final TextEditingController _freeEndController;
  String? _freeRangeError;
  bool _loading = true;
  String? _error;
  List<BiTrade> _trades = <BiTrade>[];

  Map<String, String> get _headers => <String, String>{
        'authorization': 'Bearer ${widget.sessionToken}',
        'content-type': 'application/json; charset=utf-8',
      };

  DateTimeRange get _range {
    if (_freeRange case final DateTimeRange range) return range;
    final day = DateTime(_reference.year, _reference.month, _reference.day);
    return switch (_period) {
      BiPeriod.day => DateTimeRange(start: day, end: day),
      BiPeriod.week => DateTimeRange(
          start: day.subtract(Duration(days: day.weekday - 1)),
          end: day.add(Duration(days: 7 - day.weekday)),
        ),
      BiPeriod.month => DateTimeRange(
          start: DateTime(day.year, day.month),
          end: DateTime(day.year, day.month + 1, 0),
        ),
      BiPeriod.year => DateTimeRange(
          start: DateTime(day.year),
          end: DateTime(day.year, 12, 31),
        ),
    };
  }

  @override
  void initState() {
    super.initState();
    final initialRange = _range;
    _freeStartController =
        TextEditingController(text: formatBiDateInput(initialRange.start));
    _freeEndController =
        TextEditingController(text: formatBiDateInput(initialRange.end));
    _load();
  }

  @override
  void dispose() {
    _freeStartController.dispose();
    _freeEndController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final range = _range;
      final uri = widget.apiUriBuilder('/api/day-trade/bi').replace(
        queryParameters: <String, String>{
          'from': _iso(range.start),
          'to': _iso(range.end),
        },
      );
      final response = await apiClient.get(uri, headers: _headers);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw Exception(body['message'] ?? 'Não foi possível carregar o BI.');
      }
      if (!mounted) return;
      setState(() {
        _trades = ((body['items'] as List<dynamic>?) ?? <dynamic>[])
            .map((item) => BiTrade.fromJson(item as Map<String, dynamic>))
            .toList();
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

  Future<void> _selectReference() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _reference,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) {
      setState(() {
        _reference = picked;
        _freeRange = null;
        _freeRangeError = null;
        _syncFreeRangeInputs(_range);
      });
      await _load();
    }
  }

  Future<void> _move(int direction) async {
    setState(() {
      _freeRange = null;
      _freeRangeError = null;
      _reference = switch (_period) {
        BiPeriod.day => _reference.add(Duration(days: direction)),
        BiPeriod.week => _reference.add(Duration(days: 7 * direction)),
        BiPeriod.month =>
          DateTime(_reference.year, _reference.month + direction, 1),
        BiPeriod.year => DateTime(_reference.year + direction, 1, 1),
      };
      if (_reference.isAfter(DateTime.now())) _reference = DateTime.now();
      _syncFreeRangeInputs(_range);
    });
    await _load();
  }

  void _syncFreeRangeInputs(DateTimeRange range) {
    _freeStartController.text = formatBiDateInput(range.start);
    _freeEndController.text = formatBiDateInput(range.end);
  }

  Future<void> _pickFreeDate({required bool start}) async {
    final controller = start ? _freeStartController : _freeEndController;
    final typedDate = parseBiDateInput(controller.text);
    final currentRange = _freeRange ?? _range;
    final picked = await showDatePicker(
      context: context,
      initialDate: typedDate ?? (start ? currentRange.start : currentRange.end),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('pt', 'BR'),
      helpText: start ? 'Selecione a data inicial' : 'Selecione a data final',
      cancelText: 'CANCELAR',
      confirmText: 'SELECIONAR',
      initialEntryMode: DatePickerEntryMode.calendar,
      builder: (BuildContext context, Widget? child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1976D2),
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: _navy,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      controller.text = formatBiDateInput(picked);
      _freeRangeError = null;
    });
  }

  Future<void> _applyFreeRange() async {
    FocusScope.of(context).unfocus();
    final start = parseBiDateInput(_freeStartController.text);
    final end = parseBiDateInput(_freeEndController.text);
    String? error;
    if (start == null || end == null) {
      error = 'Informe as duas datas no formato DD/MM/AAAA.';
    } else if (start.isAfter(end)) {
      error = 'A data inicial deve ser anterior ou igual à data final.';
    } else if (start.isBefore(DateTime(2020)) || end.isAfter(DateTime.now())) {
      error = 'Escolha datas entre 01/01/2020 e hoje.';
    }
    if (error != null) {
      setState(() => _freeRangeError = error);
      return;
    }
    setState(() {
      _freeRange = DateTimeRange(start: start!, end: end!);
      _freeRangeError = null;
    });
    await _load();
  }

  Future<void> _print(BiAnalytics analytics) => printDayTradeBiReport(
        period: _rangeLabel(_range),
        indicators: <String, String>{
          'Resultado líquido': _currency(analytics.net),
          'Taxa de acerto': '${analytics.winRate.toStringAsFixed(1)}%',
          'Profit factor': analytics.profitFactorText,
          'Operações': '${analytics.closed.length}',
          'Média por operação': _currency(analytics.average),
          'Drawdown máximo': _currency(analytics.maxDrawdown),
        },
        dailyRows: analytics.daily.reversed
            .map((day) => <String>[
                  _displayDate(day.date),
                  '${day.count}',
                  '${day.gains}',
                  '${day.losses}',
                  '${day.breakEvens}',
                  day.applicableWinRate == null
                      ? 'Não aplicável'
                      : '${_percent(day.applicableWinRate!)}%',
                  _currency(day.result),
                ])
            .toList(),
      );

  @override
  Widget build(BuildContext context) {
    final analytics = BiAnalytics(_trades);
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('BI - INTRADAY',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
            Text('Análise histórica • somente leitura',
                style: TextStyle(fontSize: 11, color: Color(0xFFB9CDD8))),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Imprimir relatório',
            onPressed: _loading ? null : () => _print(analytics),
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.sync_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final padding = constraints.maxWidth < 650 ? 12.0 : 22.0;
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: EdgeInsets.fromLTRB(padding, 16, padding, 32),
              children: <Widget>[
                _header(),
                if (_loading) ...<Widget>[
                  const SizedBox(height: 20),
                  const LinearProgressIndicator(color: _teal),
                ] else if (_error != null) ...<Widget>[
                  const SizedBox(height: 16),
                  _ErrorPanel(message: _error!, onRetry: _load),
                ] else ...<Widget>[
                  const SizedBox(height: 16),
                  _kpis(analytics, constraints.maxWidth),
                  const SizedBox(height: 16),
                  _accuracySection(analytics, constraints.maxWidth),
                  const SizedBox(height: 16),
                  if (_trades.isEmpty)
                    const _EmptyPanel()
                  else ...<Widget>[
                    _charts(analytics, constraints.maxWidth),
                    const SizedBox(height: 16),
                    _breakdowns(analytics, constraints.maxWidth),
                    const SizedBox(height: 16),
                    _dailyTable(analytics),
                  ],
                ],
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _accuracySection(BiAnalytics analytics, double width) => _Panel(
        title: 'Taxa de Acerto das Operações',
        subtitle:
            'Taxa de acerto = vencedoras ÷ (vencedoras + perdedoras) × 100. Break-even não altera a taxa principal.',
        child: Column(
          children: <Widget>[
            _AccuracyCards(analytics: analytics, range: _range),
            const SizedBox(height: 20),
            if (analytics.total == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text('Sem operações no período',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted)),
              )
            else
              _AccuracyDonut(analytics: analytics, compact: width < 700),
          ],
        ),
      );

  Widget _header() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[_navy, Color(0xFF174A50)],
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('Visão executiva das operações',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              const Text(
                  'Resultados, consistência, risco e padrões do seu operacional real.',
                  style: TextStyle(color: Color(0xFFC6D7DE), fontSize: 12)),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                SegmentedButton<BiPeriod>(
                  segments: const <ButtonSegment<BiPeriod>>[
                    ButtonSegment(value: BiPeriod.day, label: Text('Dia')),
                    ButtonSegment(value: BiPeriod.week, label: Text('Semana')),
                    ButtonSegment(value: BiPeriod.month, label: Text('Mês')),
                    ButtonSegment(value: BiPeriod.year, label: Text('Ano')),
                  ],
                  selected: <BiPeriod>{_period},
                  onSelectionChanged: (value) {
                    setState(() {
                      _period = value.first;
                      _freeRange = null;
                      _freeRangeError = null;
                      _syncFreeRangeInputs(_range);
                    });
                    _load();
                  },
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected)
                            ? _navy
                            : Colors.white),
                    backgroundColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected)
                            ? Colors.white
                            : const Color(0x20FFFFFF)),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Período anterior',
                  onPressed: () => _move(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                OutlinedButton.icon(
                  onPressed: _selectReference,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(
                    _period == BiPeriod.day
                        ? formatBiDayLabel(_reference)
                        : _rangeLabel(_range),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF77969C)),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Próximo período',
                  onPressed: () => _move(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ]),
              const SizedBox(height: 16),
              _freeRangeFilter(),
            ]),
      );

  Widget _freeRangeFilter() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF5FF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF8CC4F4)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x260A67A3),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Row(
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFD4EBFF),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.date_range_rounded,
                        color: Color(0xFF145DA0), size: 20),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'POR INTERVALO LIVRE',
                        style: TextStyle(
                          color: _navy,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .35,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Escolha no calendário ou digite em DD/MM/AAAA',
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final compact = constraints.maxWidth < 620;
                final startField = _freeDateField(
                  controller: _freeStartController,
                  label: 'Data inicial',
                  onCalendarTap: () => _pickFreeDate(start: true),
                );
                final endField = _freeDateField(
                  controller: _freeEndController,
                  label: 'Data final',
                  onCalendarTap: () => _pickFreeDate(start: false),
                );
                final applyButton = FilledButton.icon(
                  key: const Key('day-trade-bi-apply-free-range'),
                  onPressed: _loading ? null : _applyFreeRange,
                  icon: const Icon(Icons.filter_alt_rounded, size: 19),
                  label: const Text('Aplicar intervalo'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(170, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      startField,
                      const SizedBox(height: 10),
                      endField,
                      const SizedBox(height: 10),
                      applyButton,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: startField),
                    const SizedBox(width: 10),
                    Expanded(child: endField),
                    const SizedBox(width: 10),
                    applyButton,
                  ],
                );
              },
            ),
            if (_freeRangeError != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _freeRangeError!,
                key: const Key('day-trade-bi-free-range-error'),
                style: const TextStyle(
                  color: _red,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      );

  Widget _freeDateField({
    required TextEditingController controller,
    required String label,
    required VoidCallback onCalendarTap,
  }) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.datetime,
        inputFormatters: <TextInputFormatter>[BiDateInputFormatter()],
        maxLength: 10,
        onSubmitted: (_) => _applyFreeRange(),
        decoration: InputDecoration(
          labelText: label,
          hintText: 'DD/MM/AAAA',
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          prefixIcon: const Icon(Icons.today_rounded, color: Color(0xFF1976D2)),
          suffixIcon: IconButton(
            tooltip: 'Abrir calendário de $label',
            onPressed: onCalendarTap,
            icon: const Icon(Icons.calendar_month_rounded,
                color: Color(0xFF1976D2)),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF8CC4F4)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF8CC4F4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF1976D2), width: 1.8),
          ),
        ),
      );

  Widget _kpis(BiAnalytics a, double width) {
    final columns = width >= 1180
        ? 6
        : width >= 720
            ? 3
            : width >= 340
                ? 2
                : 1;
    final cards = <_KpiData>[
      _KpiData('Resultado líquido', _currency(a.net),
          Icons.account_balance_wallet_outlined, a.net >= 0 ? _green : _red),
      _KpiData('Taxa de acerto', '${a.winRate.toStringAsFixed(1)}%',
          Icons.track_changes_rounded, _teal),
      _KpiData(
          'Profit factor', a.profitFactorText, Icons.balance_rounded, _amber),
      _KpiData('Operações', '${a.closed.length}', Icons.receipt_long_outlined,
          _navy),
      _KpiData('Média/operação', _currency(a.average), Icons.calculate_outlined,
          a.average >= 0 ? _green : _red),
      _KpiData('Drawdown máximo', _currency(a.maxDrawdown),
          Icons.south_east_rounded, _red),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        mainAxisExtent: width >= 720 ? 92 : 98,
      ),
      itemBuilder: (_, index) => _KpiCard(data: cards[index]),
    );
  }

  Widget _charts(BiAnalytics a, double width) {
    final children = <Widget>[
      _Panel(
        title: 'Evolução do resultado acumulado',
        subtitle: 'Curva de capital operacional no período',
        child:
            SizedBox(height: 220, child: _EquityChart(points: a.equityCurve)),
      ),
      _Panel(
        title: 'Resultado por período',
        subtitle: 'Ganhos e perdas consolidados cronologicamente',
        child: SizedBox(height: 220, child: _ResultBars(points: a.timeline)),
      ),
    ];
    if (width >= 920) {
      return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: children[0]),
            const SizedBox(width: 14),
            Expanded(child: children[1]),
          ]);
    }
    return Column(children: <Widget>[
      children[0],
      const SizedBox(height: 14),
      children[1]
    ]);
  }

  Widget _breakdowns(BiAnalytics a, double width) {
    final children = <Widget>[
      _Ranking(title: 'Desempenho por ativo', values: a.byAsset),
      _Ranking(title: 'Desempenho por estratégia', values: a.byStrategy),
      _Ranking(title: 'Desempenho por dia da semana', values: a.byWeekday),
    ];
    if (width >= 1000) {
      return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var i = 0; i < children.length; i++) ...<Widget>[
              Expanded(child: children[i]),
              if (i < children.length - 1) const SizedBox(width: 12),
            ],
          ]);
    }
    return Column(children: <Widget>[
      for (var i = 0; i < children.length; i++) ...<Widget>[
        children[i],
        if (i < children.length - 1) const SizedBox(height: 12),
      ],
    ]);
  }

  Widget _dailyTable(BiAnalytics a) => _Panel(
        title: 'Resumo cronológico',
        subtitle: 'Conferência diária para análise e impressão',
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF0F4F3)),
            columns: const <DataColumn>[
              DataColumn(label: Text('Data')),
              DataColumn(label: Text('Operações'), numeric: true),
              DataColumn(label: Text('Gains'), numeric: true),
              DataColumn(label: Text('Losses'), numeric: true),
              DataColumn(label: Text('Break-even'), numeric: true),
              DataColumn(label: Text('Taxa de acerto'), numeric: true),
              DataColumn(label: Text('Resultado'), numeric: true),
            ],
            rows: a.daily.reversed
                .map((day) => DataRow(cells: <DataCell>[
                      DataCell(Text(_displayDate(day.date))),
                      DataCell(Text('${day.count}')),
                      DataCell(Text('${day.gains}')),
                      DataCell(Text('${day.losses}')),
                      DataCell(Text('${day.breakEvens}')),
                      DataCell(Text(day.applicableWinRate == null
                          ? 'Não aplicável'
                          : '${_percent(day.applicableWinRate!)}%')),
                      DataCell(Text(_currency(day.result),
                          style: TextStyle(
                              color: day.result >= 0 ? _green : _red,
                              fontWeight: FontWeight.w800))),
                    ]))
                .toList(),
          ),
        ),
      );
}

class BiTrade {
  const BiTrade(
      {required this.date,
      required this.asset,
      required this.strategy,
      required this.weekday,
      required this.status,
      required this.net,
      this.id = '',
      this.resultType = '',
      this.hasNetResult = true});
  factory BiTrade.fromJson(Map<String, dynamic> json) => BiTrade(
        id: '${json['id'] ?? ''}',
        date: '${json['trade_date'] ?? ''}',
        asset: '${json['asset'] ?? 'Sem ativo'}',
        strategy: ('${json['strategy'] ?? ''}').trim().isEmpty
            ? 'Não informada'
            : '${json['strategy']}',
        weekday: '${json['trade_weekday'] ?? ''}',
        status: '${json['status'] ?? ''}',
        net: (json['net_result'] as num?)?.toDouble() ?? 0,
        resultType: '${json['result_type'] ?? json['operation_result'] ?? ''}',
        hasNetResult: json['net_result'] is num,
      );
  final String date, asset, strategy, weekday, status;
  final String id, resultType;
  final double net;
  final bool hasNetResult;
}

enum BiTradeOutcome { win, loss, breakEven, invalid }

const double _financialTolerance = 0.01;

BiTradeOutcome classifyBiTrade(BiTrade trade) {
  if (trade.status != 'ENCERRADA' ||
      !trade.hasNetResult ||
      !trade.net.isFinite) {
    return BiTradeOutcome.invalid;
  }
  if (trade.resultType.toUpperCase() == 'BREAK_EVEN') {
    return BiTradeOutcome.breakEven;
  }
  if (trade.net.abs() < _financialTolerance) return BiTradeOutcome.breakEven;
  return trade.net > 0 ? BiTradeOutcome.win : BiTradeOutcome.loss;
}

class BiAnalytics {
  BiAnalytics(List<BiTrade> trades) : closed = _uniqueClosedTrades(trades) {
    closed.sort((a, b) => a.date.compareTo(b.date));
  }

  static List<BiTrade> _uniqueClosedTrades(List<BiTrade> trades) {
    final unique = <String, BiTrade>{};
    var anonymous = 0;
    for (final trade in trades) {
      if (classifyBiTrade(trade) == BiTradeOutcome.invalid) continue;
      final key = trade.id.isEmpty ? '__anonymous_${anonymous++}' : trade.id;
      unique[key] = trade;
    }
    return unique.values.toList();
  }

  final List<BiTrade> closed;
  double get net => closed.fold(0, (sum, item) => sum + item.net);
  int get gains => closed
      .where((item) => classifyBiTrade(item) == BiTradeOutcome.win)
      .length;
  int get losses => closed
      .where((item) => classifyBiTrade(item) == BiTradeOutcome.loss)
      .length;
  int get breakEvens => closed
      .where((item) => classifyBiTrade(item) == BiTradeOutcome.breakEven)
      .length;
  int get total => gains + losses + breakEvens;
  double? get applicableWinRate =>
      gains + losses == 0 ? null : gains / (gains + losses) * 100;
  double get winRate => applicableWinRate ?? 0;
  double percentOfTotal(int count) => total == 0 ? 0 : count / total * 100;
  double get average => closed.isEmpty ? 0 : net / closed.length;
  double get grossProfit =>
      closed.where((t) => t.net > 0).fold(0, (s, t) => s + t.net);
  double get grossLoss =>
      closed.where((t) => t.net < 0).fold(0, (s, t) => s + t.net.abs());
  String get profitFactorText => grossLoss == 0
      ? (grossProfit > 0 ? '∞' : '0,00')
      : (grossProfit / grossLoss).toStringAsFixed(2).replaceAll('.', ',');
  List<double> get equityCurve {
    var total = 0.0;
    return closed.map((t) => total += t.net).toList();
  }

  double get maxDrawdown {
    var peak = 0.0;
    var maxDd = 0.0;
    for (final v in equityCurve) {
      peak = math.max(peak, v);
      maxDd = math.max(maxDd, peak - v);
    }
    return maxDd;
  }

  Map<String, double> _group(String Function(BiTrade) key) {
    final map = <String, double>{};
    for (final t in closed) {
      map.update(key(t), (v) => v + t.net, ifAbsent: () => t.net);
    }
    return map;
  }

  Map<String, double> get byAsset => _group((t) => t.asset);
  Map<String, double> get byStrategy => _group((t) => t.strategy);
  Map<String, double> get byWeekday => _group((t) => _capitalize(t.weekday));
  List<DailyBi> get daily {
    final grouped = <String, List<BiTrade>>{};
    for (final t in closed) {
      grouped.putIfAbsent(t.date, () => <BiTrade>[]).add(t);
    }
    return grouped.entries.map((e) => DailyBi(e.key, e.value)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<double> get timeline => daily.map((d) => d.result).toList();
}

class DailyBi {
  DailyBi(this.date, this.items);
  final String date;
  final List<BiTrade> items;
  int get count => gains + losses + breakEvens;
  int get gains =>
      items.where((t) => classifyBiTrade(t) == BiTradeOutcome.win).length;
  int get losses =>
      items.where((t) => classifyBiTrade(t) == BiTradeOutcome.loss).length;
  int get breakEvens =>
      items.where((t) => classifyBiTrade(t) == BiTradeOutcome.breakEven).length;
  double get result => items.fold(0, (s, t) => s + t.net);
  double? get applicableWinRate =>
      gains + losses == 0 ? null : gains / (gains + losses) * 100;
  double get winRate => applicableWinRate ?? 0;
}

class _AccuracyCards extends StatelessWidget {
  const _AccuracyCards({required this.analytics, required this.range});

  final BiAnalytics analytics;
  final DateTimeRange range;

  @override
  Widget build(BuildContext context) {
    final rate = analytics.applicableWinRate;
    final cards = <_KpiData>[
      _KpiData(
        'Taxa de acerto',
        rate == null ? 'Não aplicável' : '${_percent(rate)}%',
        Icons.track_changes_rounded,
        _teal,
      ),
      _KpiData(
        'Vencedoras',
        '${analytics.gains} • ${_percent(analytics.percentOfTotal(analytics.gains))}%',
        Icons.trending_up_rounded,
        _green,
      ),
      _KpiData(
        'Perdedoras',
        '${analytics.losses} • ${_percent(analytics.percentOfTotal(analytics.losses))}%',
        Icons.trending_down_rounded,
        _red,
      ),
      _KpiData(
        'Break-even',
        '${analytics.breakEvens} • ${_percent(analytics.percentOfTotal(analytics.breakEvens))}%',
        Icons.horizontal_rule_rounded,
        _breakEven,
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760
          ? 4
          : constraints.maxWidth >= 340
              ? 2
              : 1;
      return Column(
        children: <Widget>[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cards.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              mainAxisExtent: 92,
            ),
            itemBuilder: (_, index) => _KpiCard(data: cards[index]),
          ),
          const SizedBox(height: 8),
          _TotalOperationsSummary(
            total: analytics.total,
            period: formatBiPeriodSummary(range),
          ),
        ],
      );
    });
  }
}

class _TotalOperationsSummary extends StatelessWidget {
  const _TotalOperationsSummary({required this.total, required this.period});

  final int total;
  final String period;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7F7),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _navy.withValues(alpha: .16)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final title = Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.receipt_long_outlined,
                      color: _navy, size: 17),
                ),
                const SizedBox(width: 8),
                const Text('Total de operações',
                    style: TextStyle(
                        color: _navy,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Text('$total',
                    style: const TextStyle(
                        color: _navy,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
              ],
            );
            final periodText = Text(
              period,
              textAlign: compact ? TextAlign.left : TextAlign.right,
              style: const TextStyle(
                  color: _muted, fontSize: 11, fontWeight: FontWeight.w700),
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  title,
                  const SizedBox(height: 7),
                  periodText,
                ],
              );
            }
            return Row(
              children: <Widget>[
                title,
                const SizedBox(width: 16),
                Container(width: 1, height: 28, color: _line),
                const SizedBox(width: 16),
                Expanded(child: periodText),
              ],
            );
          },
        ),
      );
}

class _AccuracyDonut extends StatefulWidget {
  const _AccuracyDonut({required this.analytics, required this.compact});

  final BiAnalytics analytics;
  final bool compact;

  @override
  State<_AccuracyDonut> createState() => _AccuracyDonutState();
}

class _AccuracyDonutState extends State<_AccuracyDonut> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final analytics = widget.analytics;
    final values = <(String, int, Color)>[
      ('Vencedoras', analytics.gains, _green),
      ('Perdedoras', analytics.losses, _red),
      ('Break-even', analytics.breakEvens, _breakEven),
    ];
    final chart = SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          PieChart(
            PieChartData(
              centerSpaceRadius: 68,
              sectionsSpace: 3,
              pieTouchData: PieTouchData(
                enabled: true,
                touchCallback: (event, response) {
                  final index = event.isInterestedForInteractions
                      ? response?.touchedSection?.touchedSectionIndex ?? -1
                      : -1;
                  if (index != _touchedIndex) {
                    setState(() => _touchedIndex = index);
                  }
                },
              ),
              sections: values
                  .where((item) => item.$2 > 0)
                  .toList()
                  .asMap()
                  .entries
                  .map((item) => PieChartSectionData(
                        value: item.value.$2.toDouble(),
                        color: item.value.$3,
                        radius: item.key == _touchedIndex ? 46 : 40,
                        title:
                            '${item.value.$2}\n${_percent(analytics.percentOfTotal(item.value.$2))}%',
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ))
                  .toList(),
            ),
          ),
          if (_touchedIndex >= 0 &&
              _touchedIndex < values.where((item) => item.$2 > 0).length)
            Positioned(
              top: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _navy,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  child: Builder(builder: (_) {
                    final item = values
                        .where((value) => value.$2 > 0)
                        .elementAt(_touchedIndex);
                    return Text(
                      '${item.$1}: ${item.$2} (${_percent(analytics.percentOfTotal(item.$2))}%)',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    );
                  }),
                ),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('Taxa de acerto',
                  style: TextStyle(fontSize: 11, color: _muted)),
              Text(
                analytics.applicableWinRate == null
                    ? 'N/A'
                    : '${_percent(analytics.applicableWinRate!)}%',
                style: const TextStyle(
                    color: _navy, fontSize: 22, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    );
    final legend = Wrap(
      direction: widget.compact ? Axis.horizontal : Axis.vertical,
      spacing: 16,
      runSpacing: 12,
      children: values
          .map((item) => _AccuracyLegend(
                label: item.$1,
                count: item.$2,
                percentage: analytics.percentOfTotal(item.$2),
                color: item.$3,
              ))
          .toList(),
    );
    return widget.compact
        ? Column(children: <Widget>[chart, legend])
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[chart, const SizedBox(width: 36), legend],
          );
  }
}

class _AccuracyLegend extends StatelessWidget {
  const _AccuracyLegend({
    required this.label,
    required this.count,
    required this.percentage,
    required this.color,
  });

  final String label;
  final int count;
  final double percentage;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text('$label: $count (${_percent(percentage)}%)',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      );
}

class _Panel extends StatelessWidget {
  const _Panel(
      {required this.title, required this.subtitle, required this.child});
  final String title, subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _line)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900, color: _navy)),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: _muted)),
            const SizedBox(height: 14),
            child
          ]));
}

class _KpiData {
  const _KpiData(this.label, this.value, this.icon, this.color);
  final String label, value;
  final IconData icon;
  final Color color;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});
  final _KpiData data;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: data.color.withValues(alpha: .18)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x09102A3A),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    color: data.color.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(data.icon, color: data.color, size: 15),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    data.label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              height: 23,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  data.value,
                  style: TextStyle(
                    color: data.color,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.25,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _Ranking extends StatelessWidget {
  const _Ranking({required this.title, required this.values});
  final String title;
  final Map<String, double> values;
  @override
  Widget build(BuildContext context) {
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxValue =
        entries.fold<double>(1, (m, e) => math.max(m, e.value.abs()));
    return _Panel(
        title: title,
        subtitle: 'Resultado líquido consolidado',
        child: Column(
            children: entries
                .take(7)
                .map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(children: <Widget>[
                      Row(children: <Widget>[
                        Expanded(
                            child: Text(e.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700))),
                        Text(_currency(e.value),
                            style: TextStyle(
                                color: e.value >= 0 ? _green : _red,
                                fontWeight: FontWeight.w800,
                                fontSize: 12))
                      ]),
                      const SizedBox(height: 5),
                      LinearProgressIndicator(
                          value: e.value.abs() / maxValue,
                          minHeight: 5,
                          borderRadius: BorderRadius.circular(5),
                          color: e.value >= 0 ? _green : _red,
                          backgroundColor: const Color(0xFFECECE8))
                    ])))
                .toList()));
  }
}

class _EquityChart extends StatelessWidget {
  const _EquityChart({required this.points});
  final List<double> points;
  @override
  Widget build(BuildContext context) => CustomPaint(
      painter: _ChartPainter(points, line: true),
      child: const SizedBox.expand());
}

class _ResultBars extends StatelessWidget {
  const _ResultBars({required this.points});
  final List<double> points;
  @override
  Widget build(BuildContext context) => CustomPaint(
      painter: _ChartPainter(points, line: false),
      child: const SizedBox.expand());
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.values, {required this.line});
  final List<double> values;
  final bool line;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE8EAE7)
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty) return;
    final minV = math.min(0, values.reduce(math.min)),
        maxV = math.max(0, values.reduce(math.max)),
        span = math.max(1, maxV - minV),
        zeroY = (maxV / span) * size.height;
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY),
        Paint()..color = _muted.withValues(alpha: .5));
    if (line) {
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = values.length == 1
            ? size.width / 2
            : i * size.width / (values.length - 1);
        final y = (maxV - values[i]) / span * size.height;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = _teal
            ..strokeWidth = 3
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round);
    } else {
      final slot = size.width / values.length,
          barWidth = math.max(3.0, math.min(24.0, slot * .62));
      for (var i = 0; i < values.length; i++) {
        final x = i * slot + (slot - barWidth) / 2,
            y = (maxV - values[i]) / span * size.height;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTRB(
                    x, math.min(y, zeroY), x + barWidth, math.max(y, zeroY)),
                const Radius.circular(4)),
            Paint()..color = values[i] >= 0 ? _green : _red);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.values != values || old.line != line;
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel();
  @override
  Widget build(BuildContext context) => const _Panel(
      title: 'Nenhuma operação no período',
      subtitle:
          'Selecione outro dia, semana, mês ou ano para consultar o histórico.',
      child: Padding(
          padding: EdgeInsets.all(24),
          child: Icon(Icons.query_stats_rounded, color: _muted, size: 48)));
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => _Panel(
      title: 'Não foi possível carregar',
      subtitle: message,
      child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'))));
}

String _iso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String formatBiDateInput(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().padLeft(4, '0')}';

DateTime? parseBiDateInput(String value) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(value.trim());
  if (match == null) return null;
  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

class BiDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.substring(0, math.min(8, digits.length));
    final buffer = StringBuffer();
    for (var index = 0; index < limited.length; index++) {
      if (index == 2 || index == 4) buffer.write('/');
      buffer.write(limited[index]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

String _displayDate(String iso) {
  final parts = iso.split('-');
  return parts.length == 3 ? '${parts[2]}/${parts[1]}/${parts[0]}' : iso;
}

String formatBiDayLabel(DateTime date) {
  const weekdaysPtBr = <String>[
    'Segunda-feira',
    'Terça-feira',
    'Quarta-feira',
    'Quinta-feira',
    'Sexta-feira',
    'Sábado',
    'Domingo',
  ];
  return '${_displayDate(_iso(date))} — ${weekdaysPtBr[date.weekday - 1]}';
}

String formatBiPeriodSummary(DateTimeRange range) {
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  final days = end.difference(start).inDays + 1;
  return 'De ${_displayDate(_iso(start))} até ${_displayDate(_iso(end))} '
      '• $days ${days == 1 ? 'dia' : 'dias'}';
}

String _rangeLabel(DateTimeRange r) => r.start == r.end
    ? _displayDate(_iso(r.start))
    : '${_displayDate(_iso(r.start))} a ${_displayDate(_iso(r.end))}';
String _currency(double value) {
  final sign = value < 0 ? '-' : '';
  final fixed = value.abs().toStringAsFixed(2).split('.');
  final integer =
      fixed[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
  return '$sign R\$ $integer,${fixed[1]}';
}

String _percent(double value) => value.toStringAsFixed(2).replaceAll('.', ',');

String _capitalize(String value) => value.isEmpty
    ? 'Não informado'
    : '${value[0].toUpperCase()}${value.substring(1)}';
