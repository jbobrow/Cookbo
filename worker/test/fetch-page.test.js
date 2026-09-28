import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import zlib from 'node:zlib';
import {
  validateURL, isPublicAddress, guardedLookup, createPageFetcher,
} from '../src/fetch-page.js';

// MARK: - URLs

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
  for (const bad of ['http://127.0.0.1/', 'http://169.254.169.254/computeMetadata/v1/', 'http://10.0.0.1/', 'http://[::1]/',
    'http://localhost/', 'http://intranet/', 'http://printer.local/', 'http://metadata.google.internal/']) {
    assert.equal(validateURL(bad), null, bad);
  }
});

test('rejects missing and garbage input', () => {
  assert.equal(validateURL(null), null);
  assert.equal(validateURL('not a url'), null);
  assert.equal(validateURL('https://example.com/' + 'a'.repeat(3000)), null);
});

// MARK: - Addresses

test('refuses private, internal and special-purpose addresses', () => {
  for (const address of [
    '127.0.0.1', '10.1.2.3', '172.16.0.1', '172.31.255.255', '192.168.1.1', '169.254.169.254',
    '100.64.0.1', '0.0.0.0', '224.0.0.1', '255.255.255.255',
    '::1', '::', 'fe80::1', 'fc00::1', 'fd12:3456::1', 'ff02::1',
    '::ffff:127.0.0.1', '::ffff:7f00:1', '::ffff:10.0.0.1', '64:ff9b::7f00:1', '2001:db8::1',
  ]) {
    assert.equal(isPublicAddress(address), false, address);
  }
});

test('allows public addresses, including right at the edges of private ranges', () => {
  for (const address of ['8.8.8.8', '151.101.1.1', '172.32.0.1', '172.15.255.255', '100.128.0.1', '2606:4700::1111', '::ffff:8.8.8.8']) {
    assert.equal(isPublicAddress(address), true, address);
  }
});

test('refuses anything that isn’t an IP address', () => {
  assert.equal(isPublicAddress('example.com'), false);
  assert.equal(isPublicAddress(''), false);
});

// MARK: - Lookup

const fakeDNS = (answers) => (hostname, options, callback) => callback(null, answers[hostname] ?? []);

const resolve = (lookup, hostname, options = {}) => new Promise((res) => {
  lookup(hostname, options, (error, address, family) => res({ error, address, family }));
});

test('the guarded lookup passes public addresses through', async () => {
  const lookup = guardedLookup({ lookup: fakeDNS({ 'recipes.example': [{ address: '93.184.216.34', family: 4 }] }) });
  const { error, address } = await resolve(lookup, 'recipes.example');
  assert.equal(error, null);
  assert.equal(address, '93.184.216.34');
});

test('the guarded lookup refuses a hostname that resolves somewhere private', async () => {
  const lookup = guardedLookup({ lookup: fakeDNS({ 'sneaky.example': [{ address: '169.254.169.254', family: 4 }] }) });
  const { error } = await resolve(lookup, 'sneaky.example');
  assert.equal(error?.code, 'invalid_url');
});

test('the guarded lookup refuses a hostname with any private address among public ones', async () => {
  const lookup = guardedLookup({ lookup: fakeDNS({ 'mixed.example': [{ address: '8.8.8.8', family: 4 }, { address: '10.0.0.5', family: 4 }] }) });
  const { error } = await resolve(lookup, 'mixed.example');
  assert.equal(error?.code, 'invalid_url');
});

test('the guarded lookup returns every checked address when asked for all', async () => {
  const answers = [{ address: '8.8.8.8', family: 4 }, { address: '2606:4700::1111', family: 6 }];
  const lookup = guardedLookup({ lookup: fakeDNS({ 'dual.example': answers }) });
  const { address } = await resolve(lookup, 'dual.example', { all: true });
  assert.deepEqual(address, answers);
});

// MARK: - Fetching, against a local server

