import 'dart:convert';
import 'package:ekt_ia_flutter_frontend/api_client.dart';
import 'package:ekt_ia_flutter_frontend/bank_outflows_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

String token() => '${base64Url.encode(utf8.encode(jsonEncode({
          'exp': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        })))}.test';

void main() {
  testWidgets(
      'lista inicia no mês atual e sincroniza upload de outro aparelho sem perder filtro ou sessão',
      (tester) async {
    await initializeDateFormatting('pt_BR');
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final previous = DateTime(now.year, now.month - 1, 10);
    Map<String, dynamic> row(
            int id, String who, DateTime date, double amount) =>
        {
          'id': id,
          'sequence_number': id,
          'destination': who,
          'transaction_date': DateFormat('dd/MM/yyyy').format(date),
          'amount': amount,
          'payment_type': 'Pix',
          'description': '',
          'document_number': '',
          'expense_nature_name': '',
        };
    var items = [
      row(1, 'Despesa anterior', previous, 15),
      row(2, 'Despesa atual', now, 20)
    ];
    var reads = 0;
    final api = ApiClient(client: MockClient((request) async {
      Object body;
      switch (request.url.path) {
        case '/api/banking-lab/outflows':
          reads++;
          body = {
            'ok': true,
            'outflows': items,
            'summary': {
              'count': items.length,
              'total': items.fold<double>(
                  0, (sum, item) => sum + (item['amount'] as double))
            }
          };
        case '/api/banking-lab':
          body = {'ok': true, 'files': []};
        case '/api/banking-lab/banks':
          body = {'ok': true, 'banks': []};
        case '/api/banking-lab/natures':
          body = {'ok': true, 'natures': []};
        default:
          throw StateError('Unexpected request: ${request.url}');
      }
      return http.Response(jsonEncode(body), 200);
    }));
    api.startSession(
        accessToken: token(),
        refreshToken: 'refresh',
        uriBuilder: (p) => Uri.parse('https://test$p'));
    addTearDown(api.clearSession);
    await tester.pumpWidget(MaterialApp(
        home: BankOutflowsScreen(
            apiUriBuilder: (p) => Uri.parse('https://test$p'), client: api)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Listagem de despesas'));
    await tester.tap(find.text('Listagem de despesas'));
    await tester.pumpAndSettle();
    expect(find.text('Despesa atual'), findsOneWidget);
    expect(find.text('Despesa anterior'), findsNothing);
    expect(find.textContaining('1 registros'), findsOneWidget);
    items = [...items, row(3, 'Enviada pelo celular', now, 30)];
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Enviada pelo celular'), findsOneWidget);
    expect(find.textContaining('2 registros'), findsOneWidget);
    expect(api.isAuthenticated, isTrue);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todo o histórico').last);
    await tester.pumpAndSettle();
    expect(find.text('Despesa anterior'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Despesa anterior'), findsOneWidget);
    expect(reads, greaterThanOrEqualTo(3));
    await tester.pumpWidget(const SizedBox());
    final stoppedReads = reads;
    await tester.pump(const Duration(seconds: 20));
    expect(reads, stoppedReads);
    api.clearSession();
  });

  test('falha temporária na renovação não apaga a sessão', () async {
    final api = ApiClient(
        client: MockClient((r) async =>
            http.Response('{}', r.url.path.endsWith('/refresh') ? 503 : 401)));
    var expired = false;
    api.onSessionExpired = () => expired = true;
    api.startSession(
        accessToken: token(),
        refreshToken: 'refresh',
        uriBuilder: (p) => Uri.parse('https://test$p'));
    addTearDown(api.clearSession);
    await expectLater(
        api.get(Uri.parse('https://test/api/banking-lab/outflows')),
        throwsA(isA<ApiFailure>()));
    expect(api.isAuthenticated, isTrue);
    expect(expired, isFalse);
  });

  test('credencial de renovação revogada encerra a sessão', () async {
    final api =
        ApiClient(client: MockClient((r) async => http.Response('{}', 401)));
    api.startSession(
        accessToken: token(),
        refreshToken: 'revoked',
        uriBuilder: (p) => Uri.parse('https://test$p'));
    addTearDown(api.clearSession);
    await expectLater(
        api.get(Uri.parse('https://test/api/banking-lab/outflows')),
        throwsA(isA<ApiFailure>()));
    expect(api.isAuthenticated, isFalse);
  });
}
