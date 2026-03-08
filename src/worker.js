const DEFAULT_BROKER_BASE = "https://api.preconnect.app";
const DEFAULT_SESSION_EMAIL = "web-login@preconnect.app";

function json(data, init = {}) {
  return new Response(JSON.stringify(data), {
    ...init,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...(init.headers || {}),
    },
  });
}

function normalizeEmail(input) {
  return `${input || ""}`.trim().toLowerCase();
}

function pickSessionEmail(rawEmail) {
  const email = normalizeEmail(rawEmail);
  if (email.includes("@")) return email;
  return DEFAULT_SESSION_EMAIL;
}

async function proxyToBroker(path, init = {}, env) {
  const base = `${env.BROKER_BASE || DEFAULT_BROKER_BASE}`.replace(/\/+$/, "");
  return fetch(`${base}${path}`, init);
}

async function handleCreateSession(request, env) {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, { status: 405 });
  }

  let body = {};
  try {
    const text = await request.text();
    if (text.trim() !== "") {
      body = JSON.parse(text);
    }
  } catch (_) {
    body = {};
  }

  const sessionEmail = pickSessionEmail(body?.email || body?.accountEmail || body?.googleEmail);
  const upstream = await proxyToBroker(
    "/web-login/session",
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ googleEmail: sessionEmail }),
    },
    env,
  );

  return new Response(upstream.body, {
    status: upstream.status,
    headers: upstream.headers,
  });
}

async function handleSessionProxy(request, url, env) {
  const match = url.pathname.match(/^\/api\/web-login\/session\/([^/]+)(?:\/(consume))?$/);
  if (!match) return null;
  const sessionId = match[1];
  const action = match[2] || "";

  if (request.method === "GET" && !action) {
    const qs = url.search || "";
    const upstream = await proxyToBroker(`/web-login/session/${sessionId}${qs}`, {}, env);
    return new Response(upstream.body, {
      status: upstream.status,
      headers: upstream.headers,
    });
  }

  if (request.method === "POST" && action === "consume") {
    const upstream = await proxyToBroker(
      `/web-login/session/${sessionId}/consume`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: await request.text(),
      },
      env,
    );
    return new Response(upstream.body, {
      status: upstream.status,
      headers: upstream.headers,
    });
  }

  return json({ error: "Method not allowed" }, { status: 405 });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api/web-login/session") {
      return handleCreateSession(request, env);
    }

    if (url.pathname.startsWith("/api/web-login/session/")) {
      const res = await handleSessionProxy(request, url, env);
      if (res) return res;
    }

    return env.ASSETS.fetch(request);
  },
};
