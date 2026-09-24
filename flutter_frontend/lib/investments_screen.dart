import 'package:flutter/material.dart';

typedef InvestmentsApiUriBuilder = Uri Function(String path);
typedef DayTradeCapitalLauncher = Future<void> Function();

/// Empty investment workspace; shared financial data stays in its own modules.
class InvestmentsScreen extends StatelessWidget {
  const InvestmentsScreen({
    required this.apiUriBuilder,
    required this.sessionToken,
    required this.onOpenDayTradeCapital,
    required this.onOpenDayTradeDeposit,
    super.key,
  });

  // Keep the navigation contract used by the dashboard and external modules.
  final InvestmentsApiUriBuilder apiUriBuilder;
  final String sessionToken;
  final DayTradeCapitalLauncher onOpenDayTradeCapital;
  final DayTradeCapitalLauncher onOpenDayTradeDeposit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Investimentos')),
      body: const SizedBox.expand(),
    );
  }
}
