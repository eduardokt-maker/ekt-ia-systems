import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

typedef CapitalFlowApiUriBuilder = Uri Function(String path);

const _navy = Color(0xFF102A3A);
const _teal = Color(0xFF0F766E);
const _blue = Color(0xFF2563A8);
const _green = Color(0xFF16825D);
const _red = Color(0xFFB94747);
const _muted = Color(0xFF66737D);
const _canvas = Color(0xFFF3F6F9);
const _line = Color(0xFFDCE3E8);

enum CapitalPeriod { day, week, month, year, custom }

enum CapitalView { daily, accumulated, comparative, participation }

enum InvestorFilter { all, foreign, institutional }

class CapitalFlowEntryScreen extends StatefulWidget {
  const CapitalFlowEntryScreen({required this.apiUriBuilder, super.key});
  final CapitalFlowApiUriBuilder apiUriBuilder;

  @override
  State<CapitalFlowEntryScreen> createState() => _CapitalFlowEntryScreenState();
}

class _CapitalFlowEntryScreenState extends State<CapitalFlowEntryScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.post(
        widget.apiUriBuilder('/api/investments/login'),
        headers: const {'content-type': 'application/json; charset=utf-8'},
        body: jsonEncode(
            {'login': _login.text.trim(), 'password': _password.text}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (response.statusCode == 200 && body['ok'] == true) {
        await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => CapitalFlowScreen(
            apiUriBuilder: widget.apiUriBuilder,
            sessionToken: body['session_token'] as String? ?? '',
          ),
        ));
        return;
      }
      setState(() =>
          _error = body['message'] as String? ?? 'Não foi possível entrar.');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível conectar ao sistema.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: const Text('Fluxo de Capital'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: 430,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _line),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 24,
                      offset: Offset(0, 10))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CircleAvatar(
                    radius: 25,
                    backgroundColor: Color(0xFFE4F4F0),
                    child: Icon(Icons.swap_vert_circle_outlined,
                        color: _teal, size: 29),
                  ),
                  const SizedBox(height: 18),
                  const Text('Acesso ao BI',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text(
                    'Use as mesmas credenciais da área de investimentos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _login,
                    decoration: const InputDecoration(
                        labelText: 'Login',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _red)),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                        backgroundColor: _teal,
                        minimumSize: const Size.fromHeight(48)),
                    icon: _loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.login),
                    label: Text(_loading ? 'Entrando...' : 'Acessar BI'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class CapitalFlowScreen extends StatefulWidget {
  const CapitalFlowScreen(
      {required this.apiUriBuilder, required this.sessionToken, super.key});
  final CapitalFlowApiUriBuilder apiUriBuilder;
  final String sessionToken;

  @override
  State<CapitalFlowScreen> createState() => _CapitalFlowScreenState();
}

class _CapitalFlowScreenState extends State<CapitalFlowScreen> {
  CapitalPeriod _period = CapitalPeriod.month;
  CapitalView _view = CapitalView.daily;
  InvestorFilter _investor = InvestorFilter.all;
  DateTime _reference = DateTime.now();
  DateTimeRange? _custom;
  List<CapitalFlowRecord> _records = [];
  bool _loading = true;
  String? _error;
  String? _notice;
  String? _lastUpdated;
  List<String> _sources = [];

  Map<String, String> get _headers => {
        'authorization': 'Bearer ${widget.sessionToken}',
        'content-type': 'application/json; charset=utf-8'
      };

  DateTimeRange get _range {
    final d = DateTime(_reference.year, _reference.month, _reference.day);
    return switch (_period) {
      CapitalPeriod.day => DateTimeRange(start: d, end: d),
      CapitalPeriod.week => DateTimeRange(
          start: d.subtract(Duration(days: d.weekday - 1)),
          end: d.add(Duration(days: 7 - d.weekday))),
      CapitalPeriod.month => DateTimeRange(
          start: DateTime(d.year, d.month),
          end: DateTime(d.year, d.month + 1, 0)),
      CapitalPeriod.year =>
        DateTimeRange(start: DateTime(d.year), end: DateTime(d.year, 12, 31)),
      CapitalPeriod.custom => _custom ?? DateTimeRange(start: d, end: d),
    };
  }

  List<CapitalFlowRecord> get _filtered => _records.where((record) {
        return switch (_investor) {
          InvestorFilter.all => true,
          InvestorFilter.foreign => record.investorType == 'Estrangeiro',
          InvestorFilter.institutional =>
            record.investorType == 'Institucional brasileiro',
        };
      }).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final range = _range;
      final uri = widget.apiUriBuilder('/api/capital-flow').replace(
        queryParameters: {
          'from': _iso(range.start),
          'to': _iso(range.end),
          if (force) 'refresh': 'true',
        },
      );
      final response = await http.get(uri, headers: _headers);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 401) {
        throw Exception('Sessão expirada. Volte e entre novamente.');
      }
      if (response.statusCode != 200 || body['ok'] != true) {
        throw Exception(body['message'] as String? ??
            'Não foi possível carregar os dados.');
      }
      if (!mounted) return;
      setState(() {
        _records = ((body['items'] as List<dynamic>?) ?? [])
            .map((item) =>
                CapitalFlowRecord.fromJson(item as Map<String, dynamic>))
            .toList();
        _notice = body['notice'] as String?;
        _lastUpdated = body['last_updated'] as String?;
        _sources = ((body['sources'] as List<dynamic>?) ?? [])
            .map((item) => item.toString())
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

  Future<void> _chooseReference() async {
    if (_period == CapitalPeriod.custom) {
      final selected = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2010),
        lastDate: DateTime.now(),
        initialDateRange: _custom,
        locale: const Locale('pt', 'BR'),
      );
      if (selected != null) {
        _custom = selected;
        await _load();
      }
      return;
    }
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2010),
      lastDate: DateTime.now(),
      initialDate: _reference,
      locale: const Locale('pt', 'BR'),
    );
    if (selected != null) {
      _reference = selected;
      await _load();
    }
  }

  Future<void> _setPeriod(CapitalPeriod value) async {
    setState(() => _period = value);
    if (value == CapitalPeriod.custom && _custom == null) {
      await _chooseReference();
    } else {
      await _load();
    }
  }

  Future<void> _movePeriod(int direction) async {
    final current = _reference;
    _reference = switch (_period) {
      CapitalPeriod.day => current.add(Duration(days: direction)),
      CapitalPeriod.week => current.add(Duration(days: 7 * direction)),
      CapitalPeriod.month =>
        DateTime(current.year, current.month + direction, 1),
      CapitalPeriod.year => DateTime(current.year + direction, 1, 1),
      CapitalPeriod.custom => current,
    };
    if (_reference.isAfter(DateTime.now())) _reference = DateTime.now();
    await _load();
  }

  Future<void> _openEditor([CapitalFlowRecord? record]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => CapitalFlowEditor(
        apiUriBuilder: widget.apiUriBuilder,
        headers: _headers,
        record: record,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _delete(CapitalFlowRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir registro?'),
        content: Text(
            '${_date(record.date)} — ${record.investorType}\nEsta ação não pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;
    await http.delete(widget.apiUriBuilder('/api/capital-flow/${record.id}'),
        headers: _headers);
    await _load();
  }

  Future<void> _copyCsv() async {
    final buffer = StringBuffer(
        'Data;Dia da semana;Tipo de investidor;Entrada;Saída;Saldo líquido;Fonte\n');
    for (final item in _filtered) {
      buffer.writeln(
          '${_date(item.date)};${_weekday(item.date)};${item.investorType};${item.inflow.toStringAsFixed(2)};${item.outflow.toStringAsFixed(2)};${item.net.toStringAsFixed(2)};"${item.source.replaceAll('"', '""')}"');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Dados CSV copiados. Cole em um arquivo ou planilha.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final analytics = CapitalAnalytics(_filtered);
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fluxo de Capital — B3',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            Text('Entrada e saída por tipo de investidor',
                style: TextStyle(fontSize: 11, color: Color(0xFFBDD0DA))),
          ],
        ),
        actions: [
          IconButton(
              tooltip: 'Copiar CSV',
              onPressed: _filtered.isEmpty ? null : _copyCsv,
              icon: const Icon(Icons.download_outlined)),
          IconButton(
              tooltip: 'Atualizar',
              onPressed: _loading ? null : () => _load(force: true),
              icon: const Icon(Icons.sync)),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Novo lançamento'),
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final padding = compact ? 12.0 : 22.0;
          return RefreshIndicator(
            onRefresh: () => _load(force: true),
            child: ListView(
              padding: EdgeInsets.fromLTRB(padding, 16, padding, 100),
              children: [
                _hero(compact),
                const SizedBox(height: 14),
                _filters(compact),
                if (_loading) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(color: _teal),
                ] else if (_error != null) ...[
                  const SizedBox(height: 16),
                  _messagePanel(_error!, error: true),
                ] else ...[
                  const SizedBox(height: 14),
                  _coverageSummary(analytics),
                  const SizedBox(height: 14),
                  _kpis(analytics, constraints.maxWidth),
                  const SizedBox(height: 14),
                  if (_records.isEmpty)
                    _messagePanel(
                        'Ainda não existem dados disponíveis para o período selecionado.')
                  else ...[
                    _charts(analytics, compact),
                    const SizedBox(height: 14),
                    _table(compact),
                  ],
                ],
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _hero(bool compact) => Container(
        padding: EdgeInsets.all(compact ? 16 : 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_navy, Color(0xFF17555A)]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Acompanhamento diário do capital',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(
              'Período: ${_rangeLabel(_range)}',
              style: const TextStyle(color: Color(0xFFD5E7EA)),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _heroChip(Icons.schedule,
                    'Atualizado: ${_lastUpdated == null ? 'sem dados' : _dateTime(_lastUpdated!)}'),
                _heroChip(Icons.verified_outlined,
                    'Fonte: ${_sources.isEmpty ? 'a informar' : _sources.join(', ')}'),
                _heroChip(Icons.info_outline, 'Defasagem conforme a fonte'),
              ],
            ),
            if (_notice != null) ...[
              const SizedBox(height: 12),
              Text(_notice!,
                  style: const TextStyle(
                      color: Color(0xFFFFE3A8), fontSize: 12, height: 1.35)),
            ],
          ],
        ),
      );

  Widget _heroChip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: const Color(0x18FFFFFF),
            borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 15),
            const SizedBox(width: 6),
            Flexible(
                child: Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 11))),
          ],
        ),
      );

  Widget _filters(bool compact) => _Panel(
        title: 'Filtros',
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CapitalPeriod.values
                  .map((value) => ChoiceChip(
                        label: Text(_periodName(value)),
                        selected: _period == value,
                        onSelected: (_) => _setPeriod(value),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: 'Período anterior',
                  onPressed: _period == CapitalPeriod.custom
                      ? null
                      : () => _movePeriod(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _chooseReference,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      _period == CapitalPeriod.day
                          ? '${_date(_reference)} — ${_weekday(_reference)}'
                          : _rangeLabel(_range),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Próximo período',
                  onPressed: _period == CapitalPeriod.custom ||
                          !_range.end.isBefore(DateTime.now())
                      ? null
                      : () => _movePeriod(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<InvestorFilter>(
                    initialValue: _investor,
                    isDense: true,
                    decoration: const InputDecoration(
                        labelText: 'Tipo de investidor',
                        border: OutlineInputBorder()),
                    items: InvestorFilter.values
                        .map((value) => DropdownMenuItem(
                            value: value, child: Text(_investorName(value))))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _investor = value ?? InvestorFilter.all),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: CapitalView.values
                    .map((value) => ChoiceChip(
                          avatar: Icon(_viewIcon(value), size: 17),
                          label: Text(_viewName(value)),
                          selected: _view == value,
                          onSelected: (_) => setState(() => _view = value),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      );

  Widget _coverageSummary(CapitalAnalytics analytics) {
    final dates = analytics.records.map((item) => item.date).toSet().toList()
      ..sort();
    final coverage = dates.isEmpty
        ? 'Nenhum pregão disponível'
        : '${dates.length} pregão(ões) • ${_date(dates.first)} até ${_date(dates.last)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F4F2),
        border: Border.all(color: const Color(0xFFB9DDD6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Icon(Icons.date_range_outlined, color: _teal, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '$coverage • Visão: ${_viewName(_view)}',
            style: const TextStyle(
                color: _navy, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

  Widget _kpis(CapitalAnalytics a, double width) {
    final columns = width >= 1100
        ? 4
        : width >= 650
            ? 2
            : 1;
    final cards = [
      ('Entrada estrangeira (compras)', a.foreignIn, Icons.south_west, _green),
      ('Saída estrangeira (vendas)', a.foreignOut, Icons.north_east, _red),
      (
        'Saldo estrangeiro',
        a.foreignNet,
        _trend(a.foreignNet),
        _tone(a.foreignNet)
      ),
      (
        'Entrada institucional (compras)',
        a.institutionalIn,
        Icons.south_west,
        _green
      ),
      (
        'Saída institucional (vendas)',
        a.institutionalOut,
        Icons.north_east,
        _red
      ),
      (
        'Saldo institucional',
        a.institutionalNet,
        _trend(a.institutionalNet),
        _tone(a.institutionalNet)
      ),
      (
        'Saldo líquido geral',
        a.totalNet,
        _trend(a.totalNet),
        _tone(a.totalNet)
      ),
    ];
    final List<Widget> children = cards
        .map((card) => _KpiCard(
              title: card.$1,
              value: _currency(card.$2),
              fullValue: _currency(card.$2, compact: false),
              icon: card.$3,
              color: card.$4,
            ))
        .toList();
    children.add(_ParticipationCard(
        foreign: a.foreignShare, institutional: a.institutionalShare));
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: width < 650 ? 3.35 : 2.45,
      children: children,
    );
  }

  Widget _charts(CapitalAnalytics analytics, bool compact) {
    if (_view == CapitalView.participation) {
      return _Panel(
        title: 'Participação no volume negociado',
        subtitle: 'Distribuição percentual no período selecionado.',
        child: _ParticipationDetail(
          foreign: analytics.foreignShare,
          institutional: analytics.institutionalShare,
        ),
      );
    }
    if (_view == CapitalView.comparative) {
      return _Panel(
        title: 'Comparativo por investidor',
        subtitle: 'Compras, vendas e saldo no período selecionado.',
        child: _InvestorComparison(analytics: analytics),
      );
    }
    return _Panel(
      title: 'Evolução do fluxo',
      subtitle: _view == CapitalView.accumulated
          ? 'A linha mostra a evolução do saldo acumulado no período.'
          : 'As barras mostram o saldo líquido de cada pregão.',
      child: Column(
        children: [
          SizedBox(
            height: 260,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width:
                    math.max(compact ? 640 : 900, analytics.days.length * 54.0),
                child: CustomPaint(
                  painter: CapitalFlowChartPainter(
                    analytics.days,
                    showBars: _view == CapitalView.daily,
                    showLine: _view == CapitalView.accumulated,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 18, runSpacing: 8, children: [
            if (_view == CapitalView.daily) ...const [
              _Legend(color: _teal, label: 'Saldo estrangeiro'),
              _Legend(color: _blue, label: 'Saldo institucional'),
            ],
            if (_view == CapitalView.accumulated)
              const _Legend(color: _navy, label: 'Saldo acumulado geral'),
          ]),
        ],
      ),
    );
  }

  Widget _table(bool compact) => _Panel(
        title: 'Histórico detalhado',
        subtitle: '${_filtered.length} registro(s) no período selecionado.',
        child: compact
            ? Column(
                children:
                    _filtered.reversed.map((item) => _mobileRow(item)).toList())
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Data')),
                    DataColumn(label: Text('Investidor')),
                    DataColumn(label: Text('Entrada (compras)')),
                    DataColumn(label: Text('Saída (vendas)')),
                    DataColumn(label: Text('Saldo')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Ações')),
                  ],
                  rows: _filtered.reversed.map((item) {
                    return DataRow(cells: [
                      DataCell(
                          Text('${_date(item.date)}\n${_weekday(item.date)}')),
                      DataCell(Text(item.investorType)),
                      DataCell(Text(_currency(item.inflow, compact: false))),
                      DataCell(Text(_currency(item.outflow, compact: false))),
                      DataCell(Text(_currency(item.net, compact: false),
                          style: TextStyle(
                              color: _tone(item.net),
                              fontWeight: FontWeight.w700))),
                      DataCell(_status(item.net)),
                      DataCell(Row(children: [
                        IconButton(
                            tooltip: item.isOfficial
                                ? 'Dado oficial sincronizado'
                                : 'Editar',
                            onPressed: item.isOfficial
                                ? null
                                : () => _openEditor(item),
                            icon: const Icon(Icons.edit_outlined)),
                        IconButton(
                            tooltip: 'Excluir',
                            onPressed:
                                item.isOfficial ? null : () => _delete(item),
                            icon:
                                const Icon(Icons.delete_outline, color: _red)),
                      ])),
                    ]);
                  }).toList(),
                ),
              ),
      );

  Widget _mobileRow(CapitalFlowRecord item) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xFFF8FAFB),
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('${_date(item.date)} — ${_weekday(item.date)}',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            PopupMenuButton<String>(
              enabled: !item.isOfficial,
              onSelected: (action) =>
                  action == 'edit' ? _openEditor(item) : _delete(item),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(value: 'delete', child: Text('Excluir')),
              ],
            )
          ]),
          Text(item.investorType, style: const TextStyle(color: _muted)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('Compras\n${_currency(item.inflow)}')),
            Expanded(child: Text('Vendas\n${_currency(item.outflow)}')),
            Expanded(
                child: Text('Saldo\n${_currency(item.net)}',
                    style: TextStyle(
                        color: _tone(item.net), fontWeight: FontWeight.w700))),
          ]),
        ]),
      );

  Widget _status(double value) => Chip(
        visualDensity: VisualDensity.compact,
        label: Text(value > 0
            ? 'Entrada líquida'
            : value < 0
                ? 'Saída líquida'
                : 'Equilíbrio'),
        side: BorderSide(color: _tone(value).withValues(alpha: .35)),
        backgroundColor: _tone(value).withValues(alpha: .08),
        labelStyle: TextStyle(color: _tone(value), fontSize: 11),
      );

  Widget _messagePanel(String message, {bool error = false}) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: error ? _red : _line),
            borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Icon(error ? Icons.error_outline : Icons.inbox_outlined,
              color: error ? _red : _muted, size: 34),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (error) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'))
          ],
        ]),
      );
}

