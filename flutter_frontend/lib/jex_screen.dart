import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'external_link.dart';

class JexScreen extends StatefulWidget {
  const JexScreen({required this.apiUriBuilder, super.key});
  final Uri Function(String path) apiUriBuilder;

  @override
  State<JexScreen> createState() => _JexScreenState();
}

class _JexScreenState extends State<JexScreen> {
  Map<String, dynamic>? data;
  String error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = '');
    try {
      final response = await http.get(widget.apiUriBuilder('/api/jex'));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(body['message'] ?? 'JEX indisponível.');
      }
      if (mounted) setState(() => data = body);
    } catch (exception) {
      if (mounted) {
        setState(
            () => error = exception.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('JEX')),
        body: Center(
          child: error.isEmpty
              ? const CircularProgressIndicator()
              : FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: Text(error),
                ),
        ),
      );
    }
    final company = Map<String, dynamic>.from(data!['company'] as Map);
    final financial = Map<String, dynamic>.from(data!['financial'] as Map);
    final assessment = Map<String, dynamic>.from(data!['assessment'] as Map);
    final reportingUpdate = Map<String, dynamic>.from(
        data!['reporting_update'] as Map? ?? const {});
    final timeline = ((data!['timeline'] as List<dynamic>?) ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('JEX', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              onPressed: _load,
              tooltip: 'Atualizar',
              icon: const Icon(Icons.refresh))
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const _JexHero(),
          const SizedBox(height: 16),
          _ReportingUpdatePanel(update: reportingUpdate),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final identity = _IdentityPanel(company: company);
            final financialCard = _FinancialPreview(
              financial: financial,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    JexFinancialSnapshotScreen(financial: financial),
              )),
            );
            return wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 6, child: identity),
                    const SizedBox(width: 14),
                    Expanded(flex: 5, child: financialCard),
                  ])
                : Column(children: [
                    identity,
                    const SizedBox(height: 14),
                    financialCard,
                  ]);
          }),
          const SizedBox(height: 22),
          const _SectionHeading(
            eyebrow: 'TRAJETÓRIA',
            title: 'Linha do tempo pública',
            description:
                'Marcos empresariais organizados a partir de informações públicas.',
          ),
          const SizedBox(height: 10),
          _Timeline(items: timeline),
          const SizedBox(height: 22),
          _ExecutivePanel(assessment: assessment),
          const SizedBox(height: 14),
          const _SourcesPanel(),
          const SizedBox(height: 14),
          const _Notice(),
        ],
      ),
    );
  }
}

class _JexHero extends StatelessWidget {
  const _JexHero();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF21104B), Color(0xFF5B237A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
                color: Color(0x3321104B), blurRadius: 24, offset: Offset(0, 10))
          ],
        ),
        child: Wrap(
          spacing: 22,
          runSpacing: 18,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              width: 170,
              height: 82,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(15)),
              child: Image.asset('assets/images/jex_logo.png',
                  fit: BoxFit.contain,
                  semanticLabel: 'Logomarca oficial da JEX'),
            ),
            const SizedBox(
              width: 470,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('JEX Nederland B.V.',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w900)),
                  SizedBox(height: 6),
                  Text(
                    'Perfil institucional, trajetória pública e leitura financeira organizada.',
                    style: TextStyle(color: Color(0xFFE5DDF0), fontSize: 15),
                  ),
                  SizedBox(height: 10),
                  _StatusPill(),
                ],
              ),
            )
          ],
        ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: const Color(0xFFEEE8F7).withValues(alpha: .16),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x66FFFFFF))),
        child: const Text('EMPRESA PRIVADA • PAÍSES BAIXOS',
            style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                letterSpacing: .6,
                fontWeight: FontWeight.w800)),
      );
}

class _IdentityPanel extends StatelessWidget {
  const _IdentityPanel({required this.company});
  final Map<String, dynamic> company;

  @override
  Widget build(BuildContext context) => _Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _PanelTitle(
              icon: Icons.badge_outlined, title: 'Identificação cadastral'),
          const SizedBox(height: 14),
          ...company.entries.map((entry) => _InformationRow(
                label: _companyLabel(entry.key),
                value: '${entry.value}',
              )),
        ]),
      );
}

