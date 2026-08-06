const ASSETS = [
  { ticker: "EWZ", symbol: "EWZ", name: "iShares MSCI Brazil ETF", market: "NYSE Arca" },
  { ticker: "ES", symbol: "ES=F", name: "E-mini S&P 500 futuro", market: "CME" },
  { ticker: "VIX", symbol: "^VIX", name: "Cboe Volatility Index", market: "Cboe" },
];
const CACHE_MS = 20_000;
let cached = null;
let cachedAt = 0;

const clamp = (value) => Math.max(-1, Math.min(1, value));
const finite = (value) => Number.isFinite(Number(value)) ? Number(value) : null;

async function fetchQuote(asset) {
  const url = new URL(`https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(asset.symbol)}`);
  url.searchParams.set("interval", "5m");
  url.searchParams.set("range", "1d");
  const response = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0 EKT-Monitor-Global/1.0" } });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const payload = await response.json();
  const meta = payload?.chart?.result?.[0]?.meta;
  if (!meta) throw new Error("Resposta sem cotação");
  const price = finite(meta.regularMarketPrice);
  const previousClose = finite(meta.chartPreviousClose ?? meta.previousClose);
  const changePoints = price !== null && previousClose ? price - previousClose : null;
  const changePercent = changePoints !== null ? changePoints / previousClose * 100 : null;
  const sourceDate = meta.regularMarketTime ? new Date(meta.regularMarketTime * 1000) : null;
  const ageSeconds = sourceDate ? Math.max(0, (Date.now() - sourceDate.getTime()) / 1000) : null;
  const status = ageSeconds !== null && ageSeconds <= 1200 ? "updated" : "delayed";
  return {
    ticker: asset.ticker,
    provider_symbol: asset.symbol,
    name: asset.name,
    market: asset.market,
    price,
    change_points: changePoints === null ? null : Number(changePoints.toFixed(4)),
    change_percent: changePercent === null ? null : Number(changePercent.toFixed(4)),
    previous_close: previousClose,
    day_high: finite(meta.regularMarketDayHigh),
    day_low: finite(meta.regularMarketDayLow),
    volume: finite(meta.regularMarketVolume),
    source_timestamp: sourceDate?.toISOString() ?? null,
    read_timestamp: new Date().toISOString(),
    source: "Yahoo Finance",
    data_status: status,
    message: status === "updated" ? "Atualizado pela fonte externa" : "Dado possivelmente atrasado",
    age_seconds: ageSeconds === null ? null : Number(ageSeconds.toFixed(1)),
  };
}

function evaluate(quotes) {
  const weights = { EWZ: 0.45, ES: 0.35, VIX: 0.20 };
  const byTicker = Object.fromEntries(quotes.map((quote) => [quote.ticker, quote]));
  let weightedScore = 0;
  let availableWeight = 0;
  const components = Object.entries(weights).map(([ticker, weight]) => {
    const change = byTicker[ticker]?.change_percent;
    if (change === null || change === undefined) return { ticker, available: false, effect: "indisponível", score: null };
    const raw = clamp(ticker === "VIX" ? -change / 5 : change / (ticker === "EWZ" ? 1.5 : 1));
    weightedScore += raw * weight;
    availableWeight += weight;
    return {
      ticker,
      available: true,
      change_percent: Number(change.toFixed(2)),
      effect: raw >= 0.15 ? "favorável" : raw <= -0.15 ? "desfavorável" : "neutro",
      score: Number((raw * 100).toFixed(1)),
      weight_percent: Math.round(weight * 100),
    };
  });
  const score = availableWeight ? weightedScore / availableWeight * 100 : 0;
  const bias = score >= 20 ? "favorável" : score <= -20 ? "defensivo" : "neutro";
  const summaries = {
    favorável: "Ambiente externo favorável ao apetite por risco.",
    defensivo: "Ambiente externo defensivo; risco e volatilidade pedem cautela.",
    neutro: "Sinais externos mistos ou sem direção suficiente.",
  };
  return {
    bias,
    score: Number(score.toFixed(1)),
    confidence_percent: Math.round(availableWeight * 100),
    components,
    summary: summaries[bias],
    methodology: "EWZ 45% + ES 35% + VIX invertido 20%.",
  };
}

async function marketSnapshot() {
  if (cached && Date.now() - cachedAt < CACHE_MS) return cached;
  const started = Date.now();
  const results = await Promise.allSettled(ASSETS.map(fetchQuote));
  const quotes = results.filter((item) => item.status === "fulfilled").map((item) => item.value);
  const errors = results.flatMap((item, index) => item.status === "rejected" ? [`${ASSETS[index].ticker}: ${item.reason?.message ?? "erro"}`] : []);
  cached = {
    ok: quotes.length > 0,
    quotes,
    model: evaluate(quotes),
    diagnostics: {
      provider: "Yahoo Finance",
      provider_online: quotes.length > 0,
      requested_assets: ASSETS.length,
      active_assets: quotes.length,
      delayed_assets: quotes.filter((quote) => quote.data_status === "delayed").length,
      errors,
      read_at: new Date().toISOString(),
      latency_ms: Date.now() - started,
      message: quotes.length ? `Fonte externa ativa — ${quotes.length}/${ASSETS.length} indicadores recebidos.` : "Fonte externa temporariamente indisponível.",
      delay_notice: "Cotações externas podem ter atraso e não substituem dados da corretora.",
    },
    tickers: ASSETS.map((asset) => asset.ticker),
  };
  cachedAt = Date.now();
  return cached;
}

const worker = {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && ["/api/market-global/status", "/api/market-global/quotes", "/api/market-global/diagnostics"].includes(url.pathname)) {
      const snapshot = await marketSnapshot();
      const body = url.pathname.endsWith("/quotes")
        ? { ok: snapshot.ok, quotes: snapshot.quotes, model: snapshot.model }
        : url.pathname.endsWith("/diagnostics")
          ? { ok: snapshot.ok, diagnostics: snapshot.diagnostics }
          : snapshot;
      return Response.json(body, { headers: { "Cache-Control": "public, max-age=15" } });
    }
    const response = await env.ASSETS.fetch(request);
    if (response.status !== 404 || request.method !== "GET") return response;
    if (!(request.headers.get("accept") || "").includes("text/html")) return response;
    return env.ASSETS.fetch(new Request(new URL("/index.html", request.url), request));
  },
};

export default worker;
