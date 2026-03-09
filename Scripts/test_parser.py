#!/usr/bin/env python3
"""
Test harness for RecipeURLImporter's HTML direction parsing.

Mirrors the regex logic from RecipeURLImporter.swift so we can iterate
quickly without building the full iOS app.

Usage:
    python3 Scripts/test_parser.py                  # run against built-in test HTML
    python3 Scripts/test_parser.py <url>            # fetch a URL and parse it
    python3 Scripts/test_parser.py --file page.html # parse a local HTML file
"""

import re
import sys
import html as html_module
import textwrap
from typing import Optional

# ---------------------------------------------------------------------------
# Port of RecipeURLImporter's parsing helpers
# ---------------------------------------------------------------------------

def strip_leading_bullets(s: str) -> str:
    """Port of RecipeParserCore.stripLeadingBullets(_:)"""
    bullets = set('•·▪▫■□▸▹►▻◆◇○●◉➤➢➣➥➦\u2013\u2014-*☐☑☒◻◼🔲🔳')
    s = s.strip()
    while s and s[0] in bullets:
        s = s[1:].strip()
    return s


def extract_list_items(list_html: str) -> list[str]:
    """Port of RecipeParserCore.extractListItems(from:)"""
    items = []
    for m in re.finditer(r'<li[^>]*>([\s\S]*?)</li>', list_html, re.IGNORECASE | re.DOTALL):
        content = m.group(1)
        # Remove screen-reader-only spans
        content = re.sub(
            r'<span[^>]*(?:sr-only|screen-reader-text)[^>]*>[\s\S]*?</span>',
            '', content, flags=re.IGNORECASE | re.DOTALL)
        # Remove checkbox inputs/labels
        content = re.sub(
            r'<(?:input|label)[^>]*/?>|<label[^>]*>[\s\S]*?</label>',
            '', content, flags=re.IGNORECASE | re.DOTALL)
        text = strip_leading_bullets(strip_html(content))
        if text:
            items.append(text)
    return items


def parse_ingredient_groups_from_html(html: str) -> list[dict]:
    """Port of RecipeParserCore.parseIngredientGroupsFromHTML(html:).
    Returns a list of dicts: [{'name': str, 'ingredients': [str]}]."""
    groups: list[dict] = []

    # Strategy 1: WPRM — div[class*="wprm-recipe-ingredient-group"]
    wprm_pattern = r'<div[\s][^>]*?class\s*=\s*["\']?wprm-recipe-ingredient-group\b[^>]*>([\s\S]*?)</ul>'
    for m in re.finditer(wprm_pattern, html, re.IGNORECASE | re.DOTALL):
        content = m.group(1)
        nm = re.search(
            r'<(?:h[2-6]|span)[^>]*wprm-recipe-group-name[^>]*>([\s\S]*?)</(?:h[2-6]|span)>',
            content, re.IGNORECASE | re.DOTALL)
        name = strip_html(nm.group(1)) if nm else ''
        items = extract_list_items(content)
        if items:
            groups.append({'name': name, 'ingredients': items})
    if groups:
        return groups

    # Strategy 2: ingredientgroup/ingredient-group class headers followed by <ul>
    header_pattern = (
        r'<(?:h[2-6]|p|span|div)[^>]*class\s*=\s*["\'][^"\']*'
        r'(?:ingredientgroup|ingredient-group|ingredient_group)'
        r'[^"\']*["\'][^>]*>([\s\S]*?)</(?:h[2-6]|p|span|div)>\s*<ul[^>]*>([\s\S]*?)</ul>'
    )
    for m in re.finditer(header_pattern, html, re.IGNORECASE | re.DOTALL):
        name = strip_html(m.group(1))
        items = extract_list_items(m.group(2))
        if items:
            groups.append({'name': name, 'ingredients': items})
    if groups:
        return groups

    # Strategy 3: h2-h4 headers starting with "for the" / "for " followed by <ul>
    # Use [^<]* for the header name to prevent lazy [\s\S]*? from crossing into
    # adjacent heading tags via backtracking (e.g. swallowing <h3>Title</h3><h4>Name)
    for_the_pattern = r'<h[2-4][^>]*>([^<]*)</h[2-4]>\s*<ul[^>]*>([\s\S]*?)</ul>'
    for m in re.finditer(for_the_pattern, html, re.IGNORECASE | re.DOTALL):
        name = strip_html(m.group(1))
        if name.lower().startswith('for the') or name.lower().startswith('for '):
            items = extract_list_items(m.group(2))
            if items:
                groups.append({'name': name, 'ingredients': items})
    if groups:
        return groups

    # Strategy 4: Tasty Recipes plugin — div[class*="tasty-recipes-ingredients"]
    tasty_ing_pattern = (
        r'<div[^>]*class\s*=\s*["\'][^"\']*tasty-recipes-ingredients[^"\']*["\'][^>]*>'
        r'([\s\S]*?)</div>\s*</div>'
    )
    m = re.search(tasty_ing_pattern, html, re.IGNORECASE | re.DOTALL)
    if m:
        container = m.group(1)
        # Same [^<]* fix — prevent crossing adjacent h-tag boundaries
        group_pattern = r'<h[2-6][^>]*>([^<]*)</h[2-6]>\s*<ul[^>]*>([\s\S]*?)</ul>'
        for gm in re.finditer(group_pattern, container, re.IGNORECASE | re.DOTALL):
            name = strip_html(gm.group(1))
            items = extract_list_items(gm.group(2))
            if items:
                groups.append({'name': name, 'ingredients': items})
        if not groups:
            # No named groups — gather all <ul> items into a single unnamed group
            all_items: list[str] = []
            for um in re.finditer(r'<ul[^>]*>([\s\S]*?)</ul>', container, re.IGNORECASE | re.DOTALL):
                all_items.extend(extract_list_items(um.group(1)))
            if all_items:
                groups.append({'name': '', 'ingredients': all_items})

    return groups


