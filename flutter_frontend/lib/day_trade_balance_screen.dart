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
      final response = await ApiClient.instance.post(
        widget.apiUriBuilder('/api/day-trade/balance'),
        body: {
          'date': DateFormat('yyyy-MM-dd').format(_date),
          'direction': _direction,
          'description': _description.text.trim(),
          'amount': _amount.text.trim()
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw Exception(
            body['message'] ?? 'Não foi possível salvar o lançamento.');
      }
      if (!mounted) return;
      setState(() {
        _summary = body;
        _error = null;
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
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  const Text('Novo lançamento',
                                                      style: TextStyle(
                                                          fontSize: 20,
                                                          fontWeight:
                                                              FontWeight.bold)),
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
                                                              : 'Salvar lançamento'))),
                                                ])))),
                                const SizedBox(height: 20),
                                const Text('Histórico de entradas e saídas',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                if (entries.isEmpty)
                                  const Card(
                                      child: Padding(
                                          padding: EdgeInsets.all(24),
                                          child: Text(
                                              'Nenhum lançamento. Registre o saldo inicial como uma entrada para começar.'))),
                                for (final dynamic entry in entries)
                                  Card(
                                      child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Wrap(
                                              spacing: 24,
                                              runSpacing: 12,
                                              alignment:
                                                  WrapAlignment.spaceBetween,
                                              children: [
                                                SizedBox(
                                                    width: 300,
                                                    child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                              '${entry['description']}',
                                                              style: const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize:
                                                                      16)),
                                                          Text(
                                                              '${DateFormat('dd/MM/yyyy').format(DateTime.parse(entry['date'] as String))} • ${entry['direction']}'),
                                                        ])),
                                                Text(
                                                    '${entry['direction'] == 'Entrada' ? '+' : '−'} ${_currency(entry['amount_cents'])}',
                                                    style: TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            entry['direction'] ==
                                                                    'Entrada'
                                                                ? const Color(
                                                                    0xFF16825D)
                                                                : const Color(
                                                                    0xFFB94747))),
                                                Text(
                                                    'Saldo: ${_currency(entry['balance_cents'])}'),
                                              ]))),
                              ]))),
                ),
    );
  }
}
