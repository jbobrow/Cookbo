// cookbo.app live-import demo: fetch a recipe page and return only the recipe.
//
// Because this fetches URLs on request, it's deliberately narrow. It only
// fetches public http(s) pages, re-checks every redirect hop, caps time and
// size, and responds with extracted recipe fields — never the page itself —
// so it's no use as a general-purpose proxy.

import { parseRecipe } from './parse.js';

const ALLOWED_ORIGINS = new Set(['https://cookbo.app', 'https://www.cookbo.app']);
const TIMEOUT_MS = 8_000;
const MAX_BYTES = 4 * 1024 * 1024;
const MAX_REDIRECTS = 4;
const CACHE_SECONDS = 6 * 60 * 60;
const USER_AGENT = 'Mozilla/5.0 (compatible; CookboImport/1.0; +https://cookbo.app)';

export default {
  async fetch(request, env, ctx) {
    const cors = corsHeaders(request.headers.get('Origin'));

    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (request.method !== 'GET') return error('method_not_allowed', 405, cors);

    const target = validateURL(new URL(request.url).searchParams.get('url'));
    if (!target) return error('invalid_url', 400, cors);

    if (env?.RATE_LIMITER) {
      const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
      const { success } = await env.RATE_LIMITER.limit({ key: ip });
      if (!success) return error('rate_limited', 429, cors);
    }

    // Cache parsed results per page, so repeat demos don't refetch
    const cache = globalThis.caches?.default;
    const cacheKey = new Request(`https://cookbo-import.cache/${encodeURIComponent(target.href)}`);
    const cached = cache && (await cache.match(cacheKey));
    if (cached) return withHeaders(cached, cors);

    let html;
    try {
      html = await fetchPage(target);
    } catch (e) {
      return error(e.code ?? 'fetch_failed', e.status ?? 502, cors);
    }

    const recipe = parseRecipe(html, target.href);
    if (!recipe) return error('no_recipe', 404, cors);

    const response = new Response(JSON.stringify(recipe), {
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': `public, max-age=${CACHE_SECONDS}`,
      },
    });
    if (cache && ctx?.waitUntil) ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return withHeaders(response, cors);
  },
};

/** Returns a URL if it's a public http(s) page we're willing to fetch, else null. */
export function validateURL(raw) {
  if (typeof raw !== 'string' || raw.length > 2048) return null;

  let url;
  try {
    url = new URL(raw.trim());
  } catch {
    return null;
  }

  if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
  if (url.username || url.password) return null;
  if (url.port && url.port !== '80' && url.port !== '443') return null;

  const host = url.hostname.toLowerCase();
  // Recipe sites have domain names. Refusing IP literals, bare hostnames and
  // internal suffixes rules out addressing anything private by number or name.
  // (Workers can't reach private networks anyway; this is defense in depth.)
  if (host.startsWith('[') || /^[\d.]+$/.test(host)) return null;
  if (!host.includes('.') || host === 'localhost') return null;
  if (/\.(local|localhost|internal|lan|home|corp|test|invalid)$/.test(host)) return null;

  url.hash = '';
  return url;
}

async function fetchPage(startURL) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    let url = startURL;
    for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
      const response = await fetch(url.href, {
        redirect: 'manual',
        signal: controller.signal,
        headers: { 'User-Agent': USER_AGENT, Accept: 'text/html,application/xhtml+xml' },
      });

      if (response.status >= 300 && response.status < 400) {
        const location = response.headers.get('Location');
        const next = location && validateURL(new URL(location, url).href);
        if (!next) throw failure('fetch_failed', 502);
        url = next;
        continue;
      }

      if (!response.ok) throw failure('fetch_failed', 502);

      const type = response.headers.get('Content-Type') ?? '';
      if (!/text\/html|application\/xhtml\+xml/i.test(type)) throw failure('not_html', 415);

      const declared = Number(response.headers.get('Content-Length') ?? 0);
      if (declared > MAX_BYTES) throw failure('too_large', 413);

      return await readCapped(response.body, controller);
    }
    throw failure('fetch_failed', 502);
  } catch (e) {
    if (e.name === 'AbortError') throw failure('timeout', 504);
    throw e;
  } finally {
    clearTimeout(timer);
  }
}

async function readCapped(body, controller) {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let bytes = 0;
  let text = '';
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    bytes += value.byteLength;
    if (bytes > MAX_BYTES) {
      controller.abort();
      throw failure('too_large', 413);
    }
    text += decoder.decode(value, { stream: true });
  }
  return text + decoder.decode();
}

function corsHeaders(origin) {
  const allowed =
    origin && (ALLOWED_ORIGINS.has(origin) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin));
  return {
    'Access-Control-Allow-Origin': allowed ? origin : 'https://cookbo.app',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    Vary: 'Origin',
  };
}

function error(code, status, cors) {
  return new Response(JSON.stringify({ error: code }), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json; charset=utf-8' },
  });
}

function withHeaders(response, extra) {
  const copy = new Response(response.body, response);
  for (const [key, value] of Object.entries(extra)) copy.headers.set(key, value);
  return copy;
}

function failure(code, status) {
  return Object.assign(new Error(code), { code, status });
}
