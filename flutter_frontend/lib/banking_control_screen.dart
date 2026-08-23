import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'bank_outflows_screen.dart';
import 'statement_lab_file.dart';

class BankingControlScreen extends StatefulWidget {
  const BankingControlScreen({super.key, required this.apiUriBuilder});
  final Uri Function(String path) apiUriBuilder;

  @override
  State<BankingControlScreen> createState() => _BankingControlScreenState();
}

class _BankingControlScreenState extends State<BankingControlScreen> {
  final _bank = TextEditingController();
  final _account = TextEditingController();
  bool _loading = true;
  bool _uploading = false;
  String _error = '';
  List<dynamic> _files = const [];
  List<Map<String, dynamic>> _banks = const [];
  Map<String, dynamic>? _selectedBank;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
      final responses = await Future.wait([
        apiClient.get(widget.apiUriBuilder('/api/banking-lab')),
        apiClient.get(widget.apiUriBuilder('/api/banking-lab/banks')),
      ]);
      final body = jsonDecode(responses[0].body) as Map<String, dynamic>;
      final bankBody = jsonDecode(responses[1].body) as Map<String, dynamic>;
      if (responses[0].statusCode != 200 || body['ok'] != true) {
        throw ApiFailure(
            body['message'] as String? ?? 'Não foi possível carregar.');
      }
      if (responses[1].statusCode != 200 || bankBody['ok'] != true) {
        throw ApiFailure(bankBody['message'] as String? ??
            'Não foi possível carregar os bancos.');
      }
      if (mounted) {
        setState(() {
          _files = body['files'] as List<dynamic>;
          _banks = (bankBody['banks'] as List<dynamic>)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    if (_selectedBank == null || _account.text.trim().isEmpty) {
      _message('Selecione um banco da lista oficial e informe a conta.',
          error: true);
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
      _message('Arquivo armazenado como base de testes.');
    } catch (error) {
      _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _download(Map<String, dynamic> item) async {
    try {
      final response = await apiClient.get(widget
          .apiUriBuilder('/api/banking-lab/files/${item['id']}/download'));
      if (response.statusCode != 200) {
        throw const ApiFailure('Não foi possível baixar o arquivo.');
      }
      downloadStatementFile(response.bodyBytes, item['filename'] as String,
          item['mime_type'] as String);
    } catch (error) {
      _message(error.toString(), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir arquivo de teste?'),
        content: Text(
            'O arquivo ${item['filename']} será removido definitivamente.'),
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
      final response = await apiClient
          .delete(widget.apiUriBuilder('/api/banking-lab/files/${item['id']}'));
      if (response.statusCode != 200) {
        throw const ApiFailure('Não foi possível excluir o arquivo.');
      }
      await _load();
      _message('Arquivo excluído.');
    } catch (error) {
      _message(error.toString(), error: true);
    }
  }

  Future<void> _study(Map<String, dynamic> item) async {
    _message('Lendo a estrutura do documento...');
    try {
      final response = await apiClient.get(
          widget
              .apiUriBuilder('/api/banking-lab/files/${item['id']}/structure'),
          timeout: const Duration(seconds: 60));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw ApiFailure(body['message'] as String? ??
            'Não foi possível estudar o arquivo.');
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _structureDialog(
            Map<String, dynamic>.from(body['structure'] as Map)),
      );
    } catch (error) {
      _message(error.toString(), error: true);
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

  void _openOutflows() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => BankOutflowsScreen(apiUriBuilder: widget.apiUriBuilder),
      ));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Controle bancário e cartões',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              Text('Repositório de extratos e despesas extraídas',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
            ],
          ),
          actions: <Widget>[
            IconButton(
                tooltip: 'Atualizar',
                onPressed: _load,
                icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1050),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (_error.isNotEmpty)
                            MaterialBanner(
                              content: Text(_error),
                              actions: <Widget>[
                                TextButton(
                                    onPressed: _load,
                                    child: const Text('Tentar novamente'))
                              ],
                            ),
                          const Text('Repositório de extratos bancários',
                              style: TextStyle(
                                  fontSize: 23, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 6),
                          const Text(
                              'Envie e preserve o documento original. Extratos Santander serão interpretados uma única vez e suas despesas serão gravadas separadamente no banco de dados.'),
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(children: <Widget>[
                                LayoutBuilder(builder: (context, constraints) {
                                  final compact = constraints.maxWidth < 650;
                                  final fieldWidth = compact
                                      ? constraints.maxWidth
                                      : (constraints.maxWidth - 12) / 2;
                                  return Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: <Widget>[
                                      SizedBox(
                                        width: fieldWidth,
                                        child:
                                            DropdownMenu<Map<String, dynamic>>(
                                          key:
                                              const Key('official-bank-picker'),
                                          controller: _bank,
                                          width: fieldWidth,
                                          enableFilter: true,
                                          enableSearch: true,
                                          requestFocusOnTap: true,
                                          label: const Text('Banco'),
                                          hintText: 'Digite o nome ou código',
                                          helperText:
                                              'Fonte: Banco Central do Brasil',
                                          leadingIcon:
                                              const Icon(Icons.account_balance),
                                          menuHeight: 390,
                                          dropdownMenuEntries: _banks
                                              .map((bank) => DropdownMenuEntry<
                                                      Map<String, dynamic>>(
                                                    value: bank,
                                                    label: _bankLabel(bank),
                                                  ))
                                              .toList(),
                                          onSelected: (bank) => setState(
                                              () => _selectedBank = bank),
                                        ),
                                      ),
                                      SizedBox(
                                        width: fieldWidth,
                                        child: TextField(
                                          controller: _account,
                                          decoration: const InputDecoration(
                                              labelText:
                                                  'Identificação da conta',
                                              hintText: 'Ex.: Pessoa física',
                                              border: OutlineInputBorder()),
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                                const SizedBox(height: 14),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: FilledButton.icon(
                                    key: const Key('upload-test-statement'),
                                    onPressed: _uploading ? null : _upload,
                                    icon: _uploading
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Icon(Icons.upload_file),
                                    label: Text(_uploading
                                        ? 'Enviando...'
                                        : 'Escolher e enviar extrato'),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                      'Formatos: PDF, CSV, OFX e XLSX • Limite: 15 MB',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF5F6873))),
                                ),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(children: <Widget>[
                            Expanded(
                              child: Text(
                                  'Arquivos armazenados (${_files.length})',
                                  style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900)),
                            ),
                            FilledButton.tonalIcon(
                              key: const Key('open-bank-outflows'),
                              onPressed: _files.isEmpty ? null : _openOutflows,
                              icon: const Icon(Icons.monitor_heart_outlined),
                              label: const Text('Gerenciar despesas Santander'),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          if (_files.isEmpty)
                            const Card(
                                child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                        'Nenhum arquivo enviado. Este espaço receberá nossa primeira base de testes.')))
                          else
                            ..._files.map((raw) => _fileCard(
                                Map<String, dynamic>.from(raw as Map))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      );

  Widget _fileCard(Map<String, dynamic> item) => Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
          title: Text(item['filename'] as String,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
              '${item['bank_name']} → ${item['account_label']}\n${_size(item['size_bytes'] as num)} • SHA-256 ${('${item['sha256']}').substring(0, 12)}… • Recebido'),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            tooltip: 'Ações do arquivo',
            onSelected: (action) {
              if (action == 'study') {
                _study(item);
              } else if (action == 'download') {
                _download(item);
              } else {
                _delete(item);
              }
            },
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'study', child: Text('Estudar estrutura')),
              PopupMenuItem(value: 'download', child: Text('Baixar original')),
              PopupMenuItem(value: 'delete', child: Text('Excluir')),
            ],
          ),
        ),
      );

  String _size(num bytes) => bytes >= 1048576
      ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(1)} KB';

  Widget _structureDialog(Map<String, dynamic> structure) {
    String joined(String key) =>
        (structure[key] as List<dynamic>? ?? const []).join(' • ');
    final pages = structure['pages'] as List<dynamic>? ?? const [];
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
              tooltip: 'Fechar',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close)),
          title: const Text('Estrutura do arquivo'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: <Widget>[
            Text(structure['filename'] as String,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              Chip(label: Text('${structure['document_type']}')),
              Chip(label: Text('${structure['page_count']} página(s)')),
              Chip(label: Text('${structure['line_count']} linha(s)')),
            ]),
            const SizedBox(height: 16),
            _structureSection('Títulos e seções', joined('headings')),
            _structureSection('Nomes de campos', joined('field_labels')),
            _structureSection('Datas encontradas', joined('dates_found')),
            _structureSection('Valores encontrados', joined('amounts_found')),
            _structureSection(
                'Referências de conta', joined('account_references')),
            const SizedBox(height: 8),
            const Text('Conteúdo reconhecido por página',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ...pages.map((raw) {
              final page = Map<String, dynamic>.from(raw as Map);
              return Card(
                child: ExpansionTile(
                  initiallyExpanded: pages.length == 1,
                  title: Text('Página ${page['number']}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${page['line_count']} linhas reconhecidas'),
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText('${page['text']}',
                          style: const TextStyle(height: 1.45)),
                    )
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _structureSection(String title, String content) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text(content.isEmpty ? 'Não identificado' : content),
            ],
          ),
        ),
      );

  String _bankLabel(Map<String, dynamic> bank) {
    final code = bank['bank_code'];
    return '${code ?? 'S/C'} • ${bank['short_name']}';
  }
}
