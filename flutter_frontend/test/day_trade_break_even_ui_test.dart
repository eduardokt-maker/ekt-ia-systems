import 'package:ekt_ia_flutter_frontend/day_trade_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('registro legado zerado permanece neutro', () {
    final operation = TradeOperation.fromJson(<String, dynamic>{
      'id': 2,
      'operation_result': '',
      'net_result': 0,
    });

    expect(operation.isBreakEven, isFalse);
    expect(operation.resultType, 'NEUTRAL');
  });
}
