import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

typedef BudgetBiApiUriBuilder = Uri Function(String path);

const Color _navy = Color(0xFF162A3A);
const Color _blue = Color(0xFF2F73B7);
const Color _green = Color(0xFF2E8B68);
const Color _red = Color(0xFFC25454);
const Color _amber = Color(0xFFD49632);
const Color _purple = Color(0xFF7259A5);
const Color _canvas = Color(0xFFF2F5F7);
const Color _panel = Colors.white;
const Color _ink = Color(0xFF24313B);
const Color _muted = Color(0xFF687781);

class BudgetBiScreen extends StatefulWidget {
  const BudgetBiScreen({
    required this.apiUriBuilder,
    required this.sessionToken,
    super.key,
  });

  final BudgetBiApiUriBuilder apiUriBuilder;
  final String sessionToken;

  @override
  State<BudgetBiScreen> createState() => _BudgetBiScreenState();
}

class _BudgetBiScreenState extends State<BudgetBiScreen> {
  bool _loading = true;
  bool _processing = false;
  String? _error;
  late int _year;
  late int _month;
  late DateTime _day;
  String _period = 'Ano';
  String _status = 'Todos';
  List<_BiEntry> _entries = <_BiEntry>[];

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _day = DateTime(now.year, now.month, now.day);
    _load();
  }

  List<_BiEntry> get _filtered => _entries.where(_matchesFilters).toList();
  double get _received => _filtered
      .where((e) => e.isRevenue)
      .fold(0, (total, item) => total + item.receivedAmount);
  double get _paid => _sum((e) => !e.isRevenue && e.settled);
  double get _receivable => _filtered
      .where((e) => e.isRevenue)
      .fold(0, (total, item) => total + item.remainingAmount);
  double get _payable => _sum((e) => !e.isRevenue && !e.settled);
  double get _cashBalance => _received - _paid;
  double get _overdue => _sum((e) => !e.settled && e.isOverdue);
  int get _overdueCount =>
      _filtered.where((e) => !e.settled && e.isOverdue).length;

  double _sum(bool Function(_BiEntry) test) => _filtered
      .where(test)
      .fold(0, (double total, _BiEntry item) => total + item.amount);

  bool _matchesFilters(_BiEntry item) {
    final bool statusMatches = switch (_status) {
      'Despesas pagas' => !item.isRevenue && item.settled,
      'Despesas não pagas' => !item.isRevenue && !item.settled,
      'Receitas recebidas' => item.isRevenue && item.receivedAmount > 0,
      'A receber' => item.isRevenue && item.remainingAmount > 0,
      'A pagar' => !item.isRevenue && !item.settled,
      'Vencidos' => !item.settled && item.isOverdue,
      _ => true,
    };
    if (!statusMatches) return false;
    final DateTime date = item.analysisDate;
    if (_period == 'Dia') return _sameDay(date, _day);
    if (_period == 'Mês') return date.year == _year && date.month == _month;
    return date.year == _year;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Uri uri = widget.apiUriBuilder('/api/budget/bi').replace(
        queryParameters: <String, String>{'year': '$_year'},
      );
      final http.Response response = await http.get(uri, headers: {
        'authorization': 'Bearer ${widget.sessionToken}',
        'content-type': 'application/json; charset=utf-8',
      });
      final Map<String, dynamic> body = jsonDecode(response.body);
      if (response.statusCode != 200 || body['ok'] != true) {
        throw StateError('Falha ao carregar o BI');
      }
      final List<dynamic> raw = body['items'] ?? <dynamic>[];
      final List<_BiEntry> entries = raw
          .map((value) => _BiEntry.fromJson(value as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() => _entries = entries);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar o BI-Orçamento.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDay() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(_year, 1, 1),
      lastDate: DateTime(_year, 12, 31),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) setState(() => _day = picked);
  }

  void _clearFilters() {
    final DateTime now = DateTime.now();
    setState(() {
      _year = now.year;
      _month = now.month;
      _day = DateTime(now.year, now.month, now.day);
      _period = 'Ano';
      _status = 'Todos';
    });
    _load();
  }

  String get _contextLabel => switch (_period) {
        'Dia' => _displayDate(_day),
        'Mês' => '${_months[_month - 1]} de $_year',
        _ => 'Ano de $_year',
      };

  Future<Uint8List> _pdfBytes() async {
    final List<_BiEntry> entries = List<_BiEntry>.from(_filtered)
      ..sort((a, b) => b.analysisDate.compareTo(a.analysisDate));
    final pw.Document document = pw.Document(
      title: 'BI-Orcamento - $_contextLabel',
      author: 'EKT IA Systems',
    );
    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      header: (_) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text('EKT IA SYSTEMS',
              style: const pw.TextStyle(
                  fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.Text('BI-ORCAMENTO | $_contextLabel'),
        ],
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Pagina ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8)),
      ),
      build: (_) => <pw.Widget>[
        pw.SizedBox(height: 10),
        pw.Text('Painel financeiro realizado e compromissos',
            style: const pw.TextStyle(
                fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Situacao: $_status | ${entries.length} lancamento(s)',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 14),
        pw.Wrap(spacing: 8, runSpacing: 8, children: <pw.Widget>[
          _pdfMetric('Saldo realizado', _currency(_cashBalance)),
          _pdfMetric('Recebido', _currency(_received)),
          _pdfMetric('Pago', _currency(_paid)),
          _pdfMetric('A receber', _currency(_receivable)),
          _pdfMetric('A pagar', _currency(_payable)),
          _pdfMetric('Vencido', _currency(_overdue)),
        ]),
        pw.SizedBox(height: 18),
        if (entries.isEmpty)
          pw.Text('Nenhum lancamento corresponde aos filtros selecionados.')
        else
          pw.TableHelper.fromTextArray(
            headers: const <String>[
              'Data',
              'Tipo',
              'Descricao',
              'Observacao',
              'Situacao',
              'Valor'
            ],
            data: entries
                .map((item) => <String>[
                      _displayDate(item.analysisDate),
                      item.itemType,
                      item.description,
                      item.observation,
                      item.statusLabel,
                      _currency(item.amount),
                    ])
                .toList(),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey800),
            headerStyle: const pw.TextStyle(
                color: PdfColors.white, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 7),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          ),
      ],
    ));
    return document.save();
  }

  Future<void> _print() async {
    setState(() => _processing = true);
    try {
      await Printing.layoutPdf(onLayout: (_) => _pdfBytes());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _share() async {
    setState(() => _processing = true);
    try {
      await Printing.sharePdf(
        bytes: await _pdfBytes(),
        filename: 'bi-orcamento-$_year.pdf',
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: const Text('BI-Orçamento'),
          actions: <Widget>[
            IconButton(
                tooltip: 'Atualizar dados',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorView()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(18),
                      children: <Widget>[
                        _hero(),
                        const SizedBox(height: 14),
                        _filters(),
                        const SizedBox(height: 14),
                        _metrics(),
                        const SizedBox(height: 14),
                        _visuals(),
                        const SizedBox(height: 14),
                        _details(),
                        const SizedBox(height: 14),
                        _actions(),
                      ],
                    ),
                  ),
      );

  Widget _errorView() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const Icon(Icons.cloud_off_outlined, size: 44, color: _red),
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: _ink)),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente')),
        ]),
      );

  Widget _hero() => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: <Color>[_navy, _blue]),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Wrap(
          spacing: 18,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.analytics_outlined,
                  color: Colors.white, size: 30),
            ),
            const SizedBox(
              width: 690,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Inteligência financeira do orçamento',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900)),
                  SizedBox(height: 6),
                  Text(
                    'Entradas e saídas realizadas, compromissos pendentes e valores vencidos — sem projeções artificiais.',
                    style: TextStyle(color: Color(0xFFDCEBFA), height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _filters() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(children: <Widget>[
              const Icon(Icons.tune, color: _blue),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Contexto da análise',
                      style: TextStyle(
                          color: _ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w900))),
              TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Limpar')),
            ]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                SegmentedButton<String>(
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment(value: 'Dia', label: Text('Dia')),
                    ButtonSegment(value: 'Mês', label: Text('Mês')),
                    ButtonSegment(value: 'Ano', label: Text('Ano')),
                  ],
                  selected: <String>{_period},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) =>
                      setState(() => _period = value.first),
                ),
                SizedBox(
                  width: 125,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('year-$_year'),
                    initialValue: _year,
                    decoration: _input('Ano'),
                    items: List<int>.generate(
                            7, (index) => DateTime.now().year - 3 + index)
                        .map((year) =>
                            DropdownMenuItem(value: year, child: Text('$year')))
                        .toList(),
                    onChanged: (value) {
                      if (value == null || value == _year) return;
                      setState(() {
                        _year = value;
                        _day = DateTime(value, _day.month, _day.day);
                      });
                      _load();
                    },
                  ),
                ),
                if (_period == 'Mês')
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('month-$_month'),
                      initialValue: _month,
                      decoration: _input('Mês'),
                      items: List<int>.generate(12, (index) => index + 1)
                          .map((month) => DropdownMenuItem(
                              value: month, child: Text(_months[month - 1])))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _month = value ?? _month),
                    ),
                  ),
                if (_period == 'Dia')
                  OutlinedButton.icon(
                      onPressed: _pickDay,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(_displayDate(_day))),
                SizedBox(
                  width: 225,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('status-$_status'),
                    initialValue: _status,
                    decoration: _input('Situação'),
                    items: const <String>[
                      'Todos',
                      'Despesas pagas',
                      'Despesas não pagas',
                      'Receitas recebidas',
                      'A receber',
                      'A pagar',
                      'Vencidos',
                    ]
                        .map((value) =>
                            DropdownMenuItem(value: value, child: Text(value)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _status = value ?? 'Todos'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$_contextLabel • $_status • ${_filtered.length} lançamento(s)',
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      );

  InputDecoration _input(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      );

  Widget _metrics() => LayoutBuilder(builder: (_, constraints) {
        final int columns = constraints.maxWidth >= 1050
            ? 6
            : constraints.maxWidth >= 720
                ? 3
                : constraints.maxWidth >= 430
                    ? 2
                    : 1;
        final double width =
            (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
          _metric(width, 'Saldo realizado', _cashBalance, Icons.account_balance,
              _cashBalance >= 0 ? _green : _red),
          _metric(width, 'Recebido', _received, Icons.south_west, _green),
          _metric(width, 'Pago', _paid, Icons.north_east, _red),
          _metric(width, 'A receber', _receivable, Icons.schedule, _blue),
          _metric(width, 'A pagar', _payable, Icons.event_note, _amber),
          _metric(width, 'Vencido', _overdue, Icons.warning_amber, _purple,
              detail: '$_overdueCount lançamento(s)'),
        ]);
      });

  Widget _metric(
          double width, String label, double value, IconData icon, Color color,
          {String? detail}) =>
      Container(
        width: width,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(18),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 7),
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 10),
          Text(_currency(value),
              style: const TextStyle(
                  color: _ink, fontSize: 18, fontWeight: FontWeight.w900)),
          if (detail != null) ...[
            const SizedBox(height: 3),
            Text(detail, style: const TextStyle(color: _muted, fontSize: 10)),
          ],
        ]),
      );

  Widget _visuals() => LayoutBuilder(builder: (_, constraints) {
        final bool wide = constraints.maxWidth >= 820;
        final Widget cash = _cashChart();
        final Widget commitments = _commitmentsChart();
        return wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: cash),
                const SizedBox(width: 14),
                Expanded(child: commitments),
              ])
            : Column(children: [cash, const SizedBox(height: 14), commitments]);
      });

  Widget _cashChart() => _chartCard(
        title: 'Movimentação realizada',
        subtitle: 'Somente valores efetivamente recebidos e pagos',
        child: BarChart(BarChartData(
          minY: 0,
          maxY: math.max(math.max(_received, _paid) * 1.25, 1),
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(value == 0 ? 'Recebido' : 'Pago',
                      style: const TextStyle(color: _muted, fontSize: 11)),
                ),
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(
                      _currency(rod.toY), const TextStyle(color: Colors.white)),
            ),
          ),
          barGroups: <BarChartGroupData>[
            _bar(0, _received, _green),
            _bar(1, _paid, _red),
          ],
        )),
      );

  BarChartGroupData _bar(int x, double value, Color color) => BarChartGroupData(
        x: x,
        barRods: <BarChartRodData>[
          BarChartRodData(
            toY: value,
            width: 54,
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
        ],
      );

  Widget _commitmentsChart() {
    final List<_Slice> slices = <_Slice>[
      _Slice('A receber', _receivable, _blue),
      _Slice('A pagar', _payable, _amber),
      _Slice('Vencido', _overdue, _purple),
    ];
    final double total = slices.fold(0, (sum, item) => sum + item.value);
    return _chartCard(
      title: 'Carteira de compromissos',
      subtitle: 'Obrigações abertas no contexto selecionado',
      child: Row(children: <Widget>[
        Expanded(
          child: PieChart(PieChartData(
            centerSpaceRadius: 52,
            sectionsSpace: 3,
            pieTouchData: PieTouchData(enabled: true),
            sections: total == 0
                ? <PieChartSectionData>[
                    PieChartSectionData(
                        value: 1,
                        color: const Color(0xFFDCE2E6),
                        radius: 48,
                        showTitle: false)
                  ]
                : slices
                    .where((item) => item.value > 0)
                    .map((item) => PieChartSectionData(
                          value: item.value,
                          color: item.color,
                          radius: 52,
                          title: '${(item.value / total * 100).round()}%',
                          titleStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900),
                        ))
                    .toList(),
          )),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: slices
                .map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: item.color, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(item.label,
                                style: const TextStyle(
                                    color: _muted, fontSize: 11))),
                        Text(_currency(item.value),
                            style: const TextStyle(
                                color: _ink,
                                fontSize: 11,
                                fontWeight: FontWeight.w900)),
                      ]),
                    ))
                .toList(),
          ),
        ),
      ]),
    );
  }

  Widget _chartCard(
          {required String title,
          required String subtitle,
          required Widget child}) =>
      _card(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title,
              style: const TextStyle(
                  color: _ink, fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: _muted, fontSize: 11)),
          const SizedBox(height: 18),
          SizedBox(height: 245, child: child),
        ]),
      );

  Widget _details() {
    final List<_BiEntry> entries = List<_BiEntry>.from(_filtered)
      ..sort((a, b) => b.analysisDate.compareTo(a.analysisDate));
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Lançamentos que formam os indicadores',
            style: TextStyle(
                color: _ink, fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text('${entries.length} registro(s) auditáveis',
            style: const TextStyle(color: _muted, fontSize: 11)),
        const SizedBox(height: 14),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nenhum lançamento corresponde aos filtros.',
                textAlign: TextAlign.center, style: TextStyle(color: _muted)),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: const WidgetStatePropertyAll(Color(0xFFE8EEF3)),
              border: TableBorder.all(color: const Color(0xFFC7D1D8)),
              columns: const <DataColumn>[
                DataColumn(label: Text('Data')),
                DataColumn(label: Text('Tipo')),
                DataColumn(label: Text('Descrição')),
                DataColumn(label: Text('Observação')),
                DataColumn(label: Text('Situação')),
                DataColumn(label: Text('Valor'), numeric: true),
              ],
              rows: entries
                  .map((item) => DataRow(cells: <DataCell>[
                        DataCell(Text(_displayDate(item.analysisDate))),
                        DataCell(Text(item.itemType)),
                        DataCell(Text(item.description)),
                        DataCell(SizedBox(
                          width: 280,
                          child: Text(
                            item.observation.isEmpty ? '-' : item.observation,
                            softWrap: true,
                          ),
                        )),
                        DataCell(Text(item.statusLabel,
                            style: TextStyle(
                                color: item.isOverdue && !item.settled
                                    ? _purple
                                    : item.settled
                                        ? _green
                                        : _amber,
                                fontWeight: FontWeight.w800))),
                        DataCell(Text(_currency(item.amount),
                            style: TextStyle(
                                color: item.isRevenue ? _green : _red,
                                fontWeight: FontWeight.w900))),
                      ]))
                  .toList(),
            ),
          ),
      ]),
    );
  }

  Widget _actions() => Wrap(
        alignment: WrapAlignment.end,
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          OutlinedButton.icon(
              onPressed: _processing ? null : _share,
              icon: const Icon(Icons.share_outlined),
              label: const Text('Compartilhar PDF')),
          FilledButton.icon(
              onPressed: _processing ? null : _print,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimir relatório')),
          OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.logout),
              label: const Text('Sair')),
        ],
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD9E1E6)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
                color: Color(0x0A102030), blurRadius: 14, offset: Offset(0, 5))
          ],
        ),
        child: child,
      );
}