let server;
let port;
const routes = {
  '/recipe': (req, res) => { res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); res.end('<h1>Soup</h1>'); },
  '/old': (req, res) => { res.writeHead(301, { Location: '/recipe' }); res.end(); },
  '/to-private': (req, res) => { res.writeHead(302, { Location: 'http://127.0.0.1/admin' }); res.end(); },
  '/loop': (req, res) => { res.writeHead(302, { Location: '/loop' }); res.end(); },
  '/json': (req, res) => { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end('{}'); },
  '/missing': (req, res) => { res.writeHead(404, { 'Content-Type': 'text/html' }); res.end('nope'); },
  '/huge': (req, res) => { res.writeHead(200, { 'Content-Type': 'text/html' }); res.end('x'.repeat(2048)); },
  '/gzip-bomb': (req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/html', 'Content-Encoding': 'gzip' });
    res.end(zlib.gzipSync('x'.repeat(2048)));
  },
  '/gzip': (req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/html', 'Content-Encoding': 'gzip' });
    res.end(zlib.gzipSync('<h1>Compressed soup</h1>'));
  },
  '/latin1': (req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=iso-8859-1' });
    res.end(Buffer.from([0x63, 0x72, 0xe8, 0x6d, 0x65])); // "crème" in Latin-1
  },
  '/slow': () => { /* never answers */ },
};

before(async () => {
  server = http.createServer((req, res) => (routes[req.url] ?? routes['/missing'])(req, res));
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  port = server.address().port;
});
after(() => server.close());

// The local server is on 127.0.0.1 and a random port, so these fetchers allow both;
// only the host's name is treated as public. The real guards are tested above.
const local = (overrides = {}) => createPageFetcher({
  lookup: (hostname, options, callback) => (options.all
    ? callback(null, [{ address: '127.0.0.1', family: 4 }])
    : callback(null, '127.0.0.1', 4)),
  validate: (href) => {
    const url = new URL(href);
    return url.hostname === 'recipes.example.com' ? url : validateURL(href);
  },
  timeoutMs: 1_000,
  maxBytes: 1024,
  ...overrides,
});
const at = (path) => new URL(`http://recipes.example.com:${port}${path}`);

test('fetches a page', async () => {
  assert.equal(await local()(at('/recipe')), '<h1>Soup</h1>');
});

test('follows an ordinary redirect', async () => {
  assert.equal(await local()(at('/old')), '<h1>Soup</h1>');
});

test('refuses a redirect that points somewhere private', async () => {
  await assert.rejects(local()(at('/to-private')), { code: 'fetch_failed', status: 502 });
});

test('gives up on a redirect loop', async () => {
  await assert.rejects(local()(at('/loop')), { code: 'fetch_failed' });
});

test('415 for something that isn’t a web page', async () => {
  await assert.rejects(local()(at('/json')), { code: 'not_html', status: 415 });
});

test('502 when the site says no', async () => {
  await assert.rejects(local()(at('/missing')), { code: 'fetch_failed', status: 502 });
});

test('413 when the page is too large', async () => {
  await assert.rejects(local()(at('/huge')), { code: 'too_large', status: 413 });
});

test('the size limit applies after decompression', async () => {
  await assert.rejects(local()(at('/gzip-bomb')), { code: 'too_large', status: 413 });
});

test('decompresses gzip', async () => {
  assert.equal(await local()(at('/gzip')), '<h1>Compressed soup</h1>');
});

test('honors the page’s declared character set', async () => {
  assert.equal(await local()(at('/latin1')), 'crème');
});

test('504 when the site doesn’t answer in time', async () => {
  await assert.rejects(local({ timeoutMs: 150 })(at('/slow')), { code: 'timeout', status: 504 });
});

test('with the real guard, never connects to a private address', async () => {
  let connected = false;
  server.once('connection', () => { connected = true; });
  const guarded = createPageFetcher({
    lookup: guardedLookup({ lookup: fakeDNS({ 'recipes.example.com': [{ address: '127.0.0.1', family: 4 }] }) }),
  });
  await assert.rejects(guarded(at('/recipe')), { code: 'invalid_url', status: 400 });
  assert.equal(connected, false);
});
