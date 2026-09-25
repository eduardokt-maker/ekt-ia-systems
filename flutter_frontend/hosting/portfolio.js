const reply = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } });
const fail = (message) => { throw new Error(message); };
const text = (value, max = 160) => typeof value === 'string' && value.length <= max;
const money = (v) => Number.isSafeInteger(v) && v >= 0 && v <= 1e13;
const positive = (v) => typeof v === 'number' && Number.isFinite(v) && v > 0 && v <= 1e9;
const today = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
const dateValid = (v) => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v) && !Number.isNaN(Date.parse(v)) && new Date(v).toISOString().slice(0, 10) === v;

// Validate the complete chronology before the single atomic versioned write.
export function validatePortfolio(data, maxDate = today()) {
  if (!data || !Array.isArray(data.assets) || !Array.isArray(data.events) || data.assets.length > 500 || data.events.length > 10000) fail('Carteira inválida ou limite de registros atingido.');
  const assets = new Map();
  for (const a of data.assets) {
    if (!text(a.id, 80) || !a.id || assets.has(a.id) || !['fixed', 'variable'].includes(a.kind) || !text(a.name) || !a.name.trim() || !text(a.institution) || !text(a.notes, 1000) || !text(a.ticker, 16)) fail('Confira os dados do ativo.');
    if (a.kind === 'variable' && !/^[A-Z0-9]{4,12}$/.test(a.ticker)) fail('Informe um ticker válido.');
    if (!text(a.maturity, 10) || (a.maturity && !dateValid(a.maturity))) fail('Vencimento inválido.');
    if (a.rate !== null && (typeof a.rate !== 'number' || !Number.isFinite(a.rate) || a.rate < 0 || a.rate > 1000)) fail('Taxa anual inválida.');
    assets.set(a.id, a);
  }
  const ids = new Set();
  const states = new Map();
  const events = data.events.map((e, index) => ({ ...e, index })).sort((a, b) => a.date.localeCompare(b.date) || a.index - b.index);
  for (const e of events) {
    const a = assets.get(e.assetId);
    if (!a || !text(e.id, 80) || !e.id || ids.has(e.id) || !['deposit', 'withdraw', 'income', 'valuation'].includes(e.type) || !dateValid(e.date) || e.date > maxDate || !text(e.notes, 1000) || !money(e.amount) || !money(e.fees) || !Number.isFinite(e.quantity) || e.quantity < 0 || !Number.isFinite(e.price) || e.price < 0) fail('Confira a data e os valores da movimentação. Datas futuras não são permitidas.');
    ids.add(e.id);
    const s = states.get(a.id) || { quantity: 0, balance: 0 };
    if (e.type === 'income') {
      if (!e.amount || e.fees > e.amount) fail('Rendimento inválido.');
    } else if (a.kind === 'variable') {
      if (!positive(e.price)) fail('Informe o preço por ação/cota.');
      if (e.type !== 'valuation') {
        if (!positive(e.quantity) || Math.abs(e.quantity * 1e6 - Math.round(e.quantity * 1e6)) > 0.001) fail('Quantidade inválida; use até seis casas decimais.');
        if (e.amount !== Math.round(e.quantity * e.price * 100)) fail('O total deve corresponder à quantidade multiplicada pelo preço.');
        s.quantity += e.type === 'deposit' ? e.quantity : -e.quantity;
        if (s.quantity < -0.0000001) fail('A retirada excede a quantidade disponível nessa data. Confira também as movimentações posteriores.');
      }
    } else {
      if (e.type !== 'valuation' && !e.amount) fail('Informe um valor maior que zero.');
      s.balance = e.type === 'valuation' ? e.amount : s.balance + (e.type === 'deposit' ? e.amount : -e.amount);
      if (s.balance < 0) fail('O resgate excede o saldo nessa data. Registre a posição do extrato antes do resgate, se necessário.');
    }
    if (e.type === 'withdraw' && e.fees > e.amount) fail('Custos e impostos não podem superar a retirada.');
    if (a.kind === 'variable' && e.type !== 'income' && !money(Math.round(s.quantity * e.price * 100))) fail('A posição excede o limite de valor permitido.');
    if (!money(s.balance)) fail('A posição excede o limite de valor permitido.');
    if (e.type === 'valuation' && e.fees !== 0) fail('Atualização de posição não possui custos.');
    states.set(a.id, s);
  }
  return { assets: data.assets, events: data.events };
}

export async function portfolio(request, env, authenticate = fetch) {
  if (!['GET', 'PUT'].includes(request.method)) return reply({ message: 'Método não permitido.' }, 405);
  const authorization = request.headers.get('authorization');
  if (!authorization?.startsWith('Bearer ')) return reply({ message: 'Entre no sistema para acessar sua carteira.' }, 401);
  const identity = await authenticate('https://ekt-ia-systems.onrender.com/api/auth/me', { headers: { authorization }, signal: AbortSignal.timeout(20000) });
  if (identity.status === 401 || identity.status === 403) return reply({ message: 'Sessão expirada. Entre novamente.' }, 401);
  if (!identity.ok) return reply({ message: 'Não foi possível validar a sessão. Tente novamente.' }, 503);
  const { user, ok } = await identity.json();
  if (!ok || !user || user.active === false || (!user.id && !user.login)) return reply({ message: 'Sessão inválida.' }, 401);
  const owner = user.id ? `user:${user.id}` : `legacy:${user.login}`;
  const writable = Array.isArray(user.permissions) && user.permissions.includes('write');
  if (request.method === 'GET') {
    const row = await env.DB.prepare('SELECT revision, payload FROM investment_portfolios WHERE owner_id = ?').bind(owner).first();
    return reply({ ok: true, writable, revision: row?.revision ?? 0, data: row ? JSON.parse(row.payload) : { assets: [], events: [] } });
  }
  if (!writable) return reply({ message: 'Seu perfil permite apenas consulta.' }, 403);
  const raw = await request.text();
  if (new TextEncoder().encode(raw).byteLength > 1500000) return reply({ message: 'Carteira excede o limite de tamanho.' }, 413);
  let body, data;
  try {
    body = JSON.parse(raw);
    if (!Number.isSafeInteger(body.revision) || body.revision < 0) fail('Versão inválida.');
    data = validatePortfolio(body.data);
  } catch (error) { return reply({ message: error.message || 'Dados inválidos.' }, 400); }
  const payload = JSON.stringify(data);
  // Upsert compare-and-swap: concurrent edits cannot silently overwrite balances.
  const result = body.revision === 0
    ? await env.DB.prepare('INSERT INTO investment_portfolios (owner_id, revision, payload) VALUES (?, 1, ?) ON CONFLICT(owner_id) DO NOTHING').bind(owner, payload).run()
    : await env.DB.prepare('UPDATE investment_portfolios SET payload = ?, revision = revision + 1, updated_at = CURRENT_TIMESTAMP WHERE owner_id = ? AND revision = ?').bind(payload, owner, body.revision).run();
  const changed = result.meta?.changes || 0;
  if (!changed) return reply({ message: 'A carteira mudou em outra sessão. Feche o formulário, atualize a página e tente novamente.' }, 409);
  return reply({ ok: true, revision: body.revision + 1, data, writable });
}
