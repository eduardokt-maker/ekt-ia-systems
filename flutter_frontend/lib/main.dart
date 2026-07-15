import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;

import 'budget_screen.dart';
import 'day_trade_capital_screen.dart';
import 'day_trade_deposit_screen.dart';
import 'day_trade_screen.dart';
import 'investments_screen.dart';

const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const String productionApiBaseUrl = 'https://ekt-ia-systems.onrender.com';

Uri apiUri(String path) {
  if (apiBaseUrl.isNotEmpty) {
    return Uri.parse('$apiBaseUrl$path');
  }
  if (kIsWeb) {
    return Uri.parse('$productionApiBaseUrl$path');
  }
  return Uri.parse('$productionApiBaseUrl$path');
}

void main() {
  runApp(const EktIaApp());
}

class EktIaApp extends StatelessWidget {
  const EktIaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EKT IA Systems',
      locale: const Locale('pt', 'BR'),
      supportedLocales: const <Locale>[Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F4E79),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F6F9),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String _message = '';

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _message = '';
    });

    try {
      final Uri uri = apiUri('/api/investments/login');
      final http.Response response = await http.post(
        uri,
        headers: const {'content-type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'login': _loginController.text,
          'password': _passwordController.text,
        }),
      );
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) {
        return;
      }
      if (response.statusCode == 200 && body['ok'] == true) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => DashboardScreen(
              dashboard: DashboardData.fromJson(
                  body['dashboard'] as Map<String, dynamic>),
              sessionToken: (body['session_token'] as String?) ?? '',
            ),
          ),
        );
        return;
      }
      setState(() {
        _message = (body['message'] as String?) ?? 'Nao foi possivel entrar.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = 'Nao foi possivel conectar ao backend Python.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool wide = constraints.maxWidth >= 900;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: wide
                      ? _WideLoginLayout(form: _loginForm())
                      : _CompactLoginLayout(form: _loginForm()),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _loginForm() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 430),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8DEE6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.lock_person_outlined,
                color: Color(0xFF1F4E79)),
          ),
          const SizedBox(height: 18),
          const Text(
            'Acesso restrito',
            style: TextStyle(
              color: Color(0xFF16202A),
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Entre para acessar seu painel financeiro.',
            style: TextStyle(color: Color(0xFF5F6873), fontSize: 13),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _loginController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Login',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Senha',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Mostrar senha' : 'Ocultar senha',
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
                icon: Icon(_obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
              ),
            ),
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _message,
              style: const TextStyle(color: Color(0xFFB42332), fontSize: 12),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(_loading ? 'Entrando...' : 'Entrar'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1F4E79),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}

class _WideLoginLayout extends StatelessWidget {
  const _WideLoginLayout({required this.form});

  final Widget form;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF0F2235),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EKT IA Systems',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 10),
                Text(
                  'Controle de investimentos com backend Python e nova interface Flutter.',
                  style: TextStyle(
                      color: Color(0xFFDCEAF5), fontSize: 15, height: 1.4),
                ),
                SizedBox(height: 28),
                _LoginSignal(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Carteira'),
                _LoginSignal(
                    icon: Icons.receipt_long_outlined, label: 'Meu orcamento'),
                _LoginSignal(
                    icon: Icons.show_chart_outlined,
                    label: 'Operacoes day trade'),
              ],
            ),
          ),
        ),
        const SizedBox(width: 28),
        form,
      ],
    );
  }
}

class _CompactLoginLayout extends StatelessWidget {
  const _CompactLoginLayout({required this.form});

  final Widget form;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(child: form);
  }
}

class _LoginSignal extends StatelessWidget {
  const _LoginSignal({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF8ED4FF), size: 20),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen(
      {required this.dashboard, required this.sessionToken, super.key});