def strip_html(string: str) -> str:
    """Port of RecipeURLImporter.stripHTML(_:)"""
    result = re.sub(r"<[^>]+>", "", string)

    # Decode numeric HTML entities (hex)
    def replace_hex(m):
        cp = int(m.group(1), 16)
        return chr(cp)
    result = re.sub(r"&#x([0-9a-fA-F]+);", replace_hex, result)

    # Decode numeric HTML entities (decimal)
    def replace_dec(m):
        cp = int(m.group(1))
        return chr(cp)
    result = re.sub(r"&#(\d+);", replace_dec, result)

    # Named entities
    replacements = {
        "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"',
        "&apos;": "'", "&nbsp;": " ", "&ndash;": "\u2013",
        "&mdash;": "\u2014", "&lsquo;": "\u2018", "&rsquo;": "\u2019",
        "&ldquo;": "\u201C", "&rdquo;": "\u201D", "&bull;": "\u2022",
        "&deg;": "\u00B0", "&frac12;": "\u00BD", "&frac13;": "\u2153",
        "&frac14;": "\u00BC", "&frac34;": "\u00BE",
    }
    for entity, char in replacements.items():
        result = result.replace(entity, char)

    result = result.replace("\u00A0", " ")
    return result.strip()


def extract_steps_from_html_block(html: str, pattern: str) -> Optional[list[str]]:
    """Port of RecipeURLImporter.extractStepsFromHTMLBlock(html:pattern:)"""
    matches = list(re.finditer(pattern, html, re.IGNORECASE | re.DOTALL))

    all_results = []
    for match in matches:
        content = match.group(1)
        item_pattern = r"<(?:li|p)[^>]*>([\s\S]*?)</(?:li|p)>"
        item_matches = re.finditer(item_pattern, content, re.IGNORECASE | re.DOTALL)
        for item_match in item_matches:
            raw_content = item_match.group(1)
            # Skip group wrapper items that contain nested lists
            if re.search(r"<(?:ol|ul)\b", raw_content):
                continue
            text = strip_html(raw_content)
            if text and len(text) > 15:
                all_results.append(text)

    return all_results if all_results else None


