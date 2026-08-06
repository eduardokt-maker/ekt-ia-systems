import 'package:ekt_ia_flutter_frontend/day_trade_bi_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('intervalo livre', () {
    test('converte datas válidas no formato DD/MM/AAAA', () {
      expect(parseBiDateInput('03/08/2026'), DateTime(2026, 8, 3));
      expect(formatBiDateInput(DateTime(2026, 8, 3)), '03/08/2026');
    });

    test('rejeita formato incompleto e datas inexistentes', () {
      expect(parseBiDateInput('3/8/2026'), isNull);
      expect(parseBiDateInput('31/02/2026'), isNull);
      expect(parseBiDateInput(''), isNull);
    });

    test('máscara inclui as barras durante a digitação', () {
      final result = BiDateInputFormatter().formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '03082026'),
      );
      expect(result.text, '03/08/2026');
    });
  });

  test('filtro Dia exibe data e dia da semana em pt-BR', () {
    final labels = <DateTime, String>{
      DateTime(2026, 7, 27): '27/07/2026 — Segunda-feira',
      DateTime(2026, 7, 28): '28/07/2026 — Terça-feira',
      DateTime(2026, 7, 29): '29/07/2026 — Quarta-feira',
      DateTime(2026, 7, 30): '30/07/2026 — Quinta-feira',
      DateTime(2026, 7, 31): '31/07/2026 — Sexta-feira',
      DateTime(2026, 8, 1): '01/08/2026 — Sábado',
      DateTime(2026, 8, 2): '02/08/2026 — Domingo',
    };

    for (final entry in labels.entries) {
      expect(formatBiDayLabel(entry.key), entry.value);
    }
  });

  test('resumo do total informa intervalo e contagem inclusiva de dias', () {
    expect(
      formatBiPeriodSummary(DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31),
      )),
      'De 01/07/2026 até 31/07/2026 • 31 dias',
    );
    expect(
      formatBiPeriodSummary(DateTimeRange(
        start: DateTime(2026, 7, 27),
        end: DateTime(2026, 7, 27),
      )),
      'De 27/07/2026 até 27/07/2026 • 1 dia',
    );
  });

  test('BI calcula resultado, acerto, profit factor e drawdown', () {
    final analytics = BiAnalytics(<BiTrade>[
      const BiTrade(
        date: '2026-07-01',
        asset: 'WIN',
        strategy: 'Rompimento',
        weekday: 'quarta-feira',
        status: 'ENCERRADA',
        net: 200,
      ),
      const BiTrade(
        date: '2026-07-02',
        asset: 'WIN',
        strategy: 'Rompimento',
        weekday: 'quinta-feira',
        status: 'ENCERRADA',
        net: -50,
      ),
      const BiTrade(
        date: '2026-07-02',
        asset: 'WDO',
        strategy: 'Reversão',
        weekday: 'quinta-feira',
        status: 'ENCERRADA',
        net: -100,
      ),
    ]);

    expect(analytics.net, 50);
    expect(analytics.winRate, closeTo(33.33, .01));
    expect(analytics.profitFactorText, '1,33');
    expect(analytics.maxDrawdown, 150);
    expect(analytics.daily, hasLength(2));
    expect(analytics.byAsset['WIN'], 150);
  });

  test('BI consolida somente o resultado líquido lançado em cada dia', () {
    const trades = <BiTrade>[
      BiTrade(
        id: 'gain',
        date: '2026-07-31',
        asset: 'WIN',
        strategy: 'Teste',
        weekday: 'sexta-feira',
        status: 'ENCERRADA',
        net: 600,
      ),
      BiTrade(
        id: 'loss',
        date: '2026-07-31',
        asset: 'WIN',
        strategy: 'Teste',
        weekday: 'sexta-feira',
        status: 'ENCERRADA',
        net: -100,
      ),
      BiTrade(
        id: 'break-even',
        date: '2026-07-31',
        asset: 'WIN',
        strategy: 'Teste',
        weekday: 'sexta-feira',
        status: 'ENCERRADA',
        net: -6,
        resultType: 'BREAK_EVEN',
      ),
    ];

    final analytics = BiAnalytics(trades);
    final day = analytics.daily.single;

    expect(day.date, '2026-07-31');
    expect(day.result, 494);
    expect(analytics.net, 494);
    expect(day.gains, 1);
    expect(day.losses, 1);
    expect(day.breakEvens, 1);
    expect(day.applicableWinRate, 50);
  });

  test('BI mantém o detalhamento e os contratos de cada operação do dia', () {
    final analytics = BiAnalytics(<BiTrade>[
      BiTrade.fromJson(<String, dynamic>{
        'id': 42,
        'trade_date': '2026-07-30',
        'asset': 'WIN',
        'strategy': 'Rompimento',
        'trade_weekday': 'quinta-feira',
        'status': 'ENCERRADA',
        'entry_time': '10:15',
        'direction': 'Compra',
        'quantity': 5,
        'net_result': 5022,
      }),
    ]);

    final operation = analytics.daily.single.items.single;
    expect(operation.id, '42');
    expect(operation.date, '2026-07-30');
    expect(operation.entryTime, '10:15');
    expect(operation.direction, 'Compra');
    expect(operation.quantity, 5);
    expect(operation.net, 5022);
    expect(analytics.daily.single.count, 1);
  });

  group('Taxa de Acerto das Operações', () {
    BiTrade trade(double net,
            {String resultType = '', String id = '', bool valid = true}) =>
        BiTrade(
          id: id,
          date: '2026-07-10',
          asset: 'WIN',
          strategy: 'Teste',
          weekday: 'sexta-feira',
          status: 'ENCERRADA',
          net: net,
          resultType: resultType,
          hasNetResult: valid,
        );

    test('calcula 6 vencedoras, 3 perdedoras e 1 break-even', () {
      final analytics = BiAnalytics(<BiTrade>[
        for (var i = 0; i < 6; i++) trade(100, id: 'w$i'),
        for (var i = 0; i < 3; i++) trade(-50, id: 'l$i'),
        trade(0, id: 'b0'),
      ]);

      expect(analytics.total, 10);
      expect(analytics.applicableWinRate, closeTo(66.67, .01));
      expect(analytics.percentOfTotal(analytics.gains), 60);
      expect(analytics.percentOfTotal(analytics.losses), 30);
      expect(analytics.percentOfTotal(analytics.breakEvens), 10);
    });

    test('somente vencedoras resulta em 100%', () {
      expect(BiAnalytics(<BiTrade>[trade(10)]).applicableWinRate, 100);
    });

    test('somente perdedoras resulta em 0%', () {
      expect(BiAnalytics(<BiTrade>[trade(-10)]).applicableWinRate, 0);
    });

    test('somente break-even torna taxa não aplicável', () {
      final analytics = BiAnalytics(<BiTrade>[trade(0)]);
      expect(analytics.breakEvens, 1);
      expect(analytics.applicableWinRate, isNull);
    });

    test('sem operações produz estado vazio', () {
      final analytics = BiAnalytics(<BiTrade>[]);
      expect(analytics.total, 0);
      expect(analytics.applicableWinRate, isNull);
    });

    test('resultado dentro da tolerância é break-even', () {
      expect(classifyBiTrade(trade(0.009)), BiTradeOutcome.breakEven);
      expect(classifyBiTrade(trade(-0.009)), BiTradeOutcome.breakEven);
    });

    test('break-even explícito prevalece sobre custos no líquido', () {
      expect(
        classifyBiTrade(trade(-8.50, resultType: 'BREAK_EVEN')),
        BiTradeOutcome.breakEven,
      );
    });

    test('ignora registros abertos, inválidos e IDs duplicados', () {
      const open = BiTrade(
        id: 'open',
        date: '2026-07-10',
        asset: 'WIN',
        strategy: 'Teste',
        weekday: 'sexta-feira',
        status: 'ABERTA',
        net: 10,
      );
      final analytics = BiAnalytics(<BiTrade>[
        trade(10, id: 'same'),
        trade(10, id: 'same'),
        trade(0, id: 'invalid', valid: false),
        open,
      ]);
      expect(analytics.total, 1);
    });

    test('resumo diário exclui break-even da taxa de acerto', () {
      final analytics = BiAnalytics(<BiTrade>[
        for (var i = 0; i < 6; i++) trade(100, id: 'dw$i'),
        for (var i = 0; i < 3; i++) trade(-50, id: 'dl$i'),
        trade(0, id: 'db0'),
      ]);
      final day = analytics.daily.single;
      expect(day.count, 10);
      expect(day.gains, 6);
      expect(day.losses, 3);
      expect(day.breakEvens, 1);
      expect(day.count, day.gains + day.losses + day.breakEvens);
      expect(day.applicableWinRate, closeTo(66.67, .01));
    });

    test('resumo diário somente break-even não divide por zero', () {
      final day = BiAnalytics(<BiTrade>[
        trade(0, id: 'b1'),
        trade(0, id: 'b2'),
        trade(0, id: 'b3'),
      ]).daily.single;
      expect(day.count, 3);
      expect(day.applicableWinRate, isNull);
    });
  });
}
