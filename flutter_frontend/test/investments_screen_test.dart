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
      'quote entry carries the remaining holding forward and appends snapshots',
      (tester) async {
    Map<String, dynamic> data = {
      'assets': [
        {
          'id': 'a',
          'kind': 'variable',
          'name': 'Itaúsa PN',
          'ticker': 'ITSA4',
          'institution': 'C6 Bank',
          'notes': '',
          'maturity': '',
          'rate': null
        }
      ],
      'events': [
        {
          'id': 'buy',
          'assetId': 'a',
          'type': 'deposit',
          'date': '2026-01-01',
          'quantity': 100,
          'price': 10,
          'amount': 100000,
          'fees': 0,
          'notes': ''
        },
        {
          'id': 'sale',
          'assetId': 'a',
          'type': 'withdraw',
          'date': '2026-01-02',
          'quantity': 40,
          'price': 10,
          'amount': 40000,
          'fees': 0,
          'notes': ''
        },
      ],
    };
    final original = jsonEncode(data['events']);
    var revision = 1;
    final client = ApiClient(client: MockClient((request) async {
      if (request.method == 'PUT') {
        data = jsonDecode(request.body)['data'];
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
        home: InvestmentsScreen(
            apiUriBuilder: (p) => Uri.parse('https://example.test$p'),
            sessionToken: 'test',
            onOpenDayTradeCapital: () async {},
            onOpenDayTradeDeposit: () async {},
            client: client)));
    await tester.pumpAndSettle();
    for (final price in ['12,00', '13,00']) {
      final open = find.text('Atualizar cotação');
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      final quantity = tester.widget<TextFormField>(
          find.byKey(const ValueKey('Quantidade da última posição')));
      expect(quantity.controller!.text, '60');
      expect(quantity.enabled, false);
      final input = find.byKey(const ValueKey('Cotação por ação / cota (R\$)'));
      await tester.ensureVisible(input);
      await tester.enterText(input, price);
      await tester.pump();
      expect(find.textContaining('Novo patrimônio:'), findsOneWidget);
      await tester.tap(find.text('Registrar'));
      await tester.pumpAndSettle();
    }
    expect(data['events'].length, 4);
    expect(jsonEncode((data['events'] as List).take(2).toList()), original);
    expect(data['events'][2]['quantity'], 60);
    expect(data['events'][2]['amount'], 72000);
    expect(data['events'][3]['quantity'], 60);
    expect(data['events'][3]['amount'], 78000);
    expect(data['events'][2]['id'], isNot(data['events'][3]['id']));
    final refresh = find.byTooltip('Atualizar carteira');
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(data['events'].length, 4);
    expect(tester.takeException(), isNull);
  });
  testWidgets('save reveals a required field below the fold and then submits',
      (tester) async {
    tester.view.physicalSize = const Size(720, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var writes = 0;
    Map<String, dynamic> data = {'assets': [], 'events': []};
    final client = ApiClient(client: MockClient((request) async {
      if (request.method == 'PUT') {
        writes++;
        data = jsonDecode(request.body)['data'];
      }
      return http.Response(
          jsonEncode(
              {'ok': true, 'writable': true, 'revision': writes, 'data': data}),
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
    final add = find.text('Cadastrar renda fixa');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    final amount = find.byKey(const ValueKey('Valor aplicado (R\$)'));
    expect(amount.hitTestable(), findsNothing);
    await tester.tap(find.text('Salvar ativo'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(
        find
            .text('Valor aplicado (R\$): Informe um valor maior que zero.')
            .hitTestable(),
        findsOneWidget);
    expect(amount.hitTestable(), findsOneWidget);
    await tester.enterText(amount, '1.000,00');
    await tester.tap(find.text('Salvar ativo'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(data['events'][0]['amount'], 100000);
    expect(find.text('Salvar ativo'), findsNothing);
    expect(tester.takeException(), isNull);
  });
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
