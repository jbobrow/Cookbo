// The home page's file preview must match what the app writes. These mirror
// CookbookTests/RecipeFileNamingTests.swift, plus a byte-for-byte check
// against a file the app saved.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { slug, shortHash, recipeFileName, recipeMarkdown } from '../../docs/assets/recipe-file.js';

const ID = '3F2504E0-4F89-11D3-9A0C-0305E82C3301';

test('slug matches the app', () => {
  assert.equal(slug('Chipotle Chicken Burrito Bowls'), 'chipotle-chicken-burrito-bowls');
  assert.equal(slug("Grandma's  Mac & Cheese!!"), 'grandmas-mac-cheese');
  assert.equal(slug('Mom’s Chili'), 'moms-chili');
  assert.equal(slug('Crème Brûlée'), 'creme-brulee');
  assert.equal(slug('Chipotle chicken burrito bowls 🌯'), 'chipotle-chicken-burrito-bowls');
  assert.equal(slug('5-Minute Salsa'), '5-minute-salsa');
  assert.equal(slug(''), 'untitled');
  assert.equal(slug('  ✨  '), 'untitled');
});

test('long titles are capped without a trailing hyphen', () => {
  const s = slug('pancakes '.repeat(20));
  assert.ok(s.length <= 60);
  assert.ok(!s.endsWith('-'));
});

test('file name is slug plus the first six hex of the id', () => {
  assert.equal(shortHash(ID), '3f2504');
  assert.equal(recipeFileName('Chipotle Chicken Burrito Bowls', ID), 'chipotle-chicken-burrito-bowls-3f2504.md');
});

test('reproduces a file the app wrote, byte for byte', () => {
  const name = 'caramelized-tomato-and-shallot-soup-d7dc25.md';
  const written = readFileSync(new URL(`fixtures/${name}`, import.meta.url), 'utf8');

  const field = (key) => written.match(new RegExp(`^${key}: (.*)$`, 'm'))?.[1];
  const section = (heading) => written.split(`## ${heading}\n\n`)[1]?.split('\n\n## ')[0].replace(/\n$/, '');

  const id = field('id');
  const [y, m, d] = field('dateCreated').split('-').map(Number);
  const recipe = {
    title: field('title'),
    image: field('imageName') ? 'present' : null,
    prepMinutes: parseInt(field('prepDuration'), 10),
    cookMinutes: parseInt(field('cookDuration'), 10),
    sourceURL: JSON.parse(field('sourceURL')),
    notes: section('Notes'),
    ingredients: section('Ingredients').split('\n').map((l) => l.replace('- [ ] ', '')),
    steps: section('Directions').split('\n').map((l) => l.replace(/^- \[ \] \*\*Step \d+:\*\* /, '')),
  };

  assert.equal(recipeFileName(recipe.title, id), name);
  assert.equal(recipeMarkdown(recipe, { id, dateCreated: new Date(y, m - 1, d) }), written);
});
