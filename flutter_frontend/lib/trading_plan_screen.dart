import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TradingPlan {
  const TradingPlan({
    required this.dailyStop,
    required this.operations,
    required this.contracts,
  });

  final double dailyStop;
  final int operations;
  final int contracts;

  double get stopPerOperation => dailyStop / operations;
  double get stopPerContract => stopPerOperation / contracts;
}

class MonteCarloResult {
  const MonteCarloResult({
    required this.trials,
    required this.survivalProbability,
    required this.profitableProbability,
    required this.medianFinalBalance,
    required this.percentile10Balance,
    required this.percentile90Balance,
    required this.percentile95LossStreak,
  });

  final int trials;
  final double survivalProbability;
  final double profitableProbability;
  final double medianFinalBalance;
  final double percentile10Balance;
  final double percentile90Balance;
  final int percentile95LossStreak;
}

MonteCarloResult runTradingMonteCarlo({
  required TradingPlan plan,
  double initialCapital = 500,
  double winRate = .60,
  int days = 100,
  int trials = 10000,
  int seed = 20260822,
}) {
  if (initialCapital <= 0 || winRate <= 0 || winRate >= 1) {
    throw ArgumentError('Capital e taxa de acerto devem ser válidos.');
  }
  if (days < 1 || trials < 1) {
    throw ArgumentError('Dias e simulações devem ser maiores que zero.');
  }

  final random = Random(seed);
  final finalBalances = <double>[];
  final longestLossStreaks = <int>[];
  var survivors = 0;
  var profitable = 0;
  final totalOperations = days * plan.operations;

  for (var trial = 0; trial < trials; trial++) {
    var balance = initialCapital;
    var lossStreak = 0;
    var longestLossStreak = 0;
    for (var operation = 0; operation < totalOperations; operation++) {
      if (random.nextDouble() < winRate) {
        balance += plan.stopPerOperation;
        lossStreak = 0;
      } else {
        balance -= plan.stopPerOperation;
        lossStreak++;
        longestLossStreak = max(longestLossStreak, lossStreak);
        if (balance <= 0) {
          balance = 0;
          break;
        }
      }
    }
    if (balance > 0) survivors++;
    if (balance > initialCapital) profitable++;
    finalBalances.add(balance);
    longestLossStreaks.add(longestLossStreak);
  }

  finalBalances.sort();
  longestLossStreaks.sort();
  double percentile(List<double> values, double level) =>
      values[((values.length - 1) * level).round()];

  return MonteCarloResult(
    trials: trials,
    survivalProbability: survivors / trials,
    profitableProbability: profitable / trials,
    medianFinalBalance: percentile(finalBalances, .50),
    percentile10Balance: percentile(finalBalances, .10),
    percentile90Balance: percentile(finalBalances, .90),
    percentile95LossStreak:
        longestLossStreaks[((longestLossStreaks.length - 1) * .95).round()],
  );
}

TradingPlan buildTradingPlan({
  required double dailyStop,
  required int operations,
  required int contracts,
}) {
  if (!dailyStop.isFinite || dailyStop <= 0) {
    throw ArgumentError.value(dailyStop, 'dailyStop');
  }
  if (operations < 1 || operations > 50) {
    throw ArgumentError.value(operations, 'operations');
  }
  if (contracts < 1 || contracts > 100) {
    throw ArgumentError.value(contracts, 'contracts');
  }
  return TradingPlan(
    dailyStop: dailyStop,
    operations: operations,
    contracts: contracts,
  );
}

double? parseTradingMoney(String value) {
  var normalized = value.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (normalized.isEmpty) return null;
  if (normalized.contains(',')) {
    normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(normalized);
}

String formatTradingDate(DateTime date) {
  const weekdays = <String>[
    'segunda-feira',
    'terça-feira',
    'quarta-feira',
    'quinta-feira',
    'sexta-feira',
    'sábado',
    'domingo',
  ];
  const months = <String>[
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];
  return '${weekdays[date.weekday - 1]}, ${date.day} de ${months[date.month - 1]} de ${date.year}';
}

String formatTradingCurrency(double value) {
  final parts = value.toStringAsFixed(2).split('.');
  final digits = parts.first;
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write('.');
    grouped.write(digits[index]);
  }
  return 'R\$ ${grouped.toString()},${parts.last}';
}

class TradingPlanScreen extends StatefulWidget {
  const TradingPlanScreen({super.key, this.now});

  final DateTime? now;

  @override
  State<TradingPlanScreen> createState() => _TradingPlanScreenState();
}

