import 'package:ekt_ia_flutter_frontend/ibovespa_quote.dart';
import 'package:ekt_ia_flutter_frontend/ibovespa_quote_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final quote = IbovespaQuote.fromJson(<String, dynamic>{
    'symbol': 'TEST3',
    'name': 'Empresa de Teste',
    'sector': 'Tecnologia',
    'price': 25.5,
    'change': 1.25,
    'change_percent': 5,
    'volume': 1000000,
    'financial_volume': 25500000,
    'market_cap': 1000000000,
    'day_open': 24,
    'day_high': 26,
    'day_low': 23.5,
    'market_time': '20/07/2026 10:30:15',
    'market_state': 'REGULAR',
    'is_stale': false,
    'intraday_prices': <double>[24, 24.4, 24.1, 25, 25.5],
  });

  test('modelo tipado preserva dados intradiarios e direcao', () {
    expect(quote.direction, QuoteDirection.up);
    expect(quote.intradayPrices, hasLength(5));
    expect(quote.timeLabel, '10:30:15');
    expect(formatPercent(quote.changePercent), '+5,00%');
    expect(formatBrl(quote.price), r'R$ 25,50');
  });

  testWidgets('card compacto exibe metricas, estado e favorito',
      (tester) async {
    var favoritePressed = false;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 220,
            child: IbovespaQuoteCard(
              quote: quote,
              favorite: false,
              selected: false,
              badges: const <String>['Maior alta', 'Mais negociada'],
              onTap: () {},
              onFavorite: () => favoritePressed = true,
            ),
          ),
        ),
      ),
    ));

    expect(find.text('TEST3'), findsOneWidget);
    expect(find.text(r'R$ 25,50'), findsOneWidget);
    expect(find.text('Mercado aberto'), findsOneWidget);
    expect(find.text('Maior alta'), findsOneWidget);
    await tester.tap(find.byTooltip('Adicionar aos favoritos'));
    expect(favoritePressed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
