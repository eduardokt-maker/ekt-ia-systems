import 'package:flutter/material.dart';
import 'package:ekt_ia_flutter_frontend/day_trade_navigation_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('consolida o resultado líquido por data e mantém os ativos', () {
    final results = consolidateDayTradeResults(const [
      DayTradeDailyEntry(date: '2026-08-20', asset: 'WINV26', netResult: -354),
      DayTradeDailyEntry(date: '2026-08-20', asset: 'WDOU26', netResult: 100),
      DayTradeDailyEntry(
          date: '2026-08-19', asset: 'WINV26', netResult: 842.40),
    ]);

    expect(results.map((result) => result.date), ['2026-08-20', '2026-08-19']);
    expect(results.first.total, -254);
    expect(results.first.entries.map((entry) => entry.asset),
        ['WINV26', 'WDOU26']);
    expect(results.last.total, 842.40);
  });
  const entries = [
    DayTradeDailyEntry(date: '2026-08-19', asset: 'WIN', netResult: 800),
    DayTradeDailyEntry(date: '2026-08-20', asset: 'WIN', netResult: -350),
    DayTradeDailyEntry(date: '2026-08-20', asset: 'WDO', netResult: 100),
    DayTradeDailyEntry(date: '2026-08-21', asset: 'WDO', netResult: 0),
    DayTradeDailyEntry(date: '2026-08-22', asset: 'WIN', netResult: 50),
  ];
  String value(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;
  Future<void> filter(WidgetTester tester, String start, String end) async {
    await tester.enterText(find.byKey(const Key('daily-start-date')), start);
    await tester.enterText(find.byKey(const Key('daily-end-date')), end);
    await tester.ensureVisible(find.byKey(const Key('daily-apply-filter')));
    await tester.tap(find.byKey(const Key('daily-apply-filter')));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'abre todos os dias e filtra limites inclusivos com totais por dia',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: DayTradeDailyConsolidatedScreen(entries: entries)));
    expect(value(tester, 'daily-active-period'), 'Todos os dias');
    expect(value(tester, 'daily-net-total'), contains('600,00'));
    expect(value(tester, 'daily-gain-total'), contains('850,00'));
    expect(value(tester, 'daily-loss-total'), contains('250,00'));
    await filter(tester, '20/08/2026', '21/08/2026');
    expect(value(tester, 'daily-net-total'), contains('-'));
    expect(value(tester, 'daily-net-total'), contains('250,00'));
    expect(value(tester, 'daily-gain-total'), contains('0,00'));
    expect(find.text('2 dias analisados • 1 dias zerados'), findsOneWidget);
    await filter(tester, '22/08/2026', '22/08/2026');
    expect(value(tester, 'daily-net-total'), contains('50,00'));
    await tester.tap(find.text('Mostrar todos os dias'));
    await tester.pumpAndSettle();
    expect(value(tester, 'daily-net-total'), contains('600,00'));
    expect(value(tester, 'daily-active-period'), 'Todos os dias');
  });
  testWidgets(
      'datas inválidas preservam filtro e intervalo vazio mostra saldo zero',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: DayTradeDailyConsolidatedScreen(entries: entries)));
    await filter(tester, '31/02/2026', '21/08/2026');
    expect(find.textContaining('duas datas válidas'), findsOneWidget);
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    expect(value(tester, 'daily-active-period'), 'Todos os dias');
    await filter(tester, '22/08/2026', '19/08/2026');
    expect(find.textContaining('igual ou posterior'), findsOneWidget);
    await filter(tester, '01/01/2026', '01/01/2026');
    expect(value(tester, 'daily-net-total'), contains('0,00'));
    expect(
        find.text('Nenhum lançamento no período selecionado.'), findsOneWidget);
  });
  testWidgets('resumo e datas funcionam em celular com texto ampliado',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!),
        home: const DayTradeDailyConsolidatedScreen(entries: entries)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('daily-start-date')));
    await filter(tester, '20/08/2026', '20/08/2026');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Resultado Geral shows only daily totals, colors and clickable calendar',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home:
            DayTradeDailyConsolidatedScreen(entries: entries, general: true)));
    await tester.pumpAndSettle();
    expect(find.text('Resultado Geral'), findsOneWidget);
    expect(find.text('Quarta-feira'), findsOneWidget);
    expect(find.text('WIN'), findsNothing);
    expect(find.byKey(const Key('daily-summary')), findsNothing);
    expect(
        tester
            .widget<Container>(
                find.byKey(const Key('general-value-2026-08-19')))
            .color,
        const Color(0xFF168A57));
    expect(
        tester
            .widget<Container>(
                find.byKey(const Key('general-value-2026-08-20')))
            .color,
        const Color(0xFFFFCDD2));
    expect(tester.takeException(), isNull);
    await filter(tester, '20/08/2026', '21/08/2026');
    expect(find.byKey(const Key('general-row-2026-08-19')), findsNothing);
    expect(find.byKey(const Key('general-row-2026-08-20')), findsOneWidget);
    expect(find.byKey(const Key('general-row-2026-08-21')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('general-value-2026-08-20')),
            matching: find.textContaining('250,00')),
        findsOneWidget);
    await tester.tap(find.byTooltip('Escolher Data inicial'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('19').last);
    await tester.tap(find.text('Selecionar'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('daily-start-date')))
            .controller!
            .text,
        '19/08/2026');
    await tester.tap(find.byKey(const Key('daily-apply-filter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('general-row-2026-08-19')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'period card counts days, excludes zero and follows applied filter',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home:
            DayTradeDailyConsolidatedScreen(entries: entries, general: true)));
    expect(value(tester, 'general-period-net'), contains('600,00'));
    expect(value(tester, 'general-gain-days'), '2 dias');
    expect(value(tester, 'general-loss-days'), '1 dias');
    expect(value(tester, 'general-gain-rate'), '66,7%');
    expect(value(tester, 'general-loss-rate'), '33,3%');
    expect(tester.getTopRight(find.byKey(const Key('general-period-card'))).dx,
        greaterThan(1000));
    await filter(tester, '20/08/2026', '21/08/2026');
    expect(value(tester, 'general-period-net'), contains('250,00'));
    expect(value(tester, 'general-gain-rate'), '0,0%');
    expect(value(tester, 'general-loss-rate'), '100,0%');
    await filter(tester, '21/08/2026', '21/08/2026');
    expect(value(tester, 'general-period-net'), contains('0,00'));
    expect(value(tester, 'general-gain-rate'), '—');
    await filter(tester, '01/01/2026', '01/01/2026');
    expect(value(tester, 'general-loss-days'), '0 dias');
    expect(value(tester, 'general-loss-rate'), '—');
    expect(tester.takeException(), isNull);
  });
}
