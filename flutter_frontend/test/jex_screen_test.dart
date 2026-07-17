import 'package:ekt_ia_flutter_frontend/jex_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fotografia financeira abre como tela visual independente',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: JexFinancialSnapshotScreen(financial: {
        'revenue_2023': 112.0,
        'loss_2023': 24.5,
        'working_capital_deficit': 44.0,
        'tax_debt': 25.0,
        'additional_capital': 13.0,
      }),
    ));

    expect(find.text('Fotografia financeira JEX'), findsOneWidget);
    expect(find.text('Pressões financeiras públicas — 2023'), findsOneWidget);
    expect(find.text('Déficit de capital de giro'), findsOneWidget);
    expect(find.text('DADOS VERIFICADOS • EXERCÍCIO 2023'), findsOneWidget);
  });

  testWidgets('fonte financeira apresenta leitura em português',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: JexPortugueseSourceScreen(source: {
        'year': '2024',
        'status': 'preliminary',
        'status_label': 'Preliminar',
        'title': 'Receita declarada pela administração',
        'source_label': 'De Ondernemer',
        'portuguese_summary': [
          'A receita declarada foi de aproximadamente EUR 220 milhões.'
        ],
      }),
    ));

    expect(find.text('Fonte em português'), findsOneWidget);
    expect(find.text('Conteúdo traduzido e resumido'), findsOneWidget);
    expect(find.textContaining('EUR 220 milhões'), findsOneWidget);
    expect(find.text('COMO INTERPRETAR'), findsOneWidget);
    expect(find.textContaining('Abrir publicação original'), findsNothing);
  });

  testWidgets('notícia JEX oferece leitura bilíngue e saída', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: JexNewsDetailScreen(news: {
        'published_at': '2026-07-17T12:00:00+00:00',
        'source': 'Euronext',
        'source_region': 'Amsterdam / União Europeia',
        'title_pt': 'Título em português',
        'title_en': 'English title',
        'summary_pt': 'Resumo informativo em português.',
        'summary_en': 'Informative summary in English.',
      }),
    ));

    expect(find.text('Título em português'), findsOneWidget);
    expect(find.text('Concluir leitura e sair'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pump();
    expect(find.text('English title'), findsOneWidget);
    expect(find.text('Finish reading and exit'), findsOneWidget);
  });
}
