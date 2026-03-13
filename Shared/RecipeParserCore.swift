import Foundation

struct RecipeParserCore {

    struct ParsedIngredientGroup: Codable {
        var name: String
        var ingredients: [String]
    }

    struct ParsedRecipe: Codable {
        var title: String
        var ingredientGroups: [ParsedIngredientGroup]
        var directions: [String]
        var sourceURL: String
        var imageURL: String?
        var prepDuration: TimeInterval
        var cookDuration: TimeInterval
        var notes: String

        var ingredients: [String] {
            ingredientGroups.flatMap { $0.ingredients }
        }

        enum CodingKeys: String, CodingKey {
            case title, ingredientGroups, ingredients, directions
            case sourceURL, imageURL, prepDuration, cookDuration, notes
        }

        init(
            title: String,
            ingredientGroups: [ParsedIngredientGroup]? = nil,
            ingredients: [String] = [],
            directions: [String],
            sourceURL: String,
            imageURL: String?,
            prepDuration: TimeInterval,
            cookDuration: TimeInterval,
            notes: String
        ) {
            self.title = title
            if let groups = ingredientGroups {
                self.ingredientGroups = groups
            } else {
                self.ingredientGroups = ingredients.isEmpty ? [] : [ParsedIngredientGroup(name: "", ingredients: ingredients)]
            }
            self.directions = directions
            self.sourceURL = sourceURL
            self.imageURL = imageURL
            self.prepDuration = prepDuration
            self.cookDuration = cookDuration
            self.notes = notes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            // Try ingredientGroups first, fall back to flat ingredients
            if let groups = try container.decodeIfPresent([ParsedIngredientGroup].self, forKey: .ingredientGroups) {
                ingredientGroups = groups
            } else {
                let flat = try container.decodeIfPresent([String].self, forKey: .ingredients) ?? []
                ingredientGroups = flat.isEmpty ? [] : [ParsedIngredientGroup(name: "", ingredients: flat)]
            }
            directions = try container.decode([String].self, forKey: .directions)
            sourceURL = try container.decode(String.self, forKey: .sourceURL)
            imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
            prepDuration = try container.decode(TimeInterval.self, forKey: .prepDuration)
            cookDuration = try container.decode(TimeInterval.self, forKey: .cookDuration)
            notes = try container.decode(String.self, forKey: .notes)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(title, forKey: .title)
            try container.encode(ingredientGroups, forKey: .ingredientGroups)
            // Also write flat ingredients for backward compat with share extension
            try container.encode(ingredients, forKey: .ingredients)
            try container.encode(directions, forKey: .directions)
            try container.encode(sourceURL, forKey: .sourceURL)
            try container.encodeIfPresent(imageURL, forKey: .imageURL)
            try container.encode(prepDuration, forKey: .prepDuration)
            try container.encode(cookDuration, forKey: .cookDuration)
            try container.encode(notes, forKey: .notes)
        }
    }

    // MARK: - Main Entry Point

    static func parseRecipe(html: String, sourceURL: String) -> ParsedRecipe? {
        // Try Instagram-specific parsing for Instagram URLs
        if isInstagramURL(sourceURL), let recipe = parseInstagramPage(html: html, sourceURL: sourceURL) {
            return recipe
        }

        if var recipe = parseJSONLD(html: html, sourceURL: sourceURL) {
            // Always try HTML fallback and use whichever has more steps
            let htmlDirections = parseDirectionsFromHTML(html: html)
            if htmlDirections.count > recipe.directions.count {
                recipe.directions = htmlDirections
            }
            // Try to extract ingredient groups from HTML (JSON-LD only has a flat list)
            let htmlGroups = parseIngredientGroupsFromHTML(html: html)
            if htmlGroups.count > 1 {
                recipe.ingredientGroups = htmlGroups
            }
            return recipe
        }

        if let recipe = parseMetaTags(html: html, sourceURL: sourceURL) {
            return recipe
        }

        return nil
    }

    // MARK: - Instagram Detection & Parsing

