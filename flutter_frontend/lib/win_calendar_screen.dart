import 'package:flutter/material.dart';

const String winOfficialSourceUrl =
    'https://www.b3.com.br/pt_br/produtos-e-servicos/negociacao/renda-variavel/futuro-mini-de-ibovespa.htm';

class WinContract {
  const WinContract(
      {required this.symbol, required this.expiry, required this.nextSymbol});

  final String symbol;
  final DateTime expiry;
  final String nextSymbol;

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
    final expiry = fifteenth.add(Duration(days: delta));
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

class WinCalendarScreen extends StatelessWidget {
  const WinCalendarScreen({super.key, this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final today = now ?? DateTime.now();
    final contracts = remainingWinContracts(today);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: const Text('Vencimentos Mini Índice',
              style: TextStyle(fontWeight: FontWeight.w800))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Hero(year: today.year),
                    const SizedBox(height: 18),
                    Row(children: [
                      Container(
                          width: 5,
                          height: 38,
                          decoration: BoxDecoration(
                              color: const Color(0xFF18A6C9),
                              borderRadius: BorderRadius.circular(8))),
                      const SizedBox(width: 11),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Contratos restantes de ${today.year}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900)),
                            const Text(
                                'Acompanhe o vencimento e a transição para o próximo código.',
                                style: TextStyle(color: Color(0xFF637287))),
                          ])),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                              color: const Color(0xFFE5F7FB),
                              borderRadius: BorderRadius.circular(30)),
                          child: Text('${contracts.length} futuros',
                              style: const TextStyle(
                                  color: Color(0xFF087C99),
                                  fontWeight: FontWeight.w800))),
                    ]),
                    const SizedBox(height: 16),
                    if (contracts.isEmpty)
                      const Card(
                          child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                  'O calendário do próximo ano será aberto automaticamente na virada do ano.')))
                    else
                      ...contracts.asMap().entries.map((entry) => _ContractCard(
                            contract: entry.value,
                            days: entry.value.daysUntil(today),
                            current: entry.key == 0,
                          )),
                    const SizedBox(height: 12),
                    const Card(
                      elevation: 0,
                      color: Color(0xFFEAF3FB),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.verified_outlined,
                                  color: Color(0xFF176B87)),
                              SizedBox(width: 12),
                              Expanded(
                                  child: Text(
                                      'Regra oficial B3: vencimentos nos meses pares, na quarta-feira mais próxima do dia 15. O calendário é recalculado somente na mudança de ano; a conferência é sinalizada nos dois dias anteriores a cada vencimento.')),
                            ]),
                      ),
                    ),
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.year});
  final int year;

  @override
  Widget build(BuildContext context) => Container(
        height: 270,
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
                  const Text('Calendário WIN',
                      style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                  Text('Mini Índice Futuro • $year',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB8D9E8))),
                  const SizedBox(height: 18),
                  const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.autorenew_rounded,
                        size: 17, color: Color(0xFF5FE1FF)),
                    SizedBox(width: 7),
                    Text('Ciclo anual inteligente',
                        style: TextStyle(
                            color: Color(0xFFD7F5FC),
                            fontWeight: FontWeight.w700)),
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
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: current ? 4 : 0,
        color: current ? const Color(0xFF102E47) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color:
                    current ? const Color(0xFF22B8DA) : const Color(0xFFDCE5ED),
                width: current ? 1.5 : 1)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: current
                        ? const Color(0xFF1D4D68)
                        : const Color(0xFFEAF6FA),
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.candlestick_chart_rounded,
                    color: current
                        ? const Color(0xFF63DDF5)
                        : const Color(0xFF1689A6),
                    size: 30)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(contract.symbol,
                            style: TextStyle(
                                color: current
                                    ? Colors.white
                                    : const Color(0xFF132334),
                                fontSize: 20,
                                fontWeight: FontWeight.w900)),
                        if (current)
                          const Chip(
                              backgroundColor: Color(0xFF1B7791),
                              side: BorderSide.none,
                              label: Text('CONTRATO ATUAL',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                              visualDensity: VisualDensity.compact),
                      ]),
                  Text('Vencimento: ${_date(contract.expiry)} • quarta-feira',
                      style: TextStyle(
                          color: current
                              ? const Color(0xFFD2E4ED)
                              : const Color(0xFF354658))),
                  const SizedBox(height: 3),
                  Text(
                      'Próximo: ${contract.nextSymbol} a partir de ${_date(contract.expiry.add(const Duration(days: 1)))}',
                      style: TextStyle(
                          color: current
                              ? const Color(0xFF8FC4D5)
                              : const Color(0xFF637287))),
                ])),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$days',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: days <= 2
                          ? const Color(0xFFC2410C)
                          : current
                              ? const Color(0xFF63DDF5)
                              : const Color(0xFF176B87))),
              Text(days == 1 ? 'dia restante' : 'dias restantes',
                  style: TextStyle(
                      fontSize: 11,
                      color: current
                          ? const Color(0xFFB8D0DC)
                          : const Color(0xFF536273))),
            ]),
          ]),
        ),
      );
}
