import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_client.dart';

class DayTradeBalanceScreen extends StatefulWidget {
  const DayTradeBalanceScreen({required this.apiUriBuilder, super.key});
  final Uri Function(String) apiUriBuilder;

  @override
  State<DayTradeBalanceScreen> createState() => _DayTradeBalanceScreenState();
}

class _DayTradeBalanceScreenState extends State<DayTradeBalanceScreen> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  DateTime _date = DateTime.now();
  String _direction = 'Entrada';
  Map<String, dynamic>? _summary;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  int? _editingId;
  final _formAnchor = GlobalKey();

  void _edit(Map<String, dynamic> entry) {
    setState(() {
      _editingId = entry['id'] as int;
      _date = DateTime.parse(entry['date'] as String);
      _direction = entry['direction'] as String;
      _description.text = entry['description'] as String;
      final cents = entry['amount_cents'] as int;
      _amount.text =
          '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';
    });
    Scrollable.ensureVisible(_formAnchor.currentContext!,
        duration: const Duration(milliseconds: 300));
  }

  void _cancelEdit() {
    setState(() {
      _editingId = null;
      _date = DateTime.now();
      _direction = 'Entrada';
      _description.clear();
      _amount.clear();
    });
    _form.currentState?.reset();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance
          .get(widget.apiUriBuilder('/api/day-trade/balance'));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw Exception(
            body['message'] ?? 'Não foi possível carregar o saldo.');
      }
      if (mounted) setState(() => _summary = body);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final payload = {
        if (_editingId != null) 'id': _editingId,
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'direction': _direction,
        'description': _description.text.trim(),
        'amount': _amount.text.trim()
      };
      final uri = widget.apiUriBuilder('/api/day-trade/balance');
      final response = _editingId == null
          ? await ApiClient.instance.post(uri, body: payload)
          : await ApiClient.instance.patch(uri, body: payload);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw Exception(
            body['message'] ?? 'Não foi possível salvar o lançamento.');
      }
      if (!mounted) return;
      setState(() {
        _summary = body;
        _error = null;
        _editingId = null;
      });
      _description.clear();
      _amount.clear();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lançamento salvo. Saldo atualizado.')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _currency(dynamic cents) => _money.format((cents as num? ?? 0) / 100);

  Widget _metric(String title, String key, Color color) => SizedBox(
        width: 240,
        child: Card(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title),
                      const SizedBox(height: 8),
                      Text(_currency(_summary?[key]),
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: color)),
                    ]))),
      );

  Widget _buildHistoryReport(List<dynamic> entries) {
    const ink = Color(0xFF102A3A);
    const muted = Color(0xFF65727C);
    const primary =
        TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ink);
    const secondary = TextStyle(fontSize: 14, height: 1.45, color: muted);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDCE3E8))),
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                color: const Color(0xFFF0F4F6),
                child: Row(children: [
                  const Expanded(child: Text('Data / Tipo', style: primary)),
                  if (!compact) ...[
                    const SizedBox(
                        width: 160,
                        child: Text('Valor',
                            textAlign: TextAlign.right, style: primary)),
                    const SizedBox(
                        width: 180,
                        child: Text('Saldo acumulado',
                            textAlign: TextAlign.right, style: primary)),
                    const SizedBox(width: 112),
                  ],
                ]),
              ),
              if (entries.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                        'Nenhum lançamento. Registre o saldo inicial como uma entrada para começar.',
                        style: secondary)),
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: Color(0xFFE5EAF0)),
                Builder(builder: (context) {
                  final entry = Map<String, dynamic>.from(entries[i] as Map);
                  final incoming = entry['direction'] == 'Entrada';
                  final details = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${DateFormat('dd/MM/yyyy').format(DateTime.parse(entry['date'] as String))} • ${entry['direction']}',
                            style: primary),
                        const SizedBox(height: 5),
                        Text('${entry['description']}', style: secondary),
                      ]);
                  final value = Text(
                      '${incoming ? '+' : '−'} ${_currency(entry['amount_cents'])}',
                      textAlign: TextAlign.right,
                      style: primary.copyWith(
                          color: incoming
                              ? const Color(0xFF16825D)
                              : const Color(0xFFB94747)));
                  final balance = Text(_currency(entry['balance_cents']),
                      textAlign: TextAlign.right, style: primary);
                  final edit = TextButton.icon(
                      onPressed: _saving ? null : () => _edit(entry),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Alterar',
                          style: TextStyle(fontSize: 14)));
                  return Container(
                    color: i.isEven ? Colors.white : const Color(0xFFFAFBFC),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                                details,
                                const SizedBox(height: 14),
                                Wrap(spacing: 24, runSpacing: 12, children: [
                                  Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('Valor', style: secondary),
                                        value
                                      ]),
                                  Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('Saldo acumulado',
                                            style: secondary),
                                        balance
                                      ]),
                                  edit,
                                ]),
                              ])
                        : Row(children: [
                            Expanded(child: details),
                            SizedBox(width: 160, child: value),
                            SizedBox(width: 180, child: balance),
                            SizedBox(
                                width: 112,
                                child: Align(
                                    alignment: Alignment.centerRight,
                                    child: edit)),
                          ]),
                  );
                }),
              ],
              const Divider(height: 1, color: Color(0xFFDCE3E8)),
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 20,
                      runSpacing: 10,
                      children: [
                        Text(
                            '${entries.length} lançamento${entries.length == 1 ? '' : 's'}',
                            style: secondary),
                        Text(
                            'Saldo atual: ${_currency(_summary?['balance_cents'])}',
                            style: primary),
                      ])),
            ]);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = (_summary?['entries'] as List<dynamic>?) ?? [];
    return Scaffold(
      backgroundColor: const Color(0xFFF4F1EA),
      appBar: AppBar(
          title: const Text('Controle de Saldo'),
          backgroundColor: const Color(0xFF102A3A),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
                tooltip: 'Atualizar saldo',
                onPressed: _loading || _saving ? null : _load,
                icon: const Icon(Icons.refresh)),
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
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(spacing: 12, runSpacing: 12, children: [
                                  _metric('Saldo atual', 'balance_cents',
                                      const Color(0xFF102A3A)),
                                  _metric('Total de entradas', 'incoming_cents',
                                      const Color(0xFF16825D)),
                                  _metric('Total de saídas', 'outgoing_cents',
                                      const Color(0xFFB94747)),
                                ]),
                                const SizedBox(height: 20),
                                Card(
                                    child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Form(
                                            key: _form,
                                            child: Column(
                                                key: _formAnchor,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Text(
                                                      _editingId == null
                                                          ? 'Novo lançamento'
                                                          : 'Alterar lançamento',
                                                      style: const TextStyle(
                                                          fontSize: 20,
                                                          fontWeight:
                                                              FontWeight.bold)),
                                                  if (_editingId != null)
                                                    Align(
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: TextButton(
                                                            onPressed: _saving
                                                                ? null
                                                                : _cancelEdit,
                                                            child: const Text(
                                                                'Cancelar alteração'))),
                                                  const SizedBox(height: 16),
                                                  Wrap(
                                                      spacing: 16,
                                                      runSpacing: 16,
                                                      crossAxisAlignment:
                                                          WrapCrossAlignment
                                                              .center,
                                                      children: [
                                                        SizedBox(
                                                            width: 200,
                                                            child: DropdownButtonFormField<
                                                                    String>(
                                                                key: ValueKey(
                                                                    '$_editingId:$_direction'),
                                                                initialValue:
                                                                    _direction,
                                                                decoration:
                                                                    const InputDecoration(
                                                                        labelText:
                                                                            'Tipo'),
                                                                items: const [
                                                                  DropdownMenuItem(
                                                                      value:
                                                                          'Entrada',
                                                                      child: Text(
                                                                          'Entrada')),
                                                                  DropdownMenuItem(
                                                                      value:
                                                                          'Saída',
                                                                      child: Text(
                                                                          'Saída'))
                                                                ],
                                                                onChanged: _saving
                                                                    ? null
                                                                    : (value) =>
                                                                        setState(() =>
                                                                            _direction =
                                                                                value!))),
                                                        OutlinedButton.icon(
                                                            onPressed: _saving
                                                                ? null
                                                                : () async {
                                                                    final selected = await showDatePicker(
                                                                        context:
                                                                            context,
                                                                        initialDate:
                                                                            _date,
                                                                        firstDate:
                                                                            DateTime(
                                                                                2000),
                                                                        lastDate:
                                                                            DateTime(2100));
                                                                    if (selected !=
                                                                            null &&
                                                                        mounted)
                                                                      setState(() =>
                                                                          _date =
                                                                              selected);
                                                                  },
                                                            icon: const Icon(Icons
                                                                .calendar_month),
                                                            label: Text(DateFormat(
                                                                    'dd/MM/yyyy')
                                                                .format(
                                                                    _date))),
                                                      ]),
                                                  const SizedBox(height: 16),
                                                  TextFormField(
                                                      controller: _description,
                                                      enabled: !_saving,
                                                      maxLength: 200,
                                                      decoration:
                                                          const InputDecoration(
                                                              labelText:
                                                                  'Descrição'),
                                                      validator: (value) =>
                                                          value == null ||
                                                                  value
                                                                      .trim()
                                                                      .isEmpty
                                                              ? 'Informe a descrição.'
                                                              : null),
                                                  const SizedBox(height: 8),
                                                  TextFormField(
                                                      controller: _amount,
                                                      enabled: !_saving,
                                                      keyboardType:
                                                          const TextInputType
                                                              .numberWithOptions(
                                                              decimal: true),
                                                      decoration:
                                                          const InputDecoration(
                                                              labelText:
                                                                  'Valor',
                                                              prefixText:
                                                                  'R\$ ',
                                                              hintText: '0,00'),
                                                      validator: (value) =>
                                                          value == null ||
                                                                  value
                                                                      .trim()
                                                                      .isEmpty
                                                              ? 'Informe o valor.'
                                                              : null),
                                                  const SizedBox(height: 20),
                                                  Align(
                                                      alignment:
                                                          Alignment.centerLeft,
                                                      child: FilledButton.icon(
                                                          onPressed: _saving
                                                              ? null
                                                              : _save,
                                                          icon: const Icon(Icons
                                                              .save_outlined),
                                                          label: Text(_saving
                                                              ? 'Salvando…'
                                                              : _editingId ==
                                                                      null
                                                                  ? 'Salvar lançamento'
                                                                  : 'Salvar alteração'))),
                                                ])))),
                                const SizedBox(height: 20),
                                const Text('Histórico de entradas e saídas',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                _buildHistoryReport(entries),
                              ]))),
                ),
    );
  }
}