    static func isInstagramURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return false }
        return host == "instagram.com" || host == "www.instagram.com"
            || host.hasSuffix(".instagram.com")
    }

    /// Extracts the canonical Instagram post/reel URL by stripping tracking parameters.
    private static func cleanInstagramURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return urlString
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url?.absoluteString ?? urlString
    }

    /// Parses an Instagram page to extract recipe data from the post caption.
    static func parseInstagramPage(html: String, sourceURL: String) -> ParsedRecipe? {
        let caption = extractInstagramCaption(html: html)
        let imageURL = extractMetaContent(html: html, property: "og:image")

        // Extract a title from og:title — typically "Username on Instagram: \"snippet...\""
        let ogTitle = extractMetaContent(html: html, property: "og:title") ?? ""

        guard !caption.isEmpty || !ogTitle.isEmpty else { return nil }

        // Parse recipe components from the caption text
        let parsed = parseInstagramCaption(caption)

        // Derive a recipe title: prefer one extracted from caption, fall back to og:title cleanup
        let title: String
        if !parsed.title.isEmpty {
            title = parsed.title
        } else {
            title = cleanInstagramTitle(ogTitle)
        }

        guard !title.isEmpty else { return nil }

        let cleanURL = cleanInstagramURL(sourceURL)

        return ParsedRecipe(
            title: title,
            ingredientGroups: parsed.ingredientGroups.isEmpty ? nil : parsed.ingredientGroups,
            ingredients: parsed.ingredientGroups.isEmpty ? [] : [],
            directions: parsed.directions,
            sourceURL: cleanURL,
            imageURL: imageURL,
            prepDuration: 0,
            cookDuration: 0,
            notes: parsed.notes
        )
    }

    /// Extracts the full Instagram post caption from the HTML.
    /// Tries multiple strategies since Instagram's HTML structure varies.
    private static func extractInstagramCaption(html: String) -> String {
        // Strategy 1: Look for the caption in meta description (usually most complete)
        if let desc = extractMetaContent(html: html, property: "og:description") {
            // Instagram og:description often has format: "N likes, N comments - \"caption text\""
            // or just the caption text with possible truncation
            let cleaned = cleanInstagramDescription(desc)
            if cleaned.count > 20 {
                return cleaned
            }
        }

        // Strategy 2: Look for caption in embedded JSON data (window._sharedData or similar)
        // Instagram sometimes embeds full post data in script tags
        let jsonPatterns = [
            #""caption"\s*:\s*\{[^}]*"text"\s*:\s*"([^"]+)"#,
            #""edge_media_to_caption"\s*:\s*\{[^}]*"text"\s*:\s*"([^"]+)"#
        ]
        for pattern in jsonPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let captionRange = Range(match.range(at: 1), in: html) {
                let raw = String(html[captionRange])
                // Unescape JSON string escapes
                let unescaped = raw
                    .replacingOccurrences(of: "\\n", with: "\n")
                    .replacingOccurrences(of: "\\u0026", with: "&")
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\/", with: "/")
                    .replacingOccurrences(of: "\\u2022", with: "\u{2022}")
                    .replacingOccurrences(of: "\\u2019", with: "\u{2019}")
                    .replacingOccurrences(of: "\\u2018", with: "\u{2018}")
                    .replacingOccurrences(of: "\\u201c", with: "\u{201C}")
                    .replacingOccurrences(of: "\\u201d", with: "\u{201D}")
                if unescaped.count > 20 {
                    return unescaped
                }
            }
        }

        // Strategy 3: Fall back to meta description (non-OG)
        if let desc = extractMetaContent(html: html, property: "description") {
            let cleaned = cleanInstagramDescription(desc)
            if cleaned.count > 20 {
                return cleaned
            }
        }

        return ""
    }

    /// Cleans up Instagram's og:description format.
    /// Input often looks like: "123 likes, 5 comments - \"actual caption here\""
    private static func cleanInstagramDescription(_ desc: String) -> String {
        var text = desc

        // Remove the "N likes, N comments - " prefix pattern
        if let regex = try? NSRegularExpression(
            pattern: #"^[\d,.]+ likes?,?\s*[\d,.]+ comments?\s*[-–—]\s*"#,
            options: .caseInsensitive
        ) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }

        // Also handle: "N Likes, N Comments - Author on Instagram: \"caption\""
        if let regex = try? NSRegularExpression(
            pattern: #"^.*?\bon Instagram:\s*"#,
            options: .caseInsensitive
        ) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }

        // Strip surrounding quotes
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\"") { text = String(text.dropFirst()) }
        if text.hasSuffix("\"") { text = String(text.dropLast()) }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cleans up the og:title from Instagram.
    /// Input looks like: "Username on Instagram: \"Recipe Title Here\""
    private static func cleanInstagramTitle(_ ogTitle: String) -> String {
        var title = ogTitle

        // Remove "Username on Instagram: " prefix
        if let regex = try? NSRegularExpression(
            pattern: #"^.*?\bon Instagram:\s*"#,
            options: .caseInsensitive
        ) {
            let range = NSRange(title.startIndex..., in: title)
            title = regex.stringByReplacingMatches(in: title, range: range, withTemplate: "")
        }

        // Strip surrounding quotes
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.hasPrefix("\"") { title = String(title.dropFirst()) }
        if title.hasSuffix("\"") { title = String(title.dropLast()) }

        // Truncate at first line break or period if the title is very long (caption snippet)
        let lines = title.components(separatedBy: .newlines)
        title = lines.first ?? title

        // If still very long, truncate at ~80 chars on a word boundary
        if title.count > 80 {
            let truncated = String(title.prefix(80))
            if let lastSpace = truncated.lastIndex(of: " ") {
                title = String(truncated[..<lastSpace]) + "…"
            }
        }

        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Instagram Caption Recipe Extraction

    struct InstagramRecipeParts {
        var title: String = ""
        var ingredientGroups: [ParsedIngredientGroup] = []
        var directions: [String] = []
        var notes: String = ""
    }

    /// Parses unstructured Instagram caption text to extract recipe components.
    static func parseInstagramCaption(_ caption: String) -> InstagramRecipeParts {
        guard !caption.isEmpty else { return InstagramRecipeParts() }

        var result = InstagramRecipeParts()

        // Normalize line endings
        let text = caption
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        // Identify sections by header keywords
        enum Section { case unknown, title, ingredients, directions, notes }
        var currentSection: Section = .unknown
        var titleLines: [String] = []
        var ingredientLines: [String] = []
        var directionLines: [String] = []
        var noteLines: [String] = []
        var currentGroupName = ""
        var groups: [(name: String, items: [String])] = []

        let ingredientHeaders = [
            "ingredients", "ingredient", "what you need", "what you'll need",
            "you'll need", "you will need", "shopping list", "for the recipe"
        ]
        let directionHeaders = [
            "directions", "direction", "instructions", "instruction", "steps",
            "method", "how to make", "how to", "preparation", "prep",
            "to make", "procedure", "let's cook", "let's make", "recipe"
        ]
        let noteHeaders = [
            "notes", "note", "tips", "tip", "variations", "serving",
            "nutrition", "storage", "substitutions"
        ]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let lower = trimmed.lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: ":;-*•#🔸🔹📝🥘🍳🧑\u{200D}🍴✨💡👇⬇️"))
                .trimmingCharacters(in: .whitespaces)

            // Check if this line is a section header
            if ingredientHeaders.contains(where: { lower == $0 || lower.hasPrefix($0 + ":") || lower.hasPrefix($0 + " ") && lower.count < $0.count + 15 }) {
                // Flush any current ingredient group before switching
                if !ingredientLines.isEmpty {
                    groups.append((name: currentGroupName, items: ingredientLines))
                    ingredientLines = []
                }
                currentGroupName = ""
                currentSection = .ingredients
                continue
            }

            if directionHeaders.contains(where: { lower == $0 || lower.hasPrefix($0 + ":") || lower.hasPrefix($0 + " ") && lower.count < $0.count + 15 }) {
                // Flush remaining ingredients
                if !ingredientLines.isEmpty {
                    groups.append((name: currentGroupName, items: ingredientLines))
                    ingredientLines = []
                }
                currentSection = .directions
                continue
            }

            if noteHeaders.contains(where: { lower == $0 || lower.hasPrefix($0 + ":") }) {
                currentSection = .notes
                continue
            }

            // Check for ingredient sub-group headers (e.g., "For the sauce:")
            if currentSection == .ingredients {
                let forThePattern = #"^(?:for (?:the )?|)([\w\s]+):$"#
                if let regex = try? NSRegularExpression(pattern: forThePattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                   let nameRange = Range(match.range(at: 1), in: trimmed) {
                    let name = String(trimmed[nameRange]).trimmingCharacters(in: .whitespaces)
                    // If it looks like a group header and is short
                    if name.count < 40 && !name.contains(",") {
                        if !ingredientLines.isEmpty {
                            groups.append((name: currentGroupName, items: ingredientLines))
                            ingredientLines = []
                        }
                        currentGroupName = trimmed.hasSuffix(":") ? String(trimmed.dropLast()) : trimmed
                        continue
                    }
                }
            }

            // Add lines to the appropriate section
            switch currentSection {
            case .unknown:
                // Before any section header, treat as title/intro
                titleLines.append(trimmed)
            case .title:
                titleLines.append(trimmed)
            case .ingredients:
                let cleaned = stripLeadingBullets(trimmed)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-–•*▪️✅☑️🟢"))
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty {
                    ingredientLines.append(cleaned)
                }
            case .directions:
                var cleaned = trimmed
                // Remove leading step numbers like "1.", "1)", "Step 1:"
                if let regex = try? NSRegularExpression(pattern: #"^(?:step\s*)?\d+[\.\)\:\-]\s*"#, options: .caseInsensitive) {
                    let range = NSRange(cleaned.startIndex..., in: cleaned)
                    cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
                }
                cleaned = stripLeadingBullets(cleaned)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-–•*▪️"))
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty {
                    directionLines.append(cleaned)
                }
            case .notes:
                noteLines.append(trimmed)
            }
        }

        // Flush remaining ingredient group
        if !ingredientLines.isEmpty {
            groups.append((name: currentGroupName, items: ingredientLines))
        }

        // Build the title from initial lines (before any section header)
        if !titleLines.isEmpty {
            // Use first meaningful line as title, rest as notes preamble
            result.title = titleLines.first ?? ""

            // Remove hashtags and emoji-only segments from title
            result.title = removeHashtags(result.title)
            if result.title.count > 80 {
                let truncated = String(result.title.prefix(80))
                if let lastSpace = truncated.lastIndex(of: " ") {
                    result.title = String(truncated[..<lastSpace]) + "…"
                }
            }

            // Add remaining intro lines to notes if they contain useful text
            if titleLines.count > 1 {
                let extraIntro = titleLines.dropFirst()
                    .filter { !$0.isEmpty && !isHashtagLine($0) }
                    .joined(separator: "\n")
                if !extraIntro.isEmpty {
                    noteLines.insert(contentsOf: extraIntro.components(separatedBy: "\n"), at: 0)
                }
            }
        }

        // Build ingredient groups
        result.ingredientGroups = groups.map { ParsedIngredientGroup(name: $0.name, ingredients: $0.items) }

        // Build directions
        result.directions = directionLines

        // Build notes (strip hashtag lines)
        let filteredNotes = noteLines.filter { !isHashtagLine($0) }
        result.notes = filteredNotes.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    /// Returns true if the line is primarily hashtags.
    private static func isHashtagLine(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        guard !words.isEmpty else { return false }
        let hashtagCount = words.filter { $0.hasPrefix("#") }.count
        return Double(hashtagCount) / Double(words.count) > 0.5
    }

    /// Removes hashtags from a string.
    private static func removeHashtags(_ text: String) -> String {
        text.replacingOccurrences(of: #"#\w+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - JSON-LD Parsing (Schema.org Recipe)

    /// Recursively collect all Recipe-typed dicts from a JSON-LD value.
    /// Handles @graph arrays, ItemList.itemListElement[].item nesting, and plain arrays.
    private static func collectRecipeCandidates(from value: Any) -> [[String: Any]] {
        var results: [[String: Any]] = []
        if let dict = value as? [String: Any] {
            let type_ = dict["@type"]
            let isRecipe: Bool
            if let s = type_ as? String { isRecipe = s == "Recipe" }
            else if let a = type_ as? [String] { isRecipe = a.contains("Recipe") }
            else { isRecipe = false }
            if isRecipe { results.append(dict) }
            // Recurse into @graph
            if let graph = dict["@graph"] as? [Any] {
                for item in graph { results += collectRecipeCandidates(from: item) }
            }
            // Recurse into ItemList / ListItem nested items
            if let elems = dict["itemListElement"] as? [Any] {
                for elem in elems {
                    if let elemDict = elem as? [String: Any] {
                        let nested = elemDict["item"] ?? elem
                        results += collectRecipeCandidates(from: nested)
                    }
                }
            }
        } else if let array = value as? [Any] {
            for item in array { results += collectRecipeCandidates(from: item) }
        }
        return results
    }

    static func parseJSONLD(html: String, sourceURL: String) -> ParsedRecipe? {
        let pattern = #"<script[^>]*type\s*=\s*["']?application/ld\+json["']?[^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        var best: ParsedRecipe? = nil
        for match in matches {
            guard let jsonRange = Range(match.range(at: 1), in: html) else { continue }
            let jsonString = String(html[jsonRange])
            guard let jsonData = jsonString.data(using: .utf8) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: jsonData) else { continue }

            for candidateDict in collectRecipeCandidates(from: json) {
                guard let recipe = extractRecipe(from: candidateDict, sourceURL: sourceURL) else { continue }
                // Prefer the candidate with the most directions (list beats string summary)
                if best == nil || recipe.directions.count > best!.directions.count {
                    best = recipe
                }
            }
        }

        return best
    }

    private static func extractRecipe(from dict: [String: Any], sourceURL: String) -> ParsedRecipe? {
        let type = dict["@type"]
        let isRecipe: Bool
        if let typeString = type as? String {
            isRecipe = typeString == "Recipe"
        } else if let typeArray = type as? [String] {
            isRecipe = typeArray.contains("Recipe")
        } else {
            isRecipe = false
        }

        guard isRecipe else { return nil }

        let title = dict["name"] as? String ?? ""
        let ingredients = (dict["recipeIngredient"] as? [String]) ?? []

        var directions: [String] = []
        if let instructions = dict["recipeInstructions"] {
            if let steps = instructions as? [String] {
                directions = steps
            } else if let steps = instructions as? [Any] {
                // Use [Any] instead of [[String: Any]] so mixed arrays (strings + dicts) don't fail the cast
                for step in steps {
                    if let stepString = step as? String {
                        directions.append(stepString)
                    } else if let stepDict = step as? [String: Any] {
                        let stepType = stepDict["@type"] as? String ?? ""

                        if stepType == "HowToSection" {
                            // HowToSection contains nested HowToStep items — flatten them
                            let items = (stepDict["itemListElement"] as? [Any]) ?? []
                            for item in items {
                                guard let itemDict = item as? [String: Any] else { continue }
                                if let text = itemDict["text"] as? String, !text.isEmpty {
                                    directions.append(text)
                                } else if let name = itemDict["name"] as? String, !name.isEmpty {
                                    directions.append(name)
                                }
                            }
                        } else if let text = stepDict["text"] as? String, !text.isEmpty {
                            directions.append(text)
                        } else if let items = stepDict["itemListElement"] as? [Any] {
                            for item in items {
                                guard let itemDict = item as? [String: Any] else { continue }
                                if let text = itemDict["text"] as? String, !text.isEmpty {
                                    directions.append(text)
                                } else if let name = itemDict["name"] as? String, !name.isEmpty {
                                    directions.append(name)
                                }
                            }
                        } else if let name = stepDict["name"] as? String, !name.isEmpty {
                            directions.append(name)
                        }
                    }
                }
            } else if let instructionString = instructions as? String {
                let withBreaks = instructionString
                    .replacingOccurrences(of: #"</(?:p|li|div|br\s*/?)>"#, with: "\n", options: .regularExpression)
                    .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
                directions = stripHTML(withBreaks)
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }

        let prepTime = parseISO8601Duration(dict["prepTime"] as? String)
        let cookTime = parseISO8601Duration(dict["cookTime"] as? String)

        var imageURL: String?
        if let image = dict["image"] {
            if let urlString = image as? String {
                imageURL = urlString
            } else if let imageDict = image as? [String: Any] {
                imageURL = imageDict["url"] as? String
            } else if let imageArray = image as? [Any] {
                if let first = imageArray.first as? String {
                    imageURL = first
                } else if let first = imageArray.first as? [String: Any] {
                    imageURL = first["url"] as? String
                }
            }
        }

        let notes = dict["description"] as? String ?? ""

        return ParsedRecipe(
            title: stripHTML(title),
            ingredients: ingredients.map { stripLeadingBullets(stripHTML($0)) },
            directions: directions.map { stripHTML($0) },
            sourceURL: sourceURL,
            imageURL: imageURL,
            prepDuration: prepTime,
            cookDuration: cookTime,
            notes: stripHTML(notes)
        )
    }

    // MARK: - HTML Ingredient Group Parsing

    static func parseIngredientGroupsFromHTML(html: String) -> [ParsedIngredientGroup] {
        var groups: [ParsedIngredientGroup] = []

        // Strategy 1: WPRM (WP Recipe Maker) — container divs with class wprm-recipe-ingredient-group
        // Each container has an optional group name header and a <ul> of ingredients
        let wprmGroupPattern = #"<div[\s][^>]*?class\s*=\s*["']?wprm-recipe-ingredient-group\b[^>]*>([\s\S]*?)</ul>"#
        if let regex = try? NSRegularExpression(pattern: wprmGroupPattern, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            let matches = regex.matches(in: html, range: range)
            for match in matches {
                guard let contentRange = Range(match.range(at: 1), in: html) else { continue }
                let content = String(html[contentRange])
                let name = extractGroupName(from: content)
                let items = extractListItems(from: content)
                if !items.isEmpty {
                    groups.append(ParsedIngredientGroup(name: name, ingredients: items))
                }
            }
        }
        if !groups.isEmpty { return groups }

        // Strategy 2: Headers with ingredientgroup/ingredient-group class followed by <ul> lists
        // Matches NYT Cooking and similar sites
        let groupHeaderPattern = #"<(?:h[2-6]|p|span|div)[^>]*class\s*=\s*["'][^"']*(?:ingredientgroup|ingredient-group|ingredient_group)[^"']*["'][^>]*>([\s\S]*?)</(?:h[2-6]|p|span|div)>\s*<ul[^>]*>([\s\S]*?)</ul>"#
        if let regex = try? NSRegularExpression(pattern: groupHeaderPattern, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            let matches = regex.matches(in: html, range: range)
            for match in matches {
                guard let nameRange = Range(match.range(at: 1), in: html),
                      let listRange = Range(match.range(at: 2), in: html) else { continue }
                let name = stripHTML(String(html[nameRange]))
                let items = extractListItems(from: String(html[listRange]))
                if !items.isEmpty {
                    groups.append(ParsedIngredientGroup(name: name, ingredients: items))
                }
            }
        }
        if !groups.isEmpty { return groups }

        // Strategy 3: Generic pattern — header tags (h2-h4) containing "for the" followed by <ul>
        // Use [^<]* for header name to prevent lazy [\s\S]*? from crossing adjacent heading tags
        // via backtracking (e.g. consuming <h3>Title</h3><h4>Name as a single match).
        let forThePattern = #"<h[2-4][^>]*>([^<]*)</h[2-4]>\s*<ul[^>]*>([\s\S]*?)</ul>"#
        if let regex = try? NSRegularExpression(pattern: forThePattern, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            let matches = regex.matches(in: html, range: range)
            for match in matches {
                guard let nameRange = Range(match.range(at: 1), in: html),
                      let listRange = Range(match.range(at: 2), in: html) else { continue }
                let name = stripHTML(String(html[nameRange]))
                let nameLower = name.lowercased()
                guard nameLower.hasPrefix("for the") || nameLower.hasPrefix("for ") else { continue }
                let items = extractListItems(from: String(html[listRange]))
                if !items.isEmpty {
                    groups.append(ParsedIngredientGroup(name: name, ingredients: items))
                }
            }
        }
        if !groups.isEmpty { return groups }

        // Strategy 4: Tasty Recipes plugin — h3/h4 headers + <ul> inside tasty-recipes-ingredients container
        // Matches div[class*="tasty-recipes-ingredients"], then extracts header+ul pairs within it
        let tastyIngContainerPattern = #"<div[^>]*class\s*=\s*["'][^"']*tasty-recipes-ingredients[^"']*["'][^>]*>([\s\S]*?)</div>\s*</div>"#
        if let regex = try? NSRegularExpression(pattern: tastyIngContainerPattern, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let containerRange = Range(match.range(at: 1), in: html) {
                let containerHTML = String(html[containerRange])
                // Extract header + ul pairs within the container.
                // Use [^<]* for header name to avoid crossing adjacent heading tag boundaries.
                let groupPattern = #"<h[2-6][^>]*>([^<]*)</h[2-6]>\s*<ul[^>]*>([\s\S]*?)</ul>"#
                if let groupRegex = try? NSRegularExpression(pattern: groupPattern, options: .caseInsensitive) {
                    let containerRange2 = NSRange(containerHTML.startIndex..., in: containerHTML)
                    let groupMatches = groupRegex.matches(in: containerHTML, range: containerRange2)
                    for gm in groupMatches {
                        guard let nameRange2 = Range(gm.range(at: 1), in: containerHTML),
                              let listRange2 = Range(gm.range(at: 2), in: containerHTML) else { continue }
                        let name = stripHTML(String(containerHTML[nameRange2]))
                        let items = extractListItems(from: String(containerHTML[listRange2]))
                        if !items.isEmpty {
                            groups.append(ParsedIngredientGroup(name: name, ingredients: items))
                        }
                    }
                }
                // If no groups found with headers, treat entire container as single group
                if groups.isEmpty {
                    let ulPattern = #"<ul[^>]*>([\s\S]*?)</ul>"#
                    if let ulRegex = try? NSRegularExpression(pattern: ulPattern, options: .caseInsensitive) {
                        let ulMatches = ulRegex.matches(in: containerHTML, range: NSRange(containerHTML.startIndex..., in: containerHTML))
                        var allItems: [String] = []
                        for um in ulMatches {
                            if let listRange3 = Range(um.range(at: 1), in: containerHTML) {
                                allItems += extractListItems(from: String(containerHTML[listRange3]))
                            }
                        }
                        if !allItems.isEmpty {
                            groups.append(ParsedIngredientGroup(name: "", ingredients: allItems))
                        }
                    }
                }
            }
        }

        return groups
    }

    private static func extractGroupName(from content: String) -> String {
        // Look for a group name in a header or span with wprm-recipe-group-name class
        let namePattern = #"<(?:h[2-6]|span)[^>]*wprm-recipe-group-name[^>]*>([\s\S]*?)</(?:h[2-6]|span)>"#
        if let regex = try? NSRegularExpression(pattern: namePattern, options: .caseInsensitive) {
            let range = NSRange(content.startIndex..., in: content)
            if let match = regex.firstMatch(in: content, range: range),
               let nameRange = Range(match.range(at: 1), in: content) {
                return stripHTML(String(content[nameRange]))
            }
        }
        return ""
    }

    private static func extractListItems(from listHTML: String) -> [String] {
        var items: [String] = []
        let itemPattern = #"<li[^>]*>([\s\S]*?)</li>"#
        if let regex = try? NSRegularExpression(pattern: itemPattern, options: .caseInsensitive) {
            let range = NSRange(listHTML.startIndex..., in: listHTML)
            let matches = regex.matches(in: listHTML, range: range)
            for match in matches {
                if let contentRange = Range(match.range(at: 1), in: listHTML) {
                    var content = String(listHTML[contentRange])
                    // Remove screen-reader-only spans (e.g. WPRM checkbox symbols like &#x25a2;)
                    content = content.replacingOccurrences(
                        of: #"<span[^>]*(?:sr-only|screen-reader-text)[^>]*>[\s\S]*?</span>"#,
                        with: "",
                        options: .regularExpression
                    )
                    // Remove checkbox inputs and their labels entirely
                    content = content.replacingOccurrences(
                        of: #"<(?:input|label)[^>]*/?>|<label[^>]*>[\s\S]*?</label>"#,
                        with: "",
                        options: .regularExpression
                    )
                    let text = stripLeadingBullets(stripHTML(content))
                    if !text.isEmpty {
                        items.append(text)
                    }
                }
            }
        }
        return items
    }

    // MARK: - ISO 8601 Duration Parsing

    static func parseISO8601Duration(_ duration: String?) -> TimeInterval {
        guard let duration = duration else { return 0 }

        var totalSeconds: TimeInterval = 0
        let pattern = #"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }

        let range = NSRange(duration.startIndex..., in: duration)
        guard let match = regex.firstMatch(in: duration, range: range) else { return 0 }

        if let hoursRange = Range(match.range(at: 1), in: duration),
           let hours = Double(duration[hoursRange]) {
            totalSeconds += hours * 3600
        }
        if let minutesRange = Range(match.range(at: 2), in: duration),
           let minutes = Double(duration[minutesRange]) {
            totalSeconds += minutes * 60
        }
        if let secondsRange = Range(match.range(at: 3), in: duration),
           let seconds = Double(duration[secondsRange]) {
            totalSeconds += seconds
        }

        return totalSeconds
    }

    // MARK: - HTML Directions Fallback

    static func parseDirectionsFromHTML(html: String) -> [String] {
        // Strategy 0: Tasty Recipes plugin — <ol> directly inside div[class*="tasty-recipes-instructions"]
        // Uses firstMatch to avoid duplicate steps from nested containers
        let tastyInstructionsPattern = #"class\s*=\s*["'][^"']*tasty-recipes-instructions[^"']*["'][^>]*>[\s\S]{0,500}?<ol[^>]*>([\s\S]*?)</ol>"#
        if let regex = try? NSRegularExpression(pattern: tastyInstructionsPattern, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let contentRange = Range(match.range(at: 1), in: html) {
                let items = extractListItems(from: String(html[contentRange])).filter { $0.count > 10 }
                if !items.isEmpty { return items }
            }
        }

        // Strategy 1: Find <li> elements inside an itemprop="recipeInstructions" container (Microdata)
        let itempropPattern = #"itemprop\s*=\s*["']recipeInstructions["'][^>]*>([\s\S]*?)</(?:ol|ul|div|section)>"#
        if let directions = extractStepsFromHTMLBlock(html: html, pattern: itempropPattern), !directions.isEmpty {
            return directions
        }

        // Strategy 2: Find <p> elements inside step content containers (handles deeply nested structures)
        let stepContentPattern = #"<div[^>]*class\s*=\s*["'][^"']*(?:stepContent|step_content|instruction_content)[^"']*["'][^>]*>([\s\S]*?)</div>"#
        if let regex = try? NSRegularExpression(pattern: stepContentPattern, options: .caseInsensitive) {
            var contentDirections: [String] = []
            let range = NSRange(html.startIndex..., in: html)
            let matches = regex.matches(in: html, range: range)
            for match in matches {
                if let contentRange = Range(match.range(at: 1), in: html) {
                    let step = stripHTML(String(html[contentRange]))
                    if !step.isEmpty && step.count > 15 {
                        contentDirections.append(step)
                    }
                }
            }
            if !contentDirections.isEmpty {
                return contentDirections
            }
        }

        // Strategy 3: Find <li> elements inside containers with step/instruction/preparation class names
        let classPattern = #"<(?:ol|ul|div|section)[^>]*class\s*=\s*["'][^"']*(?:preparation_step|instruction|step_content|recipe-steps|recipe_steps|steps_list)[^"']*["'][^>]*>([\s\S]*?)</(?:ol|ul|div|section)>"#
        if let directions = extractStepsFromHTMLBlock(html: html, pattern: classPattern), !directions.isEmpty {
            return directions
        }

        // Strategy 4: Find individual <li> or <p> elements with step-related class names
        var directions: [String] = []
        let stepPattern = #"<(?:li|p)[^>]*class\s*=\s*["'][^"']*(?:step_text|step_content|instruction_text|preparation_step)[^"']*["'][^>]*>([\s\S]*?)</(?:li|p)>"#
        if let regex = try? NSRegularExpression(pattern: stepPattern, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            let matches = regex.matches(in: html, range: range)
            for match in matches {
                if let contentRange = Range(match.range(at: 1), in: html) {
                    let step = stripHTML(String(html[contentRange]))
                    if !step.isEmpty && step.count > 15 {
                        directions.append(step)
                    }
                }
            }
        }

        return directions
    }

    private static func extractStepsFromHTMLBlock(html: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        var allResults: [String] = []
        for match in matches {
            guard let contentRange = Range(match.range(at: 1), in: html) else { continue }
            let content = String(html[contentRange])

            let itemPattern = #"<(?:li|p)[^>]*>([\s\S]*?)</(?:li|p)>"#
            if let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: .caseInsensitive) {
                let itemRange = NSRange(content.startIndex..., in: content)
                let itemMatches = itemRegex.matches(in: content, range: itemRange)
                for itemMatch in itemMatches {
                    if let itemContentRange = Range(itemMatch.range(at: 1), in: content) {
                        let rawContent = String(content[itemContentRange])
                        if rawContent.range(of: #"<(?:ol|ul)\b"#, options: .regularExpression) != nil {
                            continue
                        }
                        let text = stripHTML(rawContent)
                        if !text.isEmpty && text.count > 15 {
                            allResults.append(text)
                        }
                    }
                }
            }
        }

        return allResults.isEmpty ? nil : allResults
    }

    // MARK: - HTML Helpers

    /// Removes leading bullet points, decorative symbols, and list markers from ingredient text.
    /// Some sites embed characters like •, ■, -, * at the start of ingredient strings.
    static func stripLeadingBullets(_ string: String) -> String {
        // Unicode bullet/decorator characters and common ASCII list markers
        let bulletCharacters = CharacterSet(charactersIn: "•·▪▫■□▸▹►▻◆◇○●◉➤➢➣➥➦–—-*☐☑☒◻◼🔲🔳")
        var result = string
        while let first = result.unicodeScalars.first, bulletCharacters.contains(first) {
            result = String(result.dropFirst())
            result = result.trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    static func stripHTML(_ string: String) -> String {
        var result = string
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode numeric HTML entities (decimal &#8217; and hex &#x2019;)
        if let regex = try? NSRegularExpression(pattern: #"&#x([0-9a-fA-F]+);"#) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range).reversed()
            for match in matches {
                if let hexRange = Range(match.range(at: 1), in: result),
                   let codePoint = UInt32(result[hexRange], radix: 16),
                   let scalar = Unicode.Scalar(codePoint) {
                    let fullRange = Range(match.range, in: result)!
                    result.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"&#(\d+);"#) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range).reversed()
            for match in matches {
                if let decRange = Range(match.range(at: 1), in: result),
                   let codePoint = UInt32(result[decRange]),
                   let scalar = Unicode.Scalar(codePoint) {
                    let fullRange = Range(match.range, in: result)!
                    result.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }

        // Decode common named entities
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&ndash;", with: "\u{2013}")
            .replacingOccurrences(of: "&mdash;", with: "\u{2014}")
            .replacingOccurrences(of: "&lsquo;", with: "\u{2018}")
            .replacingOccurrences(of: "&rsquo;", with: "\u{2019}")
            .replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
            .replacingOccurrences(of: "&rdquo;", with: "\u{201D}")
            .replacingOccurrences(of: "&bull;", with: "\u{2022}")
            .replacingOccurrences(of: "&deg;", with: "\u{00B0}")
            .replacingOccurrences(of: "&frac12;", with: "\u{00BD}")
            .replacingOccurrences(of: "&frac13;", with: "\u{2153}")
            .replacingOccurrences(of: "&frac14;", with: "\u{00BC}")
            .replacingOccurrences(of: "&frac34;", with: "\u{00BE}")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    // MARK: - Meta Tag Fallback

    static func parseMetaTags(html: String, sourceURL: String) -> ParsedRecipe? {
        var title = ""

        if let ogTitle = extractMetaContent(html: html, property: "og:title") {
            title = ogTitle
        } else if let titleRange = html.range(of: #"<title[^>]*>(.*?)</title>"#, options: .regularExpression) {
            title = stripHTML(String(html[titleRange]))
        }

        var imageURL: String?
        if let ogImage = extractMetaContent(html: html, property: "og:image") {
            imageURL = ogImage
        }

        guard !title.isEmpty else { return nil }

        return ParsedRecipe(
            title: stripHTML(title),
            ingredients: [],
            directions: [],
            sourceURL: sourceURL,
            imageURL: imageURL,
            prepDuration: 0,
            cookDuration: 0,
            notes: ""
        )
    }

    static func extractMetaContent(html: String, property: String) -> String? {
        let pattern1 = #"<meta[^>]*(?:property|name)\s*=\s*["']\#(property)["'][^>]*content\s*=\s*["']([^"']*)["'][^>]*>"#
        if let regex = try? NSRegularExpression(pattern: pattern1, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let contentRange = Range(match.range(at: 1), in: html) {
                return String(html[contentRange])
            }
        }

        let pattern2 = #"<meta[^>]*content\s*=\s*["']([^"']*)["'][^>]*(?:property|name)\s*=\s*["']\#(property)["'][^>]*>"#
        if let regex = try? NSRegularExpression(pattern: pattern2, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let contentRange = Range(match.range(at: 1), in: html) {
                return String(html[contentRange])
            }
        }

        return nil
    }

    // MARK: - Duration Formatting

    static func formatDuration(_ seconds: TimeInterval) -> String? {
        guard seconds > 0 else { return nil }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}