class _TradingPlanScreenState extends State<TradingPlanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dailyStop = TextEditingController();
  final _operations = TextEditingController();
  final _contracts = TextEditingController();
  TradingPlan? _plan;
  MonteCarloResult? _simulation;

  @override
  void dispose() {
    _dailyStop.dispose();
    _operations.dispose();
    _contracts.dispose();
    super.dispose();
  }

  void _generate() {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      final plan = buildTradingPlan(
        dailyStop: parseTradingMoney(_dailyStop.text)!,
        operations: int.parse(_operations.text),
        contracts: int.parse(_contracts.text),
      );
      _plan = plan;
      _simulation = runTradingMonteCarlo(plan: plan);
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.now ?? DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Plan the Trading',
                style: TextStyle(fontWeight: FontWeight.w900)),
            Text('Planejamento diário de Day Trade',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 36),
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Greeting(date: date),
                  const SizedBox(height: 14),
                  _buildForm(),
                  if (_plan != null) ...<Widget>[
                    const SizedBox(height: 14),
                    _PlanResult(plan: _plan!),
                    const SizedBox(height: 14),
                    _MonteCarloCard(plan: _plan!, result: _simulation!),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text('Defina os limites de hoje',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('daily-stop-field'),
                  controller: _dailyStop,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Qual é o seu stop máximo do dia?',
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? value) {
                    final parsed = parseTradingMoney(value ?? '');
                    return parsed == null || parsed <= 0
                        ? 'Informe um valor maior que zero.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('operations-field'),
                  controller: _operations,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Quantas operações pretende fazer no dia?',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? value) {
                    final parsed = int.tryParse(value ?? '');
                    return parsed == null || parsed < 1 || parsed > 50
                        ? 'Informe de 1 a 50 operações.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('contracts-field'),
                  controller: _contracts,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Com quantos contratos você vai operar?',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? value) {
                    final parsed = int.tryParse(value ?? '');
                    return parsed == null || parsed < 1 || parsed > 100
                        ? 'Informe de 1 a 100 contratos.'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('generate-trading-plan'),
                  onPressed: _generate,
                  icon: const Icon(Icons.auto_graph_rounded),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 13),
                    child: Text('Montar meu plano de trade'),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1F4E79),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFF102A43), Color(0xFF1F4E79)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Bom dia!',
                key: Key('trading-greeting'),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(formatTradingDate(date),
                key: const Key('trading-date'),
                style: const TextStyle(color: Color(0xFFDCEAF5), fontSize: 15)),
            const SizedBox(height: 10),
            const Text(
              'Seu limite vem antes da entrada. Planeje o risco e respeite o combinado.',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
}

class _PlanResult extends StatelessWidget {
  const _PlanResult({required this.plan});
  final TradingPlan plan;

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('trading-plan-result'),
        margin: EdgeInsets.zero,
        color: const Color(0xFFF2FAF6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF9BCAB3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('Seu plano para hoje',
                  style: TextStyle(
                      color: Color(0xFF123D2B),
                      fontSize: 21,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _Metric('Stop máximo diário',
                      formatTradingCurrency(plan.dailyStop)),
                  _Metric('Stop por operação',
                      formatTradingCurrency(plan.stopPerOperation)),
                  _Metric('Stop por contrato/operação',
                      formatTradingCurrency(plan.stopPerContract)),
                  _Metric('Limite operacional',
                      '${plan.operations} operações × ${plan.contracts} contratos'),
                ],
              ),
              const SizedBox(height: 18),
              const Text('Roteiro de execução',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 6),
              ...List<Widget>.generate(plan.operations, (int index) {
                final number = index + 1;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(radius: 16, child: Text('$number')),
                  title: Text('Operação $number • ${plan.contracts} contratos'),
                  subtitle: Text(
                    'Risco máximo: ${formatTradingCurrency(plan.stopPerOperation)} • limite acumulado: ${formatTradingCurrency(plan.stopPerOperation * number)}',
                  ),
                );
              }),
              const Divider(height: 26),
              const Text(
                'Regras: não aumente a quantidade de contratos; encerre ao atingir o stop diário ou o número planejado de operações; registre o resultado antes da próxima entrada.',
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.4),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ferramenta de organização de risco. Não constitui recomendação de investimento.',
                style: TextStyle(fontSize: 11, color: Color(0xFF5F6873)),
              ),
            ],
          ),
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        width: 205,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF5F6873))),
            const SizedBox(height: 4),
            Text(value,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          ],
        ),
      );
}

class _MonteCarloCard extends StatelessWidget {
  const _MonteCarloCard({required this.plan, required this.result});

  final TradingPlan plan;
  final MonteCarloResult result;

  String _percent(double value) =>
      '${(value * 100).toStringAsFixed(1).replaceAll('.', ',')}%';

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('monte-carlo-result'),
        margin: EdgeInsets.zero,
        color: const Color(0xFFFFF8E8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFD9B766)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Row(
                children: <Widget>[
                  Icon(Icons.scatter_plot_rounded, color: Color(0xFF8A5A00)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Análise Monte Carlo • 100 dias',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${result.trials} trajetórias com capital inicial de R\$ 500, taxa de acerto de 60% e ${plan.operations * 100} operações no período.',
                style: const TextStyle(color: Color(0xFF66562F)),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Probabilidade de os R\$ 500 sobreviverem',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _percent(result.survivalProbability),
                      key: const Key('survival-probability'),
                      style: TextStyle(
                        color: result.survivalProbability >= .80
                            ? const Color(0xFF167A4B)
                            : const Color(0xFFB42332),
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      'Sobreviver significa não atingir saldo zero em nenhum momento das 100 sessões.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF5F6873)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _Metric('Chance de terminar acima de R\$ 500',
                      _percent(result.profitableProbability)),
                  _Metric('Saldo final mediano',
                      formatTradingCurrency(result.medianFinalBalance)),
                  _Metric('Cenário inferior (P10)',
                      formatTradingCurrency(result.percentile10Balance)),
                  _Metric('Cenário superior (P90)',
                      formatTradingCurrency(result.percentile90Balance)),
                  _Metric('Sequência de losses (P95)',
                      '${result.percentile95LossStreak} losses seguidos'),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Leitura: com risco de ${formatTradingCurrency(plan.stopPerOperation)} por operação, a vantagem estatística de 60% precisa atravessar oscilações aleatórias e sequências de losses antes de aparecer. Quanto maior o risco em relação aos R\$ 500, maior a chance de ruína antes disso.',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, height: 1.4),
              ),
              const SizedBox(height: 8),
              const Text(
                'Hipóteses: gain e loss de mesmo valor (1:1), resultados independentes, risco fixo, sem corretagem, impostos ou slippage. A simulação estima cenários; não garante resultados futuros.',
                style: TextStyle(fontSize: 11, color: Color(0xFF5F6873)),
              ),
            ],
          ),
        ),
      );
}