def parse_directions_from_html(html: str, verbose: bool = False) -> list[str]:
    """Port of RecipeURLImporter.parseDirectionsFromHTML(html:)"""

    # Strategy 0: Tasty Recipes plugin — <ol> inside div[class*="tasty-recipes-instructions"]
    # Uses re.search (first match only) to avoid duplicate steps from nested containers
    if verbose:
        print("\n--- Strategy 0: Tasty Recipes plugin ---")
    tasty_instructions_pattern = r'''class\s*=\s*["'][^"']*tasty-recipes-instructions[^"']*["'][^>]*>[\s\S]{0,500}?<ol[^>]*>([\s\S]*?)</ol>'''
    m = re.search(tasty_instructions_pattern, html, re.IGNORECASE | re.DOTALL)
    if m:
        items = [strip_html(li.group(1)) for li in re.finditer(r'<li[^>]*>([\s\S]*?)</li>', m.group(1), re.IGNORECASE | re.DOTALL)]
        items = [t for t in items if t and len(t) > 10]
        if items:
            if verbose:
                print(f"  MATCHED: {len(items)} steps")
                for i, d in enumerate(items, 1):
                    print(f"  {i}. {d[:80]}{'...' if len(d) > 80 else ''}")
            return items
    if verbose:
        print("  No match.")

    # Strategy 1: itemprop="recipeInstructions" container (Microdata)
    if verbose:
        print("\n--- Strategy 1: itemprop Microdata ---")
    itemprop_pattern = r'''itemprop\s*=\s*["']recipeInstructions["'][^>]*>([\s\S]*?)</(?:ol|ul|div|section)>'''
    directions = extract_steps_from_html_block(html, itemprop_pattern)
    if directions:
        if verbose:
            print(f"  MATCHED: {len(directions)} steps")
            for i, d in enumerate(directions, 1):
                print(f"  {i}. {d[:80]}{'...' if len(d) > 80 else ''}")
        return directions
    elif verbose:
        print("  No match.")

    # Strategy 2: <p> inside step content containers (handles deep nesting)
    if verbose:
        print("\n--- Strategy 2: Step content divs ---")
    step_content_pattern = r'''<div[^>]*class\s*=\s*["'][^"']*(?:stepContent|step_content|instruction_content)[^"']*["'][^>]*>([\s\S]*?)</div>'''
    content_directions = []
    for match in re.finditer(step_content_pattern, html, re.IGNORECASE | re.DOTALL):
        step = strip_html(match.group(1))
        if step and len(step) > 15:
            content_directions.append(step)
    if content_directions:
        if verbose:
            print(f"  MATCHED: {len(content_directions)} steps")
            for i, d in enumerate(content_directions, 1):
                print(f"  {i}. {d[:80]}{'...' if len(d) > 80 else ''}")
        return content_directions
    elif verbose:
        print("  No match.")

    # Strategy 3: containers with step/instruction/preparation class names
    if verbose:
        print("\n--- Strategy 3: Class-based containers ---")
    class_pattern = r'''<(?:ol|ul|div|section)[^>]*class\s*=\s*["'][^"']*(?:preparation_step|instruction|step_content|recipe-steps|recipe_steps|steps_list)[^"']*["'][^>]*>([\s\S]*?)</(?:ol|ul|div|section)>'''
    directions = extract_steps_from_html_block(html, class_pattern)
    if directions:
        if verbose:
            print(f"  MATCHED: {len(directions)} steps")
            for i, d in enumerate(directions, 1):
                print(f"  {i}. {d[:80]}{'...' if len(d) > 80 else ''}")
        return directions
    elif verbose:
        print("  No match.")

    # Strategy 4: Individual elements with step-related class names
    if verbose:
        print("\n--- Strategy 4: Individual step elements ---")
    directions = []
    step_pattern = r'''<(?:li|p)[^>]*class\s*=\s*["'][^"']*(?:step_text|step_content|instruction_text|preparation_step)[^"']*["'][^>]*>([\s\S]*?)</(?:li|p)>'''
    for match in re.finditer(step_pattern, html, re.IGNORECASE | re.DOTALL):
        step = strip_html(match.group(1))
        if step and len(step) > 15:
            directions.append(step)
    if verbose:
        if directions:
            print(f"  MATCHED: {len(directions)} steps")
            for i, d in enumerate(directions, 1):
                print(f"  {i}. {d[:80]}{'...' if len(d) > 80 else ''}")
        else:
            print("  No match.")

    return directions