class CapitalFlowEditor extends StatefulWidget {
  const CapitalFlowEditor(
      {required this.apiUriBuilder,
      required this.headers,
      this.record,
      super.key});
  final CapitalFlowApiUriBuilder apiUriBuilder;
  final Map<String, String> headers;
  final CapitalFlowRecord? record;

  @override
  State<CapitalFlowEditor> createState() => _CapitalFlowEditorState();
}

class _CapitalFlowEditorState extends State<CapitalFlowEditor> {
  late DateTime _dateValue;
  late String _investorType;
  late final TextEditingController _inflow;
  late final TextEditingController _outflow;
  late final TextEditingController _source;
  late final TextEditingController _lag;
  late final TextEditingController _notes;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _dateValue = record?.date ?? DateTime.now();
    _investorType = record?.investorType ?? 'Estrangeiro';
    _inflow = TextEditingController(
        text: record == null ? '' : record.inflow.toStringAsFixed(2));
    _outflow = TextEditingController(
        text: record == null ? '' : record.outflow.toStringAsFixed(2));
    _source = TextEditingController(text: record?.source ?? 'Cadastro manual');
    _lag = TextEditingController(text: record?.sourceLag ?? 'D+2');
    _notes = TextEditingController(text: record?.notes ?? '');
  }

  @override
  void dispose() {
    for (final controller in [_inflow, _outflow, _source, _lag, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = jsonEncode({
        'reference_date': _iso(_dateValue),
        'investor_type': _investorType,
        'inflow': _inflow.text,
        'outflow': _outflow.text,
        'source': _source.text,
        'source_lag': _lag.text,
        'notes': _notes.text,
      });
      final uri = widget.record == null
          ? widget.apiUriBuilder('/api/capital-flow')
          : widget.apiUriBuilder('/api/capital-flow/${widget.record!.id}');
      final response = widget.record == null
          ? await http.post(uri, headers: widget.headers, body: payload)
          : await http.put(uri, headers: widget.headers, body: payload);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 300 || body['ok'] != true) {
        throw Exception(
            body['message'] as String? ?? 'Não foi possível salvar.');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            widget.record == null ? 'Novo lançamento' : 'Editar lançamento'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final value = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2010),
                    lastDate: DateTime.now(),
                    initialDate: _dateValue,
                    locale: const Locale('pt', 'BR'),
                  );
                  if (value != null) setState(() => _dateValue = value);
                },
                icon: const Icon(Icons.calendar_month),
                label: Text('${_date(_dateValue)} — ${_weekday(_dateValue)}'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _investorType,
                decoration: const InputDecoration(
                    labelText: 'Tipo de investidor',
                    border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(
                      value: 'Estrangeiro',
                      child: Text('Investidor estrangeiro')),
                  DropdownMenuItem(
                      value: 'Institucional brasileiro',
                      child: Text('Institucional brasileiro')),
                ],
                onChanged: (value) =>
                    setState(() => _investorType = value ?? _investorType),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _moneyField(_inflow, 'Entrada')),
                const SizedBox(width: 10),
                Expanded(child: _moneyField(_outflow, 'Saída')),
              ]),
              const SizedBox(height: 12),
              TextField(
                  controller: _source,
                  decoration: const InputDecoration(
                      labelText: 'Fonte', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: _lag,
                  decoration: const InputDecoration(
                      labelText: 'Defasagem (ex.: D+2)',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Observação', border: OutlineInputBorder())),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: _red)),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: _teal),
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Salvando...' : 'Salvar')),
        ],
      );

  Widget _moneyField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
            labelText: label,
            prefixText: 'R\$ ',
            border: const OutlineInputBorder()),
      );
}

