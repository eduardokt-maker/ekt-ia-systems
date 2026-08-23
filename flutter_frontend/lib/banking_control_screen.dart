import 'package:flutter/material.dart';

import 'bank_outflows_screen.dart';

class BankingControlScreen extends StatelessWidget {
  const BankingControlScreen({super.key, required this.apiUriBuilder});

  final Uri Function(String path) apiUriBuilder;

  @override
  Widget build(BuildContext context) =>
      BankOutflowsScreen(apiUriBuilder: apiUriBuilder);
}
