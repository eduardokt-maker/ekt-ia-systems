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
      ],
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
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

  testWidgets('type and status filters always return matching records',
      (WidgetTester tester) async {
    await _pumpBudget(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Receita'));
    await tester.pump();
    expect(find.textContaining('1 '), findsWidgets);

    await tester.tap(find.widgetWithText(FilterChip, 'Despesa'));
    await tester.pump();
    expect(find.textContaining('1 '), findsWidgets);

    await tester.tap(find.widgetWithText(FilterChip, 'Todos'));
    await tester.pump();
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