# ---------------------------------------------------------------------------
# Test HTML samples
# ---------------------------------------------------------------------------

NYT_COOKING_HTML = '''<ol class="preparation_stepList___jqWa"><li><h3 class="pantry--label preparation_stepGroupName__vQuRQ">Prepare the Cabbage:</h3><ol class="preparation_stepList___jqWa"><li class="preparation_step__nzZHP" id="recipe-step-1"><div class="pantry--ui-lg-strong preparation_stepNumber__qWIz4">Step <!-- -->1</div><div class="preparation_stepContent__CFrQM"><p class="pantry--body-long">Cut the cabbage half lengthwise through the core to get four wedges.</p></div></li><li class="preparation_step__nzZHP" id="recipe-step-2"><div class="pantry--ui-lg-strong preparation_stepNumber__qWIz4">Step <!-- -->2</div><div class="preparation_stepContent__CFrQM"><p class="pantry--body-long">Heat a large well-seasoned cast-iron skillet or heavy-bottomed pan for which you have a lid over medium-high. Add 2 tablespoons of the olive oil. Once shimmering, add the cabbage, cut sides down, and season with \u00bd teaspoon of the salt. Using tongs, move the wedges back and forth gently to ensure they\u2019re evenly coated in the oil, and cook until browned on the bottom, 5 to 7 minutes. Carefully flip, sprinkle with the remaining \u00bd teaspoon salt, and cook until browned on the other side, 5 to 7 minutes. Transfer the wedges to a plate. Take the pan off the heat to cool for 5 to 10 minutes (do some prep or cleanup in the meantime).</p></div></li><li class="preparation_step__nzZHP" id="recipe-step-3"><div class="pantry--ui-lg-strong preparation_stepNumber__qWIz4">Step <!-- -->3</div><div class="preparation_stepContent__CFrQM"><p class="pantry--body-long">Stir the maple syrup into the canned tomatoes. Set aside.</p></div></li><li class="preparation_step__nzZHP" id="recipe-step-4"><div class="pantry--ui-lg-strong preparation_stepNumber__qWIz4">Step <!-- -->4</div><div class="preparation_stepContent__CFrQM"><p class="pantry--body-long">Heat the remaining 1 tablespoon oil in the same pan over medium heat. Add the cumin seeds and cook, tossing frequently, until they are aromatic and darker in color, 1 minute. Add the shallots and garlic and cook for 2 minutes, until the shallots starts to soften. Add the paprika, coriander, cinnamon, nutmeg and Aleppo pepper and cook for 1 minute, stirring frequently. If needed, add a drizzle of oil if things seem dry.&nbsp;</p></div></li><li class="preparation_step__nzZHP" id="recipe-step-5"><div class="pantry--ui-lg-strong preparation_stepNumber__qWIz4">Step <!-- -->5</div><div class="preparation_stepContent__CFrQM"><p class="pantry--body-long">Reduce the heat to medium-low. Pour in the tomato mixture with all the juices, stir, and carefully nestle the wedges back into the pan. Cover and simmer until the cabbage is tender and the tomatoes have thickened a bit, 8 to 10 minutes, opening the lid once to check if the tomatoes are drying up (if so, add a few splashes of water).</p></div></li></ol></li><li><h3 class="pantry--label preparation_stepGroupName__vQuRQ">Make the tahini sauce while the cabbage is simmering:</h3><ol class="preparation_stepList___jqWa"><li class="preparation_step__nzZHP" id="recipe-step-6"><div class="pantry--ui-lg-strong preparation_stepNumber__qWIz4">Step <!-- -->6</div><div class="preparation_stepContent__CFrQM"><p class="pantry--body-long">In a medium bowl, whisk together the tahini, lemon juice, maple syrup, garlic, cumin, salt and pepper to taste. Add the ice water a tablespoon at a time, whisking as you go. It will get stiff at first but eventually will become creamy yet pourable. Taste for seasonings, adding more salt as desired.</p></div></li></ol></li><li><h3 class="pantry--label preparation_stepGroupName__vQuRQ">To serve:</h3><ol class="preparation_stepList___jqWa"><li class="preparation_step__nzZHP" id="recipe-step-7"><div class="pantry--ui-lg-strong preparation_stepNumber__qWIz4">Step <!-- -->7</div><div class="preparation_stepContent__CFrQM"><p class="pantry--body-long">Serve the cabbage straight from the pan. Top with cilantro and a squeeze of lemon juice. Spoon some tahini sauce generously on top and serve more on the side.</p></div></li></ol></li><li><h3 class="pantry--label preparation_stepGroupName__vQuRQ"></h3><ol class="preparation_stepList___jqWa"></ol></li></ol>'''