class CapitalFlowRecord {
  const CapitalFlowRecord(
      {required this.id,
      required this.date,
      required this.investorType,
      required this.inflow,
      required this.outflow,
      required this.net,
      required this.source,
      required this.sourceLag,
      required this.notes});
  final int id;
  final DateTime date;
  final String investorType;
  final double inflow;
  final double outflow;
  final double net;
  final String source;
  final String sourceLag;
  final String notes;
  bool get isOfficial => source.startsWith('B3 —');

  factory CapitalFlowRecord.fromJson(Map<String, dynamic> json) =>
      CapitalFlowRecord(
        id: (json['id'] as num).toInt(),
        date: DateTime.parse(json['reference_date'] as String),
        investorType: json['investor_type'] as String,
        inflow: (json['inflow'] as num).toDouble(),
        outflow: (json['outflow'] as num).toDouble(),
        net: (json['net'] as num).toDouble(),
        source: json['source'] as String? ?? '',
        sourceLag: json['source_lag'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
      );
}

class CapitalDay {
  const CapitalDay(
      this.date, this.foreignNet, this.institutionalNet, this.accumulated);
  final DateTime date;
  final double foreignNet;
  final double institutionalNet;
  final double accumulated;
}

class CapitalAnalytics {
  CapitalAnalytics(this.records) {
    for (final record in records) {
      if (record.investorType == 'Estrangeiro') {
        foreignIn += record.inflow;
        foreignOut += record.outflow;
      } else {
        institutionalIn += record.inflow;
        institutionalOut += record.outflow;
      }
    }
    final grouped = <DateTime, List<CapitalFlowRecord>>{};
    for (final record in records) {
      grouped.putIfAbsent(record.date, () => []).add(record);
    }
    var accumulated = 0.0;
    for (final date in grouped.keys.toList()..sort()) {
      final rows = grouped[date]!;
      final foreign = rows
          .where((r) => r.investorType == 'Estrangeiro')
          .fold(0.0, (sum, r) => sum + r.net);
      final institutional = rows
          .where((r) => r.investorType != 'Estrangeiro')
          .fold(0.0, (sum, r) => sum + r.net);
      accumulated += foreign + institutional;
      days.add(CapitalDay(date, foreign, institutional, accumulated));
    }
  }
  final List<CapitalFlowRecord> records;
  double foreignIn = 0;
  double foreignOut = 0;
  double institutionalIn = 0;
  double institutionalOut = 0;
  final List<CapitalDay> days = [];
  double get foreignNet => foreignIn - foreignOut;
  double get institutionalNet => institutionalIn - institutionalOut;
  double get totalNet => foreignNet + institutionalNet;
  double get totalVolume =>
      foreignIn + foreignOut + institutionalIn + institutionalOut;
  double get foreignShare =>
      totalVolume == 0 ? 0 : (foreignIn + foreignOut) / totalVolume * 100;
  double get institutionalShare => totalVolume == 0 ? 0 : 100 - foreignShare;
}

class CapitalFlowChartPainter extends CustomPainter {
  CapitalFlowChartPainter(this.days,
      {required this.showBars, required this.showLine});
  final List<CapitalDay> days;
  final bool showBars;
  final bool showLine;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    const left = 44.0;
    const bottom = 30.0;
    final chart =
        Rect.fromLTRB(left, 10, size.width - 10, size.height - bottom);
    final values = days
        .expand((d) => [d.foreignNet, d.institutionalNet, d.accumulated])
        .toList();
    final maxValue = math.max(1.0, values.map((v) => v.abs()).reduce(math.max));
    final zeroY = chart.center.dy;
    final grid = Paint()
      ..color = _line
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(chart.left, zeroY), Offset(chart.right, zeroY), grid);
    final groupWidth = chart.width / days.length;
    final barWidth = math.min(12.0, groupWidth * .23);
    final foreignPaint = Paint()..color = _teal;
    final institutionalPaint = Paint()..color = _blue;
    final linePaint = Paint()
      ..color = _navy
      ..strokeWidth = 2.3
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final x = chart.left + groupWidth * (i + .5);
      double y(double value) => zeroY - value / maxValue * chart.height * .43;
      if (showBars) {
        canvas.drawRect(
            Rect.fromLTRB(x - barWidth - 1, math.min(zeroY, y(day.foreignNet)),
                x - 1, math.max(zeroY, y(day.foreignNet))),
            foreignPaint);
        canvas.drawRect(
            Rect.fromLTRB(x + 1, math.min(zeroY, y(day.institutionalNet)),
                x + barWidth + 1, math.max(zeroY, y(day.institutionalNet))),
            institutionalPaint);
      }
      final point = Offset(x, y(day.accumulated));
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
      if (days.length <= 16 || i.isEven) {
        final painter = TextPainter(
          text: TextSpan(
              text:
                  '${day.date.day.toString().padLeft(2, '0')}/${day.date.month.toString().padLeft(2, '0')}',
              style: const TextStyle(color: _muted, fontSize: 9)),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
            canvas, Offset(x - painter.width / 2, size.height - bottom + 8));
      }
    }
    if (showLine) canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CapitalFlowChartPainter oldDelegate) =>
      oldDelegate.days != days ||
      oldDelegate.showBars != showBars ||
      oldDelegate.showLine != showLine;
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!,
                style: const TextStyle(color: _muted, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          child,
        ]),
      );
}

