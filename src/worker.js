const DEFAULT_BROKER_BASE = "https://api.preconnect.app";
const DEFAULT_AUTH_SIGNING_KEY = "preconnect-web-auth-v1";
const TOKEN_TTL_MS = 5 * 60 * 1000;
const OAUTH_STATE_TTL_MS = 10 * 60 * 1000;

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

function isStudentEmail(email) {
  if (!email.includes("@")) return false;
  return email.endsWith(".ac.bd");
}

function base64UrlEncode(bytes) {
  const bin = String.fromCharCode(...bytes);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64UrlDecodeToBytes(input) {
  const normalized = input.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  const bin = atob(padded);
  return Uint8Array.from(bin, (ch) => ch.charCodeAt(0));
}

async function importHmacKey(secret) {
  const keyBytes = new TextEncoder().encode(secret);
  return crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

async function createSignedAuthToken(email, secret) {
  const now = Date.now();
  const payload = {
    v: 1,
    email,
    iat: now,
    exp: now + TOKEN_TTL_MS,
  };
  const payloadJson = JSON.stringify(payload);
  const payloadBytes = new TextEncoder().encode(payloadJson);
  const payloadB64 = base64UrlEncode(payloadBytes);

  const key = await importHmacKey(secret);
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(payloadB64),
  );
  const sigB64 = base64UrlEncode(new Uint8Array(signature));
  return `v1.${payloadB64}.${sigB64}`;
}

async function signStatePayload(payload, secret) {
  const payloadJson = JSON.stringify(payload);
  const payloadBytes = new TextEncoder().encode(payloadJson);
  const payloadB64 = base64UrlEncode(payloadBytes);
  const key = await importHmacKey(secret);
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(payloadB64),
  );
  const sigB64 = base64UrlEncode(new Uint8Array(signature));
  return `${payloadB64}.${sigB64}`;
}

async function verifyStatePayload(token, secret) {
  const parts = `${token || ""}`.split(".");
  if (parts.length !== 2) return null;
  const payloadB64 = parts[0];
  const sigB64 = parts[1];
  const key = await importHmacKey(secret);
  const ok = await crypto.subtle.verify(
    "HMAC",
    key,
    base64UrlDecodeToBytes(sigB64),
    new TextEncoder().encode(payloadB64),
  );
  if (!ok) return null;
  const payloadJson = new TextDecoder().decode(base64UrlDecodeToBytes(payloadB64));
  const payload = JSON.parse(payloadJson);
  const exp = Number(payload?.exp || 0);
  if (!Number.isFinite(exp) || exp <= Date.now()) return null;
  return payload;
}

async function verifySignedAuthToken(token, secret) {
  const parts = `${token || ""}`.split(".");
  if (parts.length !== 3 || parts[0] !== "v1") return null;
  const payloadB64 = parts[1];
  const sigB64 = parts[2];
  const key = await importHmacKey(secret);
  const ok = await crypto.subtle.verify(
    "HMAC",
    key,
    base64UrlDecodeToBytes(sigB64),
    new TextEncoder().encode(payloadB64),
  );
  if (!ok) return null;

  const payloadJson = new TextDecoder().decode(base64UrlDecodeToBytes(payloadB64));
  const payload = JSON.parse(payloadJson);
  if (!payload || typeof payload !== "object") return null;
  const exp = Number(payload.exp || 0);
  if (!Number.isFinite(exp) || exp <= Date.now()) return null;
  const email = normalizeEmail(payload.email);
  if (!isStudentEmail(email)) return null;
  return { email, exp };
}

async function handleIssueAuthToken(request, env) {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, { status: 405 });
  }
  const secret = `${env.AUTH_SIGNING_KEY || DEFAULT_AUTH_SIGNING_KEY}`.trim();

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const email = normalizeEmail(body?.email);
  if (!isStudentEmail(email)) {
    return json(
      { error: "Use a valid student email (example: name@g.bracu.ac.bd)." },
      { status: 400 },
    );
  }

  const token = await createSignedAuthToken(email, secret);
  return json({
    token,
    email,
    expiresAt: Date.now() + TOKEN_TTL_MS,
  });
}

