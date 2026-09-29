import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ekt_ia_flutter_frontend/api_client.dart';
import 'package:ekt_ia_flutter_frontend/day_trade_navigation_screen.dart';
import 'package:ekt_ia_flutter_frontend/day_trade_screen.dart';

void main() {
  var detailed = false;
  setUpAll(() {
    http.runWithClient(
        () => apiClient,
        () => MockClient((request) async {
              return http.Response(
                  jsonEncode({
                    'ok': true,
                    'items': detailed
                        ? [
                            {
                              'id': 1,
                              'trade_date': '2026-09-25',
                              'asset': 'WIN',
                              'net_result': 75,
                            }
                          ]
                        : [],
                    'daily_results': [
                      {'trade_date': '2026-09-28', 'net_result': 250.5},
                      {'trade_date': '2026-09-29', 'net_result': -350},
                      {'trade_date': '2026-09-30', 'net_result': 0},
                    ],
                  }),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }));
  });

  for (final mixed in [false, true]) {
    testWidgets(
        'daily records displayed, counted once and editable: mixed=$mixed',
        (tester) async {
      detailed = mixed;
      tester.view.physicalSize = const Size(1800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: DayTradeNavigationScreen(
        apiUriBuilder: (path) => Uri.parse('https://test.invalid$path'),
        sessionToken: 'test',
      )));
      await tester.pumpAndSettle();
      expect(find.text('Resultado diário'), findsNWidgets(3));
      expect(find.text('250,50'), findsOneWidget);
      expect(find.text('-350,00'), findsOneWidget);
      expect(find.text('0,00'), findsOneWidget);
      expect(find.textContaining('${mixed ? 4 : 3} REGISTROS'), findsOneWidget);
      expect(find.textContaining(mixed ? '24,50' : '99,50'), findsOneWidget);
      await tester.tap(find.byKey(const Key('navigation-daily-consolidated')));
      await tester.pumpAndSettle();
      final consolidated = tester.widget<DayTradeDailyConsolidatedScreen>(
          find.byType(DayTradeDailyConsolidatedScreen));
      expect(consolidated.entries.length, mixed ? 4 : 3);
      expect(consolidated.entries.fold<double>(0, (s, e) => s + e.netResult),
          mixed ? -24.5 : -99.5);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('EDITAR REGISTRO SELECIONADO'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<DayTradeScreen>(find.byType(DayTradeScreen))
              .initialDate,
          DateTime(2026, 9, 30));
    });
  }
}
