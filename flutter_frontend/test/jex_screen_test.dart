import 'package:ekt_ia_flutter_frontend/jex_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fotografia financeira abre como tela visual independente',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: JexFinancialSnapshotScreen(financial: {
        'revenue_2023': 112.0,
        'loss_2023': 24.5,
        'working_capital_deficit': 44.0,
        'tax_debt': 25.0,
        'additional_capital': 13.0,
      }),
    ));

    expect(find.text('Fotografia financeira JEX'), findsOneWidget);
    expect(find.text('Pressões financeiras públicas'), findsOneWidget);
    expect(find.text('Déficit de capital de giro'), findsOneWidget);
  });
}