class _KpiCard extends StatelessWidget {
  const _KpiCard(
      {required this.title,
      required this.value,
      required this.fullValue,
      required this.icon,
      required this.color});
  final String title;
  final String value;
  final String fullValue;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: fullValue,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border(top: BorderSide(color: color, width: 3)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x0B000000),
                    blurRadius: 12,
                    offset: Offset(0, 5))
              ]),
          child: Row(children: [
            Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 21)),
            const SizedBox(width: 11),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 11)),
                  const SizedBox(height: 3),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                ])),
          ]),
        ),
      );
}

class _ParticipationCard extends StatelessWidget {
  const _ParticipationCard(
      {required this.foreign, required this.institutional});
  final double foreign;
  final double institutional;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: const Border(top: BorderSide(color: _blue, width: 3))),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Participação no volume',
                  style: TextStyle(color: _muted, fontSize: 11)),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Row(children: [
                  if (foreign > 0)
                    Expanded(
                        flex: math.max(1, foreign.round()),
                        child: Container(height: 8, color: _teal)),
                  if (institutional > 0)
                    Expanded(
                        flex: math.max(1, institutional.round()),
                        child: Container(height: 8, color: _blue)),
                  if (foreign + institutional == 0)
                    Expanded(child: Container(height: 8, color: _line)),
                ]),
              ),
              const SizedBox(height: 7),
              Text(
                  'Estrangeiro ${_percent(foreign)} • Institucional ${_percent(institutional)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
      );
}

