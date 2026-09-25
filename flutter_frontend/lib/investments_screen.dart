import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_client.dart';
import 'investment_portfolio_model.dart';

typedef InvestmentsApiUriBuilder = Uri Function(String path);
typedef DayTradeCapitalLauncher = Future<void> Function();
final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _quantity = NumberFormat('#,##0.######', 'pt_BR');
String _cash(num cents) => _money.format(cents / 100);
String _day(String date) =>
    DateFormat('dd/MM/yyyy').format(DateTime.parse(date));
String _today() => DateFormat('yyyy-MM-dd').format(DateTime.now());
String _id() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
double? _parse(String text) {
  var clean = text.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (clean.contains(',')) {
    clean = clean.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(clean)) {
    clean = clean.replaceAll('.', '');
  }
  final number = double.tryParse(clean);
  return number != null && number.isFinite ? number : null;
}

String? _positiveValue(String? value) {
  final n = _parse(value ?? '');
  return n != null && n > 0 && n <= 1e9
      ? null
      : 'Informe um valor maior que zero.';
}

String? _pastDate(String? value) {
  if (value == null || value.isEmpty || _optionalDate(value) != null)
    return 'Informe uma data válida.';
  return _iso(value).compareTo(_today()) > 0
      ? 'Use hoje ou uma data anterior.'
      : null;
}

const _tickers = {
  'ITSA4': 'Itaúsa PN',
  'ITSA3': 'Itaúsa ON',
  'PETR4': 'Petrobras PN',
  'PETR3': 'Petrobras ON',
  'VALE3': 'Vale ON',
  'ITUB4': 'Itaú Unibanco PN',
  'BBAS3': 'Banco do Brasil ON',
  'BBDC4': 'Bradesco PN',
  'B3SA3': 'B3 ON',
  'BPAC11': 'BTG Pactual units',
};
String _decimal(Object? value) => value == null ? '' : _quantity.format(value);
const _green = Color(0xFF126B54);
const _ink = Color(0xFF152D42);
const _labels = {
  'deposit': 'Aporte / compra',
  'withdraw': 'Resgate / venda',
  'income': 'Rendimento recebido',
  'valuation': 'Atualização de posição'
};

