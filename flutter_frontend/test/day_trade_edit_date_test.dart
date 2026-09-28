import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ekt_ia_flutter_frontend/api_client.dart';
import 'package:ekt_ia_flutter_frontend/day_trade_screen.dart';

void main() {
  Map<String, dynamic>? sent;
  var operation = <String, dynamic>{};
  setUpAll(() {
    final client = MockClient((request) async {
      if (request.method == 'PATCH') {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'ok': true}), 200);
      }
      return http.Response(
          jsonEncode({
            'ok': true,
            'items': [operation]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    http.runWithClient(() => apiClient, () => client);
  });

  for (final entry in ['188860.0000', '']) {
    testWidgets('altera data de Break Even com entrada "$entry"',
        (tester) async {
      sent = null;
      operation = {
        'id': 1,
        'trade_date': '2026-09-15',
        'asset': 'WINV26',
        'market': 'Mini índice',
        'direction': 'Compra',
        'quantity': 2,
        'entry_time': '09:16',
        'exit_time': '09:18',
        'entry_price_text': entry,
        'exit_price_text': entry,
        'point_value_text': '0.20',
        'stop_price_text': '',
        'target_price_text': '',
        'costs_text': '0',
        'strategy': 'SCALP',
        'operation_result': 'BREAK_EVEN',
        'status': 'ENCERRADA',
        'net_result': 0,
      };
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: DayTradeScreen(
        apiUriBuilder: (path) => Uri.parse('https://test.invalid$path'),
        sessionToken: 'test',
      )));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Editar'));
      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Data da operação')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('16').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar alterações'));
      await tester.pumpAndSettle();
      expect(sent, isNotNull);
      expect(sent!['trade_date'], '2026-09-16');
      expect(sent!['stop_price_text'], '');
      expect(sent!['target_price_text'], '');
      expect(sent!['entry_price_text'], entry.isEmpty ? '' : '188860,00');
      expect(sent!['exit_time'], '09:18');
      expect(sent!['operation_result'], 'BREAK_EVEN');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  test('mensagem da API é legível no indicador de erro', () {
    expect(const TradeApiException('Informe uma data válida.').toString(),
        'Informe uma data válida.');
  });
}