# Tasty Recipes plugin HTML fixture — representative of mexicanmademeatless.com structure
TASTY_RECIPES_HTML = '''
<div class="tasty-recipes" id="tasty-recipes-12345">
  <div class="tasty-recipes-entry-content">
    <div class="tasty-recipes-ingredients">
      <h3>Ingredients</h3>
      <div class="tasty-recipes-ingredients-body">
        <h4>For the Chile Sauce:</h4>
        <ul>
          <li>5 dried guajillo chiles, stems and seeds removed</li>
          <li>3 dried ancho chiles, stems and seeds removed</li>
          <li>4 cloves garlic</li>
        </ul>
        <h4>For the Soup:</h4>
        <ul>
          <li>2 cans (29 oz each) hominy, drained and rinsed</li>
          <li>6 cups vegetable broth</li>
          <li>1 white onion, quartered</li>
        </ul>
      </div>
    </div>
    <div class="tasty-recipes-instructions">
      <h3>Instructions</h3>
      <div class="tasty-recipes-instructions-body">
        <ol>
          <li>Add the dried chiles to a large pot and cover with water. Bring to a boil, then remove from heat and soak for 20 minutes until softened.</li>
          <li>Drain the chiles, reserving 1 cup of the soaking liquid. Blend with garlic until smooth, then strain through a fine-mesh sieve.</li>
          <li>In a large pot over medium heat, cook the chile sauce for 5 minutes, stirring frequently, until it darkens slightly.</li>
          <li>Add the vegetable broth, hominy, and onion. Simmer for 30-40 minutes until hominy is tender and flavors meld.</li>
          <li>Remove the onion, taste for seasoning, and serve topped with shredded cabbage, radishes, and a squeeze of lime juice.</li>
        </ol>
      </div>
    </div>
  </div>
</div>
'''

# Tasty Recipes JSON-LD with HowToSection grouped instructions (another common format)
TASTY_RECIPES_JSONLD_HTML = '''<html><head>
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Recipe",
  "name": "Vegan Pozole Rojo",
  "image": "https://example.com/pozole.jpg",
  "description": "An authentic vegan pozole rojo.",
  "prepTime": "PT30M",
  "cookTime": "PT45M",
  "recipeIngredient": ["5 dried guajillo chiles", "3 dried ancho chiles", "2 cans hominy"],
  "recipeInstructions": [
    {
      "@type": "HowToSection",
      "name": "For the Chile Sauce",
      "itemListElement": [
        {"@type": "HowToStep", "text": "Add dried chiles to a pot, cover with water, boil then soak 20 minutes until softened."},
        {"@type": "HowToStep", "text": "Blend soaked chiles with garlic and soaking liquid until smooth. Strain through a sieve."}
      ]
    },
    {
      "@type": "HowToSection",
      "name": "For the Soup",
      "itemListElement": [
        {"@type": "HowToStep", "text": "Cook chile sauce in a large pot over medium heat for 5 minutes, stirring frequently."},
        {"@type": "HowToStep", "text": "Add vegetable broth, hominy, and onion. Simmer 30-40 minutes until hominy is tender."},
        {"@type": "HowToStep", "text": "Remove onion, season to taste, and serve with cabbage, radishes, and lime."}
      ]
    }
  ]
}
</script>
</head><body></body></html>'''


