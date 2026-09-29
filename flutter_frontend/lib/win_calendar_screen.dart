import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'b3_calendar.dart';
import 'external_link.dart';

const String winOfficialSourceUrl =
    'https://www.b3.com.br/pt_br/produtos-e-servicos/negociacao/renda-variavel/futuro-mini-de-ibovespa.htm';

class WinContract {
  const WinContract(
      {required this.symbol, required this.expiry, required this.nextSymbol});

  final String symbol;
  final DateTime expiry;
  final String nextSymbol;

  bool get isMiniDollar => symbol.startsWith('WDO');
  DateTime get lastTradingDay =>
      isMiniDollar ? previousB3TradingDay(expiry) : expiry;

  int daysUntil(DateTime now) =>
      DateUtils.dateOnly(expiry).difference(DateUtils.dateOnly(now)).inDays;
}

List<WinContract> winContractsForYear(int year) {
  const months = <(int, String)>[
    (2, 'G'),
    (4, 'J'),
    (6, 'M'),
    (8, 'Q'),
    (10, 'V'),
    (12, 'Z')
  ];
  final contracts = <WinContract>[];
  for (var index = 0; index < months.length; index++) {
    final month = months[index];
    final fifteenth = DateTime(year, month.$1, 15);
    final delta = (DateTime.wednesday - fifteenth.weekday + 3) % 7 - 3;
    final expiry = b3TradingDayOnOrAfter(fifteenth.add(Duration(days: delta)));
    final nextMonth = months[(index + 1) % months.length];
    final nextYear = index == months.length - 1 ? year + 1 : year;
    contracts.add(WinContract(
      symbol: 'WIN${month.$2}${year.toString().substring(2)}',
      expiry: expiry,
      nextSymbol: 'WIN${nextMonth.$2}${nextYear.toString().substring(2)}',
    ));
  }
  return contracts;
}

List<WinContract> remainingWinContracts(DateTime now) =>
    winContractsForYear(now.year)
        .where((contract) => contract.daysUntil(now) >= 0)
        .toList(growable: false);

WinContract currentWinContract(DateTime now) {
  final List<WinContract> remaining = remainingWinContracts(now);
  if (remaining.isNotEmpty) return remaining.first;
  return winContractsForYear(now.year + 1).first;
}