class _FinancialPreview extends StatelessWidget {
  const _FinancialPreview({required this.financial, required this.onTap});
  final Map<String, dynamic> financial;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Abrir fotografia financeira detalhada da JEX',
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE0E5EC))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Expanded(
                          child: _PanelTitle(
                              icon: Icons.donut_large,
                              title: 'Fotografia financeira')),
                      Icon(Icons.arrow_forward, color: Color(0xFF6D28A6)),
                    ]),
                    const SizedBox(height: 8),
                    const _EvidenceBadge(
                        label: 'BASE VERIFICADA • EXERCÍCIO 2023',
                        status: 'verified'),
                    const SizedBox(height: 8),
                    const Text('Valores públicos selecionados • EUR milhões',
                        style:
                            TextStyle(color: Color(0xFF667085), fontSize: 12)),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                          child: _Metric(
                              label: 'Receita 2023',
                              value: _money(financial['revenue_2023']),
                              color: const Color(0xFF0C8467))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _Metric(
                              label: 'Prejuízo 2023',
                              value: _money(financial['loss_2023']),
                              color: const Color(0xFFC24152))),
                    ]),
                    const SizedBox(height: 14),
                    const Text('Abrir comparação visual e materialidade',
                        style: TextStyle(
                            color: Color(0xFF6D28A6),
                            fontWeight: FontWeight.w800)),
                  ]),
            ),
          ),
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF667085))),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w900, color: color)),
        ]),
      );
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) => _Surface(
        child: Column(
          children: List.generate(items.length, (index) {
            final item = items[index];
            final last = index == items.length - 1;
            return IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 76,
                      child: Column(children: [
                        Container(
                          width: 68,
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0EAF7),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text('${item['year']}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Color(0xFF5B237A),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900)),
                        ),
                        if (!last)
                          Expanded(
                              child: Container(
                                  width: 2, color: const Color(0xFFD8DDE5)))
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: last ? 0 : 20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${item['title']}',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 5),
                              Text('${item['description']}',
                                  style: const TextStyle(
                                      height: 1.45, color: Color(0xFF475467))),
                            ]),
                      ),
                    )
                  ]),
            );
          }),
        ),
      );
}

class _ExecutivePanel extends StatelessWidget {
  const _ExecutivePanel({required this.assessment});
  final Map<String, dynamic> assessment;
  @override
  Widget build(BuildContext context) => _Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _PanelTitle(
              icon: Icons.query_stats, title: 'Análise executiva'),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF4D8),
                borderRadius: BorderRadius.circular(8)),
            child: Text('${assessment['sentiment'] ?? ''}',
                style: const TextStyle(
                    color: Color(0xFF8A5B00), fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 12),
          Text('${assessment['summary'] ?? ''}',
              style: const TextStyle(height: 1.5, color: Color(0xFF344054))),
          const Divider(height: 28),
          const Text('Perspectiva de IPO',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text('${assessment['ipo'] ?? ''}',
              style: const TextStyle(height: 1.5, color: Color(0xFF475467))),
        ]),
      );
}

class _ReportingUpdatePanel extends StatelessWidget {
  const _ReportingUpdatePanel({required this.update});
  final Map<String, dynamic> update;

  @override
  Widget build(BuildContext context) {
    final items = ((update['items'] as List<dynamic>?) ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F7FC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCCFEB)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: const Color(0xFF6D28A6),
                borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.fact_check_outlined, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ATUALIZAÇÃO FINANCEIRA',
                  style: TextStyle(
                      color: Color(0xFF6D28A6),
                      letterSpacing: .8,
                      fontSize: 11,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              const Text('O que está confirmado — e o que ainda não está',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Pesquisa revisada em ${update['verified_at'] ?? '--'}',
                  style:
                      const TextStyle(color: Color(0xFF667085), fontSize: 12)),
            ]),
          )
        ]),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 3
              : constraints.maxWidth >= 560
                  ? 2
                  : 1;
          final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: items
                .map((item) => SizedBox(
                    width: width, child: _ReportingEvidenceCard(item: item)))
                .toList(),
          );
        }),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 18, color: Color(0xFF667085)),
            const SizedBox(width: 8),
            Expanded(
                child: Text('${update['note'] ?? ''}',
                    style: const TextStyle(
                        color: Color(0xFF475467), fontSize: 12, height: 1.4))),
          ]),
        )
      ]),
    );
  }
}

