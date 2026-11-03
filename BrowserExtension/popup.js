import { parseRecipe } from './parse.js';
import { recipeFileName, recipeMarkdown } from './recipe-file.js';
import { api, listCookbooks, saveRecipe, NeedsFolder } from './cookbooks.js';

const $ = (id) => document.getElementById(id);

function show(section) {
  for (const id of ['loading', 'setup', 'none', 'found']) $(id).hidden = id !== section;
}

/** Runs in the page: its schema.org JSON-LD, read from the page as it is, signed in or not. */
function readPage() {
  return {
    url: location.href,
    ldJSON: [...document.querySelectorAll('script[type="application/ld+json"]')].map((s) => s.textContent),
    ogImage: document.querySelector('meta[property="og:image"]')?.content ?? null,
  };
}

async function findRecipe(tab) {
  const [{ result: page }] = await api.scripting.executeScript({ target: { tabId: tab.id }, func: readPage });
  // parse.js reads a page's HTML; hand it just the JSON-LD scripts
  const html = page.ldJSON.map((json) => `<script type="application/ld+json">${json}</script>`).join('\n');
  const recipe = parseRecipe(html, page.url);
  if (recipe && !recipe.image && page.ogImage) {
    try {
      recipe.image = new URL(page.ogImage, page.url).href;
    } catch {
      // No photo, then
    }
  }
  return recipe;
}

function summary(recipe) {
  const count = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;
  return [
    recipe.ingredients.length && count(recipe.ingredients.length, 'ingredient'),
    recipe.steps.length && count(recipe.steps.length, 'step'),
    recipe.source,
  ].filter(Boolean).join(' · ');
}

async function fillCookbooks() {
  const cookbooks = await listCookbooks();
  if (!cookbooks.length) throw new Error('There are no cookbooks in Cookbo yet. Open the app once to make one.');

  const { lastCookbookID } = await api.storage.local.get('lastCookbookID');
  const select = $('cookbook');
  select.replaceChildren(...cookbooks.map(({ id, name }) => new Option(name, id, false, id === lastCookbookID)));
  $('cookbook-label').hidden = cookbooks.length < 2;
  $('save').textContent = cookbooks.length < 2 ? `Save to ${cookbooks[0].name}` : 'Save Recipe';
}

async function save(recipe) {
  $('save').disabled = true;
  $('error').hidden = true;

  const id = crypto.randomUUID().toUpperCase();
  const cookbookID = $('cookbook').value;
  try {
    await saveRecipe({
      cookbookID,
      fileName: recipeFileName(recipe.title, id),
      markdown: recipeMarkdown(recipe, { id }),
      imageName: recipe.image ? `${id}.jpg` : null,
      imageURL: recipe.image,
    });
    await api.storage.local.set({ lastCookbookID: cookbookID });
    $('save').hidden = true;
    $('cookbook-label').hidden = true;
    $('saved').hidden = false;
    $('saved').textContent = `✓ Saved to ${$('cookbook').selectedOptions[0].text}`;
  } catch (error) {
    if (error instanceof NeedsFolder) return show('setup');
    $('error').hidden = false;
    $('error').textContent = error.message;
    $('save').disabled = false;
  }
}

async function start() {
  const [tab] = await api.tabs.query({ active: true, currentWindow: true });

  $('choose-folder').addEventListener('click', () => {
    api.runtime.openOptionsPage();
    window.close();
  });
  $('open-app').addEventListener('click', (event) => {
    event.preventDefault();
    api.tabs.update(tab.id, { url: `cookbook://import?url=${encodeURIComponent(tab.url)}` });
    window.close();
  });

  const recipe = await findRecipe(tab).catch(() => null);
  if (!recipe) return show('none');

  $('title').textContent = recipe.title || 'Untitled recipe';
  $('summary').textContent = summary(recipe);
  if (recipe.image) {
    $('photo').src = recipe.image;
    $('photo').hidden = false;
    $('photo').onerror = () => { $('photo').hidden = true; };
  }

  try {
    await fillCookbooks();
  } catch (error) {
    if (error instanceof NeedsFolder) return show('setup');
    $('error').hidden = false;
    $('error').textContent = error.message;
    $('save').disabled = true;
  }

  $('save').addEventListener('click', () => save(recipe));
  show('found');
}

start();
