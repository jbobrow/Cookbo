// Home page demo: a recipe is lifted off a cluttered web page and lands in Cookbo.
//
// Both sides are rendered from the same recipe object. Each piece that moves
// carries a matching data-part on the web page and in the phone; the flight
// clones the web piece and animates it onto its twin (a FLIP transition).
//
// Recipes from the live import come from arbitrary websites, so everything
// here builds DOM with textContent and never touches innerHTML.

import { recipeFileName, recipeMarkdown } from './recipe-file.js';

(() => {
  'use strict';

  // Must match NSUbiquitousContainerName in the app's Info.plist
  const ICLOUD_FOLDER = 'Cookbo';

  const DEMO_RECIPE = {
    id: '3F2504E0-4F89-11D3-9A0C-0305E82C3301',
    title: 'Roasted Tomato Soup',
    image: 'assets/images/tomato-soup.svg',
    prepMinutes: 10,
    cookMinutes: 40,
    yield: '4 servings',
    ingredients: [
      '2 lb ripe tomatoes, halved',
      '1 yellow onion, quartered',
      '4 cloves garlic',
      '2 tbsp olive oil',
      '2 cups vegetable stock',
      'Fresh basil, to serve',
    ],
    steps: [
      'Roast the tomatoes, onion and garlic with the oil at 425°F until soft and charred at the edges, about 35 minutes.',
      'Tip everything into a pot with the stock and simmer for 5 minutes, then blend until smooth.',
      'Season with salt and pepper and serve with torn basil on top.',
    ],
    sourceURL: 'https://example.com/roasted-tomato-soup',
    address: 'example.com/roasted-tomato-soup',
    isDemo: true,
  };

  // Shown when an imported recipe has no photo, or its photo won't load
  const PLACEHOLDER_IMAGE = 'data:image/svg+xml,' + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 250"><rect width="400" height="250" fill="#ECE2D5"/>' +
    '<g fill="none" stroke="#C9B8A4" stroke-width="10" stroke-linecap="round"><path d="M170 80v90M155 80v35a15 15 0 0 0 30 0V80"/>' +
    '<path d="M232 170V80c-14 6-22 24-22 44 0 12 6 20 22 20"/></g></svg>'
  );

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

  const stage = $('#stage');
  const page = $('#page');
  const webRecipe = $('#web-recipe');
  const viewport = $('.viewport', stage);
  const screen = $('#screen');
  const detail = $('#app-detail');
  const flyLayer = $('#fly-layer');
  const address = $('#address');
  const shareButton = $('#share-btn');
  const shareMenu = $('#share-menu');
  const shareCookbo = $('#share-cookbo');
  const cookie = $('#cookie');
  const toast = $('#toast');
  const replay = $('#replay');
  const form = $('#try-form');
  const input = $('#try-url');
  const tryButton = $('#try-button');
  const statusLine = $('#try-status');
  const caption = $('#caption');
  const fileChip = $('#file-chip');
  const fileName = $('#file-name');
  const fileAction = $('#file-action');
  const fileBar = $('#file-bar');
  const fileBody = $('#file-body');

  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const narrow = matchMedia('(max-width: 820px)');

  const endpoint = ['localhost', '127.0.0.1'].includes(location.hostname)
    ? '/api/import'
    : ($('meta[name="cookbo-import-endpoint"]')?.content ?? '').trim();

  let current = DEMO_RECIPE;
  let runId = 0;
  let running = false;
  const animations = new Set();
  const CANCELLED = Symbol('cancelled');

  // MARK: - Rendering

  function el(tag, attrs = {}, ...children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, value);
    for (const child of children) {
      if (child == null || child === false) continue;
      node.append(typeof child === 'string' ? document.createTextNode(child) : child);
    }
    return node;
  }

  function svgIcon(path, size = 10) {
    const ns = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('width', size);
    svg.setAttribute('height', size);
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', '2.4');
    svg.setAttribute('stroke-linecap', 'round');
    svg.setAttribute('stroke-linejoin', 'round');
    const p = document.createElementNS(ns, 'path');
    p.setAttribute('d', path);
    svg.append(p);
    return svg;
  }

  const ICONS = {
    back: 'M15 5l-7 7 7 7',
    more: 'M5 12h.01M12 12h.01M19 12h.01',
    clock: 'M12 7v5l3 2M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0z',
    flame: 'M12 3c1 4 5 5 5 10a5 5 0 0 1-10 0c0-2 1-3 2-4 0 2 1 3 2 3 0-3-1-6 1-9z',
  };

  function recipeImage(src) {
    const img = el('img', { alt: '', decoding: 'async', referrerpolicy: 'no-referrer' });
    img.src = src || PLACEHOLDER_IMAGE;
    img.addEventListener('error', () => { img.src = PLACEHOLDER_IMAGE; }, { once: true });
    return img;
  }

  function formatMinutes(total) {
    if (!total) return null;
    if (total < 60) return `${total} min`;
    const h = Math.floor(total / 60);
    const m = total % 60;
    return m ? `${h} hr ${m} min` : `${h} hr`;
  }

  function limits() {
    return narrow.matches ? { ingredients: 4, steps: 2 } : { ingredients: 5, steps: 3 };
  }

  function more(count, noun) {
    return count > 0 ? `+ ${count} more ${noun}${count === 1 ? '' : 's'}` : null;
  }

  function renderWeb(recipe) {
    const cap = limits();
    const ingredients = recipe.ingredients.slice(0, cap.ingredients);
    const steps = recipe.steps.slice(0, cap.steps);

    const meta = [
      recipe.prepMinutes && `Prep ${formatMinutes(recipe.prepMinutes)}`,
      recipe.cookMinutes && `Cook ${formatMinutes(recipe.cookMinutes)}`,
      !recipe.prepMinutes && !recipe.cookMinutes && recipe.totalMinutes && `Total ${formatMinutes(recipe.totalMinutes)}`,
      recipe.yield && `Serves ${recipe.yield.replace(/\s*servings?$/i, '')}`,
    ].filter(Boolean).join(' · ') || recipe.source || '';

    const moreIngredients = more(recipe.ingredients.length - ingredients.length, 'ingredient');
    const moreSteps = more(recipe.steps.length - steps.length, 'step');

    webRecipe.replaceChildren(
      el('div', { class: 'web-top' },
        el('div', { class: 'web-photo', 'data-part': 'image' }, recipeImage(recipe.image)),
        el('div', {},
          el('h4', { class: 'web-title', 'data-part': 'title' }, recipe.title),
          el('div', { class: 'web-meta', 'data-part': 'meta' }, meta))),
      el('div', { class: 'web-cols' },
        el('div', {},
          el('p', { class: 'web-h' }, 'Ingredients'),
          el('ul', { class: 'web-list web-ings' },
            ...ingredients.map((text, i) => el('li', { 'data-part': `ing-${i}` }, text))),
          moreIngredients && el('p', { class: 'web-more' }, moreIngredients)),
        el('div', {},
          el('p', { class: 'web-h' }, 'Directions'),
          el('ol', { class: 'web-list web-steps' },
            ...steps.map((text, i) => el('li', { 'data-part': `step-${i}` }, el('span', {}, text)))),
          moreSteps && el('p', { class: 'web-more' }, moreSteps))),
    );
  }

  function renderApp(recipe) {
    const cap = limits();
    const ingredients = recipe.ingredients.slice(0, cap.ingredients);
    const steps = recipe.steps.slice(0, cap.steps);

    const times = [
      recipe.prepMinutes && el('span', {}, svgIcon(ICONS.clock), ' ', formatMinutes(recipe.prepMinutes)),
      recipe.cookMinutes && el('span', {}, svgIcon(ICONS.flame), ' ', formatMinutes(recipe.cookMinutes)),
      !recipe.prepMinutes && !recipe.cookMinutes && recipe.totalMinutes &&
        el('span', {}, svgIcon(ICONS.clock), ' ', formatMinutes(recipe.totalMinutes)),
    ];

    const moreIngredients = more(recipe.ingredients.length - ingredients.length, 'ingredient');
    const moreSteps = more(recipe.steps.length - steps.length, 'step');

    detail.replaceChildren(
      el('span', { class: 'round back' }, svgIcon(ICONS.back, 12)),
      el('span', { class: 'round more' }, svgIcon(ICONS.more, 14)),
      el('div', { class: 'app-photo target', 'data-part': 'image' }, recipeImage(recipe.image)),
      el('div', { class: 'app-body' },
        el('h3', { class: 'app-title target', 'data-part': 'title' }, recipe.title),
        el('div', { class: 'app-meta target', 'data-part': 'meta' },
          el('span', { class: 'stars' }, '☆☆☆☆☆'), ...times),
        el('p', { class: 'app-h reveal' }, 'Ingredients'),
        el('ul', { class: 'app-list-ul app-ings' },
          ...ingredients.map((text, i) =>
            el('li', { 'data-part': `ing-${i}` }, el('span', { class: 'check' }), el('span', { class: 't' }, text)))),
        moreIngredients && el('p', { class: 'app-more reveal' }, moreIngredients),
        el('p', { class: 'app-h reveal' }, 'Directions'),
        el('ol', { class: 'app-list-ul app-steps' },
          ...steps.map((text, i) =>
            el('li', { 'data-part': `step-${i}` }, el('span', { class: 'num' }, String(i + 1)), el('span', { class: 't' }, text)))),
        moreSteps && el('p', { class: 'app-more reveal' }, moreSteps)),
    );
  }

  /** The Markdown file the app would save, lightly tinted like an editor would. */
  function renderFile(recipe) {
    const name = recipeFileName(recipe.title, recipe.id);
    const markdown = recipeMarkdown(recipe, { id: recipe.id });

    $('#file-path').textContent = `iCloud Drive › ${ICLOUD_FOLDER}`;
    fileName.textContent = name;
    fileBar.textContent = name;

    let inFrontMatter = false;
    const lines = markdown.split('\n').map((line, i) => {
      const row = document.createDocumentFragment();
      const span = (cls, text) => row.append(el('span', { class: cls }, text));

      if (line === '---') {
        inFrontMatter = i === 0;
        span('md-quiet', line);
      } else if (inFrontMatter && line.includes(': ')) {
        const at = line.indexOf(': ') + 2;
        span('md-key', line.slice(0, at));
        row.append(line.slice(at));
      } else if (/^#{1,3} /.test(line)) {
        span('md-head', line);
      } else if (line.startsWith('- [ ] ')) {
        span('md-quiet', '- [ ] ');
        const step = line.slice(6).match(/^(\*\*Step \d+:\*\*)(.*)$/);
        if (step) {
          span('md-bold', step[1]);
          row.append(step[2]);
        } else {
          row.append(line.slice(6));
        }
      } else {
        row.append(line);
      }
      row.append('\n');
      return row;
    });
    fileBody.replaceChildren(...lines);
    fileBody.scrollTop = 0;
  }

  function render(recipe) {
    address.textContent = recipe.address;
    page.classList.toggle('skeleton', !recipe.isDemo);
    renderWeb(recipe);
    renderApp(recipe);
    renderFile(recipe);
  }

  // MARK: - File view

  let showingFile = false;

  function setFileShown(shown) {
    showingFile = shown;
    screen.classList.toggle('file', shown);
    fileChip.setAttribute('aria-pressed', String(shown));
    fileAction.textContent = shown ? 'Back to app' : 'View file';
  }

  /** Flips the phone's screen over to the saved file, and back. */
  async function toggleFile() {
    const next = !showingFile;
    if (reducedMotion.matches) {
      setFileShown(next);
      return;
    }
    const half = { duration: 170, fill: 'forwards' };
    await screen.animate([{ transform: 'rotateY(0)' }, { transform: `rotateY(${next ? 90 : -90}deg)` }],
      { ...half, easing: 'cubic-bezier(.5, 0, .9, .6)' }).finished;
    setFileShown(next);
    const back = screen.animate([{ transform: `rotateY(${next ? -90 : 90}deg)` }, { transform: 'rotateY(0)' }],
      { ...half, duration: 230, easing: 'cubic-bezier(.1, .5, .3, 1)' });
    await back.finished;
    screen.getAnimations().forEach((a) => a.cancel());
  }

  /** Resolves once the recipe photos have loaded (or failed), capped so a slow image can't stall the demo. */
  function imagesReady(timeout = 2500) {
    const images = $$('img', webRecipe).concat($$('img', detail));
    const loads = images.map((img) => img.complete
      ? Promise.resolve()
      : new Promise((resolve) => {
          img.addEventListener('load', resolve, { once: true });
          img.addEventListener('error', resolve, { once: true });
        }));
    return Promise.race([Promise.all(loads), new Promise((r) => setTimeout(r, timeout))]);
  }

  // MARK: - Timeline

  function wait(ms, id) {
    return new Promise((resolve, reject) =>
      setTimeout(() => (id === runId ? resolve() : reject(CANCELLED)), ms));
  }

  function reset() {
    for (const animation of animations) animation.cancel();
    animations.clear();
    flyLayer.replaceChildren();

    stage.classList.add('no-anim');
    stage.classList.remove('focus');
    screen.classList.remove('detail');
    detail.classList.remove('revealed');
    page.style.transform = '';
    cookie.classList.remove('shown');
    shareMenu.classList.remove('open');
    shareButton.classList.remove('pressed');
    shareCookbo.classList.remove('hot');
    toast.classList.remove('shown');
    replay.classList.remove('shown');
    fileChip.classList.remove('shown');
    screen.getAnimations().forEach((a) => a.cancel());
    setFileShown(false);
    void stage.offsetHeight;
    stage.classList.remove('no-anim');
  }

  function scrollOffsetToRecipe() {
    const offset = webRecipe.getBoundingClientRect().top - page.getBoundingClientRect().top - 12;
    const maxOffset = page.scrollHeight - viewport.clientHeight;
    return Math.max(0, Math.min(offset, maxOffset));
  }

  /** Pairs each web piece with its twin in the phone, in the order they should fly. */
  function pieces() {
    const order = (part) => {
      if (part === 'image') return 0;
      if (part === 'title') return 1;
      if (part === 'meta') return 2;
      const [kind, n] = part.split('-');
      return (kind === 'ing' ? 10 : 100) + Number(n);
    };

    return $$('[data-part]', webRecipe)
      .map((source) => {
        const part = source.dataset.part;
        const twin = $(`[data-part="${part}"]`, detail);
        if (!twin) return null;
        return { part, source, twin, target: $('.t', twin) ?? twin };
      })
      .filter(Boolean)
      .sort((a, b) => order(a.part) - order(b.part));
  }

  function isVisibleWithin(node, container) {
    const r = node.getBoundingClientRect();
    const c = container.getBoundingClientRect();
    const visible = Math.min(r.bottom, c.bottom) - Math.max(r.top, c.top);
    return r.height > 0 && visible / r.height > 0.6;
  }

  const COPIED_STYLES = ['fontSize', 'fontWeight', 'lineHeight', 'letterSpacing', 'color', 'fontFamily'];

  function fly({ source, twin, target }, delay) {
    const origin = stage.getBoundingClientRect();
    const from = source.getBoundingClientRect();
    const to = target.getBoundingClientRect();
    const isImage = source.dataset.part === 'image';

    const clone = source.cloneNode(true);
    clone.classList.remove('detected', 'lifted');
    clone.classList.add('flying');
    clone.removeAttribute('data-part');

    const computed = getComputedStyle(source);
    if (!isImage) {
      for (const key of COPIED_STYLES) clone.style[key] = computed[key];
      clone.style.whiteSpace = 'normal';
    }

    // Text lifts off as a small card, so pad it — and account for the padding when landing
    const pad = isImage ? 0 : 5;
    Object.assign(clone.style, {
      left: `${from.left - origin.left - pad}px`,
      top: `${from.top - origin.top - pad}px`,
      width: `${from.width + pad * 2}px`,
      height: `${from.height + pad * 2}px`,
      padding: `${pad}px`,
      opacity: '0',
    });
    flyLayer.append(clone);

    // Images stretch to fit their frame; text scales by font size so it lands at the right size
    const sx = isImage ? to.width / from.width : parseFloat(getComputedStyle(target).fontSize) / parseFloat(computed.fontSize);
    const sy = isImage ? to.height / from.height : sx;

    const dx = to.left - from.left - pad * (sx - 1);
    const dy = to.top - from.top - pad * (sy - 1);

    // Arc sideways to the direction of travel: over the top when moving right,
    // out to the side when the phone is below the browser
    const length = Math.hypot(dx, dy) || 1;
    const arc = 50 + length * 0.12;
    const bendX = (dy / length) * arc;
    const bendY = (-dx / length) * arc;

    const duration = 820 + Math.min(length, 700) * 0.25;

    const flight = clone.animate([
      { transform: 'translate(0, 0) scale(1)', opacity: 1 },
      { transform: 'translate(0, -10px) scale(1.06)', opacity: 1, offset: 0.14 },
      {
        transform: `translate(${dx / 2 + bendX}px, ${dy / 2 + bendY}px) scale(${(1 + sx) / 2 + 0.04}, ${(1 + sy) / 2 + 0.04})`,
        opacity: 1,
        offset: 0.55,
      },
      { transform: `translate(${dx}px, ${dy}px) scale(${sx}, ${sy})`, opacity: 1, offset: 0.86 },
      { transform: `translate(${dx}px, ${dy}px) scale(${sx}, ${sy})`, opacity: 0 },
    ], { duration, delay, easing: 'cubic-bezier(.45, 0, .2, 1)', fill: 'both' });
    animations.add(flight);

    const lift = setTimeout(() => {
      source.classList.remove('detected');
      source.classList.add('lifted');
    }, delay);
    const land = setTimeout(() => twin.classList.add('landed'), delay + duration * 0.84);

    return flight.finished
      .catch(() => {})
      .finally(() => {
        clearTimeout(lift);
        clearTimeout(land);
        animations.delete(flight);
        clone.remove();
      });
  }

  async function play(recipe) {
    const id = ++runId;
    running = true;
    reset();
    render(recipe);

    try {
      await imagesReady();
      if (id !== runId) return;

      if (reducedMotion.matches) {
        showFinished();
        return;
      }

      await wait(500, id);
      cookie.classList.add('shown');
      await wait(450, id);

      page.style.transform = `translateY(${-scrollOffsetToRecipe()}px)`;
      await wait(1500, id);

      shareButton.classList.add('pressed');
      await wait(150, id);
      shareMenu.classList.add('open');
      await wait(550, id);
      shareCookbo.classList.add('hot');
      await wait(380, id);
      shareMenu.classList.remove('open');
      shareButton.classList.remove('pressed');
      await wait(200, id);

      // Cookbo spots the recipe; everything else fades back
      stage.classList.add('focus');
      cookie.classList.remove('shown');
      const all = pieces();
      all.forEach(({ source }, i) => setTimeout(() => id === runId && source.classList.add('detected'), i * 70));
      await wait(all.length * 70 + 450, id);

      screen.classList.add('detail');
      await wait(420, id);

      const flights = [];
      let delay = 0;
      for (const piece of all) {
        if (isVisibleWithin(piece.source, viewport) && isVisibleWithin(piece.twin, screen)) {
          flights.push(fly(piece, delay));
          delay += 85;
        } else {
          // Off-screen on either side: no flight to watch, so just settle it
          piece.source.classList.remove('detected');
          piece.twin.classList.add('landed');
        }
      }
      await Promise.all(flights);
      if (id !== runId) return;

      detail.classList.add('revealed');
      await wait(150, id);
      toast.classList.add('shown');
      await wait(1600, id);
      toast.classList.remove('shown');

      stage.classList.remove('focus');
      $$('.lifted', webRecipe).forEach((n) => n.classList.remove('lifted'));
      await wait(250, id);
      fileChip.classList.add('shown');
      replay.classList.add('shown');
    } catch (error) {
      if (error !== CANCELLED) throw error;
    } finally {
      if (id === runId) running = false;
    }
  }

  /** Jumps straight to the end state: for reduced motion, and when a resize would misalign a flight. */
  function showFinished() {
    for (const animation of animations) animation.cancel();
    flyLayer.replaceChildren();
    stage.classList.add('no-anim');
    stage.classList.remove('focus');
    page.style.transform = `translateY(${-scrollOffsetToRecipe()}px)`;
    screen.classList.add('detail');
    $$('[data-part]', detail).forEach((n) => n.classList.add('landed'));
    $$('[data-part]', webRecipe).forEach((n) => n.classList.remove('detected', 'lifted'));
    detail.classList.add('revealed');
    cookie.classList.remove('shown');
    toast.classList.remove('shown');
    replay.classList.add('shown');
    fileChip.classList.add('shown');
    void stage.offsetHeight;
    stage.classList.remove('no-anim');
    runId++;
    running = false;
  }

  // MARK: - Live import

  const MESSAGES = {
    invalid_url: 'That doesn’t look like a link to a recipe page.',
    no_recipe: 'Couldn’t find a recipe on that page. Cookbo reads the recipe data most recipe sites include, and this page doesn’t have it.',
    fetch_failed: 'Couldn’t load that page. Some sites turn away automated visits, though the app can often still import them.',
    timeout: 'That page took too long to respond.',
    not_html: 'That link doesn’t lead to a recipe page.',
    too_large: 'That page is too large to import here.',
    rate_limited: 'Too many tries in a row. Give it a minute.',
    unavailable: 'Live import isn’t available right now.',
  };

  function setStatus(text, isError = false) {
    statusLine.textContent = text;
    statusLine.classList.toggle('error', isError);
  }

  function setBusy(busy) {
    input.disabled = busy;
    tryButton.disabled = busy;
    tryButton.textContent = busy ? 'Importing…' : 'Import';
  }

  function normalizeLink(raw) {
    const text = raw.trim();
    if (!text) return null;
    try {
      const url = new URL(/^https?:\/\//i.test(text) ? text : `https://${text}`);
      return url.protocol === 'https:' || url.protocol === 'http:' ? url : null;
    } catch {
      return null;
    }
  }

  function displayAddress(url) {
    const path = url.pathname === '/' ? '' : url.pathname.replace(/\/$/, '');
    return url.hostname.replace(/^www\./, '') + path;
  }

  const clip = (value, max) => (typeof value === 'string' ? value.trim().slice(0, max) : '');
  const strings = (list, max) => (Array.isArray(list) ? list.map((s) => clip(s, max)).filter(Boolean) : []);
  const wholeMinutes = (n) => (Number.isFinite(n) && n > 0 && n < 10_000 ? Math.round(n) : 0);

  /** Trusts nothing about the response's shape. */
  function toRecipe(data, url) {
    let image = null;
    try {
      const parsed = new URL(data.image);
      if (parsed.protocol === 'https:' || parsed.protocol === 'http:') image = parsed.href;
    } catch { /* no usable image */ }

    return {
      id: crypto.randomUUID().toUpperCase(),
      title: clip(data.title, 140) || 'Untitled recipe',
      image,
      ingredients: strings(data.ingredients, 200),
      steps: strings(data.steps, 600),
      prepMinutes: wholeMinutes(data.prepMinutes),
      cookMinutes: wholeMinutes(data.cookMinutes),
      totalMinutes: wholeMinutes(data.totalMinutes),
      yield: clip(data.yield, 40) || null,
      notes: clip(data.notes, 2000),
      sourceURL: url.href,
      source: url.hostname.replace(/^www\./, ''),
      address: displayAddress(url),
      isDemo: false,
    };
  }

  async function importLink(raw) {
    const url = normalizeLink(raw);
    if (!url) {
      setStatus(MESSAGES.invalid_url, true);
      return;
    }

    setBusy(true);
    setStatus('Fetching the recipe…');

    let data;
    try {
      const response = await fetch(`${endpoint}?url=${encodeURIComponent(url.href)}`, {
        signal: AbortSignal.timeout(15_000),
      });
      data = await response.json().catch(() => ({}));
      if (!response.ok) throw Object.assign(new Error('import failed'), { code: data.error });
    } catch (error) {
      const code = error.code ?? (error.name === 'TimeoutError' ? 'timeout' : 'unavailable');
      setStatus(MESSAGES[code] ?? MESSAGES.fetch_failed, true);
      setBusy(false);
      return;
    }

    const recipe = toRecipe(data, url);
    if (recipe.ingredients.length === 0 && recipe.steps.length === 0) {
      setStatus(MESSAGES.no_recipe, true);
      setBusy(false);
      return;
    }

    current = recipe;
    const counts = [
      recipe.ingredients.length && `${recipe.ingredients.length} ingredient${recipe.ingredients.length === 1 ? '' : 's'}`,
      recipe.steps.length && `${recipe.steps.length} step${recipe.steps.length === 1 ? '' : 's'}`,
    ].filter(Boolean).join(' and ');
    setStatus(`Found “${recipe.title}” with ${counts}.`);
    setBusy(false);
    await play(recipe);
  }

  // MARK: - Wiring

  if (endpoint) {
    form.hidden = false;
    caption.textContent = 'Paste a link to any recipe and watch Cookbo keep just the recipe.';
    form.addEventListener('submit', (event) => {
      event.preventDefault();
      importLink(input.value);
    });
  }

  fileChip.addEventListener('click', toggleFile);

  replay.addEventListener('click', () => {
    setStatus('');
    play(current);
  });

  // Recompute limits and layout when crossing the narrow breakpoint mid-demo
  let resizeTimer;
  addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      if (running) {
        render(current);
        showFinished();
      }
    }, 150);
  });
  narrow.addEventListener('change', () => {
    if (!running) {
      render(current);
      showFinished();
    }
  });

  // Render right away so the page is never empty, then start when it's on screen
  render(current);
  const start = () => {
    if (reducedMotion.matches) showFinished();
    else play(current);
  };

  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) {
        observer.disconnect();
        setTimeout(start, 300);
      }
    }, { threshold: 0.35 });
    observer.observe(stage);
  } else {
    start();
  }
})();