WinContract? winExpiryAlert(DateTime now) {
  for (final contract in remainingWinContracts(now)) {
    final days = contract.daysUntil(now);
    if (days >= 0 && days <= 2) return contract;
  }
  return null;
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

const String wdoOfficialSourceUrl =
    'https://www.b3.com.br/pt_br/produtos-e-servicos/negociacao/moedas/futuro-mini-de-taxa-de-cambio-de-reais-por-dolar-comercial.htm';
const String b3CalendarSourceUrl =
    'https://www.b3.com.br/pt_br/noticias/calendario-de-negociacao-da-b3-confira-o-funcionamento-da-bolsa-em-2026.htm';

List<WinContract> wdoContractsForYear(int year) {
  const letters = ['F', 'G', 'H', 'J', 'K', 'M', 'N', 'Q', 'U', 'V', 'X', 'Z'];
  return List.generate(12, (index) {
    final nextYear = index == 11 ? year + 1 : year;
    return WinContract(
      symbol: 'WDO${letters[index]}${year.toString().substring(2)}',
      expiry: b3TradingDayOnOrAfter(DateTime(year, index + 1, 1)),
      nextSymbol:
          'WDO${letters[(index + 1) % 12]}${nextYear.toString().substring(2)}',
    );
  });
}

List<WinContract> remainingWdoContracts(DateTime now) =>
    wdoContractsForYear(now.year)
        .where((contract) => contract.daysUntil(now) >= 0)
        .toList(growable: false);

WinContract currentWdoContract(DateTime now) => [
      ...wdoContractsForYear(now.year),
      ...wdoContractsForYear(now.year + 1)
    ].firstWhere((contract) => contract.daysUntil(now) > 0);

WinContract? wdoExpiryAlert(DateTime now) {
  for (final contract in [
    ...remainingWdoContracts(now),
    wdoContractsForYear(now.year + 1).first,
  ]) {
    if (contract.daysUntil(now) <= 2) return contract;
  }
  return null;
}

class WinCalendarScreen extends StatefulWidget {
  const WinCalendarScreen({super.key, this.now});
  final DateTime? now;

  @override
  State<WinCalendarScreen> createState() => _WinCalendarScreenState();
}

class _WinCalendarScreenState extends State<WinCalendarScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  late DateTime _today;

  @override
  void initState() {
    super.initState();
    _today = widget.now ?? b3Today();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  void _refresh() {
    final today = widget.now ?? b3Today();
    if (today != _today && mounted) setState(() => _today = today);
  }

  @override
  void didUpdateWidget(WinCalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _today = widget.now ?? b3Today();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final win = remainingWinContracts(_today);
    final wdo = remainingWdoContracts(_today);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Vencimento de contratos futuros',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Hero(year: _today.year),
                  const SizedBox(height: 20),
                  _CalendarSection(
                    title: 'Mini Índice • WIN',
                    today: _today,
                    contracts: win.isEmpty
                        ? [winContractsForYear(_today.year + 1).first]
                        : win,
                    currentSymbol: currentWinContract(_today).symbol,
                    rule:
                        'Meses pares, na quarta-feira mais próxima do dia 15. Se não houver pregão, o vencimento passa para a próxima sessão.',
                    source: winOfficialSourceUrl,
                  ),
                  const SizedBox(height: 24),
                  _CalendarSection(
                    title: 'Mini Dólar • WDO',
                    today: _today,
                    contracts: wdo.isEmpty
                        ? [wdoContractsForYear(_today.year + 1).first]
                        : wdo,
                    currentSymbol: currentWdoContract(_today).symbol,
                    rule:
                        'Todos os meses, no primeiro dia útil. A negociação termina na sessão anterior ao vencimento.',
                    source: wdoOfficialSourceUrl,
                  ),
                  const SizedBox(height: 12),
                  const Card(
                    elevation: 0,
                    color: Color(0xFFEAF3FB),
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Atualização automática',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                          SizedBox(height: 6),
                          Text(
                              'Datas e contagem regressiva acompanham o dia no horário de Brasília. Após o último vencimento do ano, aparece o primeiro do ano seguinte. Destaques de atenção nos dois dias anteriores e no dia do vencimento.'),
                          SizedBox(height: 8),
                          Text(
                              'Cálculo pelas regras recorrentes da B3 e feriados conferidos para 2026. Anos seguintes são projeções; mudanças extraordinárias da bolsa exigem nova conferência.'),
                          _SourceLink(
                              label: 'Calendário oficial B3 • 2026',
                              url: b3CalendarSourceUrl),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarSection extends StatelessWidget {
  const _CalendarSection(
      {required this.title,
      required this.today,
      required this.contracts,
      required this.currentSymbol,
      required this.rule,
      required this.source});
  final String title, currentSymbol, rule, source;
  final DateTime today;
  final List<WinContract> contracts;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF132334))),
          const SizedBox(height: 6),
          Text(rule,
              style: const TextStyle(fontSize: 16, color: Color(0xFF354658))),
          _SourceLink(label: 'Especificações oficiais B3', url: source),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
                'Próximos vencimentos • ${contracts.length} ${contracts.length == 1 ? 'contrato' : 'contratos'}',
                style: const TextStyle(
                    color: Color(0xFF637287), fontWeight: FontWeight.w600)),
          ),
          ...contracts.map((contract) => _ContractCard(
              contract: contract,
              days: contract.daysUntil(today),
              current: contract.symbol == currentSymbol)),
        ],
      );
}

