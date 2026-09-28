import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import worker, { validateURL } from '../src/index.js';

const realFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = realFetch; });

const RECIPE_HTML = `<script type="application/ld+json">${JSON.stringify({
  '@type': 'Recipe', name: 'Soup', recipeIngredient: ['water'], recipeInstructions: ['Boil.'],
})}</script>`;

const call = (url, origin = 'https://cookbo.app') =>
  worker.fetch(new Request(`https://worker.example/?url=${encodeURIComponent(url)}`, { headers: { Origin: origin } }), {}, {});

const html = (body, init = {}) =>
  new Response(body, { status: 200, headers: { 'Content-Type': 'text/html; charset=utf-8' }, ...init });

// MARK: URL validation

test('accepts ordinary recipe URLs', () => {
  assert.ok(validateURL('https://www.seriouseats.com/some-recipe'));
  assert.ok(validateURL('http://example.com/recipe'));
});

test('rejects non-http schemes, credentials and odd ports', () => {
  for (const bad of ['javascript:alert(1)', 'file:///etc/passwd', 'ftp://example.com/', 'https://user:pw@example.com/', 'https://example.com:8080/']) {
    assert.equal(validateURL(bad), null, bad);
  }
});

test('rejects IP literals and internal hostnames', () => {
  for (const bad of ['http://127.0.0.1/', 'http://169.254.169.254/latest/meta-data', 'http://10.0.0.1/', 'http://[::1]/', 'http://localhost/', 'http://intranet/', 'http://printer.local/', 'http://db.internal/']) {
    assert.equal(validateURL(bad), null, bad);
  }
});

test('rejects missing and garbage input', () => {
  assert.equal(validateURL(null), null);
  assert.equal(validateURL('not a url'), null);
  assert.equal(validateURL('https://example.com/' + 'a'.repeat(3000)), null);
});

// MARK: handler

test('returns only the extracted recipe', async () => {
  globalThis.fetch = async () => html(RECIPE_HTML + '<p>secret page content</p>');
  const response = await call('https://example.com/soup');
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.title, 'Soup');
  assert.ok(!JSON.stringify(body).includes('secret page content'));
});

test('400 for a disallowed URL, without fetching it', async () => {
  let fetched = false;
  globalThis.fetch = async () => { fetched = true; return html(''); };
  const response = await call('http://169.254.169.254/latest/meta-data');
  assert.equal(response.status, 400);
  assert.equal(fetched, false);
});

test('re-validates redirects and refuses one pointing somewhere private', async () => {
  globalThis.fetch = async () => new Response(null, { status: 302, headers: { Location: 'http://127.0.0.1/admin' } });
  const response = await call('https://example.com/soup');
  assert.equal(response.status, 502);
});

test('follows an ordinary redirect', async () => {
  let calls = 0;
  globalThis.fetch = async (url) => {
    calls++;
    return url.includes('/old')
      ? new Response(null, { status: 301, headers: { Location: '/new' } })
      : html(RECIPE_HTML);
  };
  const response = await call('https://example.com/old');
  assert.equal(response.status, 200);
  assert.equal(calls, 2);
});

test('404 when the page has no recipe', async () => {
  globalThis.fetch = async () => html('<html>nothing</html>');
  assert.equal((await call('https://example.com/')).status, 404);
});

test('415 for non-HTML responses', async () => {
  globalThis.fetch = async () => new Response('{}', { headers: { 'Content-Type': 'application/json' } });
  assert.equal((await call('https://example.com/data.json')).status, 415);
});

test('413 when the page is too large', async () => {
  globalThis.fetch = async () => html('x'.repeat(5 * 1024 * 1024));
  assert.equal((await call('https://example.com/huge')).status, 413);
});

test('CORS allows cookbo.app and localhost, and nothing else', async () => {
  globalThis.fetch = async () => html(RECIPE_HTML);
  const allowed = await call('https://example.com/', 'https://cookbo.app');
  assert.equal(allowed.headers.get('Access-Control-Allow-Origin'), 'https://cookbo.app');
  const local = await call('https://example.com/', 'http://localhost:8787');
  assert.equal(local.headers.get('Access-Control-Allow-Origin'), 'http://localhost:8787');
  const other = await call('https://example.com/', 'https://evil.example');
  assert.equal(other.headers.get('Access-Control-Allow-Origin'), 'https://cookbo.app');
});
