import 'package:flutter_test/flutter_test.dart';
import 'package:ekt_ia_flutter_frontend/main.dart';

void main() {
  testWidgets('abre a central Flutter e acessa investimentos',
      (WidgetTester tester) async {
    await tester.pumpWidget(const EktIaApp());

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Ibovespa'), findsOneWidget);
    expect(find.text('Investimentos'), findsOneWidget);
    expect(find.text('JEX'), findsOneWidget);

    await tester.tap(find.text('Investimentos'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