def run_test(name: str, html: str):
    print(f"\n{'='*70}")
    print(f"TEST: {name}")
    print(f"{'='*70}")

    groups = parse_ingredient_groups_from_html(html)
    total_ingredients = sum(len(g['ingredients']) for g in groups)
    print(f"\n--- INGREDIENTS: {total_ingredients} item(s) in {len(groups)} group(s) ---")
    for g in groups:
        label = g['name'] if g['name'] else '(ungrouped)'
        print(f"  [{label}]")
        for ing in g['ingredients']:
            print(f"    • {ing}")

    directions = parse_directions_from_html(html, verbose=True)

    print(f"\n--- DIRECTIONS: {len(directions)} step(s) ---")
    for i, d in enumerate(directions, 1):
        print(f"\n  Step {i}:")
        print(textwrap.fill(d, width=76, initial_indent="    ", subsequent_indent="    "))

    return directions


def fetch_and_parse(url: str):
    import urllib.request
    import json
    print(f"\nFetching {url}...")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req) as resp:
        html = resp.read().decode("utf-8", errors="replace")
    print(f"Fetched {len(html)} bytes.")

    # Show JSON-LD recipe summary (informational)
    ld_pattern = r'<script[^>]*type\s*=\s*["\']?application/ld\+json["\']?[^>]*>([\s\S]*?)</script>'
    for m in re.finditer(ld_pattern, html, re.IGNORECASE):
        try:
            data = json.loads(m.group(1))
            recipes = []
            if isinstance(data, dict):
                if data.get("@type") == "Recipe":
                    recipes.append(data)
                for item in (data.get("@graph") or []):
                    if isinstance(item, dict) and item.get("@type") == "Recipe":
                        recipes.append(item)
            elif isinstance(data, list):
                for item in data:
                    if isinstance(item, dict) and item.get("@type") == "Recipe":
                        recipes.append(item)
            for recipe in recipes:
                ings = recipe.get("recipeIngredient", [])
                instructions = recipe.get("recipeInstructions", [])
                print(f"\n--- JSON-LD: {len(ings)} ingredient(s), {len(instructions)} instruction entr(ies) ---")
                for i, inst in enumerate(instructions):
                    if isinstance(inst, str):
                        print(f"  {i+1}. [string] {inst[:80]}")
                    elif isinstance(inst, dict):
                        t = inst.get("@type", "?")
                        text = inst.get("text", inst.get("name", ""))[:60]
                        items = inst.get("itemListElement", [])
                        print(f"  {i+1}. [{t}] {text!r} ({len(items)} sub-items)")
        except json.JSONDecodeError:
            pass

    print(f"\n{'='*70}")
    print(f"FULL PARSE (JSON-LD + HTML fallback): {url}")
    print(f"{'='*70}")

    # Ingredients: JSON-LD flat list, upgraded to groups via HTML if available
    json_ld_ings: list[str] = []
    for m in re.finditer(ld_pattern, html, re.IGNORECASE):
        try:
            data = json.loads(m.group(1))
            candidates = []
            if isinstance(data, dict):
                candidates.append(data)
                for item in (data.get("@graph") or []):
                    if isinstance(item, dict):
                        candidates.append(item)
            elif isinstance(data, list):
                for item in data:
                    if isinstance(item, dict):
                        candidates.append(item)
            for d in candidates:
                dtype = d.get("@type")
                is_recipe = dtype == "Recipe" or (isinstance(dtype, list) and "Recipe" in dtype)
                if is_recipe:
                    json_ld_ings = d.get("recipeIngredient", [])
                    break
            if json_ld_ings:
                break
        except json.JSONDecodeError:
            pass

    html_groups = parse_ingredient_groups_from_html(html)
    if html_groups and len(html_groups) > 1:
        groups = html_groups
        print(f"\n--- INGREDIENTS (HTML groups): {sum(len(g['ingredients']) for g in groups)} item(s) in {len(groups)} group(s) ---")
    elif html_groups:
        groups = html_groups
        print(f"\n--- INGREDIENTS (HTML): {sum(len(g['ingredients']) for g in groups)} item(s) ---")
    elif json_ld_ings:
        groups = [{'name': '', 'ingredients': [strip_leading_bullets(strip_html(i)) for i in json_ld_ings]}]
        print(f"\n--- INGREDIENTS (JSON-LD flat): {len(json_ld_ings)} item(s) ---")
    else:
        groups = []
        print("\n--- INGREDIENTS: none found ---")

    for g in groups:
        label = g['name'] if g['name'] else '(ungrouped)'
        print(f"  [{label}]")
        for ing in g['ingredients']:
            print(f"    • {ing}")

    # Directions: use full_parse (JSON-LD preferred, HTML fallback)
    directions = full_parse(html, source_url=url, verbose=True)
    print(f"\n--- DIRECTIONS: {len(directions)} step(s) ---")
    for i, d in enumerate(directions, 1):
        print(f"\n  Step {i}:")
        print(textwrap.fill(d, width=76, initial_indent="    ", subsequent_indent="    "))