class InvestmentsScreen extends StatefulWidget {
  const InvestmentsScreen(
      {required this.apiUriBuilder,
      required this.sessionToken,
      required this.onOpenDayTradeCapital,
      required this.onOpenDayTradeDeposit,
      this.client,
      super.key});
  final ApiClient? client;
  final InvestmentsApiUriBuilder apiUriBuilder;
  final String sessionToken;
  final DayTradeCapitalLauncher onOpenDayTradeCapital;
  final DayTradeCapitalLauncher onOpenDayTradeDeposit;
  @override
  State<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends State<InvestmentsScreen> {
  ApiClient get _api => widget.client ?? apiClient;
  List<PortfolioRecord> _assets = [], _events = [];
  int _revision = 0;
  bool _loading = true, _writable = false, _saving = false;
  String? _error;
  String _filter = 'all', _cutoff = _today();
  Uri get _endpoint => kIsWeb
      ? Uri.base.resolve('/api/portfolio-v2')
      : Uri.parse(
          'https://ekt-ia-systems-flutter.eduardo-kat.chatgpt.site/api/portfolio-v2');
  Map<String, String> get _headers => {
        'authorization': 'Bearer ${widget.sessionToken}',
        'content-type': 'application/json'
      };
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _accept(Map<String, dynamic> body) {
    final data = body['data'] as Map<String, dynamic>;
    _assets = (data['assets'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    _events = (data['events'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    _revision = body['revision'] as int;
    _writable = body['writable'] == true;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get(_endpoint, headers: _headers);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200)
        throw Exception(
            body['message'] ?? 'Não foi possível carregar a carteira.');
      if (mounted) setState(() => _accept(body));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(
      List<PortfolioRecord> assets, List<PortfolioRecord> events) async {
    if (_saving) throw Exception('Aguarde a gravação em andamento.');
    setState(() => _saving = true);
    try {
      final response = await _api.put(_endpoint,
          headers: _headers,
          body: jsonEncode({
            'revision': _revision,
            'data': {'assets': assets, 'events': events}
          }));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200)
        throw Exception(body['message'] ?? 'Não foi possível salvar.');
      if (mounted) setState(() => _accept(body));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _assetForm(String kind, [PortfolioRecord? asset]) async {
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AssetDialog(
            kind: kind,
            asset: asset,
            onSave: (value, initial) async {
              final updated = [..._assets];
              final i = updated.indexWhere((a) => a['id'] == value['id']);
              if (i < 0) {
                updated.add(value);
              } else {
                updated[i] = value;
              }
              await _save(updated, [..._events, if (initial != null) initial]);
            }));
  }

  Future<void> _eventForm(PortfolioRecord asset, String type) async {
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _MovementDialog(
            asset: asset,
            type: type,
            onSave: (value) => _save(_assets, [..._events, value])));
  }

  Future<void> _removeEvent(PortfolioRecord e) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Excluir lançamento?'),
                content: const Text(
                    'A posição será recalculada. Para corrigir um lançamento, exclua-o e registre novamente com os dados corretos.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Voltar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Excluir'))
                ]));
    if (confirmed != true) return;
    try {
      await _save(_assets, _events.where((v) => v['id'] != e['id']).toList());
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _pickCutoff() async {
    final date = await showDatePicker(
        context: context,
        initialDate: DateTime.parse(_cutoff),
        firstDate: DateTime(1990),
        lastDate: DateTime.now());
    if (date != null)
      setState(() => _cutoff = DateFormat('yyyy-MM-dd').format(date));
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        _assets.where((a) => _filter == 'all' || a['kind'] == _filter).toList();
    final positions = visible
        .map((a) => PortfolioPosition.calculate(a, _events, _cutoff))
        .toList();
    int sum(int Function(PortfolioPosition) get) =>
        positions.fold(0, (s, p) => s + get(p));
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(title: const Text('Meus investimentos'), actions: [
        IconButton(
            tooltip: 'Atualizar carteira',
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh))
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: _load,
                            child: const Text('Tentar novamente'))
                      ])))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1180),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 16,
                                    runSpacing: 12,
                                    children: [
                                      const Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text('Sua carteira, por data',
                                                style: TextStyle(
                                                    fontSize: 26,
                                                    fontWeight: FontWeight.w800,
                                                    color: _ink)),
                                            SizedBox(height: 5),
                                            Text(
                                                'Renda fixa e renda variável • acompanhamento manual',
                                                style: TextStyle(fontSize: 14))
                                          ]),
                                      OutlinedButton.icon(
                                          onPressed: _pickCutoff,
                                          icon:
                                              const Icon(Icons.calendar_month),
                                          label: Text(
                                              'Posição em ${_day(_cutoff)}'))
                                    ]),
                                const SizedBox(height: 20),
                                Wrap(spacing: 12, runSpacing: 12, children: [
                                  _metric('Patrimônio informado',
                                      sum((p) => p.balance),
                                      dark: true),
                                  _metric('Aportes + custos',
                                      sum((p) => p.deposits)),
                                  _metric('Retiradas líquidas',
                                      sum((p) => p.withdrawals)),
                                  _metric('Resultado acumulado',
                                      sum((p) => p.result))
                                ]),
                                const SizedBox(height: 12),
                                const Text(
                                    'Resultado = patrimônio + retiradas + rendimentos recebidos − aportes e custos. Valores dependem das posições informadas; não incluem tributos futuros.',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF526476))),
                                const SizedBox(height: 24),
                                Wrap(spacing: 10, runSpacing: 10, children: [
                                  FilledButton.icon(
                                      onPressed: _writable && !_saving
                                          ? () => _assetForm('fixed')
                                          : null,
                                      icon: const Icon(Icons.add),
                                      label:
                                          const Text('Cadastrar renda fixa')),
                                  OutlinedButton.icon(
                                      onPressed: _writable && !_saving
                                          ? () => _assetForm('variable')
                                          : null,
                                      icon: const Icon(Icons.add_chart),
                                      label: const Text(
                                          'Cadastrar renda variável'))
                                ]),
                                const SizedBox(height: 20),
                                Wrap(spacing: 8, children: [
                                  for (final entry in {
                                    'all': 'Todos',
                                    'fixed': 'Renda fixa',
                                    'variable': 'Renda variável'
                                  }.entries)
                                    ChoiceChip(
                                        label: Text(entry.value),
                                        selected: _filter == entry.key,
                                        onSelected: (_) =>
                                            setState(() => _filter = entry.key))
                                ]),
                                const SizedBox(height: 12),
                                if (visible.isEmpty)
                                  Container(
                                      padding: const EdgeInsets.all(28),
                                      decoration: _box(),
                                      child: const Column(children: [
                                        Icon(
                                            Icons
                                                .account_balance_wallet_outlined,
                                            size: 40,
                                            color: _green),
                                        SizedBox(height: 12),
                                        Text('Comece pelo seu primeiro ativo',
                                            style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w700)),
                                        SizedBox(height: 8),
                                        Text(
                                            'Cadastre Tesouro Prefixado 2029 pelo C6 ou selecione ITSA4 e outros tickers. Depois registre o primeiro aporte.',
                                            textAlign: TextAlign.center)
                                      ])),
                                for (final asset in visible) _assetCard(asset),
                                const SizedBox(height: 24),
                                const Text('Histórico de movimentações',
                                    style: TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800,
                                        color: _ink)),
                                const SizedBox(height: 6),
                                Text(
                                    'Lançamentos até ${_day(_cutoff)} • filtros aplicados à carteira e ao histórico',
                                    style: const TextStyle(fontSize: 14)),
                                const SizedBox(height: 12),
                                _history(visible),
                                const SizedBox(height: 20),
                                const Text(
                                    'Registro de controle pessoal. Os lançamentos não enviam ordens ao C6 ou à B3. Cotações e posições são informadas pelo usuário.',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF526476))),
                                if (!_writable)
                                  const Padding(
                                      padding: EdgeInsets.only(top: 10),
                                      child: Text(
                                          'Perfil de consulta: alterações indisponíveis.')),
                              ])))),
    );
  }

  BoxDecoration _box() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFDCE4EA)));
  Widget _metric(String label, int cents, {bool dark = false}) => Container(
      width: 265,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: dark ? _ink : Colors.white,
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style:
                TextStyle(fontSize: 14, color: dark ? Colors.white70 : _ink)),
        const SizedBox(height: 8),
        Text(_cash(cents),
            style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                color: dark
                    ? Colors.white
                    : cents < 0
                        ? Colors.red.shade800
                        : _ink))
      ]));
  Widget _assetCard(PortfolioRecord a) {
    final p = PortfolioPosition.calculate(a, _events, _cutoff);
    final fixed = a['kind'] == 'fixed';
    return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: _box(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
                backgroundColor:
                    fixed ? const Color(0xFFE2F3EB) : const Color(0xFFE5EDFC),
                child: Icon(fixed ? Icons.account_balance : Icons.show_chart,
                    color: _ink)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(fixed ? a['name'] : '${a['ticker']} • ${a['name']}',
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800)),
                  Text(
                      '${fixed ? 'Renda fixa' : 'B3 • Renda variável'} · ${a['institution']}',
                      style: const TextStyle(fontSize: 14))
                ])),
            IconButton(
                tooltip: 'Editar cadastro',
                onPressed: _writable && !_saving
                    ? () => _assetForm(a['kind'], a)
                    : null,
                icon: const Icon(Icons.edit_outlined))
          ]),
          const SizedBox(height: 18),
          Wrap(spacing: 28, runSpacing: 12, children: [
            _detail('Posição', _cash(p.balance)),
            if (!fixed) _detail('Ações / cotas', _quantity.format(p.quantity)),
            if (!fixed) _detail('Preço de referência', _money.format(p.price)),
            _detail('Resultado acumulado', _cash(p.result)),
            _detail('Rendimentos recebidos', _cash(p.income)),
            if (fixed && a['maturity'] != '')
              _detail('Vencimento', _day(a['maturity'])),
            if (fixed && a['rate'] != null)
              _detail('Taxa cadastrada', '${_decimal(a['rate'])}% a.a.')
          ]),
          const SizedBox(height: 12),
          Text(
              p.priceDate == null
                  ? 'Sem posição registrada. Adicione o primeiro aporte.'
                  : '${p.marked ? 'Posição informada' : 'Referência do último lançamento'} em ${_day(p.priceDate!)}${fixed && !p.marked ? ' • atualize pelo extrato para refletir a valorização' : ''}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF526476))),
          if ((a['notes'] as String).isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(a['notes'])),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in {
              'deposit': fixed ? 'Novo aporte' : 'Comprar / aportar',
              'withdraw': fixed ? 'Resgatar / retirar' : 'Vender / retirar',
              'valuation': fixed ? 'Atualizar saldo' : 'Atualizar cotação',
              'income': 'Registrar rendimento'
            }.entries)
              OutlinedButton(
                  onPressed:
                      _writable && !_saving ? () => _eventForm(a, e.key) : null,
                  child: Text(e.value))
          ]),
        ]));
  }

  Widget _detail(String label, String value) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF526476))),
        Text(value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))
      ]);
  Widget _history(List<PortfolioRecord> visible) {
    final ids = visible.map((a) => a['id']).toSet();
    final events = _events
        .asMap()
        .entries
        .where((e) =>
            ids.contains(e.value['assetId']) &&
            (e.value['date'] as String).compareTo(_cutoff) <= 0)
        .toList()
      ..sort((a, b) {
        final d =
            (b.value['date'] as String).compareTo(a.value['date'] as String);
        return d == 0 ? b.key.compareTo(a.key) : d;
      });
    if (events.isEmpty)
      return Container(
          padding: const EdgeInsets.all(20),
          decoration: _box(),
          child: const Text('Nenhuma movimentação neste período.'));
    return Container(
        decoration: _box(),
        child: Column(children: [
          for (final entry in events)
            Builder(builder: (_) {
              final e = entry.value,
                  a = _assets
                      .firstWhere((a) => a['id'] == entry.value['assetId']);
              final variable = a['kind'] == 'variable';
              return ListTile(
                  isThreeLine: true,
                  leading: Icon(
                      e['type'] == 'withdraw'
                          ? Icons.north_east
                          : e['type'] == 'valuation'
                              ? Icons.update
                              : Icons.south_west,
                      color: _green),
                  title: Text(
                      '${_labels[e['type']]} • ${variable ? a['ticker'] : a['name']}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${_day(e['date'])} · ${variable && e['type'] != 'income' ? '${_quantity.format(e['quantity'])} ações/cotas · preço ${_money.format(e['price'])}' : _cash(e['amount'])}\n${e['fees'] > 0 ? 'Custos/impostos: ${_cash(e['fees'])} · ' : ''}${e['notes']}'),
                  trailing: _writable
                      ? IconButton(
                          tooltip: 'Excluir lançamento',
                          onPressed: _saving ? null : () => _removeEvent(e),
                          icon: const Icon(Icons.delete_outline))
                      : null);
            })
        ]));
  }
}

