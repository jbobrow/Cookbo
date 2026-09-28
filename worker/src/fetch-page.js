// Fetches a public web page for the import demo — and only a public one.
//
// The service fetches whatever link a stranger pastes, so the risk to guard
// against is a link that leads back into our own network: localhost, private
// ranges, or the cloud metadata server. Cloudflare Workers blocked those at the
// platform level; Cloud Run doesn't, so it's done here:
//
//   1. The URL itself must be an ordinary public http(s) address (validateURL).
//   2. The hostname is resolved, and every address it resolves to must be public.
//   3. The connection is made to exactly those checked addresses, via the same
//      lookup, so DNS can't return a safe answer for the check and a private
//      one for the connection.
//
// Redirects are followed by hand so each hop goes through all three again.

import dns from 'node:dns';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import zlib from 'node:zlib';

export const TIMEOUT_MS = 8_000;
export const MAX_BYTES = 4 * 1024 * 1024;
const MAX_REDIRECTS = 4;
const USER_AGENT = 'Mozilla/5.0 (compatible; CookboImport/1.0; +https://cookbo.app)';

// MARK: - URLs

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
  // Recipe sites have domain names: refuse IP literals, bare hostnames and internal suffixes
  // outright. Hostnames that resolve somewhere private are caught at connect time.
  if (host.startsWith('[') || /^[\d.]+$/.test(host)) return null;
  if (!host.includes('.') || host === 'localhost') return null;
  if (/\.(local|localhost|internal|lan|home|corp|test|invalid)$/.test(host)) return null;

  url.hash = '';
  return url;
}

// MARK: - Addresses

// Everywhere a public web page can't be: private and shared networks, loopback,
// link-local (including the metadata server at 169.254.169.254), documentation
// and benchmarking ranges, multicast and reserved space.
const BLOCKED = new net.BlockList();
for (const [address, prefix] of [
  ['0.0.0.0', 8], ['10.0.0.0', 8], ['100.64.0.0', 10], ['127.0.0.0', 8], ['169.254.0.0', 16],
  ['172.16.0.0', 12], ['192.0.0.0', 24], ['192.0.2.0', 24], ['192.88.99.0', 24], ['192.168.0.0', 16],
  ['198.18.0.0', 15], ['198.51.100.0', 24], ['203.0.113.0', 24], ['224.0.0.0', 4], ['240.0.0.0', 4],
]) BLOCKED.addSubnet(address, prefix, 'ipv4');
// BlockList compares IPv4-mapped IPv6 addresses (::ffff:10.0.0.1) against the IPv4
// rules above, so those need no rule of their own; adding ::ffff:0:0/96 here would
// block every IPv4 address.
for (const [address, prefix] of [
  ['::', 96],            // unspecified, loopback, and IPv4-compatible addresses
  ['64:ff9b::', 96],     // NAT64, which embeds an IPv4 address
  ['100::', 64],         // discard
  ['2001::', 32],        // Teredo, which embeds an IPv4 address
  ['2001:db8::', 32],    // documentation
  ['fc00::', 7],         // unique local
  ['fe80::', 10],        // link-local
  ['ff00::', 8],         // multicast
]) BLOCKED.addSubnet(address, prefix, 'ipv6');

export function isPublicAddress(address) {
  const family = net.isIP(address);
  if (family === 4) return !BLOCKED.check(address, 'ipv4');
  if (family === 6) return !BLOCKED.check(address, 'ipv6');
  return false;
}

/**
 * A `lookup` for http.request that only ever hands back public addresses. A host
 * with any non-public address is refused outright, since a legitimate recipe site
 * has no reason to resolve into a private network.
 */
export function guardedLookup({ lookup = dns.lookup, isAllowedAddress = isPublicAddress } = {}) {
  return (hostname, options, callback) => {
    if (typeof options === 'function') [options, callback] = [{}, options];
    lookup(hostname, { ...options, all: true }, (error, addresses) => {
      if (error) return callback(error);
      if (!addresses.length || addresses.some(({ address }) => !isAllowedAddress(address))) {
        return callback(failure('invalid_url', 400));
      }
      if (options.all) callback(null, addresses);
      else callback(null, addresses[0].address, addresses[0].family);
    });
  };
}

// MARK: - Fetching

/**
 * Creates the page fetcher. Everything is injectable so tests can point it at a
 * local server; production uses the defaults.
 */
export function createPageFetcher({
  lookup = guardedLookup(),
  validate = (href) => validateURL(href),
  timeoutMs = TIMEOUT_MS,
  maxBytes = MAX_BYTES,
} = {}) {
  return async function fetchPage(startURL) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);

    try {
      let url = startURL;
      for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
        const response = await get(url, lookup, controller.signal);
        const status = response.statusCode ?? 0;

        if (status >= 300 && status < 400) {
          response.resume();
          const location = response.headers.location;
          const next = location && validate(new URL(location, url).href);
          if (!next) throw failure('fetch_failed', 502);
          url = next;
          continue;
        }

        if (status < 200 || status >= 300) {
          response.resume();
          throw failure('fetch_failed', 502);
        }

        const type = response.headers['content-type'] ?? '';
        if (!/text\/html|application\/xhtml\+xml/i.test(type)) {
          response.resume();
          throw failure('not_html', 415);
        }

        if (Number(response.headers['content-length'] ?? 0) > maxBytes) {
          response.resume();
          throw failure('too_large', 413);
        }

        return await readBody(response, type, maxBytes, controller);
      }
      throw failure('fetch_failed', 502);
    } catch (error) {
      if (error.status) throw error; // one of ours, including a refused address or an oversized page
      if (controller.signal.aborted) throw failure('timeout', 504);
      throw failure('fetch_failed', 502);
    } finally {
      clearTimeout(timer);
    }
  };
}

function get(url, lookup, signal) {
  return new Promise((resolve, reject) => {
    const client = url.protocol === 'https:' ? https : http;
    const request = client.request(url, {
      method: 'GET',
      lookup,
      signal,
      agent: false, // no pooled sockets: every connection goes through the guarded lookup
      headers: {
        'User-Agent': USER_AGENT,
        Accept: 'text/html,application/xhtml+xml',
        'Accept-Encoding': 'gzip, deflate, br',
      },
    }, resolve);
    request.on('error', reject);
    request.end();
  });
}

/** Reads the body, decompressing if needed, and stops once it passes maxBytes (after decompression). */
async function readBody(response, contentType, maxBytes, controller) {
  const encoding = (response.headers['content-encoding'] ?? '').toLowerCase();
  let stream = response;
  if (encoding === 'gzip' || encoding === 'x-gzip') stream = response.pipe(zlib.createGunzip());
  else if (encoding === 'deflate') stream = response.pipe(zlib.createInflate());
  else if (encoding === 'br') stream = response.pipe(zlib.createBrotliDecompress());

  const chunks = [];
  let bytes = 0;
  for await (const chunk of stream) {
    bytes += chunk.length;
    if (bytes > maxBytes) {
      controller.abort();
      throw failure('too_large', 413);
    }
    chunks.push(chunk);
  }

  const charset = /charset=["']?([\w-]+)/i.exec(contentType)?.[1] ?? 'utf-8';
  let decoder;
  try {
    decoder = new TextDecoder(charset);
  } catch {
    decoder = new TextDecoder('utf-8');
  }
  return decoder.decode(Buffer.concat(chunks));
}

export function failure(code, status) {
  return Object.assign(new Error(code), { code, status });
}