def extract_json_ld_directions(html: str) -> list[str]:
    """Port of the JSON-LD recipeInstructions extraction path."""
    import json
    ld_pattern = r'<script[^>]*type\s*=\s*["\']?application/ld\+json["\']?[^>]*>([\s\S]*?)</script>'
    for m in re.finditer(ld_pattern, html, re.IGNORECASE):
        try:
            data = json.loads(m.group(1))
        except json.JSONDecodeError:
            continue

        candidates = []
        if isinstance(data, dict):
            candidates.append(data)
            for item in (data.get("@graph") or []):
                if isinstance(item, dict):
                    candidates.append(item)
        elif isinstance(data, list):
            for item in data:
                if isinstance(item, dict):
                    candidates.append(item)
                    for gi in (item.get("@graph") or []):
                        if isinstance(gi, dict):
                            candidates.append(gi)

        for d in candidates:
            dtype = d.get("@type")
            is_recipe = dtype == "Recipe" or (isinstance(dtype, list) and "Recipe" in dtype)
            if not is_recipe:
                continue

            instructions = d.get("recipeInstructions", [])
            directions = []
            if isinstance(instructions, list) and all(isinstance(s, str) for s in instructions):
                directions = instructions
            elif isinstance(instructions, list):
                # Use element-by-element checking (like [Any] in Swift) to handle mixed arrays
                for step in instructions:
                    if isinstance(step, str):
                        directions.append(step)
                    elif isinstance(step, dict):
                        step_type = step.get("@type", "")
                        if step_type == "HowToSection":
                            for item in (step.get("itemListElement") or []):
                                if isinstance(item, dict):
                                    t = item.get("text") or item.get("name") or ""
                                    if t:
                                        directions.append(t)
                        elif step.get("text"):
                            directions.append(step["text"])
                        elif step.get("itemListElement"):
                            for item in step["itemListElement"]:
                                if isinstance(item, dict):
                                    t = item.get("text") or item.get("name") or ""
                                    if t:
                                        directions.append(t)
                        elif step.get("name"):
                            directions.append(step["name"])
            elif isinstance(instructions, str):
                text = re.sub(r"</(?:p|li|div|br\s*/?)>", "\n", instructions)
                text = re.sub(r"<br\s*/?>", "\n", text)
                text = strip_html(text)
                directions = [l.strip() for l in text.split("\n") if l.strip()]

            if directions:
                return [strip_html(d) for d in directions]
    return []