class _BiEntry {
  const _BiEntry({
    required this.itemType,
    required this.description,
    required this.observation,
    required this.amount,
    required this.receivedAmount,
    required this.dueDate,
    required this.paymentDate,
    required this.settled,
  });

  factory _BiEntry.fromJson(Map<String, dynamic> json) => _BiEntry(
        itemType: json['item_type']?.toString() ?? 'Despesa',
        description: json['description']?.toString() ?? '',
        observation: json['observation']?.toString() ?? '',
        amount: _parseAmount(json['amount_text']?.toString() ?? '0'),
        receivedAmount:
            _parseAmount(json['received_amount_text']?.toString() ?? '0'),
        dueDate: _parseDate(json['due_date']?.toString()) ?? DateTime.now(),
        paymentDate: _parseDate(json['payment_date']?.toString()),
        settled: json['settled'] == true,
      );

  final String itemType;
  final String description;
  final String observation;
  final double amount;
  final double receivedAmount;
  final DateTime dueDate;
  final DateTime? paymentDate;
  final bool settled;

  bool get isRevenue => itemType == 'Receita';
  double get remainingAmount =>
      (amount - receivedAmount).clamp(0, double.infinity);
  bool get partiallyReceived =>
      isRevenue && receivedAmount > 0 && remainingAmount > 0;
  DateTime get analysisDate =>
      settled && paymentDate != null ? paymentDate! : dueDate;
  bool get isOverdue {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return dueDate.isBefore(today);
  }

