// Local preview: serves ../docs and mounts the import service at /api/import, so
// the site and its live import can be tried together without deploying.
//   node dev-server.mjs   →   http://localhost:8787

import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHandler } from './src/handler.js';
import { send, sendError, toRequest } from './src/node-adapter.js';

const PORT = Number(process.env.PORT ?? 8787);
const handle = createHandler();
const ROOT = resolve(fileURLToPath(new URL('../docs', import.meta.url)));
const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.ico': 'image/x-icon',
};

createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  if (url.pathname === '/api/import') {
    try {
      await send(res, await handle(await toRequest(req)));
    } catch (error) {
      sendError(res, error.status ?? 500);
    }
    return;
  }

  // Static files, confined to ROOT; extensionless paths resolve like GitHub Pages
  let path = normalize(join(ROOT, decodeURIComponent(url.pathname)));
  if (!path.startsWith(ROOT)) { res.writeHead(403).end(); return; }
  try {
    if ((await stat(path)).isDirectory()) path = join(path, 'index.html');
  } catch {
    path += '.html';
  }
  try {
    const body = await readFile(path);
    res.writeHead(200, { 'Content-Type': TYPES[extname(path)] ?? 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(body);
  } catch {
    res.writeHead(404).end('Not found');
  }
}).listen(PORT, () => console.log(`Cookbo site: http://localhost:${PORT}`));
