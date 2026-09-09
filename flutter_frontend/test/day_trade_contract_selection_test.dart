import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ekt_ia_flutter_frontend/api_client.dart';
import 'package:ekt_ia_flutter_frontend/day_trade_screen.dart';
import 'package:ekt_ia_flutter_frontend/win_calendar_screen.dart';
import 'package:ekt_ia_flutter_frontend/b3_calendar.dart';

void main() {
  Map<String, dynamic>? sent;
  setUpAll(() {
    final client = MockClient((request) async {
      if (request.method == 'POST')
        sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'ok': true, 'items': []}),
          request.method == 'POST' ? 201 : 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    http.runWithClient(() => apiClient, () => client);
  });

  testWidgets(
      'seleciona contratos, calcula WDO e envia lançamento com R\$ 10 por ponto',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: DayTradeScreen(
            apiUriBuilder: (path) => Uri.parse('https://test.invalid$path'),
            sessionToken: 'test')));
    await tester.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label);
    Future<void> enter(String label, String value) async {
      await tester.ensureVisible(field(label));
      await tester.enterText(field(label), value);
      await tester.pump();
    }

    final wdo = find.byKey(const Key('use-current-wdo-contract'));
    await tester.ensureVisible(wdo);
    await tester.tap(wdo);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field('Ativo')).controller!.text,
        currentWdoContract(b3Today()).symbol);
    await enter('Quantidade', '3');
    await enter('Preço de entrada', '5430');
    await enter('Preço do stop', '5420');
    await enter('Preço do alvo', '5440');
    expect(find.textContaining('300,00 | +10 pontos'), findsOneWidget);
    await tester.ensureVisible(find.text('GANHO NO ALVO'));
    await tester.tap(find.text('GANHO NO ALVO'));
    await tester.pump();
    await enter('Custos operacionais', '5');
    expect(tester.widget<Text>(find.byKey(const Key('trade-net-preview'))).data,
        contains('295,00'));
    await enter('Horário da entrada', '1030');
    await enter('Estratégia', 'Rompimento');
    await tester.ensureVisible(find.text('Registrar operação'));
    await tester.tap(find.text('Registrar operação'));
    await tester.pumpAndSettle();
    expect(sent?['market'], 'Mini dólar');
    expect(sent?['point_value_text'], '10');
    expect(sent?['quantity'], 3);
    expect(sent?['operation_result'], 'Gain');
    final win = find.byKey(const Key('use-current-win-contract'));
    await tester.ensureVisible(win);
    await tester.tap(win);
    await tester.pump();
    expect(tester.widget<TextField>(field('Ativo')).controller!.text,
        currentWinContract(b3Today()).symbol);
    expect(find.textContaining('0,20 / contrato'), findsOneWidget);
    await enter('Ativo', 'WDOX26');
    expect(find.textContaining('10,00 / contrato'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
