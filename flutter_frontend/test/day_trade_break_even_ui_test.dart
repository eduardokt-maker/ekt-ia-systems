import 'package:ekt_ia_flutter_frontend/day_trade_screen.dart';
import 'package:ekt_ia_flutter_frontend/trade_result_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pontos consideram direção e ignoram quantidade de contratos', () {
    expect(
      calculateOperationPoints(
        direction: 'Compra',
        entryText: '170.000',
        exitText: '170.300',
      ),
      300,
    );
    expect(
      calculateOperationPoints(
        direction: 'Venda',
        entryText: '170.000',
        exitText: '169.700',
      ),
      300,
    );
    expect(formatOperationPoints(300), '+300 pontos');
    expect(formatOperationPoints(-300), '-300 pontos');
    expect(formatOperationPoints(0), '0 pontos');
    expect(
      calculateOperationPoints(
        direction: 'Compra',
        entryText: '',
        exitText: '170.300',
      ),
      isNull,
    );
  });

  test('modelo visual reconhece Break Even mesmo com custos', () {
    final operation = TradeOperation.fromJson(<String, dynamic>{
      'id': 1,
      'trade_date': '2026-07-21',
      'trade_weekday': 'terça-feira',
      'asset': 'WINQ26',
      'market': 'Mini índice',
      'direction': 'Compra',
      'quantity': 2,
      'entry_time': '10:30',
      'exit_time': '10:30',
      'entry_price_text': '135000',
      'exit_price_text': '135000',
      'point_value_text': '0.20',
      'stop_price_text': '',
      'target_price_text': '',
      'costs_text': '4.50',
      'strategy': 'Rompimento',
      'notes': '',
      'exit_reason': 'BREAK_EVEN',
      'operation_result': 'BREAK_EVEN',
      'status': 'ENCERRADA',
      'planned_risk': 0,
      'risk_reward': 0,
      'net_result': -4.5,
    });

    expect(operation.isBreakEven, isTrue);
    expect(operation.resultType, 'BREAK_EVEN');
    expect(operation.direction, 'Compra');
    expect(operation.costs, 4.5);
    expect(operation.netResult, -4.5);
  });

  test('registro legado zerado segue classificação Break Even do backend', () {
    final operation = TradeOperation.fromJson(<String, dynamic>{
      'id': 2,
      'operation_result': '',
      'result_type': 'BREAK_EVEN',
      'net_result': 0,
    });

    expect(operation.isBreakEven, isTrue);
    expect(operation.resultType, 'BREAK_EVEN');
  });

  test('horário de entrada é formatado como HH-MM', () {
    final formatter = TradeTimeInputFormatter();

    expect(
      formatter
          .formatEditUpdate(
            TextEditingValue.empty,
            const TextEditingValue(text: '0930'),
          )
          .text,
      '09-30',
    );
    expect(
      formatter
          .formatEditUpdate(
            TextEditingValue.empty,
            const TextEditingValue(text: '18-45'),
          )
          .text,
      '18-45',
    );
  });
}
