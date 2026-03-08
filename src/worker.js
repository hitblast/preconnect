const FIREBASE_AUTH_ORIGIN = "https://preconnect-bracu.firebaseapp.com";

function shouldProxyToFirebase(url) {
  return (
    url.pathname.startsWith("/__/auth/") ||
    url.pathname === "/__/firebase/init.json"
  );
}

function buildFirebaseProxyRequest(request, url) {
  const upstreamUrl = new URL(url.toString());
  upstreamUrl.protocol = "https:";
  upstreamUrl.host = "preconnect-bracu.firebaseapp.com";

  const headers = new Headers(request.headers);
  headers.set("host", "preconnect-bracu.firebaseapp.com");

  return new Request(upstreamUrl.toString(), {
    method: request.method,
    headers,
    body:
      request.method === "GET" || request.method === "HEAD"
        ? undefined
        : request.body,
    redirect: "manual",
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (shouldProxyToFirebase(url)) {
      const upstreamRequest = buildFirebaseProxyRequest(request, url);
      const upstreamResponse = await fetch(upstreamRequest);
      const headers = new Headers(upstreamResponse.headers);
      headers.set("access-control-allow-origin", url.origin);
      headers.append("vary", "Origin");
      return new Response(upstreamResponse.body, {
        status: upstreamResponse.status,
        statusText: upstreamResponse.statusText,
        headers,
      });
    }

    return env.ASSETS.fetch(request);
  },
};
