import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class JexScreen extends StatefulWidget {
  const JexScreen({required this.apiUriBuilder, super.key});
  final Uri Function(String path) apiUriBuilder;
  @override State<JexScreen> createState() => _JexScreenState();
}

class _JexScreenState extends State<JexScreen> {
  Map<String, dynamic>? data; String error = '';
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final response = await http.get(widget.apiUriBuilder('/api/jex'));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) throw Exception(body['message'] ?? 'JEX indisponível.');
      if (mounted) setState(() => data = body);
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
  }
  @override Widget build(BuildContext context) {
    if (data == null) return Scaffold(appBar: AppBar(title: const Text('JEX')), body: Center(child: error.isEmpty ? const CircularProgressIndicator() : Text(error)));
    final company = Map<String, dynamic>.from(data!['company'] as Map);
    final financial = Map<String, dynamic>.from(data!['financial'] as Map);
    final assessment = Map<String, dynamic>.from(data!['assessment'] as Map);
    return Scaffold(appBar: AppBar(title: const Text('JEX')), body: ListView(padding: const EdgeInsets.all(16), children: [
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF0F2235), borderRadius: BorderRadius.circular(16)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('JEX Nederland B.V.', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
        SizedBox(height: 5), Text('Perfil público, histórico e fotografia financeira', style: TextStyle(color: Color(0xFFDCEAF5))),
      ])),
      _Panel(title: 'Identificação cadastral', entries: company),
      const Padding(padding: EdgeInsets.only(top: 12, bottom: 4), child: Text('Linha do tempo pública', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
      ...((data!['timeline'] as List<dynamic>?) ?? const []).map((item) { final x = Map<String, dynamic>.from(item as Map); return Card(child: ListTile(leading: CircleAvatar(child: Text('${x['year']}', style: const TextStyle(fontSize: 10))), title: Text('${x['title']}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${x['description']}'))); }),
      _Panel(title: 'Fotografia financeira (EUR milhões)', entries: financial),
      _Panel(title: 'Análise executiva', entries: assessment),
      const Card(color: Color(0xFFFFF4D8), child: Padding(padding: EdgeInsets.all(14), child: Text('A JEX é uma empresa privada. A análise organiza informações públicas e não substitui documentos oficiais ou recomendação de investimento.'))),
    ]));
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.entries});
  final String title; final Map<String, dynamic> entries;
  @override Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(top: 12), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 10),
    ...entries.entries.map((e) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('${_label(e.key)}: ${e.value}'))),
  ])));
}

String _label(String value) => value.replaceAll('_', ' ').split(' ').map((x) => x.isEmpty ? x : '${x[0].toUpperCase()}${x.substring(1)}').join(' ');
