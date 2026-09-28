import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseRecipe, minutes, stripHTML } from '../src/parse.js';

const page = (json) => `<html><head><script type="application/ld+json">${JSON.stringify(json)}</script></head></html>`;

test('parses a plain Recipe object', () => {
  const recipe = parseRecipe(page({
    '@type': 'Recipe',
    name: 'Tomato Soup',
    image: 'https://example.com/soup.jpg',
    recipeIngredient: ['2 lb tomatoes', '1 onion'],
    recipeInstructions: [{ '@type': 'HowToStep', text: 'Chop.' }, { '@type': 'HowToStep', text: 'Simmer.' }],
    prepTime: 'PT15M',
    cookTime: 'PT1H10M',
    recipeYield: ['4', '4 servings'],
    description: '<p>A <em>cozy</em> soup.</p>',
  }), 'https://www.example.com/soup');

  assert.equal(recipe.title, 'Tomato Soup');
  assert.equal(recipe.image, 'https://example.com/soup.jpg');
  assert.deepEqual(recipe.ingredients, ['2 lb tomatoes', '1 onion']);
  assert.deepEqual(recipe.steps, ['Chop.', 'Simmer.']);
  assert.equal(recipe.prepMinutes, 15);
  assert.equal(recipe.cookMinutes, 70);
  assert.equal(recipe.yield, '4');
  assert.equal(recipe.source, 'example.com');
  assert.equal(recipe.notes, 'A cozy soup.');
});

test('finds the recipe inside an @graph', () => {
  const recipe = parseRecipe(page({
    '@context': 'https://schema.org',
    '@graph': [
      { '@type': 'WebPage', name: 'Blog' },
      { '@type': ['Recipe', 'NewsArticle'], name: 'Pasta', recipeIngredient: ['pasta'], recipeInstructions: 'Boil it.' },
    ],
  }), 'https://example.com/p');
  assert.equal(recipe.title, 'Pasta');
  assert.deepEqual(recipe.steps, ['Boil it.']);
});

test('flattens HowToSection steps', () => {
  const recipe = parseRecipe(page({
    '@type': 'Recipe',
    name: 'Cake',
    recipeIngredient: ['flour'],
    recipeInstructions: [
      { '@type': 'HowToSection', name: 'Batter', itemListElement: [{ '@type': 'HowToStep', text: 'Mix.' }] },
      { '@type': 'HowToSection', name: 'Bake', itemListElement: [{ '@type': 'HowToStep', text: 'Bake.' }] },
    ],
  }), 'https://example.com/c');
  assert.deepEqual(recipe.steps, ['Mix.', 'Bake.']);
});

test('splits an HTML instruction string into steps', () => {
  const recipe = parseRecipe(page({
    '@type': 'Recipe',
    name: 'Toast',
    recipeIngredient: ['bread'],
    recipeInstructions: '<p>Slice the bread.</p><p>Toast it.</p>',
  }), 'https://example.com/t');
  assert.deepEqual(recipe.steps, ['Slice the bread.', 'Toast it.']);
});

test('prefers the candidate with the most steps', () => {
  const html = page({ '@type': 'Recipe', name: 'Summary', recipeIngredient: ['x'], recipeInstructions: 'All in one.' })
    + page({ '@type': 'Recipe', name: 'Full', recipeIngredient: ['x'], recipeInstructions: ['One.', 'Two.', 'Three.'] });
  assert.equal(parseRecipe(html, 'https://example.com/').title, 'Full');
});

test('resolves relative and object-shaped images', () => {
  const a = parseRecipe(page({ '@type': 'Recipe', name: 'A', recipeIngredient: ['x'], image: '/img/a.jpg' }), 'https://example.com/r/a');
  assert.equal(a.image, 'https://example.com/img/a.jpg');
  const b = parseRecipe(page({ '@type': 'Recipe', name: 'B', recipeIngredient: ['x'], image: [{ url: 'https://cdn.example.com/b.jpg' }] }), 'https://example.com/');
  assert.equal(b.image, 'https://cdn.example.com/b.jpg');
});

test('decodes entities and strips bullets from ingredients', () => {
  const recipe = parseRecipe(page({
    '@type': 'Recipe', name: 'Mac &amp; Cheese',
    recipeIngredient: ['• 1&frac12; cups milk', '<b>2</b> cups cheese'],
  }), 'https://example.com/');
  assert.equal(recipe.title, 'Mac & Cheese');
  assert.deepEqual(recipe.ingredients, ['1½ cups milk', '2 cups cheese']);
});

test('returns null when there is no recipe', () => {
  assert.equal(parseRecipe('<html><body>Hello</body></html>', 'https://example.com/'), null);
  assert.equal(parseRecipe(page({ '@type': 'Article', name: 'News' }), 'https://example.com/'), null);
  assert.equal(parseRecipe('<script type="application/ld+json">{not json</script>', 'https://example.com/'), null);
});

test('ISO 8601 durations', () => {
  assert.equal(minutes('PT45M'), 45);
  assert.equal(minutes('PT1H30M'), 90);
  assert.equal(minutes('P1DT2H'), 1560);
  assert.equal(minutes('PT90S'), 2);
  assert.equal(minutes('45 minutes'), 0);
  assert.equal(minutes(undefined), 0);
});

test('stripHTML collapses whitespace', () => {
  assert.equal(stripHTML('  <p>Hello\n   <em>there</em></p> '), 'Hello there');
});
