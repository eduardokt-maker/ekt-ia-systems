import 'package:flutter/material.dart';

class DayTradeScreen extends StatelessWidget {
  const DayTradeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Operações day trade',
                style: TextStyle(fontWeight: FontWeight.w800)),
            Text('Módulo separado da área logada',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: const Border(
                      left: BorderSide(width: 4, color: Color(0xFFD97706))),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 18,
                        offset: Offset(0, 8))
                  ],
                ),
                child: const Column(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: Color(0xFFFFF3DF),
                      child: Icon(Icons.show_chart,
                          size: 36, color: Color(0xFFD97706)),
                    ),
                    SizedBox(height: 18),
                    Text('Módulo de operações day trade em preparação.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    SizedBox(height: 8),
                    Text(
                      'Esta é a mesma situação funcional do backend Python atual. A interface já está em Flutter e pronta para receber cadastro de operações quando as regras forem definidas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF5F6873), height: 1.45),
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
}
