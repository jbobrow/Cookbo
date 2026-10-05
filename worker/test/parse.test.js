import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseRecipe, minutes, stripHTML, splitNumberedSteps, isOtherMethod } from '../src/parse.js';

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

// Half Baked Harvest's Cider Braised Pot Roast, as its JSON-LD publishes it:
// the oven method numbered inline in one step, the Crockpot method in a
// section of its own.
const potRoast = {
  '@type': 'Recipe',
  name: 'Cider Braised Pot Roast with Parmesan Sweet Potatoes',
  description: 'Cider Braised Pot Roast with tender beef, apple cider, caramelized onions, and crispy Parmesan sweet potatoes. A cozy fall dinner!',
  recipeIngredient: ['1 (4 pound)  beef chuck roast', '3  yellow onions, thinly sliced'],
  recipeInstructions: [
    { '@type': 'HowToStep', text: '1. Preheat the oven to 325° F. Season the roast with salt and pepper, then coat with flour.2. Arrange the onions and shallots in a large Dutch oven and dot with butter. Set the roast on top. 3. Cover and roast for 2 1/2 to 3 hours, until the beef is fork tender. Remove the sweet potatoes to a baking sheet and increase the oven temperature to 425° F.4. Toss the potatoes with the butter, garlic powder, Parmesan, and sage. Roast for 20 minutes, until crisp.5.  At the same time, return the roast to the oven, uncovered, for 10-15 minutes, until caramelized on top.6. Spoon the onions and gravy over the roast.' },
    { '@type': 'HowToSection', name: 'The Crockpot', itemListElement: [
      { '@type': 'HowToStep', text: '1. Season the roast with salt and pepper, then coat with flour. Add the onions and shallots to the Crockpot. 2. Cover and cook on LOW for 6-8 hours or HIGH for 3-4 hours, until the beef is fork tender.3. Remove the sweet potatoes to a baking sheet. Roast at 425° F for 20 minutes.4. Spoon the onions and gravy over the roast.' },
    ] },
  ],
};

test('splits a method numbered inline into steps', () => {
  const recipe = parseRecipe(page(potRoast), 'https://www.halfbakedharvest.com/x/');
  assert.equal(recipe.steps.length, 6);
  assert.equal(recipe.steps[0], 'Preheat the oven to 325° F. Season the roast with salt and pepper, then coat with flour.');
  assert.ok(recipe.steps[2].startsWith('Cover and roast for 2 1/2 to 3 hours'), 'the 2 in "2 1/2" is not a step');
  assert.ok(recipe.steps[4].startsWith('At the same time, return the roast'));
});

test('puts another way to make it in the notes', () => {
  const recipe = parseRecipe(page(potRoast), 'https://www.halfbakedharvest.com/x/');
  assert.ok(!recipe.steps.some((s) => s.includes('Crockpot')), 'the Crockpot method is not more steps');
  assert.ok(recipe.notes.startsWith('Cider Braised Pot Roast with tender beef'), 'the description comes first');
  assert.ok(recipe.notes.includes('\n\nThe Crockpot\n1. Season the roast'));
  assert.ok(recipe.notes.includes('\n2. Cover and cook on LOW for 6-8 hours'));
  assert.ok(recipe.notes.endsWith('4. Spoon the onions and gravy over the roast.'));
});

test('a method named first is the recipe', () => {
  const recipe = parseRecipe(page({
    '@type': 'Recipe',
    name: 'Chili',
    recipeIngredient: ['beans'],
    recipeInstructions: [{ '@type': 'HowToSection', name: 'Slow Cooker', itemListElement: [
      { '@type': 'HowToStep', text: 'Add everything to the slow cooker.' },
      { '@type': 'HowToStep', text: 'Cook on low for 8 hours.' },
    ] }],
  }), 'https://example.com/chili');
  assert.deepEqual(recipe.steps, ['Add everything to the slow cooker.', 'Cook on low for 8 hours.']);
});

test('splits numbered steps only when they count up from the start', () => {
  assert.deepEqual(splitNumberedSteps(['1. Mix the dough. 2. Let it rise.']), ['Mix the dough.', 'Let it rise.']);
  assert.deepEqual(splitNumberedSteps(['Mix the dough. 2. Let it rise.']), ['Mix the dough. 2. Let it rise.'], 'does not start at 1');
  assert.deepEqual(splitNumberedSteps(['1. Mix the dough with 1.5 cups flour.']), ['1. Mix the dough with 1.5 cups flour.'], 'one number is one step');
  assert.deepEqual(splitNumberedSteps(['1. Mix. 3. Bake for 20 minutes. 2. Cool.']), ['Mix. 3. Bake for 20 minutes.', 'Cool.'], 'out of order stays in the text');
  assert.deepEqual(splitNumberedSteps(['Simmer 10 minutes.', 'Serve.']), ['Simmer 10 minutes.', 'Serve.']);
});

test('knows a section that makes it another way', () => {
  for (const name of ['The Crockpot', 'Instant Pot', 'Slow Cooker Directions', 'Stovetop Method']) assert.ok(isOtherMethod(name), name);
  for (const name of ['For the sauce', 'Oven']) assert.ok(!isOtherMethod(name), name);
});