class _ParticipationDetail extends StatelessWidget {
  const _ParticipationDetail(
      {required this.foreign, required this.institutional});
  final double foreign;
  final double institutional;

  @override
  Widget build(BuildContext context) => Column(children: [
        _participationRow('Investidor estrangeiro', foreign, _teal),
        const SizedBox(height: 16),
        _participationRow('Institucional brasileiro', institutional, _blue),
      ]);

  Widget _participationRow(String label, double value, Color color) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(_percent(value),
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 7),
        LinearProgressIndicator(
          minHeight: 12,
          value: (value / 100).clamp(0, 1),
          color: color,
          backgroundColor: _line,
          borderRadius: BorderRadius.circular(8),
        ),
      ]);
}

class _InvestorComparison extends StatelessWidget {
  const _InvestorComparison({required this.analytics});
  final CapitalAnalytics analytics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final children = [
            _comparisonCard('Estrangeiro', analytics.foreignIn,
                analytics.foreignOut, analytics.foreignNet, _teal),
            _comparisonCard(
                'Institucional brasileiro',
                analytics.institutionalIn,
                analytics.institutionalOut,
                analytics.institutionalNet,
                _blue),
          ];
          return constraints.maxWidth < 650
              ? Column(children: [
                  children.first,
                  const SizedBox(height: 10),
                  children.last
                ])
              : Row(children: [
                  Expanded(child: children.first),
                  const SizedBox(width: 10),
                  Expanded(child: children.last)
                ]);
        },
      );

  Widget _comparisonCard(String label, double inflow, double outflow,
          double net, Color color) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .06),
          border: Border.all(color: color.withValues(alpha: .25)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text('Compras: ${_currency(inflow)}'),
          Text('Vendas: ${_currency(outflow)}'),
          const SizedBox(height: 5),
          Text('Saldo: ${_currency(net)}',
              style: TextStyle(
                  color: _tone(net),
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
        ]),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
      ]);
}

