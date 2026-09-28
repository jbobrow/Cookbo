# cookbo-import

The service behind the "paste a link" demo on cookbo.app. It fetches a recipe
page and returns only the extracted recipe, using the same schema.org JSON-LD
approach as the app's parser (`Shared/RecipeParserCore.swift`).

A browser can't read another site's page from cookbo.app (CORS), which is why
this needs to exist at all. It runs on Google Cloud Run.

```
POST /   {"url": "https://…"}   →   {"title": …, "ingredients": […], "steps": […], …}
```

## Try it locally

```bash
npm run dev
```

Serves `../docs` at http://localhost:8787 with the service mounted at
`/api/import`. On localhost the page uses that endpoint automatically.

```bash
npm test
```

## Deploy

Deploys from source; Cloud Build builds the `Dockerfile`.

```bash
gcloud run deploy cookbo-import \
  --project=cookbo-app --region=us-central1 --source=. \
  --service-account=cookbo-import@cookbo-app.iam.gserviceaccount.com \
  --allow-unauthenticated \
  --max-instances=2 --concurrency=40 --memory=256Mi --timeout=20s
```

It runs as a service account with no roles, so it holds no credentials worth
stealing. `--max-instances` caps the cost of a flood.

It's live at https://cookbo-import-87726969279.us-central1.run.app, under a
$5/month budget alert on the `cookbo-app` project. The site reads that URL from
`docs/index.html`:

```html
<meta name="cookbo-import-endpoint" content="https://cookbo-import-87726969279.us-central1.run.app">
```

While that's empty, the site still plays the demo; it just hides the link field.

## Safety

Since it fetches whatever link a stranger pastes, the thing to prevent is a link
that leads back into Google's network. `src/fetch-page.js`:

- only accepts public http(s) URLs: no IP addresses, internal hostnames,
  credentials or unusual ports;
- resolves the hostname and refuses it if any address is private, loopback,
  link-local (including the metadata server) or otherwise special;
- connects to exactly the addresses it checked, so DNS can't pass the check
  and then point somewhere else;
- re-checks every redirect, and gives up after 8 seconds or 4 MB (measured
  after decompression);
- accepts only HTML, and returns recipe fields, never the page.

The link travels in the POST body, so it never appears in Cloud Run's request
logs, and the service doesn't log it. Results are cached in memory for up to six
hours. Each visitor gets 20 requests a minute, and each instance 120 overall.
