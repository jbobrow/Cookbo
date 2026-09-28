// The file Cookbo writes for a recipe: its name and its Markdown.
//
// Mirrors RecipeFileNaming.swift and RecipeMarkdownSerializer.swift so the home
// page shows exactly what the app would save. Tested against a file the app
// actually wrote (worker/test/recipe-file.test.js); keep them in step.

const HASH_LENGTH = 6;
const MAX_SLUG_LENGTH = 60;

/** kebab-case title: accents folded, apostrophes dropped, everything else not a letter or digit becomes a hyphen. */
export function slug(title) {
  let s = String(title)
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/['’]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  if (s.length > MAX_SLUG_LENGTH) s = s.slice(0, MAX_SLUG_LENGTH).replace(/-+$/, '');
  return s || 'untitled';
}

/** First six hex characters of the recipe's UUID. */
export function shortHash(id) {
  return id.replace(/-/g, '').toLowerCase().slice(0, HASH_LENGTH);
}

export function recipeFileName(title, id) {
  return `${slug(title)}-${shortHash(id)}.md`;
}

function yamlEscape(s) {
  const needsQuotes = s.includes(':') || s.includes('#') || s.includes('"')
    || s.startsWith(' ') || s.endsWith(' ') || s.startsWith("'");
  return needsQuotes ? `"${s.replace(/"/g, '\\"')}"` : s;
}

function isoDay(date) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/**
 * The Markdown for a newly imported recipe: unrated, uncooked, in no category.
 * @param {{title: string, image?: string|null, prepMinutes?: number, cookMinutes?: number,
 *          sourceURL?: string|null, notes?: string, ingredients: string[], steps: string[]}} recipe
 */
export function recipeMarkdown(recipe, { id, dateCreated = new Date() }) {
  const lines = ['---', `title: ${yamlEscape(recipe.title)}`, `id: ${id}`];
  if (recipe.image) lines.push(`imageName: ${id}.jpg`);
  lines.push(
    `dateCreated: ${isoDay(dateCreated)}`,
    'rating: 0',
    `prepDuration: ${recipe.prepMinutes || 0} minutes`,
    `cookDuration: ${recipe.cookMinutes || 0} minutes`,
  );
  if (recipe.sourceURL) lines.push(`sourceURL: ${yamlEscape(recipe.sourceURL)}`);
  lines.push('---', '', `# ${recipe.title}`, '');

  if (recipe.notes) lines.push('## Notes', '', recipe.notes, '');

  if (recipe.ingredients.length) {
    lines.push('## Ingredients', '');
    for (const ingredient of recipe.ingredients) lines.push(`- [ ] ${ingredient}`);
    lines.push('');
  }

  if (recipe.steps.length) {
    lines.push('## Directions', '');
    recipe.steps.forEach((step, i) => lines.push(`- [ ] **Step ${i + 1}:** ${step}`));
    lines.push('');
  }

  return lines.join('\n');
}