String _iso(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
String _weekday(DateTime value) => const [
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado',
      'Domingo'
    ][value.weekday - 1];
String _dateTime(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return '${_date(parsed)} às ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
}

String _rangeLabel(DateTimeRange range) => range.start == range.end
    ? _date(range.start)
    : '${_date(range.start)} até ${_date(range.end)}';
String _periodName(CapitalPeriod value) => switch (value) {
      CapitalPeriod.day => 'Dia',
      CapitalPeriod.week => 'Semana',
      CapitalPeriod.month => 'Mês',
      CapitalPeriod.year => 'Ano',
      CapitalPeriod.custom => 'Personalizado',
    };
String _viewName(CapitalView value) => switch (value) {
      CapitalView.daily => 'Fluxo diário',
      CapitalView.accumulated => 'Saldo acumulado',
      CapitalView.comparative => 'Comparativo',
      CapitalView.participation => 'Participação',
    };
IconData _viewIcon(CapitalView value) => switch (value) {
      CapitalView.daily => Icons.bar_chart,
      CapitalView.accumulated => Icons.show_chart,
      CapitalView.comparative => Icons.compare_arrows,
      CapitalView.participation => Icons.donut_large,
    };
String _investorName(InvestorFilter value) => switch (value) {
      InvestorFilter.all => 'Todos',
      InvestorFilter.foreign => 'Estrangeiro',
      InvestorFilter.institutional => 'Institucional brasileiro',
    };
String _percent(double value) =>
    '${value.toStringAsFixed(2).replaceAll('.', ',')}%';
String _currency(double value, {bool compact = true}) {
  final sign = value < 0
      ? '- '
      : value > 0
          ? '+ '
          : '';
  final absolute = value.abs();
  if (compact && absolute >= 1000000000) {
    return '${sign}R\$ ${(absolute / 1000000000).toStringAsFixed(2).replaceAll('.', ',')} bi';
  }
  if (compact && absolute >= 1000000) {
    return '${sign}R\$ ${(absolute / 1000000).toStringAsFixed(2).replaceAll('.', ',')} mi';
  }
  if (compact && absolute >= 1000) {
    return '${sign}R\$ ${(absolute / 1000).toStringAsFixed(1).replaceAll('.', ',')} mil';
  }
  final fixed = absolute.toStringAsFixed(2).split('.');
  final chars = fixed[0].split('').reversed.toList();
  final groups = <String>[];
  for (var i = 0; i < chars.length; i += 3) {
    groups.add(chars.skip(i).take(3).toList().reversed.join());
  }
  return '${sign}R\$ ${groups.reversed.join('.')},${fixed[1]}';
}

Color _tone(double value) => value > 0
    ? _green
    : value < 0
        ? _red
        : _muted;
IconData _trend(double value) => value > 0
    ? Icons.trending_up
    : value < 0
        ? Icons.trending_down
        : Icons.trending_flat;
