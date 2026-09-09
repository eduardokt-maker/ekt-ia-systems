import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ekt_ia_flutter_frontend/b3_calendar.dart';
import 'package:ekt_ia_flutter_frontend/win_calendar_screen.dart';

void main() {
  test('WDO: códigos e vencimentos de todos os meses de 2026', () {
    final contracts = wdoContractsForYear(2026);
    expect(contracts.map((c) => c.symbol), [
      'WDOF26',
      'WDOG26',
      'WDOH26',
      'WDOJ26',
      'WDOK26',
      'WDOM26',
      'WDON26',
      'WDOQ26',
      'WDOU26',
      'WDOV26',
      'WDOX26',
      'WDOZ26',
    ]);
    expect(contracts.map((c) => c.expiry.day),
        [2, 2, 2, 1, 4, 1, 1, 3, 1, 1, 3, 1]);
    expect(
        contracts.map((c) => c.expiry.month), List.generate(12, (i) => i + 1));
    expect(contracts.last.nextSymbol, 'WDOF27');
    expect(contracts[4].lastTradingDay, DateTime(2026, 4, 30));
    expect(contracts[10].lastTradingDay, DateTime(2026, 10, 30));
    expect(wdoContractsForYear(2027).first.expiry, DateTime(2027, 1, 4));
    expect(
        wdoContractsForYear(2027).first.lastTradingDay, DateTime(2026, 12, 30));
  });

  test('retém vencimento de hoje, mas WDO negociável já é o seguinte', () {
    expect(remainingWdoContracts(DateTime(2026, 9, 9)).first.symbol, 'WDOV26');
    expect(remainingWdoContracts(DateTime(2026, 10, 1)).first.symbol, 'WDOV26');
    expect(currentWdoContract(DateTime(2026, 10, 1)).symbol, 'WDOX26');
    expect(remainingWdoContracts(DateTime(2026, 10, 2)).first.symbol, 'WDOX26');
    expect(currentWdoContract(DateTime(2026, 12, 31)).symbol, 'WDOF27');
  });

  test('alerta WDO: dois dias anteriores, vencimento e virada do ano', () {
    expect(wdoExpiryAlert(DateTime(2026, 9, 28)), isNull);
    expect(wdoExpiryAlert(DateTime(2026, 9, 29))?.symbol, 'WDOV26');
    expect(wdoExpiryAlert(DateTime(2026, 10, 1))?.symbol, 'WDOV26');
    expect(wdoExpiryAlert(DateTime(2026, 10, 2)), isNull);
    expect(wdoExpiryAlert(DateTime(2028, 12, 31))?.symbol, 'WDOF29');
  });

  test('feriados móveis, pregão de Cinzas e ajuste de WIN no feriado', () {
    expect(isB3TradingDay(DateTime(2026, 2, 16)), isFalse);
    expect(isB3TradingDay(DateTime(2026, 2, 17)), isFalse);
    expect(isB3TradingDay(DateTime(2026, 2, 18)), isTrue);
    expect(isB3TradingDay(DateTime(2026, 4, 3)), isFalse);
    expect(isB3TradingDay(DateTime(2026, 6, 4)), isFalse);
    expect(isB3TradingDay(DateTime(2026, 7, 9)), isTrue);
    expect(winContractsForYear(2033)[4].expiry, DateTime(2033, 10, 13));
  });

  for (final width in [390.0, 1200.0]) {
    testWidgets('exibe WIN e WDO, fontes e virada anual na largura $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          MaterialApp(home: WinCalendarScreen(now: DateTime(2026, 9, 9))));
      expect(find.text('Vencimento de contratos futuros'), findsOneWidget);
      expect(find.text('Mini Índice • WIN'), findsOneWidget);
      expect(find.text('Mini Dólar • WDO'), findsOneWidget);
      expect(find.text('WDOV26'), findsOneWidget);
      expect(find.text('WINV26'), findsOneWidget);
      expect(find.text('Especificações oficiais B3'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
          MaterialApp(home: WinCalendarScreen(now: DateTime(2026, 12, 31))));
      expect(find.text('WING27'), findsOneWidget);
      expect(find.text('WDOF27'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
