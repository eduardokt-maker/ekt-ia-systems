import 'package:ekt_ia_flutter_frontend/day_trade_navigation_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gera PDF impresso otimizado sem status e estratégia', () async {
    final bytes = await buildDayTradeNavigationReport(
      period: '01/08/2026 a 03/08/2026',
      generatedAt: '03/08/2026 18:00',
      metrics: const <NavigationReportMetric>[
        NavigationReportMetric('Registros', '2'),
        NavigationReportMetric('Resultados positivos', r'R$ 250,00'),
        NavigationReportMetric('Resultados negativos', r'-R$ 100,00'),
        NavigationReportMetric('Saldo liquido', r'R$ 150,00'),
      ],
      rows: List<List<String>>.generate(
        18,
        (index) => <String>[
          '03/08/2026',
          '09:10 - 09:22',
          'WIN',
          'Mini indice',
          'Compra',
          '1',
          '135.000',
          '134.900',
          '135.200',
          '135.150',
          r'R$ 250,00',
          '150',
          'ENCERRADA',
          'Rompimento',
        ],
      ),
      printOptimized: true,
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(2500));
  });
}
