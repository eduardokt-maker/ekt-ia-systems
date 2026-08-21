import 'package:ekt_ia_flutter_frontend/capital_flow_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fluxo de investidores abre diretamente sem login',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CapitalFlowEntryScreen(
        apiUriBuilder: (String path) => Uri.parse('https://example.test$path'),
      ),
    ));

    expect(find.text('ACESSO AO MONITOR B3'), findsNothing);
    expect(find.text('LOGIN'), findsNothing);
    expect(find.text('FLUXO DE INVESTIDORES B3'), findsWidgets);
  });
}
