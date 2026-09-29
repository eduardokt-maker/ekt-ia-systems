import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ekt_ia_flutter_frontend/api_client.dart';
import 'package:ekt_ia_flutter_frontend/day_trade_screen.dart';

void main() {
  Map<String, dynamic>? saved;
  var fail = false;
  var failLoad = false;
  var writes = 0;
  setUpAll(() {
    http.runWithClient(
        () => apiClient,
        () => MockClient((request) async {
              if (request.method == 'GET' && failLoad) return http.Response('{}', 503);
        if (request.method == 'PUT') {
                writes++;
                if (fail)
                  return http.Response(
                      jsonEncode({
                        'ok': false,
                        'message': 'Falha de conexão. Tente novamente.'
                      }),
                      503);
                expect(request.url.path, '/api/day-trade/daily-result');
                final body = jsonDecode(request.body) as Map<String, dynamic>;
                saved = {
                  ...body,
                  'revision': (body['expected_revision'] as int) + 1,
                  'net_result': double.parse(
                      (body['net_result_text'] as String).replaceAll(',', '.'))
                };
              }
              return http.Response(
                  jsonEncode({
                    'ok': true,
                    'items': [],
                    'daily_result': saved,
                    'summary': {'net_result': saved?['net_result'] ?? 0}
                  }),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }));
  });

  testWidgets('save, reload, correct and retain input on failure',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget screen() => MaterialApp(
        home: DayTradeScreen(
            apiUriBuilder: (path) => Uri.parse('https://test.invalid$path'),
            sessionToken: 'test'));
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Somente resultado líquido do dia'));
    await tester.pumpAndSettle();
    final amount = find.byKey(const Key('daily-net-result'));
    final save = find.byKey(const Key('save-daily-result'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.enterText(amount, '-350,00');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved?['net_result'], -350);
    expect(saved?['expected_revision'], 0);
    expect(find.text('Atualizar resultado do dia'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(amount).controller!.text, '-350,00');
    await tester.enterText(amount, '0');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved?['net_result'], 0);
    expect(saved?['expected_revision'], 1);
    fail = true;
    await tester.enterText(amount, '125,50');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(amount).controller!.text, '125,50');
    expect(find.text('Servidor indisponivel. Tente novamente em instantes.'),
        findsOneWidget);
    expect(saved?['net_result'], 0);
    failLoad = true;
    await tester.tap(find.byTooltip('Atualizar'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
