import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

typedef BudgetBiApiUriBuilder = Uri Function(String path);

const Color _biNavy = Color(0xFF26384A);
const Color _biBlue = Color(0xFF3978B8);
const Color _biGreen = Color(0xFF58865B);
const Color _biRed = Color(0xFFB45E59);
const Color _biGold = Color(0xFFC28A34);
const Color _biCanvas = Color(0xFFF3F5F7);
const Color _biPanel = Color(0xFFFFFFFF);
const Color _biInk = Color(0xFF26313B);
const Color _biMuted = Color(0xFF687582);

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
  List<_BudgetBiMonth> _months = <_BudgetBiMonth>[];

  double get _revenue => _months.fold(
      0, (double total, _BudgetBiMonth month) => total + month.revenue);
  double get _expenses => _months.fold(
      0, (double total, _BudgetBiMonth month) => total + month.expenses);
  double get _received => _months.fold(
      0, (double total, _BudgetBiMonth month) => total + month.received);
  double get _paid => _months.fold(
      0, (double total, _BudgetBiMonth month) => total + month.paid);
  double get _balance => _revenue - _expenses;
  double get _pendingRevenue => _revenue - _received;
  double get _pendingExpenses => _expenses - _paid;

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<_BudgetBiMonth> months = await Future.wait(
        List<int>.generate(12, (int index) => index + 1).map(_loadMonth),
      );
      if (mounted) setState(() => _months = months);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar o BI do orçamento.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<_BudgetBiMonth> _loadMonth(int month) async {
    final String reference = '$_year-${month.toString().padLeft(2, '0')}';
    final Uri uri = widget.apiUriBuilder('/api/budget').replace(
      queryParameters: <String, String>{'month': reference},
    );
    final http.Response response =
        await http.get(uri, headers: <String, String>{
      'authorization': 'Bearer ${widget.sessionToken}',
      'content-type': 'application/json; charset=utf-8',
    });
    final Map<String, dynamic> body =
        jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || body['ok'] != true) {
      throw StateError('Falha ao carregar $reference');
    }
    final List<dynamic> raw = (body['items'] as List<dynamic>?) ?? <dynamic>[];
    double revenue = 0;
    double expenses = 0;
    double received = 0;
    double paid = 0;
    for (final dynamic value in raw) {
      final Map<String, dynamic> item = value as Map<String, dynamic>;
      final double amount =
          _parseAmount((item['amount_text'] as String?) ?? '0');
      final bool settled = (item['settled'] as bool?) ?? false;
      if (item['item_type'] == 'Receita') {
        revenue += amount;
        if (settled) received += amount;
      } else {
        expenses += amount;
        if (settled) paid += amount;
      }
    }
    return _BudgetBiMonth(
      reference: reference,
      revenue: revenue,
      expenses: expenses,
      received: received,
      paid: paid,
      entries: raw.length,
    );
  }

  Future<Uint8List> _pdfBytes() async {
    final pw.Document document = pw.Document(
      title: 'BI Orcamento $_year',
      author: 'EKT IA Systems',
    );
    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      header: (pw.Context context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text('EKT IA SYSTEMS',
              style: const pw.TextStyle(
                  fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.Text('BI ORCAMENTO - $_year'),
        ],
      ),
      footer: (pw.Context context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Pagina ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8)),
      ),
      build: (pw.Context context) => <pw.Widget>[
        pw.SizedBox(height: 18),
        pw.Text('Visao gerencial do orcamento',
            style: const pw.TextStyle(
                fontSize: 21, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 14),
        pw.Wrap(spacing: 8, runSpacing: 8, children: <pw.Widget>[
          _pdfMetric('Receitas', _currency(_revenue)),
          _pdfMetric('Despesas', _currency(_expenses)),
          _pdfMetric('Saldo projetado', _currency(_balance)),
          _pdfMetric('Recebido', _currency(_received)),
          _pdfMetric('Pago', _currency(_paid)),
          _pdfMetric('A receber', _currency(_pendingRevenue)),
          _pdfMetric('A pagar', _currency(_pendingExpenses)),
        ]),
        pw.SizedBox(height: 18),
        pw.TableHelper.fromTextArray(
          headers: const <String>[
            'Mes',
            'Lancamentos',
            'Receitas',
            'Despesas',
            'Recebido',
            'Pago',
            'Saldo'
          ],
          data: _months
              .map((_BudgetBiMonth month) => <String>[
                    month.label,
                    '${month.entries}',
                    _currency(month.revenue),
                    _currency(month.expenses),
                    _currency(month.received),
                    _currency(month.paid),
                    _currency(month.balance),
                  ])
              .toList(),
          headerDecoration:
              const pw.BoxDecoration(color: PdfColors.blueGrey800),
          headerStyle: const pw.TextStyle(
              color: PdfColors.white, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 8),
          border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
          cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        ),
      ],
    ));
    return document.save();
  }

  pw.Widget _pdfMetric(String label, String value) => pw.Container(
        width: 135,
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          border: pw.Border.all(color: PdfColors.grey300),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 3),
            pw.Text(value,
                style: const pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  Future<void> _print() async {
    setState(() => _processing = true);
    try {
      final Uint8List bytes = await _pdfBytes();
      await Printing.layoutPdf(
        name: 'BI-Orcamento-$_year.pdf',
        onLayout: (_) async => bytes,
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _share() async {
    setState(() => _processing = true);
    try {
      await Printing.sharePdf(
        bytes: await _pdfBytes(),
        filename: 'BI-Orcamento-$_year.pdf',
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _biCanvas,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: _biNavy,
        foregroundColor: Colors.white,
        title: const Text('BI-Orçamento'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorState()
                : _dashboard(),
      ),
    );
  }

  Widget _errorState() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(_error!),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente')),
        ]),
      );

  Widget _dashboard() {
    return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
      final double padding = constraints.maxWidth < 600 ? 12 : 20;
      return SingleChildScrollView(
        padding: EdgeInsets.all(padding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _hero(),
                const SizedBox(height: 14),
                _metrics(),
                const SizedBox(height: 14),
                _monthlyAnalysis(),
                const SizedBox(height: 14),
                _actions(),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _hero() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient:
              const LinearGradient(colors: <Color>[_biNavy, Color(0xFF365A78)]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: <Widget>[
          const CircleAvatar(
            radius: 27,
            backgroundColor: Color(0x334FA0D8),
            child: Icon(Icons.insights_rounded, color: Colors.white, size: 29),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                const Text('INTELIGÊNCIA ORÇAMENTÁRIA',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        letterSpacing: .8,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Visão consolidada de $_year',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                const Text('Receitas, despesas, liquidação e evolução mensal',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ])),
        ]),
      );

  Widget _metrics() => LayoutBuilder(builder: (_, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        final double width =
            (constraints.maxWidth - (columns - 1) * 10) / columns;
        final List<Widget> cards = <Widget>[
          _metric('Receitas', _revenue, _biGreen, Icons.trending_up_rounded),
          _metric('Despesas', _expenses, _biRed, Icons.trending_down_rounded),
          _metric('Saldo projetado', _balance, _biBlue, Icons.balance_rounded),
          _metric(
              'A receber', _pendingRevenue, _biGold, Icons.schedule_rounded),
          _metric('Recebido', _received, _biGreen, Icons.check_circle_rounded),
          _metric('Pago', _paid, _biBlue, Icons.payments_rounded),
          _metric('A pagar', _pendingExpenses, _biRed,
              Icons.pending_actions_rounded),
        ];
        return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: cards
                .map((Widget card) => SizedBox(width: width, child: card))
                .toList());
      });

  Widget _metric(String title, double value, Color color, IconData icon) =>
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: _biPanel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: .25))),
        child: Row(children: <Widget>[
          CircleAvatar(
              backgroundColor: color.withValues(alpha: .12),
              child: Icon(icon, color: color)),
          const SizedBox(width: 11),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                Text(title,
                    style: const TextStyle(color: _biMuted, fontSize: 11)),
                const SizedBox(height: 3),
                Text(_currency(value),
                    style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
              ])),
        ]),
      );

  Widget _monthlyAnalysis() {
    final double maxValue =
        _months.fold<double>(1, (double max, _BudgetBiMonth month) {
      final double value =
          month.revenue > month.expenses ? month.revenue : month.expenses;
      return value > max ? value : max;
    });
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: _biPanel, borderRadius: BorderRadius.circular(20)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('Evolução mensal',
                style: TextStyle(
                    color: _biInk, fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('Comparação entre receitas e despesas planejadas',
                style: TextStyle(color: _biMuted, fontSize: 11)),
            const SizedBox(height: 16),
            for (final _BudgetBiMonth month in _months)
              _monthBar(month, maxValue),
          ]),
    );
  }

  Widget _monthBar(_BudgetBiMonth month, double maxValue) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: <Widget>[
          SizedBox(
              width: 38,
              child: Text(month.shortLabel,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800))),
          Expanded(
              child: Column(children: <Widget>[
            _bar(month.revenue / maxValue, _biGreen,
                'R ${_currency(month.revenue)}'),
            const SizedBox(height: 3),
            _bar(month.expenses / maxValue, _biRed,
                'D ${_currency(month.expenses)}'),
          ])),
          const SizedBox(width: 8),
          SizedBox(
              width: 94,
              child: Text(_currency(month.balance),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: month.balance >= 0 ? _biGreen : _biRed))),
        ]),
      );

  Widget _bar(double ratio, Color color, String label) => LayoutBuilder(
        builder: (_, BoxConstraints constraints) => Stack(children: <Widget>[
          Container(
              height: 17,
              decoration: BoxDecoration(
                  color: const Color(0xFFE9EDF0),
                  borderRadius: BorderRadius.circular(5))),
          Container(
              height: 17,
              width: constraints.maxWidth * ratio.clamp(0, 1),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(5))),
          Positioned(
              left: 6,
              top: 2,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 9,
                      color: _biInk,
                      fontWeight: FontWeight.w700))),
        ]),
      );

  Widget _actions() => Wrap(
        alignment: WrapAlignment.end,
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          OutlinedButton.icon(
              onPressed: _processing ? null : _share,
              icon: const Icon(Icons.share_outlined),
              label: const Text('Compartilhar PDF')),
          OutlinedButton.icon(
              onPressed: _processing ? null : _print,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimir relatório')),
          FilledButton.icon(
              onPressed: _processing ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sair'),
              style: FilledButton.styleFrom(
                  backgroundColor: _biNavy, foregroundColor: Colors.white)),
        ],
      );
}

class _BudgetBiMonth {
  const _BudgetBiMonth({
    required this.reference,
    required this.revenue,
    required this.expenses,
    required this.received,
    required this.paid,
    required this.entries,
  });

  final String reference;
  final double revenue;
  final double expenses;
  final double received;
  final double paid;
  final int entries;

  double get balance => revenue - expenses;
  int get month => int.parse(reference.substring(5, 7));
  String get label => '${_monthNames[month - 1]} ${reference.substring(0, 4)}';
  String get shortLabel => _monthNames[month - 1].substring(0, 3).toUpperCase();
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

double _parseAmount(String value) {
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