class _ReportingEvidenceCard extends StatelessWidget {
  const _ReportingEvidenceCard({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFFE0E5EC))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${item['year']}',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const Spacer(),
            _EvidenceBadge(
                label: '${item['status_label']}', status: '${item['status']}'),
          ]),
          const SizedBox(height: 12),
          Text('${item['title']}',
              style: const TextStyle(fontWeight: FontWeight.w800, height: 1.3)),
          const SizedBox(height: 6),
          Text('${item['description']}',
              style: const TextStyle(
                  color: Color(0xFF475467), fontSize: 12, height: 1.45)),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => _openExternal(context, '${item['source_url']}'),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.open_in_new, size: 15, color: Color(0xFF6D28A6)),
              const SizedBox(width: 5),
              Flexible(
                  child: Text('Fonte: ${item['source_label']}',
                      style: const TextStyle(
                          color: Color(0xFF6D28A6),
                          fontSize: 11,
                          fontWeight: FontWeight.w800))),
            ]),
          )
        ]),
      );
}

class _EvidenceBadge extends StatelessWidget {
  const _EvidenceBadge({required this.label, required this.status});
  final String label;
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'verified' => const Color(0xFF087A5B),
      'preliminary' => const Color(0xFF9A6700),
      _ => const Color(0xFFB42332),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withValues(alpha: .22))),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 9,
              letterSpacing: .3,
              fontWeight: FontWeight.w900)),
    );
  }
}

class _SourcesPanel extends StatelessWidget {
  const _SourcesPanel();
  static const sources = [
    ('Site oficial', 'Institucional JEX', 'https://www.jex.nl/'),
    ('Registro', 'KVK — Câmara de Comércio', 'https://www.kvk.nl/'),
    (
      'Auditoria',
      'Accountant.nl',
      'https://www.accountant.nl/nieuws/2025/2/accountant-jex-onthoudt-zich-van-oordeel-over-jaarverslag/'
    ),
    (
      'Imprensa setorial',
      'Flexmarkt',
      'https://www.flexmarkt.nl/brancheinformatie/financiele-druk-op-uitzendbureau-jex-neemt-toe-onzekerheid-over-voortbestaan/'
    ),
    (
      'Atualização financeira',
      'De Ondernemer — dados preliminares de 2024 e projeção de 2025',
      'https://www.deondernemer.nl/financien/jex-nick-hillebrand-rotterdam-verlies-omzet~a45ddc0'
    ),
  ];

  @override
  Widget build(BuildContext context) => _Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _PanelTitle(icon: Icons.link, title: 'Fontes públicas'),
          const SizedBox(height: 6),
          const Text(
              'Os links abaixo abrem as referências externas utilizadas.',
              style: TextStyle(color: Color(0xFF667085), fontSize: 12)),
          const SizedBox(height: 10),
          ...sources.map((source) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.open_in_new,
                    size: 19, color: Color(0xFF6D28A6)),
                title: Text(source.$2,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(source.$1),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openExternal(context, source.$3),
              )),
        ]),
      );
}

class JexFinancialSnapshotScreen extends StatelessWidget {
  const JexFinancialSnapshotScreen({required this.financial, super.key});
  final Map<String, dynamic> financial;