  String get statusLabel {
    if (!settled && isOverdue) {
      return isRevenue ? 'A receber vencida' : 'A pagar vencida';
    }
    if (isRevenue) {
      if (settled) return 'Recebida';
      if (partiallyReceived) return 'Recebida parcialmente';
      return 'A receber';
    }
    return settled ? 'Paga' : 'A pagar';
  }
}

class _Slice {
  const _Slice(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

pw.Widget _pdfMetric(String label, String value) => pw.Container(
      width: 145,
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(4)),
      child:
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(label,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        pw.Text(value,
            style: const pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold)),
      ]),
    );

const List<String> _months = <String>[
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
  'Dezembro',
];

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime? _parseDate(String? value) {
  if (value == null || value.isEmpty) return null;
  final DateTime? date = DateTime.tryParse(value);
  return date == null ? null : DateTime(date.year, date.month, date.day);
}

String _displayDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

double _parseAmount(String value) {
  String cleaned = value.replaceAll('R\$', '').replaceAll(' ', '');
  if (cleaned.contains(',')) {
    cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(cleaned) ?? 0;
}

String _currency(double value) {
  final bool negative = value < 0;
  final String fixed = value.abs().toStringAsFixed(2);
  final List<String> parts = fixed.split('.');
  final String digits = parts[0];
  final StringBuffer formatted = StringBuffer();
  for (int index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) formatted.write('.');
    formatted.write(digits[index]);
  }
  return '${negative ? '-' : ''}R\$ ${formatted.toString()},${parts[1]}';
}
