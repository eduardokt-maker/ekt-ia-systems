import 'package:ekt_ia_flutter_frontend/day_trade_navigation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cores do resultado líquido distinguem ganhos e perdas', () {
    expect(navigationNetResultCellColor(125.50), const Color(0xFF168A57));
    expect(navigationNetResultCellColor(-82), const Color(0xFFD65C62));
    expect(navigationNetResultCellColor(0), isNull);
  });
}
