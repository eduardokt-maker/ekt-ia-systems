import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ekt_ia_flutter_frontend/main.dart';
import 'package:ekt_ia_flutter_frontend/jex_screen.dart';

void main() {
  testWidgets('abre a central Flutter e acessa investimentos',
      (WidgetTester tester) async {
    await tester.pumpWidget(const EktIaApp());

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Ibovespa'), findsOneWidget);
    expect(find.text('Investimentos'), findsOneWidget);
    expect(find.text('Plan the Trading'), findsOneWidget);
    expect(find.text('JEX'), findsOneWidget);

    await tester.ensureVisible(find.text('Investimentos'));
    await tester.tap(find.text('Investimentos'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('abre Plan the Trading como módulo independente',
      (WidgetTester tester) async {
    await tester.pumpWidget(const EktIaApp());

    await tester.ensureVisible(find.text('Plan the Trading'));
    await tester.tap(find.text('Plan the Trading'));
    await tester.pumpAndSettle();

    expect(find.text('Planejamento diário de Day Trade'), findsOneWidget);
    expect(find.text('Bom dia!'), findsOneWidget);
  });

  testWidgets('exibe Controle bancário e cartões no menu inicial',
      (WidgetTester tester) async {
    await tester.pumpWidget(const EktIaApp());

    expect(find.text('Controle bancário e cartões'), findsOneWidget);
    await tester.ensureVisible(find.text('Controle bancário e cartões'));
    await tester.tap(find.text('Controle bancário e cartões'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('abre a JEX pela rota contextual', (WidgetTester tester) async {
    await tester.pumpWidget(const EktIaApp());

    Navigator.of(tester.element(find.byType(HomeScreen))).pushNamed(jexRoute);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(JexScreen), findsOneWidget);
  });
}
