import 'package:flutter_test/flutter_test.dart';
import 'package:ekt_ia_flutter_frontend/main.dart';

void main() {
  testWidgets('abre a tela de login', (WidgetTester tester) async {
    await tester.pumpWidget(const EktIaApp());

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
