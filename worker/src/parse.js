// Recipe extraction for the cookbo.app live-import demo.
//
// Mirrors the JSON-LD path of the app's parser (Shared/RecipeParserCore.swift):
// find schema.org Recipe objects in <script type="application/ld+json">, walking
// @graph and ItemList nesting, and prefer the candidate with the most steps.
// The app also has Instagram and HTML-heuristic fallbacks; the demo doesn't.

const LD_JSON = /<script[^>]*type\s*=\s*["']?application\/ld\+json["']?[^>]*>([\s\S]*?)<\/script>/gi;

/** @returns {object|null} a recipe, or null if the page has none */
export function parseRecipe(html, sourceURL) {
  let best = null;

  for (const match of html.matchAll(LD_JSON)) {
    let json;
    try {
      json = JSON.parse(match[1].trim());
    } catch {
      continue;
    }

    for (const candidate of collectRecipeCandidates(json)) {
      const recipe = extractRecipe(candidate, sourceURL);
      if (!recipe) continue;
      // A list of steps beats a one-paragraph summary
      if (!best || recipe.steps.length > best.steps.length) best = recipe;
    }
  }

  if (!best || (best.ingredients.length === 0 && best.steps.length === 0)) return null;
  return best;
}

function isRecipeType(type) {
  if (typeof type === 'string') return type === 'Recipe';
  if (Array.isArray(type)) return type.includes('Recipe');
  return false;
}

export function collectRecipeCandidates(value) {
  const results = [];
  if (Array.isArray(value)) {
    for (const item of value) results.push(...collectRecipeCandidates(item));
  } else if (value && typeof value === 'object') {
    if (isRecipeType(value['@type'])) results.push(value);
    if (Array.isArray(value['@graph'])) {
      for (const item of value['@graph']) results.push(...collectRecipeCandidates(item));
    }
    if (Array.isArray(value.itemListElement)) {
      for (const element of value.itemListElement) {
        if (element && typeof element === 'object') {
          results.push(...collectRecipeCandidates(element.item ?? element));
        }
      }
    }
  }
  return results;
}

function extractRecipe(dict, sourceURL) {
  if (!isRecipeType(dict['@type'])) return null;

  const ingredients = asArray(dict.recipeIngredient)
    .filter((i) => typeof i === 'string')
    .map((i) => stripLeadingBullets(stripHTML(i)))
    .filter(Boolean);

  return {
    title: stripHTML(typeof dict.name === 'string' ? dict.name : ''),
    image: extractImage(dict.image, sourceURL),
    ingredients,
    steps: extractSteps(dict.recipeInstructions),
    prepMinutes: minutes(dict.prepTime),
    cookMinutes: minutes(dict.cookTime),
    totalMinutes: minutes(dict.totalTime),
    yield: extractYield(dict.recipeYield),
    // The app saves this as the recipe's Notes
    notes: stripHTML(typeof dict.description === 'string' ? dict.description : ''),
    source: hostname(sourceURL),
    sourceURL,
  };
}

function extractSteps(instructions) {
  if (!instructions) return [];

  if (typeof instructions === 'string') {
    const withBreaks = instructions
      .replace(/<\/(?:p|li|div)>/gi, '\n')
      .replace(/<br\s*\/?>/gi, '\n');
    return stripHTML(withBreaks, { keepNewlines: true })
      .split('\n')
      .map((s) => s.trim())
      .filter(Boolean);
  }

  const steps = [];
  for (const step of asArray(instructions)) {
    if (typeof step === 'string') {
      steps.push(step);
    } else if (step && typeof step === 'object') {
      if (typeof step.text === 'string' && step.text && step['@type'] !== 'HowToSection') {
        steps.push(step.text);
      } else if (Array.isArray(step.itemListElement)) {
        // HowToSection (or a bare list): flatten its HowToSteps
        for (const item of step.itemListElement) {
          if (typeof item === 'string') steps.push(item);
          else if (item?.text) steps.push(item.text);
          else if (item?.name) steps.push(item.name);
        }
      } else if (typeof step.name === 'string' && step.name) {
        steps.push(step.name);
      }
    }
  }
  return steps.map((s) => stripHTML(s)).filter(Boolean);
}

function extractImage(image, sourceURL) {
  let url = null;
  if (typeof image === 'string') url = image;
  else if (Array.isArray(image)) {
    const first = image[0];
    url = typeof first === 'string' ? first : first?.url ?? null;
  } else if (image && typeof image === 'object') url = image.url ?? null;

  if (typeof url !== 'string' || !url) return null;
  try {
    const resolved = new URL(url, sourceURL);
    return resolved.protocol === 'https:' || resolved.protocol === 'http:' ? resolved.href : null;
  } catch {
    return null;
  }
}

function extractYield(value) {
  const first = Array.isArray(value) ? value.find((v) => typeof v === 'string') ?? value[0] : value;
  if (typeof first === 'number') return `${first} servings`;
  return typeof first === 'string' ? stripHTML(first) : null;
}

/** ISO 8601 duration (PT1H30M) to whole minutes; also tolerates a day part (P1DT2H). */
export function minutes(duration) {
  if (typeof duration !== 'string') return 0;
  const m = duration.match(/^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$/i);
  if (!m) return 0;
  const [, d = 0, h = 0, min = 0, s = 0] = m;
  return Math.round(Number(d) * 1440 + Number(h) * 60 + Number(min) + Number(s) / 60);
}

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', frac12: '½', frac14: '¼', frac34: '¾', deg: '°', ndash: '–', mdash: '—', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“', hellip: '…' };

export function decodeEntities(text) {
  return text.replace(/&(#x[0-9a-f]+|#\d+|[a-z][a-z0-9]*);/gi, (whole, code) => {
    if (code[0] === '#') {
      const n = code[1] === 'x' || code[1] === 'X' ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10);
      return Number.isFinite(n) && n > 0 && n < 0x110000 ? String.fromCodePoint(n) : whole;
    }
    return ENTITIES[code.toLowerCase()] ?? whole;
  });
}

export function stripHTML(text, { keepNewlines = false } = {}) {
  const noTags = String(text).replace(/<[^>]*>/g, ' ');
  // Some sites double-encode (&amp;frac12;), so decode twice
  const decoded = decodeEntities(decodeEntities(noTags));
  const collapsed = keepNewlines
    ? decoded.replace(/[^\S\n]+/g, ' ')
    : decoded.replace(/\s+/g, ' ');
  return collapsed.trim();
}

function stripLeadingBullets(text) {
  return text.replace(/^[\s•▪■◦·*\-–]+/, '').trim();
}

function asArray(value) {
  if (value == null) return [];
  return Array.isArray(value) ? value : [value];
}

function hostname(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return '';
  }
}
