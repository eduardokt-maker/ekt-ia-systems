import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api_client.dart';

class BankOutflowsScreen extends StatefulWidget {
  const BankOutflowsScreen({super.key, required this.apiUriBuilder});
  final Uri Function(String path) apiUriBuilder;

  @override
  State<BankOutflowsScreen> createState() => _BankOutflowsScreenState();
}

class _BankOutflowsScreenState extends State<BankOutflowsScreen> {
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _search = TextEditingController();
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _summary = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final uri = widget.apiUriBuilder('/api/banking-lab/outflows').replace(
          queryParameters: _search.text.trim().isEmpty
              ? null
              : <String, String>{'q': _search.text.trim()});
      final response = await apiClient.get(uri, timeout: const Duration(seconds: 90));
      if (response.body.trim().isEmpty) throw const ApiFailure('O servidor não concluiu a consulta.');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw ApiFailure(body['message'] as String? ?? 'Não foi possível carregar os lançamentos.');
      }
      if (!mounted) return;
      setState(() {
        _items = (body['outflows'] as List<dynamic>)
            .map((value) => Map<String, dynamic>.from(value as Map)).toList();
        _summary = Map<String, dynamic>.from(body['summary'] as Map);
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([Map<String, dynamic>? item]) async {
    final editing = item != null;
    final date = TextEditingController(text: '${item?['transaction_date'] ?? ''}');
    final posting = TextEditingController(text: '${item?['posting_date'] ?? ''}');
    final type = TextEditingController(text: '${item?['payment_type'] ?? ''}');
    final destination = TextEditingController(text: '${item?['destination'] ?? ''}');
    final description = TextEditingController(text: '${item?['description'] ?? ''}');
    final document = TextEditingController(text: '${item?['document_number'] ?? ''}');
    final amount = TextEditingController(text: item == null ? '' : '${item['amount']}'.replaceAll('.', ','));
    final notes = TextEditingController(text: '${item?['notes'] ?? ''}');
    String validation = '';
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, updateDialog) {
        Widget field(TextEditingController controller, String label,
                {int lines = 1, TextInputType? keyboard}) =>
            TextField(controller: controller, maxLines: lines, keyboardType: keyboard,
                decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()));
        return AlertDialog(
          title: Text(editing ? 'Editar despesa nº ${item['sequence_number']}' : 'Nova despesa'),
          content: SizedBox(width: 660, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(children: <Widget>[
                Expanded(child: field(date, 'Data da despesa (DD/MM)')),
                const SizedBox(width: 12),
                Expanded(child: field(posting, 'Data do lançamento (DD/MM)')),
              ]),
              const SizedBox(height: 12),
              Row(children: <Widget>[
                Expanded(child: field(type, 'Forma do débito (Pix, Débito, TED...)')),
                const SizedBox(width: 12),
                Expanded(child: field(amount, 'Valor (R\$)', keyboard: const TextInputType.numberWithOptions(decimal: true))),
              ]),
              const SizedBox(height: 12), field(destination, 'Para quem foi / favorecido'),
              const SizedBox(height: 12), field(description, 'Descrição original'),
              const SizedBox(height: 12), field(document, 'Documento / referência'),
              const SizedBox(height: 12), field(notes, 'Observações', lines: 2),
              if (editing) ...<Widget>[
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft,
                    child: Text('Origem: ${item['source_filename']} • página ${item['source_page'] ?? '—'}',
                        style: const TextStyle(color: Color(0xFF66727E), fontSize: 12))),
              ],
              if (validation.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(validation, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ))),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () {
              if (date.text.trim().isEmpty || type.text.trim().isEmpty ||
                  destination.text.trim().isEmpty || amount.text.trim().isEmpty) {
                updateDialog(() => validation = 'Preencha data, forma, favorecido e valor.');
                return;
              }
              Navigator.pop(context, true);
            }, child: const Text('Salvar')),
          ],
        );
      }),
    );
    if (save != true || !mounted) return;
    final parsedAmount = double.tryParse(amount.text.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    final payload = <String, dynamic>{
      'transaction_date': date.text.trim(),
      'posting_date': posting.text.trim().isEmpty ? date.text.trim() : posting.text.trim(),
      'payment_type': type.text.trim(),
      'destination': destination.text.trim(),
      'description': description.text.trim(),
      'document_number': document.text.trim(),
      'amount': parsedAmount,
      'notes': notes.text.trim(),
    };
    try {
      final uri = widget.apiUriBuilder(editing
          ? '/api/banking-lab/outflows/${item['id']}'
          : '/api/banking-lab/outflows');
      final response = editing
          ? await apiClient.put(uri, body: jsonEncode(payload))
          : await apiClient.post(uri, body: jsonEncode(payload));
      final body = response.body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      if ((response.statusCode != 200 && response.statusCode != 201) || body['ok'] != true) {
        throw ApiFailure(body['message'] as String? ?? 'Não foi possível salvar a despesa.');
      }
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir despesa?'),
        content: Text('O lançamento nº ${item['sequence_number']} será retirado da lista, sem alterar o PDF original.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final response = await apiClient.delete(widget.apiUriBuilder('/api/banking-lab/outflows/${item['id']}'));
      if (response.statusCode != 200) throw const ApiFailure('Não foi possível excluir a despesa.');
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('Extrato de despesas', style: TextStyle(fontWeight: FontWeight.w900)),
        Text('Cadastro dos débitos extraídos do arquivo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
      ]),
      actions: <Widget>[IconButton(tooltip: 'Atualizar', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _openForm(), icon: const Icon(Icons.add), label: const Text('Nova despesa')),
    body: _loading
        ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            CircularProgressIndicator(), SizedBox(height: 14), Text('Preparando os 50 lançamentos...')]))
        : _error.isNotEmpty ? _errorView() : _content(),
  );

  Widget _errorView() => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      const Icon(Icons.receipt_long_outlined, size: 48),
      const SizedBox(height: 12), Text(_error, textAlign: TextAlign.center),
      const SizedBox(height: 14), FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Tentar novamente')),
    ]),
  ));

  Widget _content() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
    children: <Widget>[Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1180),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Card(color: Theme.of(context).colorScheme.primaryContainer, child: Padding(
          padding: const EdgeInsets.all(18),
          child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 20, runSpacing: 14, children: <Widget>[
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                const Text('Lançamentos extraídos', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                Text('${_summary['count'] ?? 0} despesas gravadas e disponíveis para conferência'),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                const Text('Total apresentado'),
                Text(_money.format(_summary['total'] ?? 0), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFB42332))),
              ]),
            ]),
        )),
        const SizedBox(height: 12),
        TextField(controller: _search, textInputAction: TextInputAction.search, onSubmitted: (_) => _load(),
          decoration: InputDecoration(labelText: 'Pesquisar favorecido, descrição ou forma',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(tooltip: 'Pesquisar', onPressed: _load, icon: const Icon(Icons.arrow_forward)),
            border: const OutlineInputBorder())),
        const SizedBox(height: 12),
        if (_items.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(26), child: Text('Nenhuma despesa encontrada.')))
        else
          ..._items.map(_expenseRow),
      ]),
    ))],
  );

  Widget _expenseRow(Map<String, dynamic> item) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: InkWell(onTap: () => _openForm(item), borderRadius: BorderRadius.circular(12), child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: <Widget>[
        SizedBox(width: 42, child: Text('${item['sequence_number']}', style: const TextStyle(fontSize: 16, color: Color(0xFF687582), fontWeight: FontWeight.w800))),
        CircleAvatar(radius: 20, backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: Icon(_icon('${item['payment_type']}'), size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('${item['destination']}', style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text('${item['transaction_date']} • ${item['payment_type']} • ${item['description']}', maxLines: 2,
              overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF5F6873))),
          if ('${item['document_number']}'.isNotEmpty)
            Text('Documento: ${item['document_number']}', style: const TextStyle(fontSize: 12, color: Color(0xFF78828C))),
        ])),
        const SizedBox(width: 12),
        Text(_money.format(item['amount']), style: const TextStyle(color: Color(0xFFB42332), fontWeight: FontWeight.w900)),
        PopupMenuButton<String>(tooltip: 'Ações',
          onSelected: (value) => value == 'edit' ? _openForm(item) : _delete(item),
          itemBuilder: (_) => const <PopupMenuEntry<String>>[
            PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar'))),
            PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Excluir'))),
          ]),
      ]),
    )),
  );

  IconData _icon(String type) {
    if (type.contains('Pix')) return Icons.pix;
    if (type.contains('Cartão')) return Icons.credit_card;
    if (type.contains('Boleto')) return Icons.receipt_long;
    if (type.contains('Débito automático')) return Icons.sync_alt;
    if (type.contains('IOF') || type.contains('Juros')) return Icons.percent;
    return Icons.south_east;
  }
}
