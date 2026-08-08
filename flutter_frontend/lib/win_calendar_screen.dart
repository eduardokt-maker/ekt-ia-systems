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
      appBar: AppBar(
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
                    Text('Contratos restantes de ${today.year}',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    const Text(
                        'Os contratos vencidos são removidos automaticamente. A troca indicada ocorre após o vencimento.'),
                    const SizedBox(height: 14),
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
                      color: Color(0xFFFFF8DF),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.verified_outlined,
                                  color: Color(0xFF8A6500)),
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
        height: 190,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFFFD43B), Color(0xFFF1A900)]),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33000000), blurRadius: 22, offset: Offset(0, 10))
          ],
        ),
        child: Stack(children: [
          const Positioned(
              right: -22,
              bottom: -38,
              child: Icon(Icons.candlestick_chart_rounded,
                  size: 210, color: Color(0x22FFFFFF))),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: const Color(0xFF0D6B3B),
                          borderRadius: BorderRadius.circular(20)),
                      child: const Text('MERCADO BRASILEIRO • B3',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12))),
                  const SizedBox(height: 13),
                  const Text('Calendário WIN',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF17202A))),
                  Text('Mini Índice Futuro • $year',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3F3A21))),
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
        elevation: current ? 3 : 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color:
                    current ? const Color(0xFFE4AD00) : const Color(0xFFDDE3EA),
                width: current ? 2 : 1)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: current
                        ? const Color(0xFFFFE58A)
                        : const Color(0xFFF0F3F6),
                    borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.show_chart_rounded,
                    color: Color(0xFF0D6B3B), size: 30)),
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
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w900)),
                        if (current)
                          const Chip(
                              label: Text('CONTRATO ATUAL'),
                              visualDensity: VisualDensity.compact),
                      ]),
                  Text('Vencimento: ${_date(contract.expiry)} • quarta-feira'),
                  const SizedBox(height: 3),
                  Text(
                      'Próximo: ${contract.nextSymbol} a partir de ${_date(contract.expiry.add(const Duration(days: 1)))}',
                      style: const TextStyle(color: Color(0xFF536273))),
                ])),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$days',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: days <= 2
                          ? const Color(0xFFC2410C)
                          : const Color(0xFF1F4E79))),
              Text(days == 1 ? 'dia restante' : 'dias restantes',
                  style: const TextStyle(fontSize: 11)),
            ]),
          ]),
        ),
      );
}
