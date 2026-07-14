import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

typedef DayTradeCapitalApiUriBuilder = Uri Function(String path);

class DayTradeCapitalScreen extends StatefulWidget {
  const DayTradeCapitalScreen({
    required this.apiUriBuilder,
    required this.sessionToken,
    super.key,
  });

  final DayTradeCapitalApiUriBuilder apiUriBuilder;
  final String sessionToken;

  @override
  State<DayTradeCapitalScreen> createState() => _DayTradeCapitalScreenState();
}

class _DayTradeCapitalScreenState extends State<DayTradeCapitalScreen> {
  final TextEditingController _capitalController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String _savedCapital = '0';
  String? _capitalError;

  Map<String, String> get _headers => <String, String>{
        'authorization': 'Bearer ${widget.sessionToken}',
        'content-type': 'application/json; charset=utf-8',
      };

  @override
  void initState() {
    super.initState();
    _loadCapital();
  }

  @override
  void dispose() {
    _capitalController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw const _CapitalException(
          'O servidor retornou uma resposta inválida.');
    }
  }

  Future<void> _loadCapital() async {
    setState(() => _loading = true);
    try {
      final http.Response response = await http.get(
        widget.apiUriBuilder('/api/day-trade/capital'),
        headers: _headers,
      );
      final Map<String, dynamic> body = await _decode(response);
      if (response.statusCode != 200 || body['ok'] != true) {
        throw _CapitalException(
          (body['message'] as String?) ??
              'Não foi possível carregar o capital.',
        );
      }
      final String capital = '${body['capital_text'] ?? '0'}';
      if (!mounted) return;
      setState(() {
        _savedCapital = capital;
        _capitalController.text = _parseNumber(capital) > 0
            ? _inputNumber(_parseNumber(capital))
            : '';
      });
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveCapital() async {
    FocusScope.of(context).unfocus();
    final double capital = _parseNumber(_capitalController.text);
    if (_capitalController.text.trim().isEmpty || capital <= 0) {
      setState(() => _capitalError = 'Informe um valor maior que zero');
      _showMessage('Informe o capital que será destinado ao Day Trade.',
          error: true);
      return;
    }
    setState(() {
      _saving = true;
      _capitalError = null;
    });
    try {
      final http.Response response = await http.put(
        widget.apiUriBuilder('/api/day-trade/capital'),
        headers: _headers,
        body: jsonEncode(<String, String>{
          'capital_text': _capitalController.text.trim(),
        }),
      );
      final Map<String, dynamic> body = await _decode(response);
      if (response.statusCode != 200 || body['ok'] != true) {
        throw _CapitalException(
          (body['message'] as String?) ?? 'Não foi possível salvar o capital.',
        );
      }
      final String saved = '${body['capital_text'] ?? capital}';
      if (!mounted) return;
      setState(() {
        _savedCapital = saved;
        _capitalController.text = _inputNumber(_parseNumber(saved));
      });
      _showMessage('Capital alocado em Day Trade salvo.');
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor:
            error ? const Color(0xFFB42332) : const Color(0xFF167A4B),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F3E8),
      appBar: AppBar(
        title: const Text('Capital alocado • Day Trade',
            style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: const Color(0xFF102A35),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _CapitalHero(capital: _parseNumber(_savedCapital)),
                      const SizedBox(height: 16),
                      Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: const BorderSide(color: Color(0xFFE4DCC8)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const Text('Cadastrar capital',
                                  style: TextStyle(
                                      color: Color(0xFF17333C),
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900)),
                              const SizedBox(height: 5),
                              const Text(
                                'Informe quanto do seu patrimônio está separado exclusivamente para operações de Day Trade.',
                                style: TextStyle(
                                    color: Color(0xFF65747A), fontSize: 12),
                              ),
                              const SizedBox(height: 18),
                              TextField(
                                controller: _capitalController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.,]')),
                                ],
                                onChanged: (_) =>
                                    setState(() => _capitalError = null),
                                decoration: InputDecoration(
                                  labelText: 'Capital alocado',
                                  prefixText: 'R\$ ',
                                  prefixIcon: const Icon(
                                      Icons.account_balance_wallet_outlined),
                                  errorText: _capitalError,
                                  filled: true,
                                  fillColor: const Color(0xFFFAF8F2),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _saving ? null : _saveCapital,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 17,
                                        height: 17,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: Text(_saving
                                    ? 'Salvando...'
                                    : 'Salvar capital alocado'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF167A4B),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const _CapitalNotice(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _CapitalHero extends StatelessWidget {
  const _CapitalHero({required this.capital});

  final double capital;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF102A35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          const CircleAvatar(
            radius: 28,
            backgroundColor: Color(0xFF24505A),
            foregroundColor: Color(0xFFFFD98B),
            child: Icon(Icons.savings_outlined, size: 29),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Capital atualmente alocado',
                    style: TextStyle(color: Color(0xFFC8D8DC), fontSize: 12)),
                const SizedBox(height: 4),
                Text(_currency(capital),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                const Text('Conta real • Base do plano de risco',
                    style: TextStyle(color: Color(0xFFFFD98B), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CapitalNotice extends StatelessWidget {
  const _CapitalNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8C878)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline_rounded, color: Color(0xFF9A6B00)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Salvar o capital não registra uma operação. O valor fica disponível para o controle e para o plano de risco do Day Trade.',
              style: TextStyle(
                  color: Color(0xFF765500),
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapitalException implements Exception {
  const _CapitalException(this.message);
  final String message;
}

String _messageFor(Object error) => error is _CapitalException
    ? error.message
    : 'Não foi possível conectar ao backend Python.';

double _parseNumber(String value) {
  String cleaned = value.replaceAll('R\$', '').replaceAll(' ', '');
  if (cleaned.contains(',')) {
    cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(cleaned) ?? 0;
}

String _inputNumber(double value) {
  final String text = value.toStringAsFixed(2).replaceAll('.', ',');
  return text;
}

String _currency(double value) {
  final List<String> parts = value.toStringAsFixed(2).split('.');
  final StringBuffer whole = StringBuffer();
  for (int index = 0; index < parts[0].length; index++) {
    if (index > 0 && (parts[0].length - index) % 3 == 0) whole.write('.');
    whole.write(parts[0][index]);
  }
  return 'R\$ $whole,${parts[1]}';
}
