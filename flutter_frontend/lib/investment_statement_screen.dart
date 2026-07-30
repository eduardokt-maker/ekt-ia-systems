import 'dart:convert';

import 'api_client.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

typedef InvestmentStatementApiUriBuilder = Uri Function(String path);

class InvestmentStatementScreen extends StatefulWidget {
  const InvestmentStatementScreen({
    required this.apiUriBuilder,
    required this.sessionToken,
    super.key,
  });

  final InvestmentStatementApiUriBuilder apiUriBuilder;
  final String sessionToken;

  @override
  State<InvestmentStatementScreen> createState() =>
      _InvestmentStatementScreenState();
}

class _InvestmentStatementScreenState extends State<InvestmentStatementScreen> {
  bool _loading = true;
  String? _error;
  _InvestmentStatement? _statement;

  Map<String, String> get _headers => <String, String>{
        'authorization': 'Bearer ${widget.sessionToken}',
        'content-type': 'application/json; charset=utf-8',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final http.Response response = await apiClient.get(
        widget.apiUriBuilder('/api/investments/statement'),
        headers: _headers,
      );
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw Exception(
          (body['message'] as String?) ??
              'Não foi possível carregar o memorial dos investimentos.',
        );
      }
      if (!mounted) return;
      setState(() => _statement = _InvestmentStatement.fromJson(body));
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F3E8),
      appBar: AppBar(
        title: const Text(
          'Memorial do total aplicado',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFF102A35),
        foregroundColor: Colors.white,
        actions: <Widget>[
          IconButton(
            tooltip: 'Atualizar extrato',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : _buildContent(_statement!),
    );
  }

  Widget _buildContent(_InvestmentStatement statement) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _TotalHero(statement: statement),
                  const SizedBox(height: 16),
                  const _SectionTitle(
                    title: 'Composição atual da carteira',
                    subtitle:
                        'Valores que formam o total aplicado neste momento.',
                  ),
                  const SizedBox(height: 9),
                  ...statement.investments.map(_InvestmentCompositionCard.new),
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    title: 'Extrato patrimonial Day Trade',
                    subtitle:
                        'Capital inicial, aportes, retiradas, ajustes e operações de todos os ativos e mercados.',
                  ),
                  const SizedBox(height: 9),
                  if (statement.entries.isEmpty)
                    const _EmptyStatement()
                  else
                    _StatementList(entries: statement.entries),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalHero extends StatelessWidget {
  const _TotalHero({required this.statement});

  final _InvestmentStatement statement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF102A35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Total aplicado conciliado',
            style: TextStyle(color: Color(0xFFC8D8DC), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            _currency(statement.totalApplied),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: <Widget>[
              _HeroValue(
                label: 'Saldo Day Trade',
                value: _currency(statement.dayTradeBalance),
              ),
              _HeroValue(
                label: 'Patrimônio aportado DT',
                value: _currency(statement.contributedCapital),
              ),
              _HeroValue(
                label: 'Resultado automático DT',
                value: _currency(statement.automaticDayTradeResult),
              ),
              _HeroValue(
                label: 'Ajustes manuais DT',
                value: _currency(statement.manualDayTradeAdjustment),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroValue extends StatelessWidget {
  const _HeroValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: const TextStyle(color: Color(0xFF9FB6BC), fontSize: 10)),
          Text(value,
              style: const TextStyle(
                  color: Color(0xFFFFD98B), fontWeight: FontWeight.w800)),
        ],
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title,
              style: const TextStyle(
                  color: Color(0xFF17333C),
                  fontSize: 19,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(subtitle,
              style: const TextStyle(color: Color(0xFF65747A), fontSize: 12)),
        ],
      );
}

class _InvestmentCompositionCard extends StatelessWidget {
  const _InvestmentCompositionCard(this.item);

  final _StatementInvestment item;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE4DCC8)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: item.isDayTrade
              ? const Color(0xFFE5F3EF)
              : const Color(0xFFEAF4FF),
          child: Icon(
            item.isDayTrade
                ? Icons.candlestick_chart_rounded
                : Icons.account_balance_wallet_outlined,
            color: item.isDayTrade
                ? const Color(0xFF167A4B)
                : const Color(0xFF1F4E79),
          ),
        ),
        title: Text(item.name,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${item.category} • ${item.source}'),
        trailing: Text(
          _currency(item.amount),
          style: const TextStyle(
              color: Color(0xFF17333C), fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _StatementList extends StatelessWidget {
  const _StatementList({required this.entries});

  final List<_StatementEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE4DCC8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: entries
              .map((entry) => _StatementRow(entry: entry))
              .toList()
              .separatedBy(const Divider(height: 1)),
        ),
      ),
    );
  }
}

class _StatementRow extends StatelessWidget {
  const _StatementRow({required this.entry});

  final _StatementEntry entry;

