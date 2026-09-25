import { portfolio } from './portfolio.js';

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
});

const normalizeName = (value) => String(value || "")
  .normalize("NFKD")
  .replace(/\p{Diacritic}/gu, "")
  .trim()
  .replace(/\s+/g, " ")
  .toLocaleLowerCase("pt-BR");

async function paymentOrigins(request, env, url) {
  const userId = request.headers.get("oai-authenticated-user-id");
  if (!userId) return json({ message: "Entre com sua conta do ChatGPT para acessar suas origens." }, 401);

  if (request.method === "GET" && url.pathname === "/api/payment-origins") {
    const result = await env.DB.prepare(
      "SELECT id, name, created_at, updated_at FROM payment_origins WHERE user_id = ? ORDER BY name COLLATE NOCASE"
    ).bind(userId).all();
    return json({ origins: result.results || [] });
  }

  if (request.method === "POST" && url.pathname === "/api/payment-origins") {
    const body = await request.json().catch(() => ({}));
    const name = String(body.name || "").trim().replace(/\s+/g, " ");
    if (!name) return json({ message: "Informe o nome da origem." }, 400);
    if (name.length > 80) return json({ message: "Use no máximo 80 caracteres." }, 400);
    const id = crypto.randomUUID();
    try {
      await env.DB.prepare(
        "INSERT INTO payment_origins (id, user_id, name, normalized_name) VALUES (?, ?, ?, ?)"
      ).bind(id, userId, name, normalizeName(name)).run();
    } catch (error) {
      if (String(error).includes("UNIQUE")) return json({ message: "Já existe uma origem com esse nome." }, 409);
      throw error;
    }
    return json({ origin: { id, name } }, 201);
  }

  const match = url.pathname.match(/^\/api\/payment-origins\/([^/]+)$/);
  if (!match) return json({ message: "Não encontrado." }, 404);
  const id = decodeURIComponent(match[1]);

  if (request.method === "PUT") {
    const body = await request.json().catch(() => ({}));
    const name = String(body.name || "").trim().replace(/\s+/g, " ");
    if (!name) return json({ message: "Informe o nome da origem." }, 400);
    if (name.length > 80) return json({ message: "Use no máximo 80 caracteres." }, 400);
    try {
      const result = await env.DB.prepare(
        "UPDATE payment_origins SET name = ?, normalized_name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND user_id = ?"
      ).bind(name, normalizeName(name), id, userId).run();
      if (!result.meta?.changes) return json({ message: "Origem não encontrada." }, 404);
    } catch (error) {
      if (String(error).includes("UNIQUE")) return json({ message: "Já existe uma origem com esse nome." }, 409);
      throw error;
    }
    return json({ origin: { id, name } });
  }

  if (request.method === "DELETE") {
    const result = await env.DB.prepare(
      "DELETE FROM payment_origins WHERE id = ? AND user_id = ?"
    ).bind(id, userId).run();
    if (!result.meta?.changes) return json({ message: "Origem não encontrada." }, 404);
    return json({ ok: true });
  }

  return json({ message: "Método não permitido." }, 405);
}

const worker = {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/api/portfolio-v2') {
      try { return await portfolio(request, env); }
      catch (error) {
        console.error('portfolio_error', error);
        return json({ message: 'Carteira indisponível. Seus dados não foram descartados; tente novamente.' }, 503);
      }
    }
    if (url.pathname.startsWith("/api/payment-origins")) {
      try {
        return await paymentOrigins(request, env, url);
      } catch (error) {
        console.error("payment_origins_error", error);
        return json({ message: "Não foi possível acessar as origens agora." }, 500);
      }
    }

    const response = await env.ASSETS.fetch(request);

    if (response.status !== 404 || request.method !== "GET") {
      return response;
    }

    const accept = request.headers.get("accept") || "";
    if (!accept.includes("text/html")) {
      return response;
    }

    const indexUrl = new URL("/index.html", request.url);
    return env.ASSETS.fetch(new Request(indexUrl, request));
  },
};

export default worker;