class _SourceLink extends StatelessWidget {
  const _SourceLink({required this.label, required this.url});
  final String label, url;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () async {
            if (!openExternalLink(url)) {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link da B3 copiado.')));
            }
          },
          icon: const Icon(Icons.open_in_new, size: 16),
          label: Text(label),
        ),
      );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.year});
  final int year;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 240),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF071B2D),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
                color: Color(0x26051B2C), blurRadius: 28, offset: Offset(0, 14))
          ],
        ),
        child: Stack(children: [
          Positioned.fill(
              child: Image.asset('assets/images/win_futures_3d.png',
                  fit: BoxFit.cover, alignment: Alignment.centerRight)),
          Positioned.fill(
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
            const Color(0xFF06192B).withValues(alpha: .98),
            const Color(0xFF06192B).withValues(alpha: .74),
            const Color(0xFF06192B).withValues(alpha: .08),
          ], stops: const [
            0,
            .46,
            1
          ])))),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                          color: const Color(0xFF0E89A8).withValues(alpha: .9),
                          borderRadius: BorderRadius.circular(20)),
                      child: const Text('MERCADO BRASILEIRO • B3',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12))),
                  const SizedBox(height: 13),
                  const Text('Contratos futuros',
                      style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                  Text('Mini Índice (WIN) e Mini Dólar (WDO) • $year',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB8D9E8))),
                  const SizedBox(height: 18),
                  const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.autorenew_rounded,
                        size: 17, color: Color(0xFF5FE1FF)),
                    SizedBox(width: 7),
                    Flexible(
                        child: Text('Ciclo anual inteligente',
                            style: TextStyle(
                                color: Color(0xFFD7F5FC),
                                fontWeight: FontWeight.w700))),
                  ]),
                ]),
          ),
        ]),
      );
}

class _ContractCard extends StatelessWidget {
  const _ContractCard(
      {required this.contract, required this.days, required this.current});
  final WinContract contract;
  final int days;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final textColor = current ? Colors.white : const Color(0xFF132334);
    final secondaryColor =
        current ? const Color(0xFFD2E4ED) : const Color(0xFF354658);
    final accentColor =
        current ? const Color(0xFF63DDF5) : const Color(0xFF176B87);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: current ? 4 : 0,
      color: current ? const Color(0xFF102E47) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color:
                  current ? const Color(0xFF22B8DA) : const Color(0xFFDCE5ED))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                    contract.isMiniDollar
                        ? Icons.currency_exchange
                        : Icons.candlestick_chart_rounded,
                    color: accentColor,
                    size: 28),
                Text(contract.symbol,
                    style: TextStyle(
                        color: textColor,
                        fontSize: 23,
                        fontWeight: FontWeight.w900)),
                if (current)
                  const Chip(
                      backgroundColor: Color(0xFF1B7791),
                      side: BorderSide.none,
                      label: Text('PRÓXIMO A VENCER',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                      visualDensity: VisualDensity.compact),
                Text(
                    days == 0
                        ? 'Vence hoje'
                        : '$days ${days == 1 ? 'dia restante' : 'dias restantes'}',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: days <= 2
                            ? (current
                                ? const Color(0xFFFFD180)
                                : const Color(0xFF9A3412))
                            : accentColor)),
              ]),
          const SizedBox(height: 10),
          Text('Vencimento: ${_date(contract.expiry)}',
              style: TextStyle(color: secondaryColor, fontSize: 16)),
          Text('Último pregão: ${_date(contract.lastTradingDay)}',
              style: TextStyle(color: secondaryColor, fontSize: 16)),
          const SizedBox(height: 4),
          Text('Próximo código: ${contract.nextSymbol}',
              style: TextStyle(color: accentColor, fontSize: 16)),
          if (days <= 2)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Atenção ao vencimento',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: current
                            ? const Color(0xFFFFD180)
                            : const Color(0xFF9A3412)))),
        ]),
      ),
    );
  }
}
