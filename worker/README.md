# cookbo-import

The Cloudflare Worker behind the "paste a link" demo on cookbo.app. It fetches a
recipe page and returns only the extracted recipe, using the same schema.org
JSON-LD approach as the app's parser (`Shared/RecipeParserCore.swift`).

A browser can't read another site's page from cookbo.app (CORS), which is why
this needs to exist at all.

## Try it locally

```bash
node dev-server.mjs
```

Serves `../docs` at http://localhost:8787 with the Worker mounted at
`/api/import`. On localhost the page uses that endpoint automatically.

```bash
npm test
```

## Deploy

```bash
npx wrangler login
npx wrangler deploy
```

Wrangler prints the Worker's URL, e.g. `https://cookbo-import.<you>.workers.dev`.
Put it in `docs/index.html`:

```html
<meta name="cookbo-import-endpoint" content="https://cookbo-import.<you>.workers.dev">
```

While that's empty, the site still plays the demo; it just hides the link field.

## Safety

Since it fetches URLs on request, it only fetches public http(s) pages (no IP
addresses, internal hostnames, credentials or unusual ports), re-checks every
redirect, gives up after 8 seconds or 4 MB, accepts only HTML, and answers only
from cookbo.app (plus localhost). It never returns the page itself, only the
recipe fields, so it's no use as a general proxy.

For a per-IP rate limit, uncomment the `RATE_LIMITER` block in `wrangler.toml`.
