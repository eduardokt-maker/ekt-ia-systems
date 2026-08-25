import 'package:ekt_ia_flutter_frontend/budget_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BudgetItem _item({
  required int id,
  required String type,
  required String description,
  required bool settled,
  String referenceMonth = '2026-07',
}) {
  return BudgetItem.fromJson(<String, dynamic>{
    'id': id,
    'reference_month': referenceMonth,
    'item_type': type,
    'description': description,
    'observation': '',
    'amount_text': '100,00',
    'received_amount_text': type == 'Receita' && settled ? '100,00' : '0,00',
    'due_date': '2026-08-10',
    'payment_date': settled ? '2026-08-11' : null,
    'settled': settled,
  });
}

Future<void> _pumpBudget(WidgetTester tester,
    {Size size = const Size(1345, 605)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: BudgetScreen(
      apiUriBuilder: (String path) => Uri.parse('https://example.test$path'),
      sessionToken: 'test',
      initialItems: <BudgetItem>[
        _item(id: 1, type: 'Receita', description: 'SALARIO', settled: true),
        _item(
            id: 2,
            type: 'Despesa',
            description: 'ENERGIA',
            settled: false,
            referenceMonth: ''),
        _item(id: 3, type: 'Despesa', description: 'ALUGUEL', settled: true),
        _item(
            id: 4, type: 'Receita', description: 'DIVIDENDOS', settled: false),
      ],
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('gera relatório PDF profissional com os itens recebidos da visualização',
      () async {
    final bytes = await buildBudgetListingReportPdf(
      items: <BudgetItem>[
        _item(id: 1, type: 'Receita', description: 'SALARIO', settled: true),
        _item(id: 2, type: 'Despesa', description: 'ENERGIA', settled: false),
      ],
      filters: const <String>['Período: todos os meses', 'Tipo: Todos'],
      generatedAt: DateTime(2026, 8, 20, 10, 30),
    );

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(3000));
  });

  test('periodo principal limita os lancamentos pela referencia', () {
    final List<BudgetItem> items = <BudgetItem>[
      _item(id: 1, type: 'Receita', description: 'JULHO', settled: true),
      _item(
          id: 2,
          type: 'Despesa',
          description: 'AGOSTO',
          settled: false,
          referenceMonth: '2026-08'),
    ];

    expect(filterBudgetItemsByPeriod(items, null), hasLength(2));
    expect(filterBudgetItemsByPeriod(items, '2026-07').single.description,
        'JULHO');
    expect(filterBudgetItemsByPeriod(items, '2026-08').single.description,
        'AGOSTO');
  });

  testWidgets('primary actions card is the third section in compact layout',
      (WidgetTester tester) async {
    await _pumpBudget(tester);

    final Finder actions = find.byKey(const Key('budget-primary-actions'));
    expect(actions, findsOneWidget);
    expect(find.byKey(const Key('open-new-budget-entry')), findsOneWidget);
    expect(find.byKey(const Key('print-current-budget')), findsOneWidget);
    expect(
        find.byKey(const Key('print-current-budget-appbar')), findsOneWidget);
    expect(find.byKey(const Key('open-cash-report')), findsOneWidget);
    expect(find.byKey(const Key('open-budget-bi')), findsOneWidget);
    expect(find.byKey(const Key('bank-balance-placeholder')), findsOneWidget);
    expect(
        find.byKey(const Key('budget-primary-period-filter')), findsOneWidget);
    final double actionsTop = tester.getTopLeft(actions).dy;
    await tester.scrollUntilVisible(
      find.text('Buscar descrição'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(actionsTop,
        lessThan(tester.getTopLeft(find.text('Buscar descrição')).dy));
  });

  testWidgets('primary actions card is above workspace on desktop',
      (WidgetTester tester) async {
    await _pumpBudget(tester, size: const Size(1200, 800));

    final Finder actions = find.byKey(const Key('budget-primary-actions'));
    expect(actions, findsOneWidget);
    expect(tester.getTopLeft(actions).dy,
        lessThan(tester.getTopLeft(find.text('Buscar descrição')).dy));
  });

  testWidgets('novo lancamento de receita remove somente natureza da despesa',
      (WidgetTester tester) async {
    await _pumpBudget(tester);

    await tester.tap(find.byKey(const Key('open-new-budget-entry')));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma natureza cadastrada'), findsOneWidget);
    expect(find.text('Mês de Referência'), findsOneWidget);

    await tester.tap(find.text('Receita').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('budget-new-revenue-type')), findsOneWidget);
    expect(find.byKey(const Key('budget-new-expense-nature')), findsNothing);
    expect(find.text('Nenhuma natureza cadastrada'), findsNothing);
    expect(find.text('Mês de Referência'), findsOneWidget);
    expect(find.text('Data de Vencimento'), findsOneWidget);
    expect(find.text('Data de Pagamento'), findsOneWidget);
  });

  testWidgets('periodo principal fica ao lado de configurar despesas',
      (WidgetTester tester) async {
    await _pumpBudget(tester);

    final Finder configure = find.byKey(const Key('open-expense-natures'));
    final Finder period = find.byKey(const Key('budget-primary-period-filter'));
    expect(tester.getTopLeft(period).dx,
        greaterThan(tester.getTopLeft(configure).dx));
    expect(
        (tester.getTopLeft(period).dy - tester.getTopLeft(configure).dy).abs(),
        lessThan(12));
    expect(find.text('Todos os meses'), findsWidgets);
    expect(
        find.byKey(const Key('budget-month-status-control')), findsOneWidget);
    expect(
        find.byKey(const Key('import-previous-budget-month')), findsOneWidget);
    expect(find.text('Selecione um mês'), findsOneWidget);
  });

  testWidgets(
      'compact layout lists all items by default and preserves legacy item',
      (WidgetTester tester) async {
    await _pumpBudget(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('budget-entry-2')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey<String>('budget-entry-1')), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('budget-entry-2')), findsOneWidget);
    expect(find.text('ENERGIA').hitTestable(), findsOneWidget);
  });

  testWidgets('type and status filters can be combined',
      (WidgetTester tester) async {
    await _pumpBudget(tester, size: const Size(1200, 800));
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Receita'));
    await tester.pumpAndSettle();

    expect(find.text('Mais filtros'), findsNothing);
    expect(find.byType(FilterChip), findsNWidgets(5));
    expect(find.byKey(const Key('budget-filtered-total')), findsNothing);
    expect(
        tester
            .widgetList<FilterChip>(find.byType(FilterChip))
            .where((FilterChip chip) => chip.selected),
        hasLength(1));

    await tester.tap(find.widgetWithText(FilterChip, 'Receita'));
    await tester.pump();
    expect(find.textContaining('2 '), findsWidgets);
    expect(
        tester
            .widgetList<FilterChip>(find.byType(FilterChip))
            .where((FilterChip chip) => chip.selected),
        hasLength(1));

    await tester.tap(find.widgetWithText(FilterChip, 'Despesa'));
    await tester.pump();
    expect(find.textContaining('2 '), findsWidgets);
    expect(find.byKey(const Key('budget-filtered-total')), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Quitado'));
    await tester.pump();
    expect(find.textContaining('1 '), findsWidgets);
    expect(
        find.descendant(
            of: find.byKey(const Key('budget-filtered-total')),
            matching: find.text('R\$ 100,00')),
        findsOneWidget);
    expect(
        tester
            .widgetList<FilterChip>(find.byType(FilterChip))
            .where((FilterChip chip) => chip.selected),
        hasLength(2));

    await tester.tap(find.widgetWithText(FilterChip, 'Pendente'));
    await tester.pump();
    expect(find.textContaining('1 '), findsWidgets);
    expect(
        find.descendant(
            of: find.byKey(const Key('budget-filtered-total')),
            matching: find.text('R\$ 100,00')),
        findsOneWidget);
    expect(
        tester
            .widgetList<FilterChip>(find.byType(FilterChip))
            .where((FilterChip chip) => chip.selected),
        hasLength(2));

    await tester.tap(find.widgetWithText(FilterChip, 'Todos'));
    await tester.pump();
    expect(find.textContaining('2 '), findsWidgets);
    expect(find.byKey(const Key('budget-filtered-total')), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Receita'));
    await tester.pump();
    expect(
        find.descendant(
            of: find.byKey(const Key('budget-filtered-total')),
            matching: find.text('R\$ 100,00')),
        findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Quitado'));
    await tester.pump();
    expect(
        find.descendant(
            of: find.byKey(const Key('budget-filtered-total')),
            matching: find.text('R\$ 100,00')),
        findsOneWidget);
  });

  testWidgets('revenue uses received as settled and not received as pending',
      (WidgetTester tester) async {
    await _pumpBudget(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -220));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Receita'));
    await tester.pump();
    expect(find.textContaining('2 '), findsWidgets);

    await tester.tap(find.widgetWithText(FilterChip, 'Quitado'));
    await tester.pump();
    expect(find.textContaining('1 '), findsWidgets);

    await tester.tap(find.widgetWithText(FilterChip, 'Pendente'));
    await tester.pump();
    expect(find.textContaining('1 '), findsWidgets);
  });

  testWidgets('mobile layout keeps legacy and current entries reachable',
      (WidgetTester tester) async {
    await _pumpBudget(tester, size: const Size(390, 844));

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('budget-entry-2')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey<String>('budget-entry-1')), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('budget-entry-2')), findsOneWidget);
  });
}
