import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_client.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({
    required this.apiUriBuilder,
    required this.currentUser,
    super.key,
  });

  final Uri Function(String path) apiUriBuilder;
  final Map<String, dynamic> currentUser;

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<Map<String, dynamic>> _users = const [];
  bool _loading = false;
  String _message = '';

  bool get _isAdmin => widget.currentUser['role'] == 'admin';

  @override
  void initState() {
    super.initState();
    if (_isAdmin) _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _message = '';
    });
    try {
      final response = await ApiClient.instance
          .get(widget.apiUriBuilder('/api/admin/users'));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (response.statusCode == 200 && body['users'] is List) {
        setState(() {
          _users = (body['users'] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
        });
      } else {
        setState(() => _message = body['message'] as String? ??
            'Não foi possível carregar os usuários.');
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final password = TextEditingController();
    final confirmation = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Alterar minha senha'),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: current,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha atual',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nova senha',
                  helperText: 'Use pelo menos 12 caracteres.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmation,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmar nova senha',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (password.text != confirmation.text) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('A confirmação da senha não confere.')));
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Alterar senha'),
          ),
        ],
      ),
    );
    if (submitted != true || !mounted) return;
    try {
      final response = await ApiClient.instance.post(
        widget.apiUriBuilder('/api/auth/change-password'),
        body: {
          'current_password': current.text,
          'new_password': password.text,
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (response.statusCode == 200) {
        ApiClient.instance.clearSession();
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.verified_user_outlined,
                color: Color(0xFF087A55)),
            title: const Text('Senha alterada'),
            content: const Text(
                'Por segurança, entre novamente utilizando a nova senha.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Continuar'),
              ),
            ],
          ),
        );
        if (mounted) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/investimentos', (_) => false);
        }
      } else {
        _showMessage(
            body['message'] as String? ?? 'Não foi possível alterar a senha.');
      }
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<void> _editUser([Map<String, dynamic>? user]) async {
    final creating = user == null;
    final name =
        TextEditingController(text: user?['display_name'] as String? ?? '');
    final login = TextEditingController(text: user?['login'] as String? ?? '');
    final password = TextEditingController();
    var role = user?['role'] as String? ?? 'viewer';
    var active = user?['active'] as bool? ?? true;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(creating ? 'Novo usuário' : 'Editar usuário'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                        labelText: 'Nome', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: login,
                    enabled: creating,
                    decoration: const InputDecoration(
                        labelText: 'Login', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(
                        labelText: 'Perfil', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(
                          value: 'admin', child: Text('Administrador')),
                      DropdownMenuItem(
                          value: 'operator', child: Text('Operador')),
                      DropdownMenuItem(
                          value: 'viewer', child: Text('Consulta')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => role = value ?? role),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText:
                          creating ? 'Senha inicial' : 'Nova senha (opcional)',
                      helperText: 'Use pelo menos 12 caracteres.',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (!creating)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Usuário ativo'),
                      value: active,
                      onChanged: (value) =>
                          setDialogState(() => active = value),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(creating ? 'Criar usuário' : 'Salvar alterações'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted) return;
    try {
      final response = creating
          ? await ApiClient.instance.post(
              widget.apiUriBuilder('/api/admin/users'),
              body: {
                'display_name': name.text,
                'login': login.text,
                'password': password.text,
                'role': role,
              },
            )
          : await ApiClient.instance.patch(
              widget.apiUriBuilder('/api/admin/users/${user['id']}'),
              body: {
                'display_name': name.text,
                'role': role,
                'active': active,
                if (password.text.isNotEmpty) 'new_password': password.text,
              },
            );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 || response.statusCode == 201) {
        await _loadUsers();
      } else {
        _showMessage(
            body['message'] as String? ?? 'Não foi possível salvar o usuário.');
      }
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  void _showMessage(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.currentUser['display_name'] as String? ??
        widget.currentUser['login'] as String? ??
        'Usuário';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuários e acessos'),
        backgroundColor: const Color(0xFF0F2235),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _editUser(),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Novo usuário'),
            )
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 14,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const CircleAvatar(
                          radius: 28,
                          child: Icon(Icons.person_outline, size: 30),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w800)),
                            Text(
                                widget.currentUser['role_label'] as String? ??
                                    '',
                                style:
                                    const TextStyle(color: Color(0xFF5F6873))),
                          ],
                        ),
                        const SizedBox(width: 20),
                        FilledButton.icon(
                          onPressed: _changePassword,
                          icon: const Icon(Icons.password_outlined),
                          label: const Text('Alterar minha senha'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isAdmin) ...[
                  const SizedBox(height: 20),
                  const Text('Usuários cadastrados',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  if (_loading) const LinearProgressIndicator(),
                  if (_message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_message,
                          style: const TextStyle(color: Color(0xFFB42332))),
                    ),
                  ..._users.map((user) => Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: user['active'] == true
                                ? const Color(0xFFE4F7EF)
                                : const Color(0xFFF1F2F4),
                            child: Icon(
                              user['active'] == true
                                  ? Icons.verified_user_outlined
                                  : Icons.person_off_outlined,
                              color: user['active'] == true
                                  ? const Color(0xFF087A55)
                                  : const Color(0xFF737A83),
                            ),
                          ),
                          title: Text(user['display_name'] as String? ?? ''),
                          subtitle: Text(
                              '${user['login']} • ${user['role_label']} • ${user['active'] == true ? 'Ativo' : 'Bloqueado'}'),
                          trailing: IconButton(
                            tooltip: 'Editar usuário',
                            onPressed: () => _editUser(user),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ),
                      )),
                  const SizedBox(height: 80),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
