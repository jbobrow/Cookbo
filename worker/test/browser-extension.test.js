// The browser extension (BrowserExtension/) keeps copies of the parser and the
// file writer, since an extension can only load its own files. They must stay
// the same as the originals: run Scripts/sync_browser_extension.sh after a change.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (path) => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');

test('the extension parses recipes like the site', () => {
  assert.equal(read('BrowserExtension/parse.js'), read('worker/src/parse.js'));
});

test('the extension writes recipe files like the site', () => {
  assert.equal(read('BrowserExtension/recipe-file.js'), read('docs/assets/recipe-file.js'));
});

test('the manifest only names files the extension has', () => {
  const manifest = JSON.parse(read('BrowserExtension/manifest.json'));
  const files = [
    ...Object.values(manifest.icons),
    ...Object.values(manifest.action.default_icon),
    manifest.action.default_popup,
    manifest.options_ui.page,
  ];
  for (const file of files) assert.ok(read(`BrowserExtension/${file}`), file);
});
