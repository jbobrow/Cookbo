// The import service as it runs on Cloud Run.

import http from 'node:http';
import { createHandler } from './handler.js';
import { send, sendError, toRequest } from './node-adapter.js';

const handle = createHandler();
const port = Number(process.env.PORT ?? 8080);

http.createServer(async (req, res) => {
  try {
    await send(res, await handle(await toRequest(req)));
  } catch (error) {
    // Never log the request itself: it carries the visitor's link
    if (!error.status) console.error('import failed:', error.name, error.message);
    sendError(res, error.status ?? 500);
  }
}).listen(port, () => console.log(`cookbo-import listening on ${port}`));
