import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_client.dart';
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
      final response =
          await apiClient.get(widget.apiUriBuilder('/api/banking-lab'));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw ApiFailure(
            body['message'] as String? ?? 'Não foi possível carregar.');
      }
      if (mounted) setState(() => _files = body['files'] as List<dynamic>);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    if (_bank.text.trim().isEmpty || _account.text.trim().isEmpty) {
      _message('Informe o banco e a identificação da conta.', error: true);
      return;
    }
    final file = await pickStatementFile();
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final response = await apiClient.post(
        widget.apiUriBuilder('/api/banking-lab/upload'),
        body: <String, dynamic>{
          'bank_name': _bank.text.trim(),
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

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(text),
          backgroundColor:
              error ? const Color(0xFFB42332) : const Color(0xFF167A4B)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Controle bancário e cartões',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              Text('Laboratório de leitura de extratos',
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
                          const Text('Primeiro arquivo de testes',
                              style: TextStyle(
                                  fontSize: 23, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 6),
                          const Text(
                              'Envie o extrato original. Nesta etapa ele será preservado com identificação e hash de integridade, sem gerar movimentações.'),
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(children: <Widget>[
                                Row(children: <Widget>[
                                  Expanded(
                                    child: TextField(
                                      controller: _bank,
                                      decoration: const InputDecoration(
                                          labelText: 'Banco',
                                          hintText: 'Ex.: Santander',
                                          border: OutlineInputBorder()),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _account,
                                      decoration: const InputDecoration(
                                          labelText: 'Identificação da conta',
                                          hintText: 'Ex.: Pessoa física',
                                          border: OutlineInputBorder()),
                                    ),
                                  ),
                                ]),
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
                          Text('Arquivos armazenados (${_files.length})',
                              style: const TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w900)),
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
            onSelected: (action) =>
                action == 'download' ? _download(item) : _delete(item),
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'download', child: Text('Baixar original')),
              PopupMenuItem(value: 'delete', child: Text('Excluir')),
            ],
          ),
        ),
      );

  String _size(num bytes) => bytes >= 1048576
      ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(1)} KB';
}