def full_parse(html: str, source_url: str = "test", verbose: bool = False):
    """Port of the full importRecipe logic (JSON-LD + HTML fallback)."""
    json_ld_directions = extract_json_ld_directions(html)
    if verbose:
        print(f"\n--- JSON-LD extracted {len(json_ld_directions)} directions ---")
        for i, d in enumerate(json_ld_directions, 1):
            print(f"  {i}. {d[:80]}{'...' if len(d) > 80 else ''}")

    # Always try both JSON-LD and HTML, use whichever has more steps
    html_directions = parse_directions_from_html(html, verbose=verbose)

    if json_ld_directions and html_directions:
        if html_directions and len(html_directions) > len(json_ld_directions):
            if verbose:
                print(f"  -> JSON-LD had {len(json_ld_directions)} step(s), HTML found {len(html_directions)}. Using HTML.")
            return html_directions
        if verbose:
            print(f"  -> JSON-LD had {len(json_ld_directions)} step(s), HTML had {len(html_directions)}. Using JSON-LD.")
        return json_ld_directions

    if json_ld_directions:
        if verbose:
            print("  -> Using JSON-LD directions (no HTML results).")
        return json_ld_directions

    return html_directions


def check_results(result: list[str], expected: int, test_name: str):
    print(f"\n{'='*70}")
    if len(result) == expected:
        print(f"PASS [{test_name}]: Got {expected} steps as expected.")
    else:
        print(f"FAIL [{test_name}]: Expected {expected} steps, got {len(result)}.")

    # Verify no step contains "Step N" prefix junk
    prefixed = [s for s in result if re.match(r"^Step\s+\d", s)]
    if prefixed:
        print(f"WARNING: {len(prefixed)} steps have 'Step N' prefix (should be clean):")
        for s in prefixed:
            print(f"  '{s[:60]}...'")
    else:
        print(f"PASS [{test_name}]: No steps have 'Step N' prefix junk.")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg == "--file":
            with open(sys.argv[2]) as f:
                html = f.read()
            print("=== HTML-only parse ===")
            run_test(f"File: {sys.argv[2]}", html)
            print("\n=== Full parse (JSON-LD + HTML fallback) ===")
            result = full_parse(html, verbose=True)
            print(f"\n--- FULL PARSE RESULT: {len(result)} steps ---")
            for i, d in enumerate(result, 1):
                print(f"\n  Step {i}:")
                print(textwrap.fill(d, width=76, initial_indent="    ", subsequent_indent="    "))
        elif arg.startswith("http"):
            fetch_and_parse(arg)
        else:
            print(f"Unknown argument: {arg}")
            print(__doc__)
    else:
        # Run built-in test against the HTML snippet (no JSON-LD present)
        result = run_test("NYT Cooking (nested grouped steps)", NYT_COOKING_HTML)
        check_results(result, 7, "NYT Cooking HTML")

        # Tasty Recipes HTML fallback (no JSON-LD — tests Strategy 0 for directions + Strategy 4 for ingredients)
        result = run_test("Tasty Recipes HTML (mexicanmademeatless.com style)", TASTY_RECIPES_HTML)
        check_results(result, 5, "Tasty Recipes HTML")

        # Verify ingredient groups are parsed correctly from the same HTML
        groups = parse_ingredient_groups_from_html(TASTY_RECIPES_HTML)
        total = sum(len(g['ingredients']) for g in groups)
        print(f"\n{'='*70}")
        if len(groups) == 2 and total == 6:
            print(f"PASS [Tasty Recipes HTML ingredients]: Got 2 groups, 6 ingredients.")
        else:
            print(f"FAIL [Tasty Recipes HTML ingredients]: Expected 2 groups / 6 ingredients, got {len(groups)} groups / {total} ingredients.")

        # Tasty Recipes JSON-LD with HowToSection (tests robust [Any] array handling)
        result_jsonld = full_parse(TASTY_RECIPES_JSONLD_HTML, verbose=True)
        print(f"\n{'='*70}")
        if len(result_jsonld) == 5:
            print(f"PASS [Tasty Recipes JSON-LD HowToSection]: Got 5 steps as expected.")
        else:
            print(f"FAIL [Tasty Recipes JSON-LD HowToSection]: Expected 5 steps, got {len(result_jsonld)}.")
        for i, d in enumerate(result_jsonld, 1):
            print(f"  {i}. {d[:80]}{'...' if len(d) > 80 else ''}")
