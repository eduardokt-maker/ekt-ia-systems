import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_client.dart';

class BankExpenseNaturesDialog extends StatefulWidget {
  const BankExpenseNaturesDialog({super.key, required this.apiUriBuilder});

  final Uri Function(String path) apiUriBuilder;

  @override
  State<BankExpenseNaturesDialog> createState() =>
      _BankExpenseNaturesDialogState();
}

class _BankExpenseNaturesDialogState extends State<BankExpenseNaturesDialog> {
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _items = const [];
  int _index = 0;
  int _nextCode = 1;

  Map<String, dynamic>? get _current =>
      _items.isEmpty || _index >= _items.length ? null : _items[_index];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? keepId}) async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final response =
          await apiClient.get(widget.apiUriBuilder('/api/banking-lab/natures'));
      final body = response.body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw ApiFailure(body['message'] as String? ??
            'Não foi possível carregar as naturezas.');
      }
      if (!mounted) return;
      setState(() {
        _items = (body['natures'] as List<dynamic>)
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        _nextCode = (body['next_code'] as num?)?.toInt() ?? 1;
        final found = keepId == null
            ? -1
            : _items.indexWhere((item) => item['id'] == keepId);
        _index = found >= 0
            ? found
            : (_items.isEmpty ? 0 : _index.clamp(0, _items.length - 1));
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmEdit(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar natureza de despesa?'),
        content: Text(
            'Deseja liberar para edição o código ${item['code']} — ${item['name']}?'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmed == true) await _form(item);
  }

  Future<void> _form([Map<String, dynamic>? item]) async {
    final editing = item != null;
    final name = TextEditingController(text: '${item?['name'] ?? ''}');
    String validation = '';
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
                title: Text(
                    editing ? 'Editar natureza' : 'Nova natureza de despesa'),
                content: SizedBox(
                    width: 480,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          TextFormField(
                              initialValue: '${item?['code'] ?? _nextCode}',
                              readOnly: true,
                              decoration: const InputDecoration(
                                  labelText: 'Código automático',
                                  filled: true,
                                  prefixIcon: Icon(Icons.tag_rounded),
                                  border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          TextField(
                              controller: name,
                              autofocus: true,
                              textCapitalization: TextCapitalization.sentences,
                              onSubmitted: (_) => Navigator.pop(
                                  context, name.text.trim().isNotEmpty),
                              decoration: const InputDecoration(
                                  labelText: 'Natureza da despesa',
                                  hintText: 'Ex.: Educação, Saúde, Feira',
                                  prefixIcon: Icon(Icons.category_outlined),
                                  border: OutlineInputBorder())),
                          if (validation.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 8),
                            Text(validation,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                          ],
                        ])),
                actions: <Widget>[
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton.icon(
                      onPressed: () {
                        if (name.text.trim().isEmpty) {
                          update(() =>
                              validation = 'Informe a natureza da despesa.');
                          return;
                        }
                        Navigator.pop(context, true);
                      },
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Gravar')),
                ],
              )),
    );
    if (save != true || !mounted) return;
    try {
      final uri = widget.apiUriBuilder(editing
          ? '/api/banking-lab/natures/${item['id']}'
          : '/api/banking-lab/natures');
      final response = editing
          ? await apiClient.put(uri,
              body: jsonEncode(<String, String>{'name': name.text.trim()}))
          : await apiClient.post(uri,
              body: jsonEncode(<String, String>{'name': name.text.trim()}));
      final body = response.body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      if ((response.statusCode != 200 && response.statusCode != 201) ||
          body['ok'] != true) {
        throw ApiFailure(body['message'] as String? ??
            'Não foi possível gravar a natureza.');
      }
      await _load(keepId: editing ? item['id'] as int : body['id'] as int?);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir natureza de despesa?'),
        content: Text(
            'Confirma a exclusão do código ${item['code']} — ${item['name']}?'),
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
          widget.apiUriBuilder('/api/banking-lab/natures/${item['id']}'));
      if (response.statusCode != 200) {
        throw const ApiFailure('Não foi possível excluir a natureza.');
      }
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _current;
    return AlertDialog(
      title: const Row(children: <Widget>[
        Icon(Icons.category_rounded, color: Color(0xFF9A6B2F)),
        SizedBox(width: 9),
        Expanded(child: Text('Naturezas de despesa')),
      ]),
      content: SizedBox(
          width: 680,
          child: _loading
              ? const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                      if (_error.isNotEmpty) ...<Widget>[
                        Text(_error,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                        const SizedBox(height: 8),
                      ],
                      Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: const Color(0xFFF5EFE5),
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: const Color(0xFFD8C8AF))),
                          child: item == null
                              ? const Padding(
                                  padding: EdgeInsets.all(18),
                                  child: Text(
                                      'Nenhuma natureza cadastrada. Use “Acrescentar”.',
                                      textAlign: TextAlign.center))
                              : Row(children: <Widget>[
                                  SizedBox(
                                      width: 130,
                                      child: TextFormField(
                                          key: ValueKey(
                                              'nature-code-${item['id']}'),
                                          initialValue: '${item['code']}',
                                          readOnly: true,
                                          decoration: const InputDecoration(
                                              labelText: 'Código',
                                              filled: true,
                                              fillColor: Colors.white,
                                              border: OutlineInputBorder()))),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: TextFormField(
                                          key: ValueKey(
                                              'nature-name-${item['id']}'),
                                          initialValue: '${item['name']}',
                                          readOnly: true,
                                          decoration: const InputDecoration(
                                              labelText: 'Natureza da despesa',
                                              filled: true,
                                              fillColor: Colors.white,
                                              border: OutlineInputBorder()))),
                                ])),
                      const SizedBox(height: 10),
                      Wrap(spacing: 7, runSpacing: 7, children: <Widget>[
                        OutlinedButton.icon(
                            onPressed: _index > 0
                                ? () => setState(() => _index = 0)
                                : null,
                            icon: const Icon(Icons.first_page),
                            label: const Text('Primeiro')),
                        OutlinedButton.icon(
                            onPressed: _index > 0
                                ? () => setState(() => _index--)
                                : null,
                            icon: const Icon(Icons.chevron_left),
                            label: const Text('Anterior')),
                        OutlinedButton.icon(
                            onPressed: _index < _items.length - 1
                                ? () => setState(() => _index++)
                                : null,
                            icon: const Icon(Icons.chevron_right),
                            label: const Text('Próximo')),
                        OutlinedButton.icon(
                            onPressed: _index < _items.length - 1
                                ? () =>
                                    setState(() => _index = _items.length - 1)
                                : null,
                            icon: const Icon(Icons.last_page),
                            label: const Text('Último')),
                        FilledButton.tonalIcon(
                            onPressed:
                                item == null ? null : () => _confirmEdit(item),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Editar')),
                        FilledButton.tonalIcon(
                            onPressed:
                                item == null ? null : () => _delete(item),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Excluir')),
                        FilledButton.icon(
                            onPressed: () => _form(),
                            icon: const Icon(Icons.add),
                            label: const Text('Acrescentar')),
                      ]),
                      if (_items.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 9),
                        Text('Registro ${_index + 1} de ${_items.length}',
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF6F6558))),
                      ],
                    ])),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar')),
      ],
    );
  }
}