  final DashboardData dashboard;
  final String sessionToken;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final int columns = constraints.maxWidth >= 900 ? 3 : 1;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DashboardHeader(
                        data: dashboard,
                        onLogout: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: dashboard.actions.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          mainAxisExtent: 190,
                        ),
                        itemBuilder: (context, index) => ActionCard(
                          action: dashboard.actions[index],
                          onTap: () {
                            final DashboardAction action =
                                dashboard.actions[index];
                            final Widget? destination = switch (action.id) {
                              'investments' => InvestmentsScreen(
                                  apiUriBuilder: apiUri,
                                  sessionToken: sessionToken,
                                  onOpenDayTradeCapital: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => DayTradeCapitalScreen(
                                          apiUriBuilder: apiUri,
                                          sessionToken: sessionToken,
                                        ),
                                      ),
                                    );
                                  },
                                  onOpenDayTradeDeposit: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => DayTradeDepositScreen(
                                          apiUriBuilder: apiUri,
                                          sessionToken: sessionToken,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              'budget' => BudgetScreen(
                                  apiUriBuilder: apiUri,
                                  sessionToken: sessionToken,
                                ),
                              'day_trade' => DayTradeScreen(
                                  apiUriBuilder: apiUri,
                                  sessionToken: sessionToken,
                                ),
                              _ => null,
                            };
                            if (destination != null) {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => destination,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.data, required this.onLogout});

  final DashboardData data;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2235),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        runSpacing: 12,
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  data.subtitle,
                  style:
                      const TextStyle(color: Color(0xFFA8B4C0), fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF173552),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_open_outlined,
                    color: Color(0xFF8ED4FF), size: 18),
                const SizedBox(width: 6),
                Text(
                  data.status,
                  style: const TextStyle(
                      color: Color(0xFFDCEAF5),
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout, size: 17),
            label: const Text('Sair'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF6F8294)),
            ),
          ),
        ],
      ),
    );
  }
}

class ActionCard extends StatelessWidget {
  const ActionCard({required this.action, required this.onTap, super.key});

  final DashboardAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border(
              top: BorderSide(width: 3, color: action.accentColor),
              right: const BorderSide(color: Color(0xFFD8DEE6)),
              bottom: const BorderSide(color: Color(0xFFD8DEE6)),
              left: const BorderSide(color: Color(0xFFD8DEE6)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: action.id == 'budget'
                          ? const Color(0xFFFFF3DF)
                          : const Color(0xFFEEF3F8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_iconFor(action.id),
                        color: action.accentColor, size: 22),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7FA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      action.badge,
                      style: const TextStyle(
                          color: Color(0xFF5F6873),
                          fontSize: 10,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                action.title,
                style: const TextStyle(
                    color: Color(0xFF20242B),
                    fontSize: 17,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                action.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xFF5F6873), fontSize: 12, height: 1.35),
              ),
              const Spacer(),
              Row(
                children: [
                  Text(
                    'Abrir',
                    style: TextStyle(
                        color: action.accentColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward,
                      color: action.accentColor, size: 17),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String id) {
    switch (id) {
      case 'budget':
        return Icons.account_balance_outlined;
      case 'day_trade':
        return Icons.show_chart_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }
}

class DashboardData {
  DashboardData({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.actions,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    return DashboardData(
      title: (json['title'] as String?) ?? 'Controle de investimentos',
      subtitle: (json['subtitle'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      actions: ((json['actions'] as List<dynamic>?) ?? <dynamic>[])
          .map((item) => DashboardAction.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final String title;
  final String subtitle;
  final String status;
  final List<DashboardAction> actions;
}

class DashboardAction {
  DashboardAction({
    required this.id,
    required this.title,
    required this.description,
    required this.badge,
    required this.accent,
  });

  factory DashboardAction.fromJson(Map<String, dynamic> json) {
    return DashboardAction(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      badge: (json['badge'] as String?) ?? '',
      accent: (json['accent'] as String?) ?? '#1F4E79',
    );
  }

  final String id;
  final String title;
  final String description;
  final String badge;
  final String accent;

  Color get accentColor {
    final String normalized = accent.replaceFirst('#', '');
    final int value = int.tryParse('FF$normalized', radix: 16) ?? 0xFF1F4E79;
    return Color(value);
  }
}