  @override
  Widget build(BuildContext context) {
    final bool incoming = entry.amount >= 0;
    final Color color =
        incoming ? const Color(0xFF167A4B) : const Color(0xFFB42332);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 20,
            backgroundColor:
                incoming ? const Color(0xFFE5F3EF) : const Color(0xFFFFECEE),
            child: Icon(
              incoming ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: color,
              size: 19,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(entry.title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(entry.description,
                    style: const TextStyle(
                        color: Color(0xFF65747A), fontSize: 12)),
                if (entry.date.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    '${_dateDisplay(entry.date)}${entry.time.isEmpty ? '' : ' • ${entry.time}'}',
                    style:
                        const TextStyle(color: Color(0xFF8A9498), fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '${incoming ? '+' : '-'}${_currency(entry.amount.abs())}',
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                'Saldo ${_currency(entry.balance)}',
                style: const TextStyle(color: Color(0xFF65747A), fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyStatement extends StatelessWidget {
  const _EmptyStatement();

  @override
  Widget build(BuildContext context) => const Card(
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Nenhuma movimentação Day Trade registrada.'),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline_rounded,
                  color: Color(0xFFB42332), size: 42),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
}

class _InvestmentStatement {
  const _InvestmentStatement({
    required this.totalApplied,
    required this.dayTradeBalance,
    required this.contributedCapital,
    required this.automaticDayTradeResult,
    required this.manualDayTradeAdjustment,
    required this.investments,
    required this.entries,
  });

  factory _InvestmentStatement.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> dayTrade =
        (json['day_trade'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return _InvestmentStatement(
      totalApplied: _parseAmount('${json['total_applied_text'] ?? '0'}'),
      dayTradeBalance: _parseAmount('${dayTrade['capital_text'] ?? '0'}'),
      contributedCapital:
          _parseAmount('${dayTrade['contributed_capital_text'] ?? '0'}'),
      automaticDayTradeResult:
          _parseAmount('${dayTrade['automatic_day_trade_result_text'] ?? '0'}'),
      manualDayTradeAdjustment: _parseAmount(
          '${dayTrade['manual_day_trade_adjustment_text'] ?? '0'}'),
      investments: ((json['investments'] as List<dynamic>?) ?? <dynamic>[])
          .map((item) =>
              _StatementInvestment.fromJson(item as Map<String, dynamic>))
          .toList(),
      entries: ((dayTrade['statement_entries'] as List<dynamic>?) ??
              <dynamic>[])
          .map((item) => _StatementEntry.fromJson(item as Map<String, dynamic>))
          .toList()
          .reversed
          .toList(),
    );
  }

  final double totalApplied;
  final double dayTradeBalance;
  final double contributedCapital;
  final double automaticDayTradeResult;
  final double manualDayTradeAdjustment;
  final List<_StatementInvestment> investments;
  final List<_StatementEntry> entries;
}

class _StatementInvestment {
  const _StatementInvestment({
    required this.name,
    required this.category,
    required this.source,
    required this.amount,
    required this.isDayTrade,
  });

  factory _StatementInvestment.fromJson(Map<String, dynamic> json) =>
      _StatementInvestment(
        name: '${json['name'] ?? ''}',
        category: '${json['category'] ?? ''}',
        source: '${json['source'] ?? ''}',
        amount: _parseAmount('${json['amount_text'] ?? '0'}'),
        isDayTrade: json['is_day_trade'] == true,
      );

  final String name;
  final String category;
  final String source;
  final double amount;
  final bool isDayTrade;
}

class _StatementEntry {
  const _StatementEntry({
    required this.date,
    required this.time,
    required this.title,
    required this.description,
    required this.amount,
    required this.balance,
  });

  factory _StatementEntry.fromJson(Map<String, dynamic> json) =>
      _StatementEntry(
        date: '${json['date'] ?? ''}',
        time: '${json['time'] ?? ''}',
        title: '${json['title'] ?? ''}',
        description: '${json['description'] ?? ''}',
        amount: _parseAmount('${json['amount_text'] ?? '0'}'),
        balance: _parseAmount('${json['balance_text'] ?? '0'}'),
      );

  final String date;
  final String time;
  final String title;
  final String description;
  final double amount;
  final double balance;
}

double _parseAmount(String raw) {
  String value = raw.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (value.contains(',')) {
    value = value.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(value) ?? 0;
}

String _currency(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

String _dateDisplay(String iso) {
  final List<String> parts = iso.split('-');
  return parts.length == 3 ? '${parts[2]}/${parts[1]}/${parts[0]}' : iso;
}

extension _StatementSeparatedWidgets on List<Widget> {
  List<Widget> separatedBy(Widget separator) {
    if (length < 2) return this;
    final List<Widget> result = <Widget>[];
    for (int index = 0; index < length; index++) {
      if (index > 0) result.add(separator);
      result.add(this[index]);
    }
    return result;
  }
}
