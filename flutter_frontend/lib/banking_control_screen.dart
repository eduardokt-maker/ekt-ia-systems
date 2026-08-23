import 'package:flutter/material.dart';

class BankingControlScreen extends StatelessWidget {
  const BankingControlScreen({super.key, required this.apiUriBuilder});

  final Uri Function(String path) apiUriBuilder;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Controle bancário e cartões',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              Text('Nova estrutura em preparação',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
            ],
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircleAvatar(
                        radius: 32,
                        child: Icon(Icons.account_balance_outlined, size: 34),
                      ),
                      SizedBox(height: 18),
                      Text('Módulo reiniciado',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w900)),
                      SizedBox(height: 10),
                      Text(
                        'A estrutura anterior e todos os seus dados foram removidos. A nova central será construída do zero, especializada na leitura e conferência de extratos bancários.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
