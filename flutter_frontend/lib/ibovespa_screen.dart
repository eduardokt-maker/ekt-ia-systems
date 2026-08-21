import 'dart:async';
import 'dart:convert';

import 'api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import 'ibovespa_quote.dart';
import 'ibovespa_quote_card.dart';
import 'official_logo_assets.dart';
import 'technical_chart.dart';

enum _QuoteFilter { all, winners, losers, stable }

enum _QuoteSort { symbol, changeDescending, changeAscending, volume, marketCap }

enum _QuickView { none, winners, losers, volume }

class IbovespaScreen extends StatefulWidget {
  const IbovespaScreen({required this.apiUriBuilder, super.key});
  final Uri Function(String path) apiUriBuilder;

  @override
  State<IbovespaScreen> createState() => _IbovespaScreenState();
}

class _IbovespaScreenState extends State<IbovespaScreen>
    with WidgetsBindingObserver {
  static const Duration refreshInterval = Duration(seconds: 60);
  bool loading = true;
  bool refreshing = false;
  String error = '';
  String source = '';
  Map<String, dynamic>? index;
  List<IbovespaQuote> quotes = <IbovespaQuote>[];
  final Set<String> favorites = <String>{};
  Timer? refreshTimer;
  bool active = true;
  String query = '';
  String selectedSector = 'Todos';
  String? selectedSymbol;
  _QuoteFilter filter = _QuoteFilter.all;
  _QuoteSort sort = _QuoteSort.symbol;
  _QuickView quickView = _QuickView.none;
  bool favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    refreshTimer = Timer.periodic(refreshInterval, (_) {
      if (active) _load(background: true);
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) _load(background: true);
  }

  Future<void> _load({bool background = false}) async {
    if (refreshing) return;
    setState(() {
      refreshing = true;
      if (!background && quotes.isEmpty) loading = true;
      if (!background) error = '';
    });
    try {
      final response = await apiClient.get(
        widget.apiUriBuilder('/api/market/ibovespa'),
        timeout: marketApiTimeout,
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw Exception(body['message'] ?? 'Dados indisponíveis.');
      }
      if (!mounted) return;
      setState(() {
        source = '${body['source'] ?? ''}';
        index = body['index'] as Map<String, dynamic>?;
        quotes = ((body['quotes'] as List<dynamic>?) ?? const <dynamic>[])
            .map((e) =>
                IbovespaQuote.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          if (quotes.isEmpty) {
            error = e.toString().replaceFirst('Exception: ', '');
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          refreshing = false;
        });
      }
    }
  }

  List<IbovespaQuote> get visibleQuotes {
    final needle = query.trim().toLowerCase();
    var result = quotes.where((quote) {
      final matchesQuery = needle.isEmpty ||
          '${quote.symbol} ${quote.name} ${quote.sector}'
              .toLowerCase()
              .contains(needle);
      final matchesSector =
          selectedSector == 'Todos' || quote.sector == selectedSector;
      final matchesFavorite =
          !favoritesOnly || favorites.contains(quote.symbol);
      final matchesDirection = switch (filter) {
        _QuoteFilter.all => true,
        _QuoteFilter.winners => quote.direction == QuoteDirection.up,
        _QuoteFilter.losers => quote.direction == QuoteDirection.down,
        _QuoteFilter.stable => quote.direction == QuoteDirection.neutral,
      };
      return matchesQuery &&
          matchesSector &&
          matchesFavorite &&
          matchesDirection;
    }).toList();
    final effectiveSort = switch (quickView) {
      _QuickView.winners => _QuoteSort.changeDescending,
      _QuickView.losers => _QuoteSort.changeAscending,
      _QuickView.volume => _QuoteSort.volume,
      _QuickView.none => sort,
    };
    result.sort((a, b) => switch (effectiveSort) {
          _QuoteSort.symbol => a.symbol.compareTo(b.symbol),
          _QuoteSort.changeDescending =>
            (b.changePercent ?? double.negativeInfinity)
                .compareTo(a.changePercent ?? double.negativeInfinity),
          _QuoteSort.changeAscending => (a.changePercent ?? double.infinity)
              .compareTo(b.changePercent ?? double.infinity),
          _QuoteSort.volume => (b.financialVolume ?? double.negativeInfinity)
              .compareTo(a.financialVolume ?? double.negativeInfinity),
          _QuoteSort.marketCap => (b.marketCap ?? double.negativeInfinity)
              .compareTo(a.marketCap ?? double.negativeInfinity),
        });
    return result;
  }

  Set<String> get sectors => <String>{
        'Todos',
        ...quotes.map((quote) => quote.sector),
      };

  Map<String, List<String>> get highlights {
    final available =
        quotes.where((quote) => quote.changePercent != null).toList();
    if (available.isEmpty) return const <String, List<String>>{};
    final winner = available.reduce(
        (a, b) => (a.changePercent ?? 0) >= (b.changePercent ?? 0) ? a : b);
    final loser = available.reduce(
        (a, b) => (a.changePercent ?? 0) <= (b.changePercent ?? 0) ? a : b);
    final volume =
        quotes.where((quote) => quote.financialVolume != null).toList();
    final mostTraded = volume.isEmpty
        ? null
        : volume.reduce((a, b) =>
            (a.financialVolume ?? 0) >= (b.financialVolume ?? 0) ? a : b);
    final result = <String, List<String>>{
      winner.symbol: <String>['Maior alta'],
      loser.symbol: <String>['Maior queda'],
    };
    if (mostTraded != null) {
      result
          .putIfAbsent(mostTraded.symbol, () => <String>[])
          .add('Mais negociada');
    }
    return result;
  }

  Future<void> _openAnalysis(IbovespaQuote quote) async {
    setState(() => selectedSymbol = quote.symbol);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => IbovespaAnalysisScreen(
        apiUriBuilder: widget.apiUriBuilder,
        symbol: quote.symbol,
      ),
    ));
    if (mounted) setState(() => selectedSymbol = null);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = visibleQuotes;
    final cardHighlights = highlights;
    return Scaffold(
      appBar: AppBar(
          title: const Text('Ibovespa',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            if (refreshing && !loading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Center(
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            IconButton(
                onPressed: refreshing ? null : _load,
                tooltip: 'Atualizar',
                icon: const Icon(Icons.refresh)),
          ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverList.list(children: <Widget>[
                if (index != null)
                  _IndexHeader(
                    data: index!,
                    source: source,
                  ),
                const SizedBox(height: 14),
                _MarketControls(
                  queryChanged: (value) => setState(() => query = value),
                  sectors: sectors.toList()..sort(),
                  selectedSector: selectedSector,
                  onSectorChanged: (value) =>
                      setState(() => selectedSector = value ?? 'Todos'),
                  filter: filter,
                  onFilterChanged: (value) =>
                      setState(() => filter = value ?? _QuoteFilter.all),
                  sort: sort,
                  onSortChanged: (value) =>
                      setState(() => sort = value ?? _QuoteSort.symbol),
                  favoritesOnly: favoritesOnly,
                  favoritesCount: favorites.length,
                  onFavoritesChanged: (value) =>
                      setState(() => favoritesOnly = value),
                  quickView: quickView,
                  onQuickViewChanged: (value) =>
                      setState(() => quickView = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${filtered.length} ativos exibidos',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(Icons.sync, size: 14),
                    const SizedBox(width: 4),
                    const Text('Atualização automática: 60 s',
                        style: TextStyle(fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 10),
                if (error.isNotEmpty)
                  _MessageCard(message: error, onRetry: _load),
              ]),
            ),
            if (loading)
              const SliverPadding(
                padding: EdgeInsets.all(16),
                sliver: _QuoteSkeletonGrid(),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyQuotes(favoritesOnly: favoritesOnly),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final columns = width >= 1320
                        ? 4
                        : width >= 980
                            ? 3
                            : width >= 680
                                ? 2
                                : 1;
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        mainAxisExtent: 220,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final quote = filtered[index];
                          return IbovespaQuoteCard(
                            key: ValueKey<String>(quote.symbol),
                            quote: quote,
                            favorite: favorites.contains(quote.symbol),
                            selected: selectedSymbol == quote.symbol,
                            badges: cardHighlights[quote.symbol] ??
                                const <String>[],
                            onFavorite: () => setState(() {
                              if (!favorites.add(quote.symbol)) {
                                favorites.remove(quote.symbol);
                              }
                            }),
                            onTap: () => _openAnalysis(quote),
                          );
                        },
                        childCount: filtered.length,
                        addAutomaticKeepAlives: true,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IndexHeader extends StatelessWidget {
  const _IndexHeader({
    required this.data,
    required this.source,
  });
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

// Compatibilidade visual legada mantida durante a migracao dos cards.
// ignore: unused_element
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
  const _CompanyLogo({required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    final isAxia = symbol == 'AXIA3';
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

    final assetPath = officialLogoAssets[symbol];
    if (assetPath == null) return fallback;

    final logo = assetPath.toLowerCase().endsWith('.svg')
        ? SvgPicture.asset(
            assetPath,
            fit: isAxia ? BoxFit.fitWidth : BoxFit.contain,
            semanticsLabel: 'Logo oficial de $symbol',
            placeholderBuilder: (_) => fallback,
          )
        : Image.asset(
            assetPath,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => fallback,
          );

    return Container(
      width: isAxia ? 64 : 48,
      height: 48,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        // A marca oficial da AXIA é um lettering branco; o fundo escuro
        // preserva o arquivo original e garante contraste no cartão.
        color: isAxia ? const Color(0xFF17283B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1F0B5FA5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: logo,
    );
  }
}

class _MarketControls extends StatelessWidget {
  const _MarketControls({
    required this.queryChanged,
    required this.sectors,
    required this.selectedSector,
    required this.onSectorChanged,
    required this.filter,
    required this.onFilterChanged,
    required this.sort,
    required this.onSortChanged,
    required this.favoritesOnly,
    required this.favoritesCount,
    required this.onFavoritesChanged,
    required this.quickView,
    required this.onQuickViewChanged,
  });

  final ValueChanged<String> queryChanged;
  final List<String> sectors;
  final String selectedSector;
  final ValueChanged<String?> onSectorChanged;
  final _QuoteFilter filter;
  final ValueChanged<_QuoteFilter?> onFilterChanged;
  final _QuoteSort sort;
  final ValueChanged<_QuoteSort?> onSortChanged;
  final bool favoritesOnly;
  final int favoritesCount;
  final ValueChanged<bool> onFavoritesChanged;
  final _QuickView quickView;
  final ValueChanged<_QuickView> onQuickViewChanged;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 310,
                    child: TextField(
                      onChanged: queryChanged,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Pesquisar ticker ou empresa',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 205,
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedSector,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Setor',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: sectors
                          .map((sector) => DropdownMenuItem<String>(
                                value: sector,
                                child: Text(sector,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(growable: false),
                      onChanged: onSectorChanged,
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<_QuoteFilter>(
                      initialValue: filter,
                      decoration: const InputDecoration(
                        labelText: 'Movimento',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const <DropdownMenuItem<_QuoteFilter>>[
                        DropdownMenuItem(
                            value: _QuoteFilter.all, child: Text('Todos')),
                        DropdownMenuItem(
                            value: _QuoteFilter.winners, child: Text('Altas')),
                        DropdownMenuItem(
                            value: _QuoteFilter.losers, child: Text('Baixas')),
                        DropdownMenuItem(
                            value: _QuoteFilter.stable,
                            child: Text('Estáveis')),
                      ],
                      onChanged: onFilterChanged,
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<_QuoteSort>(
                      initialValue: sort,
                      decoration: const InputDecoration(
                        labelText: 'Ordenar por',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const <DropdownMenuItem<_QuoteSort>>[
                        DropdownMenuItem(
                            value: _QuoteSort.symbol, child: Text('Ticker')),
                        DropdownMenuItem(
                            value: _QuoteSort.changeDescending,
                            child: Text('Maior variação')),
                        DropdownMenuItem(
                            value: _QuoteSort.changeAscending,
                            child: Text('Menor variação')),
                        DropdownMenuItem(
                            value: _QuoteSort.volume,
                            child: Text('Volume financeiro')),
                        DropdownMenuItem(
                            value: _QuoteSort.marketCap,
                            child: Text('Valor de mercado')),
                      ],
                      onChanged: onSortChanged,
                    ),
                  ),
                  FilterChip(
                    selected: favoritesOnly,
                    avatar: const Icon(Icons.star, size: 17),
                    label: Text('Favoritos ($favoritesCount)'),
                    onSelected: onFavoritesChanged,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _QuickButton(
                    label: 'Todos os ativos',
                    icon: Icons.grid_view,
                    selected: quickView == _QuickView.none,
                    onTap: () => onQuickViewChanged(_QuickView.none),
                  ),
                  _QuickButton(
                    label: 'Maiores altas',
                    icon: Icons.trending_up,
                    selected: quickView == _QuickView.winners,
                    onTap: () => onQuickViewChanged(_QuickView.winners),
                  ),
                  _QuickButton(
                    label: 'Maiores baixas',
                    icon: Icons.trending_down,
                    selected: quickView == _QuickView.losers,
                    onTap: () => onQuickViewChanged(_QuickView.losers),
                  ),
                  _QuickButton(
                    label: 'Mais negociadas',
                    icon: Icons.bar_chart,
                    selected: quickView == _QuickView.volume,
                    onTap: () => onQuickViewChanged(_QuickView.volume),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => selected
      ? FilledButton.tonalIcon(
          onPressed: onTap, icon: Icon(icon), label: Text(label))
      : OutlinedButton.icon(
          onPressed: onTap, icon: Icon(icon), label: Text(label));
}

class _QuoteSkeletonGrid extends StatelessWidget {
  const _QuoteSkeletonGrid();
  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.crossAxisExtent >= 1120
              ? 3
              : constraints.crossAxisExtent >= 700
                  ? 2
                  : 1;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 260,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, __) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                          width: 54,
                          height: 46,
                          color: const Color(0xFFE6EBF0)),
                      const SizedBox(height: 20),
                      Container(
                          width: 150,
                          height: 20,
                          color: const Color(0xFFE6EBF0)),
                      const SizedBox(height: 10),
                      Container(
                          width: 110,
                          height: 14,
                          color: const Color(0xFFE6EBF0)),
                      const Spacer(),
                      Container(height: 54, color: const Color(0xFFF0F3F6)),
                    ],
                  ),
                ),
              ),
              childCount: 6,
            ),
          );
        },
      );
}

class _EmptyQuotes extends StatelessWidget {
  const _EmptyQuotes({required this.favoritesOnly});
  final bool favoritesOnly;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(favoritesOnly ? Icons.star_border : Icons.search_off,
                  size: 44),
              const SizedBox(height: 10),
              Text(
                favoritesOnly
                    ? 'Nenhum favorito selecionado.'
                    : 'Nenhum ativo corresponde aos filtros.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
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
  bool loading = true;
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
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Análise técnica ${widget.symbol}'),
        actions: [
          IconButton(
              onPressed: loading ? null : _load,
              tooltip: 'Atualizar agora',
              icon: const Icon(Icons.refresh))
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _MessageCard(message: error, onRetry: _load),
                  ),
                )
              : _technicalContent(),
    );
  }

  Widget _technicalContent() {
    final quote = Map<String, dynamic>.from(data!['quote'] as Map? ?? {});
    final candles = ((data!['candles'] as List<dynamic>?) ?? const [])
        .map((item) =>
            WeeklyCandle.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF071D35), Color(0xFF164D82)]),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            runAlignment: WrapAlignment.center,
            spacing: 24,
            runSpacing: 10,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.symbol,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w900)),
                Text('${quote['name'] ?? ''}',
                    style: const TextStyle(color: Color(0xFFB8C7D9))),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('R\$ ${_number(quote['price'])}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const Text('Candles semanais • atualização sob consulta',
                    style: TextStyle(color: Color(0xFFB8C7D9), fontSize: 12)),
              ])
            ],
          ),
        ),
        const SizedBox(height: 14),
        TechnicalChart(candles: candles),
        const SizedBox(height: 10),
        const Text(
          'Indicadores calculados sobre até 5 anos de histórico semanal. '
          'O gráfico exibe as 104 semanas mais recentes. Bandas de Bollinger: 20 períodos e 2 desvios-padrão.',
          style: TextStyle(color: Color(0xFF667085), fontSize: 12),
        ),
      ],
    );
  }
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
