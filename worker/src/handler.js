// The import endpoint: POST {"url": "..."} → the recipe on that page.
//
// The link travels in the request body rather than the query string so it never
// lands in the platform's request logs. Responses carry only extracted recipe
// fields, never the page, so this is no use as a general-purpose proxy.

import { createPageFetcher, validateURL } from './fetch-page.js';
import { parseRecipe } from './parse.js';

const ALLOWED_ORIGINS = new Set(['https://cookbo.app', 'https://www.cookbo.app']);
const LOCAL_ORIGIN = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

export const CACHE_TTL_MS = 6 * 60 * 60 * 1000;

export function createHandler({
  fetchPage = createPageFetcher(),
  cache = new TTLCache({ ttlMs: CACHE_TTL_MS, maxEntries: 500 }),
  perVisitor = new RateLimiter({ limit: 20, windowMs: 60_000 }),
  overall = new RateLimiter({ limit: 120, windowMs: 60_000 }),
} = {}) {
  return async function handle(request) {
    const cors = corsHeaders(request.headers.get('Origin'));

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: { ...cors, 'Access-Control-Allow-Headers': 'Content-Type', 'Access-Control-Max-Age': '86400' },
      });
    }
    if (request.method !== 'POST') return error('method_not_allowed', 405, cors);

    // A per-visitor limit for fairness, and an overall one per instance so the
    // service can't be turned into a way to hammer other sites
    if (!perVisitor.allow(clientAddress(request)) || !overall.allow('all')) {
      return error('rate_limited', 429, cors);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return error('invalid_url', 400, cors);
    }
    const target = validateURL(body?.url);
    if (!target) return error('invalid_url', 400, cors);

    const cached = cache.get(target.href);
    if (cached) return json(cached, cors);

    let html;
    try {
      html = await fetchPage(target);
    } catch (e) {
      return error(e.code ?? 'fetch_failed', e.status ?? 502, cors);
    }

    const recipe = parseRecipe(html, target.href);
    if (!recipe) return error('no_recipe', 404, cors);

    cache.set(target.href, recipe);
    return json(recipe, cors);
  };
}

/**
 * The visitor's address. Cloud Run appends the address it received the request
 * from to X-Forwarded-For, so the last entry is the one a client can't forge.
 */
export function clientAddress(request) {
  const forwarded = request.headers.get('X-Forwarded-For');
  return forwarded?.split(',').pop()?.trim() || 'unknown';
}

function corsHeaders(origin) {
  const allowed = origin && (ALLOWED_ORIGINS.has(origin) || LOCAL_ORIGIN.test(origin));
  return {
    'Access-Control-Allow-Origin': allowed ? origin : 'https://cookbo.app',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    Vary: 'Origin',
  };
}

function json(data, cors) {
  return new Response(JSON.stringify(data), {
    headers: { ...cors, 'Content-Type': 'application/json; charset=utf-8' },
  });
}

function error(code, status, cors) {
  return new Response(JSON.stringify({ error: code }), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json; charset=utf-8' },
  });
}

// MARK: - In-memory helpers

/** A small time-limited cache. Oldest entries go first once it's full. */
export class TTLCache {
  constructor({ ttlMs, maxEntries, now = Date.now }) {
    Object.assign(this, { ttlMs, maxEntries, now, entries: new Map() });
  }

  get(key) {
    const entry = this.entries.get(key);
    if (!entry) return undefined;
    if (entry.expires <= this.now()) {
      this.entries.delete(key);
      return undefined;
    }
    return entry.value;
  }

  set(key, value) {
    this.entries.delete(key);
    this.entries.set(key, { value, expires: this.now() + this.ttlMs });
    while (this.entries.size > this.maxEntries) {
      this.entries.delete(this.entries.keys().next().value);
    }
  }
}

/** Fixed-window request counting per key. */
export class RateLimiter {
  constructor({ limit, windowMs, now = Date.now }) {
    Object.assign(this, { limit, windowMs, now, windows: new Map() });
  }

  allow(key) {
    const now = this.now();
    let window = this.windows.get(key);
    if (!window || window.resetsAt <= now) {
      if (this.windows.size > 10_000) this.prune(now);
      window = { count: 0, resetsAt: now + this.windowMs };
      this.windows.set(key, window);
    }
    window.count += 1;
    return window.count <= this.limit;
  }

  prune(now) {
    for (const [key, window] of this.windows) {
      if (window.resetsAt <= now) this.windows.delete(key);
    }
  }
}