class _AssetDialog extends StatefulWidget {
  const _AssetDialog({required this.kind, required this.onSave, this.asset});
  final String kind;
  final PortfolioRecord? asset;
  final Future<void> Function(PortfolioRecord, PortfolioRecord?) onSave;
  @override
  State<_AssetDialog> createState() => _AssetDialogState();
}

class _AssetDialogState extends State<_AssetDialog> {
  final _form = GlobalKey<FormState>();
  final initialDate = TextEditingController(text: _day(_today()));
  final initialAmount = TextEditingController(),
      initialQuantity = TextEditingController(),
      initialPrice = TextEditingController(),
      initialFees = TextEditingController(text: '0,00');
  bool withInitial = true;
  late final TextEditingController name,
      ticker,
      institution,
      rate,
      maturity,
      notes;
  bool _busy = false;
  String? _error;
  bool get fixed => widget.kind == 'fixed';
  @override
  void initState() {
    super.initState();
    final a = widget.asset;
    name = TextEditingController(
        text: a?['name'] ?? (fixed ? 'Tesouro Prefixado 2029' : 'Itaúsa PN'));
    ticker =
        TextEditingController(text: a?['ticker'] ?? (fixed ? '' : 'ITSA4'));
    institution = TextEditingController(text: a?['institution'] ?? 'C6 Bank');
    rate = TextEditingController(text: _decimal(a?['rate']));
    maturity = TextEditingController(
        text: a?['maturity'] == null
            ? (fixed ? '01/01/2029' : '')
            : (a!['maturity'] == '' ? '' : _day(a['maturity'])));
    notes = TextEditingController(text: a?['notes'] ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      name,
      ticker,
      institution,
      rate,
      maturity,
      notes,
      initialDate,
      initialAmount,
      initialQuantity,
      initialPrice,
      initialFees
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = widget.asset?['id'] ?? _id();
      final initial = widget.asset == null && withInitial
          ? <String, dynamic>{
              'id': _id(),
              'assetId': id,
              'type': 'deposit',
              'date': _iso(initialDate.text),
              'amount': fixed
                  ? (_parse(initialAmount.text)! * 100).round()
                  : (_parse(initialQuantity.text)! *
                          _parse(initialPrice.text)! *
                          100)
                      .round(),
              'quantity': fixed ? 0 : _parse(initialQuantity.text)!,
              'price': fixed ? 0 : _parse(initialPrice.text)!,
              'fees': (_parse(initialFees.text)! * 100).round(),
              'notes': 'Aporte inicial',
            }
          : null;
      await widget.onSave({
        'id': id,
        'kind': widget.kind,
        'name': name.text.trim(),
        'ticker': fixed ? '' : ticker.text.trim().toUpperCase(),
        'institution': institution.text.trim(),
        'rate': fixed && rate.text.isNotEmpty ? _parse(rate.text) : null,
        'maturity':
            fixed && maturity.text.isNotEmpty ? _iso(maturity.text) : '',
        'notes': notes.text.trim()
      }, initial);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
          title: Text(
              '${widget.asset == null ? 'Cadastrar' : 'Editar'} ${fixed ? 'renda fixa' : 'renda variável'}'),
          content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (fixed)
                              const Padding(
                                  padding: EdgeInsets.only(bottom: 16),
                                  child: Text(
                                      'Tesouro Prefixado 2029 pelo C6 já preenchido. Você pode alterar os dados para cadastrar outro título.')),
                            if (!fixed) ...[
                              const Text(
                                  'Selecione um ticker ou digite outro ativo da B3.'),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, children: [
                                for (final e in _tickers.entries)
                                  ActionChip(
                                      label: Text('${e.key} · ${e.value}'),
                                      onPressed: _busy
                                          ? null
                                          : () => setState(() {
                                                ticker.text = e.key;
                                                name.text = e.value;
                                              }))
                              ]),
                              _input(ticker, 'Ticker B3',
                                  validator: (v) => RegExp(
                                              r'^[A-Za-z0-9]{4,12}$')
                                          .hasMatch(v ?? '')
                                      ? null
                                      : 'Informe o ticker, por exemplo ITSA4.',
                                  enabled: !_busy)
                            ],
                            _input(name,
                                fixed ? 'Nome do título' : 'Nome do ativo',
                                required: true, enabled: !_busy),
                            _input(institution, 'Banco / corretora',
                                required: true, enabled: !_busy),
                            if (fixed) ...[
                              _input(maturity, 'Vencimento (dd/mm/aaaa)',
                                  validator: _optionalDate, enabled: !_busy),
                              _input(
                                  rate, 'Taxa contratada (% ao ano) — opcional',
                                  numeric: true,
                                  validator: (v) => v!.isEmpty ||
                                          (_parse(v) != null &&
                                              _parse(v)! >= 0 &&
                                              _parse(v)! <= 1000)
                                      ? null
                                      : 'Taxa inválida.',
                                  enabled: !_busy),
                              const Text(
                                  'A taxa é uma referência cadastral. O saldo será acompanhado pelo valor do extrato; resgates antecipados variam com o preço de mercado.',
                                  style: TextStyle(fontSize: 13))
                            ],
                            if (widget.asset == null) ...[
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                      'Registrar o primeiro aporte agora'),
                                  value: withInitial,
                                  onChanged: _busy
                                      ? null
                                      : (v) =>
                                          setState(() => withInitial = v!)),
                              if (withInitial) ...[
                                _input(initialDate,
                                    'Data da aplicação / compra (dd/mm/aaaa)',
                                    enabled: !_busy, validator: _pastDate),
                                if (fixed)
                                  _input(initialAmount, 'Valor aplicado (R\$)',
                                      numeric: true,
                                      enabled: !_busy,
                                      validator: _positiveValue)
                                else ...[
                                  _input(initialQuantity,
                                      'Quantidade de ações / cotas',
                                      numeric: true,
                                      enabled: !_busy,
                                      validator: _positiveValue),
                                  _input(initialPrice,
                                      'Preço de compra por ação / cota (R\$)',
                                      numeric: true,
                                      enabled: !_busy,
                                      validator: _positiveValue),
                                ],
                                _input(initialFees, 'Custos já cobrados (R\$)',
                                    numeric: true,
                                    enabled: !_busy,
                                    validator: (v) => _parse(v ?? '') != null &&
                                            _parse(v!)! >= 0
                                        ? null
                                        : 'Valor inválido.'),
                              ],
                            ],
                            _input(notes, 'Observações (opcional)',
                                enabled: !_busy, maxLength: 1000),
                            if (_error != null)
                              Text(_error!,
                                  style: const TextStyle(color: Colors.red)),
                          ])))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Salvando…' : 'Salvar ativo'))
          ]));
}

