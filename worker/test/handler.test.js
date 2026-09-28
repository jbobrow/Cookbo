import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler, clientAddress, TTLCache, RateLimiter } from '../src/handler.js';
import { failure } from '../src/fetch-page.js';

const RECIPE_HTML = `<script type="application/ld+json">${JSON.stringify({
  '@type': 'Recipe', name: 'Soup', recipeIngredient: ['water'], recipeInstructions: ['Boil.'],
})}</script><p>secret page content</p>`;

function handlerWith(fetchPage, options = {}) {
  const calls = [];
  const handle = createHandler({
    fetchPage: async (url) => { calls.push(url.href); return fetchPage(url); },
    ...options,
  });
  return { handle, calls };
}

const post = (url, { origin = 'https://cookbo.app', forwardedFor } = {}) => new Request('https://import.example/', {
  method: 'POST',
  headers: { Origin: origin, 'Content-Type': 'application/json', ...(forwardedFor && { 'X-Forwarded-For': forwardedFor }) },
  body: JSON.stringify({ url }),
});

test('returns only the extracted recipe', async () => {
  const { handle } = handlerWith(async () => RECIPE_HTML);
  const response = await handle(post('https://example.com/soup'));
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.title, 'Soup');
  assert.ok(!JSON.stringify(body).includes('secret page content'));
});

test('takes the link from the body, never the query string', async () => {
  const { handle, calls } = handlerWith(async () => RECIPE_HTML);
  const response = await handle(new Request('https://import.example/?url=https%3A%2F%2Fexample.com%2F', { method: 'GET' }));
  assert.equal(response.status, 405);
  assert.equal(calls.length, 0);
});

test('answers the CORS preflight', async () => {
  const { handle } = handlerWith(async () => RECIPE_HTML);
  const response = await handle(new Request('https://import.example/', { method: 'OPTIONS', headers: { Origin: 'https://cookbo.app' } }));
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('Access-Control-Allow-Headers'), 'Content-Type');
  assert.match(response.headers.get('Access-Control-Allow-Methods'), /POST/);
});

test('400 for a disallowed link, without fetching it', async () => {
  const { handle, calls } = handlerWith(async () => RECIPE_HTML);
  for (const bad of ['http://169.254.169.254/computeMetadata/v1/', 'file:///etc/passwd', 'not a url', undefined]) {
    assert.equal((await handle(post(bad))).status, 400, String(bad));
  }
  assert.equal(calls.length, 0);
});

test('400 for a body that isn’t JSON', async () => {
  const { handle } = handlerWith(async () => RECIPE_HTML);
  const response = await handle(new Request('https://import.example/', { method: 'POST', body: 'https://example.com/' }));
  assert.equal(response.status, 400);
});

test('404 when the page has no recipe', async () => {
  const { handle } = handlerWith(async () => '<html>nothing</html>');
  assert.equal((await handle(post('https://example.com/'))).status, 404);
});

test('passes the fetcher’s refusals through', async () => {
  for (const [code, status] of [['too_large', 413], ['not_html', 415], ['timeout', 504], ['fetch_failed', 502], ['invalid_url', 400]]) {
    const { handle } = handlerWith(async () => { throw failure(code, status); });
    const response = await handle(post('https://example.com/'));
    assert.equal(response.status, status, code);
    assert.equal((await response.json()).error, code);
  }
});

test('serves a repeat link from the cache', async () => {
  const { handle, calls } = handlerWith(async () => RECIPE_HTML);
  await handle(post('https://example.com/soup'));
  const again = await handle(post('https://example.com/soup'));
  assert.equal(again.status, 200);
  assert.equal(calls.length, 1);
});

test('limits each visitor', async () => {
  const { handle } = handlerWith(async () => RECIPE_HTML, {
    perVisitor: new RateLimiter({ limit: 2, windowMs: 60_000 }),
  });
  const statuses = [];
  for (let i = 0; i < 3; i++) statuses.push((await handle(post(`https://example.com/${i}`, { forwardedFor: '203.0.113.9' }))).status);
  assert.deepEqual(statuses, [200, 200, 429]);
  // Someone else is unaffected
  assert.equal((await handle(post('https://example.com/x', { forwardedFor: '198.51.100.7' }))).status, 200);
});

test('caps requests overall, whoever sends them', async () => {
  const { handle } = handlerWith(async () => RECIPE_HTML, {
    overall: new RateLimiter({ limit: 2, windowMs: 60_000 }),
  });
  const statuses = [];
  for (let i = 0; i < 3; i++) statuses.push((await handle(post(`https://example.com/${i}`, { forwardedFor: `192.0.2.${i}` }))).status);
  assert.deepEqual(statuses, [200, 200, 429]);
});

test('uses the address the platform appended, not one the client made up', () => {
  const request = new Request('https://import.example/', { headers: { 'X-Forwarded-For': '1.2.3.4, 203.0.113.9' } });
  assert.equal(clientAddress(request), '203.0.113.9');
  assert.equal(clientAddress(new Request('https://import.example/')), 'unknown');
});

test('CORS allows cookbo.app and localhost, and nothing else', async () => {
  const { handle } = handlerWith(async () => RECIPE_HTML);
  const origin = async (o) => (await handle(post('https://example.com/', { origin: o }))).headers.get('Access-Control-Allow-Origin');
  assert.equal(await origin('https://cookbo.app'), 'https://cookbo.app');
  assert.equal(await origin('http://localhost:8787'), 'http://localhost:8787');
  assert.equal(await origin('https://evil.example'), 'https://cookbo.app');
});

// MARK: - Helpers

test('the cache forgets entries after their time is up', () => {
  let now = 0;
  const cache = new TTLCache({ ttlMs: 1_000, maxEntries: 10, now: () => now });
  cache.set('a', 1);
  now = 999;
  assert.equal(cache.get('a'), 1);
  now = 1_000;
  assert.equal(cache.get('a'), undefined);
});

test('the cache drops the oldest entry when full', () => {
  const cache = new TTLCache({ ttlMs: 1_000, maxEntries: 2 });
  cache.set('a', 1);
  cache.set('b', 2);
  cache.set('c', 3);
  assert.equal(cache.get('a'), undefined);
  assert.equal(cache.get('c'), 3);
});

test('the rate limiter resets each window', () => {
  let now = 0;
  const limiter = new RateLimiter({ limit: 1, windowMs: 1_000, now: () => now });
  assert.equal(limiter.allow('k'), true);
  assert.equal(limiter.allow('k'), false);
  now = 1_000;
  assert.equal(limiter.allow('k'), true);
});