function popupCallbackHtml({ origin, email, error }) {
  const payload = error
    ? { type: "preconnect_google_oauth", error }
    : { type: "preconnect_google_oauth", email };
  const encoded = JSON.stringify(payload).replace(/</g, "\\u003c");
  const safeOrigin = origin.replace(/'/g, "");
  return `<!doctype html>
<html><head><meta charset="utf-8"><title>PreConnect Login</title></head>
<body>
<script>
  (function() {
    var payload = ${encoded};
    try {
      if (window.opener && !window.opener.closed) {
        window.opener.postMessage(JSON.stringify(payload), '${safeOrigin}');
      }
    } catch (_) {}
    window.close();
  })();
</script>
</body></html>`;
}

function callbackOrigin(url, env) {
  const configured = `${env.PUBLIC_WEB_ORIGIN || ""}`.trim();
  if (configured) return configured.replace(/\/+$/, "");
  return `${url.protocol}//${url.host}`;
}

async function handleGoogleOauthStart(request, env) {
  if (request.method !== "GET") {
    return json({ error: "Method not allowed" }, { status: 405 });
  }
  const clientId = `${env.GOOGLE_OAUTH_CLIENT_ID || ""}`.trim();
  const secret = `${env.AUTH_SIGNING_KEY || DEFAULT_AUTH_SIGNING_KEY}`.trim();
  if (!clientId) {
    return json({ error: "OAuth is not configured" }, { status: 503 });
  }
  const url = new URL(request.url);
  const origin = callbackOrigin(url, env);
  const redirectUri = `${origin}/auth/google/callback`;
  const state = await signStatePayload(
    {
      v: 1,
      n: base64UrlEncode(crypto.getRandomValues(new Uint8Array(16))),
      exp: Date.now() + OAUTH_STATE_TTL_MS,
      origin,
    },
    secret,
  );
  const authUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  authUrl.searchParams.set("client_id", clientId);
  authUrl.searchParams.set("redirect_uri", redirectUri);
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("scope", "openid email profile");
  authUrl.searchParams.set("prompt", "select_account");
  authUrl.searchParams.set("state", state);
  return Response.redirect(authUrl.toString(), 302);
}

async function handleGoogleOauthCallback(request, env) {
  const clientId = `${env.GOOGLE_OAUTH_CLIENT_ID || ""}`.trim();
  const clientSecret = `${env.GOOGLE_OAUTH_CLIENT_SECRET || ""}`.trim();
  const secret = `${env.AUTH_SIGNING_KEY || DEFAULT_AUTH_SIGNING_KEY}`.trim();
  const url = new URL(request.url);
  const origin = callbackOrigin(url, env);
  const stateRaw = `${url.searchParams.get("state") || ""}`.trim();
  const code = `${url.searchParams.get("code") || ""}`.trim();
  const oauthError = `${url.searchParams.get("error") || ""}`.trim();

  if (oauthError) {
    return new Response(
      popupCallbackHtml({ origin, error: `Sign-in failed: ${oauthError}` }),
      { status: 200, headers: { "content-type": "text/html; charset=utf-8" } },
    );
  }

  const state = await verifyStatePayload(stateRaw, secret);
  if (!state || state.origin !== origin) {
    return new Response(
      popupCallbackHtml({ origin, error: "Invalid sign-in state. Please try again." }),
      { status: 200, headers: { "content-type": "text/html; charset=utf-8" } },
    );
  }
  if (!clientId || !clientSecret || !code) {
    return new Response(
      popupCallbackHtml({ origin, error: "OAuth is not configured correctly." }),
      { status: 200, headers: { "content-type": "text/html; charset=utf-8" } },
    );
  }

  const redirectUri = `${origin}/auth/google/callback`;
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: redirectUri,
      grant_type: "authorization_code",
    }),
  });
  if (!tokenResponse.ok) {
    return new Response(
      popupCallbackHtml({ origin, error: "Could not complete Google sign-in." }),
      { status: 200, headers: { "content-type": "text/html; charset=utf-8" } },
    );
  }
  const tokenJson = await tokenResponse.json();
  const accessToken = `${tokenJson?.access_token || ""}`.trim();
  if (!accessToken) {
    return new Response(
      popupCallbackHtml({ origin, error: "Google sign-in did not return an access token." }),
      { status: 200, headers: { "content-type": "text/html; charset=utf-8" } },
    );
  }

  const userInfoResponse = await fetch("https://openidconnect.googleapis.com/v1/userinfo", {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  if (!userInfoResponse.ok) {
    return new Response(
      popupCallbackHtml({ origin, error: "Could not read email from Google account." }),
      { status: 200, headers: { "content-type": "text/html; charset=utf-8" } },
    );
  }
  const userInfo = await userInfoResponse.json();
  const email = normalizeEmail(userInfo?.email);
  if (!isStudentEmail(email)) {
    return new Response(
      popupCallbackHtml({
        origin,
        error: "Use a valid student Google account (example: name@g.bracu.ac.bd).",
      }),
      { status: 200, headers: { "content-type": "text/html; charset=utf-8" } },
    );
  }

  return new Response(
    popupCallbackHtml({ origin, email }),
    { status: 200, headers: { "content-type": "text/html; charset=utf-8" } },
  );
}

function getBearerToken(request) {
  const auth = `${request.headers.get("authorization") || ""}`.trim();
  if (!auth.toLowerCase().startsWith("bearer ")) return "";
  return auth.slice(7).trim();
}

async function proxyToBroker(path, init = {}, env) {
  const base = `${env.BROKER_BASE || DEFAULT_BROKER_BASE}`.replace(/\/+$/, "");
  const upstream = await fetch(`${base}${path}`, init);
  return upstream;
}

async function handleCreateSession(request, env) {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, { status: 405 });
  }
  const secret = `${env.AUTH_SIGNING_KEY || DEFAULT_AUTH_SIGNING_KEY}`.trim();
  const token = getBearerToken(request);
  if (!token) return json({ error: "Missing auth token" }, { status: 401 });
  const verified = await verifySignedAuthToken(token, secret);
  if (!verified) return json({ error: "Invalid or expired auth token" }, { status: 401 });

  const upstream = await proxyToBroker(
    "/web-login/session",
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ googleEmail: verified.email }),
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

    if (url.pathname === "/auth/google/start") {
      return handleGoogleOauthStart(request, env);
    }

    if (url.pathname === "/auth/google/callback") {
      return handleGoogleOauthCallback(request, env);
    }

    if (url.pathname === "/auth/request-token") {
      return handleIssueAuthToken(request, env);
    }

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