class _MovementDialog extends StatefulWidget {
  const _MovementDialog(
      {required this.asset, required this.type, required this.onSave});
  final PortfolioRecord asset;
  final String type;
  final Future<void> Function(PortfolioRecord) onSave;
  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  final _form = GlobalKey<FormState>();
  final date = TextEditingController(text: _day(_today()));
  final amount = TextEditingController(),
      quantity = TextEditingController(),
      price = TextEditingController(),
      fees = TextEditingController(text: '0,00'),
      notes = TextEditingController();
  bool _busy = false;
  String? _error;
  bool get variable =>
      widget.asset['kind'] == 'variable' && widget.type != 'income';
  bool get valuation => widget.type == 'valuation';
  @override
  void dispose() {
    for (final c in [date, amount, quantity, price, fees, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _positive(String? v) {
    final n = _parse(v ?? '');
    return n != null && n.isFinite && n > 0 && n <= 1e9
        ? null
        : 'Informe um número maior que zero (use vírgula).';
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final q = variable && !valuation ? _parse(quantity.text)! : 0.0,
        p = variable ? _parse(price.text)! : 0.0;
    final cents =
        variable ? (q * p * 100).round() : (_parse(amount.text)! * 100).round();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave({
        'id': _id(),
        'assetId': widget.asset['id'],
        'type': widget.type,
        'date': _iso(date.text),
        'amount': cents,
        'quantity': q,
        'price': p,
        'fees': valuation ? 0 : (_parse(fees.text)! * 100).round(),
        'notes': notes.text.trim()
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
          title: Text(_labels[widget.type]!),
          content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                                '${widget.asset['name']}${widget.asset['ticker'] == '' ? '' : ' • ${widget.asset['ticker']}'}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            _input(date, 'Data (dd/mm/aaaa)', enabled: !_busy,
                                validator: (v) {
                              final error = _optionalDate(v);
                              if (v!.isEmpty || error != null)
                                return 'Informe uma data válida.';
                              return _iso(v).compareTo(_today()) > 0
                                  ? 'Use hoje ou uma data anterior.'
                                  : null;
                            }),
                            if (variable) ...[
                              if (!valuation)
                                _input(quantity, 'Quantidade de ações / cotas',
                                    numeric: true,
                                    validator: _positive,
                                    enabled: !_busy,
                                    onChanged: (_) => setState(() {})),
                              _input(
                                  price,
                                  valuation
                                      ? 'Cotação por ação / cota (R\$)'
                                      : 'Preço por ação / cota (R\$)',
                                  numeric: true,
                                  validator: _positive,
                                  enabled: !_busy,
                                  onChanged: (_) => setState(() {})),
                              if (!valuation)
                                Text(
                                    'Valor da operação: ${_cash(((_parse(quantity.text) ?? 0) * (_parse(price.text) ?? 0) * 100).round())}',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700))
                            ] else
                              _input(
                                  amount,
                                  valuation
                                      ? 'Saldo bruto total no extrato (R\$)'
                                      : 'Valor bruto (R\$)',
                                  numeric: true,
                                  enabled: !_busy,
                                  validator: (v) =>
                                      valuation && _parse(v ?? '') == 0
                                          ? null
                                          : _positive(v)),
                            if (!valuation)
                              _input(
                                  fees, 'Custos e impostos já cobrados (R\$)',
                                  numeric: true,
                                  enabled: !_busy,
                                  validator: (v) => _parse(v ?? '') != null &&
                                          _parse(v!)! >= 0
                                      ? null
                                      : 'Valor inválido.'),
                            const SizedBox(height: 8),
                            Text(
                                valuation
                                    ? 'Atualiza a referência de valor nessa data, sem registrar entrada ou saída de dinheiro.'
                                    : widget.type == 'income'
                                        ? 'Dividendos, JCP ou juros efetivamente recebidos fora da posição. Para reinvestir, registre também um novo aporte.'
                                        : widget.type == 'withdraw'
                                            ? 'Registre a venda ou o resgate efetivo. A quantidade ou o saldo será reduzido; o líquido desconta os custos informados.'
                                            : 'Registre a compra ou aplicação efetiva. O aporte inclui os custos informados.',
                                style: const TextStyle(fontSize: 13)),
                            _input(notes, 'Observações (opcional)',
                                enabled: !_busy, maxLength: 1000),
                            if (_error != null)
                              Text(_error!,
                                  style: const TextStyle(color: Colors.red)),
                          ])))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Salvando…' : 'Registrar'))
          ]));
}

Widget _input(TextEditingController controller, String label,
        {bool required = false,
        bool numeric = false,
        bool enabled = true,
        int maxLength = 160,
        String? Function(String?)? validator,
        ValueChanged<String>? onChanged}) =>
    Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: TextFormField(
            controller: controller,
            enabled: enabled,
            maxLength: maxLength,
            onChanged: onChanged,
            keyboardType: numeric
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                counterText: ''),
            validator: validator ??
                (v) => required && (v == null || v.trim().isEmpty)
                    ? 'Preencha este campo.'
                    : null));
String _iso(String value) => DateFormat('yyyy-MM-dd')
    .format(DateFormat('dd/MM/yyyy').parseStrict(value));
String? _optionalDate(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    _iso(value);
    return null;
  } catch (_) {
    return 'Use dd/mm/aaaa.';
  }
}
