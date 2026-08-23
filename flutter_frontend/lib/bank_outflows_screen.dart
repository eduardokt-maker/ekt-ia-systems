import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api_client.dart';
import 'statement_lab_file.dart';

class BankOutflowsScreen extends StatefulWidget {
  const BankOutflowsScreen({super.key, required this.apiUriBuilder});
  final Uri Function(String path) apiUriBuilder;

  @override
  State<BankOutflowsScreen> createState() => _BankOutflowsScreenState();
}

class _BankOutflowsScreenState extends State<BankOutflowsScreen> {
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _search = TextEditingController();
  final _bank = TextEditingController();
  final _account = TextEditingController();
  bool _loading = true;
  bool _uploading = false;
  String _error = '';
  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> _files = const [];
  List<Map<String, dynamic>> _banks = const [];
  Map<String, dynamic>? _selectedBank;
  Map<String, dynamic> _summary = const {};
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _bank.dispose();
    _account.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = widget.apiUriBuilder('/api/banking-lab/outflows').replace(
          queryParameters: _search.text.trim().isEmpty
              ? null
              : <String, String>{'q': _search.text.trim()});
      final responses = await Future.wait(<Future<dynamic>>[
        apiClient.get(uri, timeout: const Duration(seconds: 90)),
        apiClient.get(widget.apiUriBuilder('/api/banking-lab')),
        apiClient.get(widget.apiUriBuilder('/api/banking-lab/banks')),
      ]);
      final response = responses[0];
      if (response.body.trim().isEmpty) {
        throw const ApiFailure('O servidor não concluiu a consulta.');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final filesBody = jsonDecode(responses[1].body) as Map<String, dynamic>;
      final banksBody = jsonDecode(responses[2].body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw ApiFailure(body['message'] as String? ??
            'Não foi possível carregar os lançamentos.');
      }
      if (!mounted) return;
      setState(() {
        final selectedId = _items.isNotEmpty && _selectedIndex < _items.length
            ? _items[_selectedIndex]['id']
            : null;
        _items = (body['outflows'] as List<dynamic>)
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        _files = (filesBody['files'] as List<dynamic>? ?? const [])
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        _banks = (banksBody['banks'] as List<dynamic>? ?? const [])
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        _summary = Map<String, dynamic>.from(body['summary'] as Map);
        final found = _items.indexWhere((value) => value['id'] == selectedId);
        _selectedIndex = found >= 0
            ? found
            : (_items.isEmpty ? 0 : _selectedIndex.clamp(0, _items.length - 1));
        if (_selectedBank == null && _files.isNotEmpty) {
          final file = _files.first;
          _selectedBank = _banks.cast<Map<String, dynamic>?>().firstWhere(
              (value) => value?['ispb'] == file['bank_ispb'],
              orElse: () => null);
          _bank.text = _selectedBank == null
              ? '${file['bank_name']}'
              : _bankLabel(_selectedBank!);
          _account.text = '${file['account_label']}';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    if (_selectedBank == null || _account.text.trim().isEmpty) {
      _message('Selecione o banco e informe a conta.', error: true);
      return;
    }
    final file = await pickStatementFile();
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final response = await apiClient.post(
        widget.apiUriBuilder('/api/banking-lab/upload'),
        body: <String, dynamic>{
          'bank_ispb': _selectedBank!['ispb'],
          'account_label': _account.text.trim(),
          'filename': file.name,
          'content_base64': base64Encode(file.bytes),
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 201 || body['ok'] != true) {
        throw ApiFailure(
            body['message'] as String? ?? 'Não foi possível enviar o arquivo.');
      }
      await _load();
      _message('Arquivo armazenado. As despesas foram atualizadas.');
    } catch (error) {
      _message('$error', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _downloadFile(Map<String, dynamic> item) async {
    try {
      final response = await apiClient.get(widget
          .apiUriBuilder('/api/banking-lab/files/${item['id']}/download'));
      if (response.statusCode != 200) {
        throw const ApiFailure('Não foi possível baixar o arquivo.');
      }
      downloadStatementFile(
          response.bodyBytes, '${item['filename']}', '${item['mime_type']}');
    } catch (error) {
      _message('$error', error: true);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(text),
          backgroundColor:
              error ? const Color(0xFFB42332) : const Color(0xFF167A4B)));
  }

  Map<String, dynamic>? get _selectedItem =>
      _items.isEmpty || _selectedIndex >= _items.length
          ? null
          : _items[_selectedIndex];

  void _select(int index) {
    if (index < 0 || index >= _items.length) return;
    setState(() => _selectedIndex = index);
  }

  String _bankLabel(Map<String, dynamic> bank) =>
      '${bank['bank_code'] ?? 'S/C'} • ${bank['short_name']}';

  String _size(num bytes) => bytes >= 1048576
      ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(1)} KB';

  Future<void> _openForm([Map<String, dynamic>? item]) async {
    final editing = item != null;
    final date =
        TextEditingController(text: '${item?['transaction_date'] ?? ''}');
    final posting =
        TextEditingController(text: '${item?['posting_date'] ?? ''}');
    final type = TextEditingController(text: '${item?['payment_type'] ?? ''}');
    final destination =
        TextEditingController(text: '${item?['destination'] ?? ''}');
    final description =
        TextEditingController(text: '${item?['description'] ?? ''}');
    final document =
        TextEditingController(text: '${item?['document_number'] ?? ''}');
    final amount = TextEditingController(
        text: item == null ? '' : '${item['amount']}'.replaceAll('.', ','));
    final notes = TextEditingController(text: '${item?['notes'] ?? ''}');
    String validation = '';
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, updateDialog) {
        Widget field(TextEditingController controller, String label,
                {int lines = 1, TextInputType? keyboard}) =>
            TextField(
                controller: controller,
                maxLines: lines,
                keyboardType: keyboard,
                decoration: InputDecoration(
                    labelText: label, border: const OutlineInputBorder()));
        return AlertDialog(
          title: Text(editing
              ? 'Editar despesa nº ${item['sequence_number']}'
              : 'Nova despesa'),
          content: SizedBox(
              width: 660,
              child: SingleChildScrollView(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(children: <Widget>[
                    Expanded(child: field(date, 'Data da despesa (DD/MM)')),
                    const SizedBox(width: 12),
                    Expanded(
                        child: field(posting, 'Data do lançamento (DD/MM)')),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: <Widget>[
                    Expanded(
                        child: field(
                            type, 'Forma do débito (Pix, Débito, TED...)')),
                    const SizedBox(width: 12),
                    Expanded(
                        child: field(amount, 'Valor (R\$)',
                            keyboard: const TextInputType.numberWithOptions(
                                decimal: true))),
                  ]),
                  const SizedBox(height: 12),
                  field(destination, 'Para quem foi / favorecido'),
                  const SizedBox(height: 12),
                  field(description, 'Descrição original'),
                  const SizedBox(height: 12),
                  field(document, 'Documento / referência'),
                  const SizedBox(height: 12),
                  field(notes, 'Observações', lines: 2),
                  if (editing) ...<Widget>[
                    const SizedBox(height: 12),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                            'Origem: ${item['source_filename']} • página ${item['source_page'] ?? '—'}',
                            style: const TextStyle(
                                color: Color(0xFF66727E), fontSize: 12))),
                  ],
                  if (validation.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(validation,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ))),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () {
                  if (date.text.trim().isEmpty ||
                      type.text.trim().isEmpty ||
                      destination.text.trim().isEmpty ||
                      amount.text.trim().isEmpty) {
                    updateDialog(() => validation =
                        'Preencha data, forma, favorecido e valor.');
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text('Salvar')),
          ],
        );
      }),
    );
    if (save != true || !mounted) return;
    final parsedAmount =
        double.tryParse(amount.text.replaceAll('.', '').replaceAll(',', '.')) ??
            0;
    final payload = <String, dynamic>{
      'transaction_date': date.text.trim(),
      'posting_date':
          posting.text.trim().isEmpty ? date.text.trim() : posting.text.trim(),
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
      if ((response.statusCode != 200 && response.statusCode != 201) ||
          body['ok'] != true) {
        throw ApiFailure(
            body['message'] as String? ?? 'Não foi possível salvar a despesa.');
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir despesa?'),
        content: Text(
            'O lançamento nº ${item['sequence_number']} será retirado da lista, sem alterar o PDF original.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final response = await apiClient.delete(
          widget.apiUriBuilder('/api/banking-lab/outflows/${item['id']}'));
      if (response.statusCode != 200) {
        throw const ApiFailure('Não foi possível excluir a despesa.');
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Extrato de despesas',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                Text('Cadastro dos débitos extraídos do arquivo',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
              ]),
          actions: <Widget>[
            IconButton(
                tooltip: 'Atualizar',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh))
          ],
        ),
        body: _loading
            ? const Center(
                child:
                    Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('Preparando os 50 lançamentos...')
              ]))
            : _error.isNotEmpty
                ? _errorView()
                : _content(),
      );

  Widget _errorView() => Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const Icon(Icons.receipt_long_outlined, size: 48),
          const SizedBox(height: 12),
          Text(_error, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente')),
        ]),
      ));

  Widget _content() => ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
        children: <Widget>[
          Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _topCards(),
                  const SizedBox(height: 12),
                  _recordForm(),
                  const SizedBox(height: 12),
                  Row(children: <Widget>[
                    const Expanded(
                        child: Text('Listagem das despesas',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w900))),
                    Text(
                        '${_summary['count'] ?? 0} registros • ${_money.format(_summary['total'] ?? 0)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB42332))),
                  ]),
                  const SizedBox(height: 7),
                  if (_items.isEmpty)
                    const Card(
                        child: Padding(
                            padding: EdgeInsets.all(26),
                            child: Text('Nenhuma despesa encontrada.')))
                  else
                    _recordsTable(),
                ]),
          ))
        ],
      );

  Widget _topCards() => LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        final width =
            compact ? constraints.maxWidth : (constraints.maxWidth - 12) / 2;
        return Wrap(spacing: 12, runSpacing: 12, children: <Widget>[
          SizedBox(
              width: width,
              child: Card(
                  child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(children: <Widget>[
                        const Icon(Icons.folder_copy_outlined, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text('Arquivos (${_files.length})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900))),
                        TextButton.icon(
                            onPressed: _uploading ? null : _upload,
                            icon: _uploading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.upload_file, size: 18),
                            label: const Text('Enviar')),
                      ]),
                      SizedBox(
                          height: 108,
                          child: _files.isEmpty
                              ? const Center(
                                  child: Text('Nenhum arquivo enviado.'))
                              : Scrollbar(
                                  child: ListView.separated(
                                      itemCount: _files.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (_, index) {
                                        final file = _files[index];
                                        return ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            leading: const Icon(
                                                Icons.picture_as_pdf_outlined),
                                            title: Text('${file['filename']}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            subtitle: Text(
                                                '${file['bank_name']} • ${_size(file['size_bytes'] as num)}'),
                                            trailing: IconButton(
                                                tooltip: 'Baixar original',
                                                onPressed: () =>
                                                    _downloadFile(file),
                                                icon: const Icon(
                                                    Icons.download_outlined,
                                                    size: 20)));
                                      }))),
                    ]),
              ))),
          SizedBox(
              width: width,
              child: Card(
                  child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Row(children: <Widget>[
                        Icon(Icons.account_balance_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('Banco e conta',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                      ]),
                      const SizedBox(height: 10),
                      DropdownMenu<Map<String, dynamic>>(
                          controller: _bank,
                          expandedInsets: EdgeInsets.zero,
                          enableFilter: true,
                          enableSearch: true,
                          label: const Text('Banco'),
                          hintText: 'Digite o banco ou código',
                          menuHeight: 320,
                          dropdownMenuEntries: _banks
                              .map((bank) =>
                                  DropdownMenuEntry<Map<String, dynamic>>(
                                      value: bank, label: _bankLabel(bank)))
                              .toList(),
                          onSelected: (value) =>
                              setState(() => _selectedBank = value)),
                      const SizedBox(height: 9),
                      TextField(
                          controller: _account,
                          decoration: const InputDecoration(
                              labelText: 'Identificação da conta',
                              prefixIcon: Icon(Icons.badge_outlined),
                              border: OutlineInputBorder(),
                              isDense: true)),
                    ]),
              ))),
        ]);
      });

  Widget _recordForm() {
    final item = _selectedItem;
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(children: <Widget>[
              Expanded(
                  child: Text(
                      item == null
                          ? 'Registro'
                          : 'Registro ${_selectedIndex + 1} de ${_items.length}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900))),
              if (item != null)
                Text('Nº ${item['sequence_number']}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 10),
            if (item == null)
              const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('Não há registro para apresentar.'))
            else ...<Widget>[
              LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth < 760 ? 1 : 4;
                final fieldWidth = columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 30) / 4;
                return Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
                  _readOnlyField(
                      'Data', '${item['transaction_date']}', fieldWidth),
                  _readOnlyField(
                      'Forma do débito', '${item['payment_type']}', fieldWidth),
                  _readOnlyField('Favorecido', '${item['destination']}',
                      columns == 1 ? fieldWidth : fieldWidth * 2 + 10),
                  _readOnlyField('Descrição', '${item['description']}',
                      columns == 1 ? fieldWidth : fieldWidth * 2 + 10),
                  _readOnlyField(
                      'Documento', '${item['document_number']}', fieldWidth),
                  _readOnlyField(
                      'Valor', _money.format(item['amount']), fieldWidth),
                  _readOnlyField(
                      'Arquivo / página',
                      '${item['source_filename']} • ${item['source_page'] ?? '—'}',
                      columns == 1 ? fieldWidth : fieldWidth * 2 + 10),
                  _readOnlyField('Observações', '${item['notes']}',
                      columns == 1 ? fieldWidth : fieldWidth * 2 + 10),
                ]);
              }),
              const SizedBox(height: 10),
              Wrap(spacing: 7, runSpacing: 7, children: <Widget>[
                OutlinedButton.icon(
                    onPressed: _selectedIndex > 0 ? () => _select(0) : null,
                    icon: const Icon(Icons.first_page),
                    label: const Text('Primeiro')),
                OutlinedButton.icon(
                    onPressed: _selectedIndex > 0
                        ? () => _select(_selectedIndex - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Anterior')),
                OutlinedButton.icon(
                    onPressed: _selectedIndex < _items.length - 1
                        ? () => _select(_selectedIndex + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Próximo')),
                OutlinedButton.icon(
                    onPressed: _selectedIndex < _items.length - 1
                        ? () => _select(_items.length - 1)
                        : null,
                    icon: const Icon(Icons.last_page),
                    label: const Text('Último')),
                FilledButton.tonalIcon(
                    onPressed: () => _openForm(item),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar')),
                FilledButton.tonalIcon(
                    onPressed: () => _delete(item),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Excluir')),
                FilledButton.icon(
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add),
                    label: const Text('Novo registro')),
              ]),
            ],
          ]),
    ));
  }

  Widget _readOnlyField(String label, String value, double width) => SizedBox(
        width: width,
        child: TextFormField(
            key: ValueKey('$label-$value'),
            initialValue: value,
            readOnly: true,
            decoration: InputDecoration(
                labelText: label,
                filled: true,
                border: const OutlineInputBorder(),
                isDense: true)),
      );

  Widget _recordsTable() => Card(
          child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columns: const <DataColumn>[
            DataColumn(label: Text('Nº')),
            DataColumn(label: Text('Data')),
            DataColumn(label: Text('Forma')),
            DataColumn(label: Text('Favorecido')),
            DataColumn(label: Text('Descrição')),
            DataColumn(label: Text('Documento')),
            DataColumn(label: Text('Valor'), numeric: true),
          ],
          rows: _items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return DataRow(
                selected: index == _selectedIndex,
                onSelectChanged: (_) => _select(index),
                cells: <DataCell>[
                  DataCell(Text('${item['sequence_number']}',
                      style: const TextStyle(fontWeight: FontWeight.w800))),
                  DataCell(Text('${item['transaction_date']}')),
                  DataCell(Text('${item['payment_type']}')),
                  DataCell(SizedBox(
                      width: 190,
                      child: Text('${item['destination']}',
                          overflow: TextOverflow.ellipsis))),
                  DataCell(SizedBox(
                      width: 210,
                      child: Text('${item['description']}',
                          overflow: TextOverflow.ellipsis))),
                  DataCell(Text('${item['document_number']}')),
                  DataCell(Text(_money.format(item['amount']),
                      style: const TextStyle(
                          color: Color(0xFFB42332),
                          fontWeight: FontWeight.w800))),
                ]);
          }).toList(),
        ),
      ));

}