  @override
  Widget build(BuildContext context) {
    final revenue = _value(financial['revenue_2023']);
    final items = [
      (
        'Déficit de capital de giro',
        _value(financial['working_capital_deficit']),
        const Color(0xFFD08A16)
      ),
      (
        'Dívida tributária citada',
        _value(financial['tax_debt']),
        const Color(0xFFC24152)
      ),
      (
        'Prejuízo 2023',
        _value(financial['loss_2023']),
        const Color(0xFF2563A8)
      ),
      (
        'Capital adicional indicado',
        _value(financial['additional_capital']),
        const Color(0xFF7C3FA3)
      ),
    ];
    final maxValue =
        items.map((item) => item.$2).reduce((a, b) => a > b ? a : b);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text('Fotografia financeira JEX')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const _SectionHeading(
            eyebrow: 'LEITURA VISUAL',
            title: 'Pressões financeiras públicas — 2023',
            description:
                'Comparação de magnitudes citadas publicamente, em EUR milhões.'),
        const SizedBox(height: 14),
        _Surface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _EvidenceBadge(
                label: 'DADOS VERIFICADOS • EXERCÍCIO 2023',
                status: 'verified'),
            const SizedBox(height: 14),
            _InformationRow(
                label: 'Receita de referência — 2023',
                value: '€ ${_decimal(revenue)} mi'),
            const SizedBox(height: 12),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(item.$1,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700))),
                          Text('€ ${_decimal(item.$2)} mi',
                              style: TextStyle(
                                  color: item.$3, fontWeight: FontWeight.w900)),
                        ]),
                        const SizedBox(height: 7),
                        LayoutBuilder(
                            builder: (context, constraints) => Stack(children: [
                                  Container(
                                      height: 12,
                                      decoration: BoxDecoration(
                                          color: const Color(0xFFE8ECF1),
                                          borderRadius:
                                              BorderRadius.circular(6))),
                                  Container(
                                      height: 12,
                                      width: constraints.maxWidth *
                                          item.$2 /
                                          maxValue,
                                      decoration: BoxDecoration(
                                          color: item.$3,
                                          borderRadius:
                                              BorderRadius.circular(6))),
                                ])),
                        const SizedBox(height: 5),
                        Text(
                            '${(item.$2 / revenue * 100).toStringAsFixed(1).replaceAll('.', ',')}% da receita de referência',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF667085))),
                      ]),
                )),
          ]),
        ),
        const SizedBox(height: 14),
        const _Notice(
          text:
              'Este quadro não representa uma composição contábil. Ele compara indicadores públicos distintos para evidenciar sua materialidade relativa.',
        ),
      ]),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE0E5EC)),
        ),
        child: child,
      );
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: const Color(0xFF6D28A6), size: 21),
        const SizedBox(width: 9),
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900))),
      ]);
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(
      {required this.eyebrow, required this.title, required this.description});
  final String eyebrow;
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow,
              style: const TextStyle(
                  color: Color(0xFF6D28A6),
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(title,
              style:
                  const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(description,
              style: const TextStyle(color: Color(0xFF667085), height: 1.35)),
        ],
      );
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  color: Color(0xFF7A8493),
                  fontSize: 10,
                  letterSpacing: .5,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(color: Color(0xFF253041), height: 1.35)),
        ]),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({
    this.text =
        'A JEX é uma empresa privada. Esta página organiza informações públicas e não substitui documentos oficiais nem recomendação de investimento.',
  });
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF7E6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF2D49A))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: Color(0xFF8A5B00), size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: Color(0xFF704900), height: 1.4, fontSize: 12))),
        ]),
      );
}

Future<void> _openExternal(BuildContext context, String url) async {
  final opened = openExternalLink(url);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir este link.')));
  }
}

String _companyLabel(String key) =>
    const {
      'name': 'Razão social',
      'legal_type': 'Natureza jurídica',
      'kvk': 'Registro KVK',
      'establishment': 'Estabelecimento',
      'headquarters': 'Sede',
      'address': 'Endereço',
      'activity': 'Atuação declarada',
      'market_status': 'Situação em bolsa',
    }[key] ??
    key.replaceAll('_', ' ');

double _value(dynamic value) => value is num ? value.toDouble() : 0;
String _decimal(double value) => value.toStringAsFixed(1).replaceAll('.', ',');
String _money(dynamic value) => '€ ${_decimal(_value(value))} mi';
