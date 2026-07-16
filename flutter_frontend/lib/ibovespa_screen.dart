import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

class IbovespaScreen extends StatefulWidget {
  const IbovespaScreen({required this.apiUriBuilder, super.key});
  final Uri Function(String path) apiUriBuilder;

  @override
  State<IbovespaScreen> createState() => _IbovespaScreenState();
}

class _IbovespaScreenState extends State<IbovespaScreen> {
  bool loading = true;
  String error = '';
  String source = '';
  Map<String, dynamic>? index;
  List<Map<String, dynamic>> quotes = [];
  String query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final response =
          await http.get(widget.apiUriBuilder('/api/market/ibovespa'));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw Exception(body['message'] ?? 'Dados indisponíveis.');
      }
      if (!mounted) return;
      setState(() {
        source = '${body['source'] ?? ''}';
        index = body['index'] as Map<String, dynamic>?;
        quotes = ((body['quotes'] as List<dynamic>?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = quotes.where((q) {
      final needle = query.toLowerCase();
      return '${q['symbol']} ${q['name']} ${q['sector']}'
          .toLowerCase()
          .contains(needle);
    }).toList();
    return Scaffold(
      appBar: AppBar(
          title: const Text('Ibovespa',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
                onPressed: loading ? null : _load,
                tooltip: 'Atualizar',
                icon: const Icon(Icons.refresh)),
          ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (index != null) _IndexHeader(data: index!, source: source),
            const SizedBox(height: 14),
            TextField(
              onChanged: (value) => setState(() => query = value),
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Buscar ativo ou setor',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            if (loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator())),
            if (error.isNotEmpty) _MessageCard(message: error, onRetry: _load),
            if (!loading && error.isEmpty)
              ...filtered.map((quote) => _QuoteCard(
                    quote: quote,
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => IbovespaAnalysisScreen(
                          apiUriBuilder: widget.apiUriBuilder,
                          symbol: '${quote['symbol']}'),
                    )),
                  )),
          ],
        ),
      ),
    );
  }
}

class _IndexHeader extends StatelessWidget {
  const _IndexHeader({required this.data, required this.source});
  final Map<String, dynamic> data;
  final String source;
  @override
  Widget build(BuildContext context) {
    final change = (data['change_percent'] as num?)?.toDouble();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF071D35), Color(0xFF164D82)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
              color: Color(0x330B5FA5), blurRadius: 24, offset: Offset(0, 10))
        ],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        final information = Padding(
            padding: const EdgeInsets.all(22),
            child: Wrap(
                spacing: 24,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Índice Bovespa',
                            style: TextStyle(color: Color(0xFFA8B4C0))),
                        Text('Mercado brasileiro',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                      ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_number(data['price']),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800)),
                    Text(
                        change == null
                            ? 'Variação indisponível'
                            : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                        style: TextStyle(
                            color: change == null
                                ? Colors.white70
                                : (change >= 0
                                    ? const Color(0xFF62D89D)
                                    : const Color(0xFFFF8B86)),
                            fontWeight: FontWeight.w700)),
                    Text(source,
                        style: const TextStyle(
                            color: Color(0xFFA8B4C0), fontSize: 11)),
                  ]),
                ]));
        final artwork = Image.asset('assets/images/ibovespa_market_3d.png',
            height: compact ? 180 : 240,
            width: compact ? double.infinity : 340,
            fit: BoxFit.cover,
            alignment: Alignment.centerRight);
        return compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [information, artwork])
            : Row(children: [Expanded(child: information), artwork]);
      }),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.quote, required this.onTap});
  final Map<String, dynamic> quote;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final change = (quote['change_percent'] as num?)?.toDouble();
    final positive = (change ?? 0) >= 0;
    final accent = positive ? const Color(0xFF0AA06E) : const Color(0xFFE14D50);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shadowColor: const Color(0x220B5FA5),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: accent.withValues(alpha: 0.18))),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        onTap: onTap,
        leading: _CompanyLogo(
          symbol: '${quote['symbol']}',
          logoUrl: '${quote['logo_url'] ?? ''}',
        ),
        title: Text('${quote['symbol']}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        subtitle: Text('${quote['name']}\n${quote['sector']}',
            maxLines: 2, overflow: TextOverflow.ellipsis),
        isThreeLine: true,
        trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('R\$ ${_number(quote['price'])}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                  change == null
                      ? '--'
                      : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800)),
            ]),
      ),
    );
  }
}

class _CompanyLogo extends StatelessWidget {
  const _CompanyLogo({required this.symbol, required this.logoUrl});

  final String symbol;
  final String logoUrl;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1769AA), Color(0xFF42A5F5)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        symbol.isEmpty ? '?' : symbol.substring(0, 1),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
    );

    if (logoUrl.isEmpty) return fallback;

    final logo = logoUrl.toLowerCase().contains('.svg')
        ? SvgPicture.network(
            logoUrl,
            fit: BoxFit.contain,
            placeholderBuilder: (_) => fallback,
          )
        : Image.network(
            logoUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => fallback,
          );

    return Container(
      width: 48,
      height: 48,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1F0B5FA5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: logo,
    );
  }
}

class IbovespaAnalysisScreen extends StatefulWidget {
  const IbovespaAnalysisScreen(
      {required this.apiUriBuilder, required this.symbol, super.key});
  final Uri Function(String path) apiUriBuilder;
  final String symbol;
  @override
  State<IbovespaAnalysisScreen> createState() => _IbovespaAnalysisScreenState();
}

class _IbovespaAnalysisScreenState extends State<IbovespaAnalysisScreen> {
  Map<String, dynamic>? data;
  String error = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await http
          .get(widget.apiUriBuilder('/api/market/ibovespa/${widget.symbol}'));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(body['message'] ?? 'Análise indisponível.');
      }
      if (mounted) setState(() => data = body);
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Análise ${widget.symbol}')),
        body: data == null
            ? Center(
                child: error.isEmpty
                    ? const CircularProgressIndicator()
                    : Text(error))
            : ListView(padding: const EdgeInsets.all(16), children: [
                _DataPanel(
                    title: 'Avaliação',
                    data: Map<String, dynamic>.from(data!['valuation'] as Map)),
                _DataPanel(
                    title: 'Fundamentos',
                    data: Map<String, dynamic>.from(
                        data!['fundamentals'] as Map)),
                const SizedBox(height: 10),
                const Text('Tendências por horizonte',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ...((data!['horizons'] as List<dynamic>?) ?? const []).map(
                    (e) => Card(
                        child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(Map<String, dynamic>.from(e as Map)
                                .entries
                                .map((x) => '${x.key}: ${x.value}')
                                .join('\n'))))),
              ]));
  }
}

class _DataPanel extends StatelessWidget {
  const _DataPanel({required this.title, required this.data});
  final String title;
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ...data.entries.where((e) => e.value != null).map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text('${e.key}: ${e.value}'))),
          ])));
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text(message),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: onRetry, child: const Text('Tentar novamente'))
          ])));
}

String _number(dynamic value) =>
    value is num ? value.toStringAsFixed(2).replaceAll('.', ',') : '--';
