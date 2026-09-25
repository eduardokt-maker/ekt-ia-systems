import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ekt_ia_flutter_frontend/api_client.dart';
import 'package:ekt_ia_flutter_frontend/investments_screen.dart';

void main() {
  testWidgets(
      'mobile registration offers ITSA4 and persists quantity, price and date atomically',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic> data = {'assets': [], 'events': []};
    int revision = 0;
    final client = ApiClient(client: MockClient((request) async {
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        data = body['data'];
        revision++;
      }
      return http.Response(
          jsonEncode({
            'ok': true,
            'writable': true,
            'revision': revision,
            'data': data
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: InvestmentsScreen(
            apiUriBuilder: (p) => Uri.parse('https://example.test$p'),
            sessionToken: 'test',
            onOpenDayTradeCapital: () async {},
            onOpenDayTradeDeposit: () async {},
            client: client)));
    await tester.pumpAndSettle();
    final add = find.text('Cadastrar renda variável');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('ITSA4 · Itaúsa PN'), findsOneWidget);
    final quantity =
        find.widgetWithText(TextFormField, 'Quantidade de ações / cotas');
    await tester.ensureVisible(quantity);
    await tester.enterText(quantity, '100');
    final price = find.widgetWithText(
        TextFormField, 'Preço de compra por ação / cota (R\$)');
    await tester.ensureVisible(price);
    await tester.enterText(price, '10,50');
    await tester.tap(find.text('Salvar ativo'));
    await tester.pumpAndSettle();
    expect(data['assets'][0]['ticker'], 'ITSA4');
    expect(data['events'][0]['quantity'], 100);
    expect(data['events'][0]['amount'], 105000);
    expect(data['events'][0]['date'], matches(r'^\d{4}-\d{2}-\d{2}$'));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'failed save retains entered values; fixed income defaults are editable',
      (tester) async {
    final client = ApiClient(client: MockClient((request) async {
      if (request.method == 'PUT')
        return http.Response(
            jsonEncode({'message': 'Conflito: atualize a carteira.'}), 409,
            headers: {'content-type': 'application/json; charset=utf-8'});
      return http.Response(
          jsonEncode({
            'ok': true,
            'writable': true,
            'revision': 0,
            'data': {'assets': [], 'events': []}
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    await tester.pumpWidget(MaterialApp(
        home: InvestmentsScreen(
            apiUriBuilder: (p) => Uri.parse('https://example.test$p'),
            sessionToken: 'test',
            onOpenDayTradeCapital: () async {},
            onOpenDayTradeDeposit: () async {},
            client: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cadastrar renda fixa'));
    await tester.pumpAndSettle();
    expect(find.text('Tesouro Prefixado 2029'), findsOneWidget);
    expect(find.text('C6 Bank'), findsOneWidget);
    expect(find.text('01/01/2029'), findsOneWidget);
    final amount = find.widgetWithText(TextFormField, 'Valor aplicado (R\$)');
    await tester.ensureVisible(amount);
    await tester.enterText(amount, '1.000,00');
    await tester.tap(find.text('Salvar ativo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Conflito:'), findsOneWidget);
    expect(find.text('1.000,00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
