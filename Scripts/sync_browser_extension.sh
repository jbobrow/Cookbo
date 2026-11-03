#!/bin/sh
# The browser extension parses and writes recipes with the same code as the
# website. An extension can only load files inside its own folder, so it keeps
# copies; run this after changing either original. worker/test checks they match.
set -e
cd "$(dirname "$0")/.."
cp worker/src/parse.js BrowserExtension/parse.js
cp docs/assets/recipe-file.js BrowserExtension/recipe-file.js
