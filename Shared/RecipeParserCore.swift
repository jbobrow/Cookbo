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
    /// Returns nil when the caption is truncated or lacks meaningful recipe data,
    /// so that callers can fall back to the oEmbed API.
    static func parseInstagramPage(html: String, sourceURL: String) -> ParsedRecipe? {
        let caption = extractInstagramCaption(html: html)
        let imageURL = extractMetaContent(html: html, property: "og:image")

        // Extract a title from og:title — typically "Username on Instagram: \"snippet...\""
        let ogTitle = extractMetaContent(html: html, property: "og:title") ?? ""

        guard !caption.isEmpty || !ogTitle.isEmpty else { return nil }

        // Parse recipe components from the caption text
        let parsed = parseInstagramCaption(caption)

        // Require at least some ingredients OR directions to consider this a valid recipe.
        // Instagram's og:description is often truncated, so if we only got a title
        // with no actual recipe data, return nil to let the oEmbed fallback try.
        guard !parsed.ingredientGroups.isEmpty || !parsed.directions.isEmpty else {
            return nil
        }

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
            ingredientGroups: parsed.ingredientGroups,
            ingredients: [],
            directions: parsed.directions,
            sourceURL: cleanURL,
            imageURL: imageURL,
            prepDuration: parsed.prepDuration,
            cookDuration: parsed.cookDuration,
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

    /// Decodes common HTML entities in a string.
    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&quot;", "\""), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&apos;", "'"), ("&#39;", "'"), ("&#x27;", "'"),
            ("&#x2F;", "/"), ("&#47;", "/"),
            ("&nbsp;", " "), ("&#160;", " "),
            ("&ndash;", "–"), ("&mdash;", "—"),
            ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}"),
            ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
            ("&hellip;", "…"),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Decode decimal numeric character references like &#8220;
        if let regex = try? NSRegularExpression(pattern: #"&#(\d+);"#) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range).reversed()
            for match in matches {
                if let codeRange = Range(match.range(at: 1), in: result),
                   let code = UInt32(result[codeRange]),
                   let scalar = Unicode.Scalar(code) {
                    let charRange = Range(match.range, in: result)!
                    result.replaceSubrange(charRange, with: String(Character(scalar)))
                }
            }
        }
        // Decode hex numeric character references like &#x2022; &#x1F35E;
        if let regex = try? NSRegularExpression(pattern: #"&#[xX]([0-9a-fA-F]+);"#) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range).reversed()
            for match in matches {
                if let codeRange = Range(match.range(at: 1), in: result),
                   let code = UInt32(result[codeRange], radix: 16),
                   let scalar = Unicode.Scalar(code) {
                    let charRange = Range(match.range, in: result)!
                    result.replaceSubrange(charRange, with: String(Character(scalar)))
                }
            }
        }
        return result
    }

    /// Cleans up Instagram's og:description format.
    /// Input often looks like: "71K likes, 490 comments - maxiskitchen on January 12, 2025: &quot;Chipotle..."
    private static func cleanInstagramDescription(_ desc: String) -> String {
        // First decode HTML entities
        var text = decodeHTMLEntities(desc)

        // Remove the "N likes, N comments - " prefix pattern
        // Handles suffixes like K, M (e.g., "71K likes") and date patterns
        if let regex = try? NSRegularExpression(
            pattern: #"^[\d,.]+[KkMm]?\s*likes?,?\s*[\d,.]+[KkMm]?\s*comments?\s*[-–—]\s*"#,
            options: .caseInsensitive
        ) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }

        // Remove "username on Month DD, YYYY: " pattern
        if let regex = try? NSRegularExpression(
            pattern: #"^.*?\bon \w+ \d{1,2}, \d{4}:\s*"#,
            options: .caseInsensitive
        ) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }

        // Also handle: "Author on Instagram: \"caption\""
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
        var title = decodeHTMLEntities(ogTitle)

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

    /// Strips the "Author on Instagram: \"caption\"" wrapper that the oEmbed API
    /// sometimes returns in the `title` field.
    static func stripInstagramOEmbedWrapper(_ text: String) -> String {
        // Pattern: "Name on Instagram: \"actual caption\""
        if let regex = try? NSRegularExpression(
            pattern: #"^.{1,50}\bon Instagram:\s*"?"#,
            options: .caseInsensitive
        ) {
            let range = NSRange(text.startIndex..., in: text)
            let stripped = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            if !stripped.isEmpty {
                var result = stripped
                // Remove trailing quote if the wrapper had an opening quote
                if result.hasSuffix("\"") || result.hasSuffix("\u{201D}") {
                    result = String(result.dropLast())
                }
                return result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    struct InstagramRecipeParts {
        var title: String = ""
        var ingredientGroups: [ParsedIngredientGroup] = []
        var directions: [String] = []
        var notes: String = ""
        var prepDuration: TimeInterval = 0
        var cookDuration: TimeInterval = 0
    }

    // Numbered emoji keycaps used for direction steps
    private static let numberedEmoji: [String] = [
        "1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣", "🔟"
    ]

    /// Normalizes an Instagram caption into discrete lines.
    /// Splits on `▪️` / `•` bullets, numbered emoji, and newlines so that
    /// each ingredient or direction becomes its own line.
    private static func normalizeInstagramCaption(_ caption: String) -> String {
        var text = caption
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Replace inline bullet separators with newlines
        // ■ (U+25A0 BLACK SQUARE) is used by many Instagram recipe accounts (e.g. @maxiskitchen)
        for bullet in ["■", "▪️", "•", "▫️", "◾", "◽", "🔸", "🔹", "➡️", "👉"] {
            text = text.replacingOccurrences(of: bullet, with: "\n")
        }

        // Insert newline before each numbered emoji so directions get their own lines
        for emoji in numberedEmoji {
            text = text.replacingOccurrences(of: emoji, with: "\n" + emoji)
        }

        // Insert newline before timer emoji (often used for cook/prep time)
        text = text.replacingOccurrences(of: "⏲", with: "\n⏲")
        text = text.replacingOccurrences(of: "⏱", with: "\n⏱")
        text = text.replacingOccurrences(of: "⏰", with: "\n⏰")

        // Insert newline before common modifier/note emoji that start a new thought
        for emoji in ["🌱", "💡", "📝", "⭐", "❗", "‼️", "⚠️"] {
            text = text.replacingOccurrences(of: emoji, with: "\n" + emoji)
        }

        return text
    }

    /// Returns true if the line looks like a numbered direction (starts with a digit-keycap emoji or "1.", "Step 1", etc.).
    private static func isDirectionLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for emoji in numberedEmoji {
            if trimmed.hasPrefix(emoji) { return true }
        }
        if let regex = try? NSRegularExpression(pattern: #"^(?:step\s*)?\d+[\.\)\:\-]\s+"#, options: .caseInsensitive),
           regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }
        return false
    }

    /// Strips numbered-emoji or "Step N:" prefixes from a direction line.
    private static func stripDirectionPrefix(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        // Strip keycap emoji prefix
        for emoji in numberedEmoji {
            if text.hasPrefix(emoji) {
                text = String(text.dropFirst(emoji.count)).trimmingCharacters(in: .whitespaces)
                // Also strip a trailing period/colon/dash right after the emoji
                if let first = text.first, ".:-)– ".contains(first) {
                    text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                return text
            }
        }
        // Strip textual step number prefix
        if let regex = try? NSRegularExpression(pattern: #"^(?:step\s*)?\d+[\.\)\:\-]\s*"#, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Tries to parse a time string like "10 minute total prep + 45 minute cook time"
    /// and returns (prepSeconds, cookSeconds).
    private static func parseInstagramTimeInfo(_ line: String) -> (TimeInterval, TimeInterval)? {
        let lower = line.lowercased()
        guard lower.contains("min") || lower.contains("hour") || lower.contains("hr") else { return nil }

        var prep: TimeInterval = 0
        var cook: TimeInterval = 0

        // Match patterns like "10 minute prep", "45 minute cook", "1 hour cook"
        let pattern = #"(\d+)\s*(?:minute|min|hour|hr)s?\s*(?:total\s*)?(\w+)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(lower.startIndex..., in: lower)
            let matches = regex.matches(in: lower, range: range)
            for match in matches {
                guard let numRange = Range(match.range(at: 1), in: lower),
                      let labelRange = Range(match.range(at: 2), in: lower) else { continue }
                let num = Double(lower[numRange]) ?? 0
                let label = String(lower[labelRange])
                let isHours = lower[Range(match.range, in: lower)!].contains("hour") || lower[Range(match.range, in: lower)!].contains("hr")
                let seconds = num * (isHours ? 3600 : 60)
                if label.hasPrefix("prep") {
                    prep = seconds
                } else if label.hasPrefix("cook") {
                    cook = seconds
                }
            }
        }

        return (prep > 0 || cook > 0) ? (prep, cook) : nil
    }

    /// Parses unstructured Instagram caption text to extract recipe components.
    ///
    /// Handles two main formats seen in the wild:
    /// 1. **Inline bullets** – `GroupName:▪️item1▪️item2▪️` with `1️⃣`-prefixed directions
    /// 2. **Line-per-item** – newline-separated with keyword headers ("Ingredients:", "Directions:", etc.)
    static func parseInstagramCaption(_ caption: String) -> InstagramRecipeParts {
        guard !caption.isEmpty else { return InstagramRecipeParts() }

        var result = InstagramRecipeParts()

        // Normalize: split inline bullets and numbered emoji into separate lines
        let normalized = normalizeInstagramCaption(caption)
        let lines = normalized.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Classify each line into sections
        enum Section { case preamble, ingredients, directions, notes }
        var currentSection: Section = .preamble
        var preambleLines: [String] = []
        var directionLines: [String] = []
        var noteLines: [String] = []
        var groups: [(name: String, items: [String])] = []
        var currentGroupName = ""
        var currentGroupItems: [String] = []
        var prepDuration: TimeInterval = 0
        var cookDuration: TimeInterval = 0

        let ingredientHeaders: Set<String> = [
            "ingredients", "ingredient", "what you need", "what you'll need",
            "you'll need", "you will need", "shopping list", "for the recipe"
        ]
        let directionHeaders: Set<String> = [
            "directions", "direction", "instructions", "instruction", "steps",
            "method", "how to make", "how to", "preparation",
            "to make", "procedure"
        ]
        let noteHeaders: Set<String> = [
            "notes", "note", "tips", "tip", "variations", "serving",
            "nutrition", "storage", "substitutions"
        ]

        /// Strips emoji and punctuation to get the keyword core of a potential header.
        func headerKeyword(_ line: String) -> String {
            line.lowercased()
                .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                .trimmingCharacters(in: .whitespaces)
        }

        for line in lines {
            let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stripped.isEmpty else { continue }

            // ── Detect explicit section keyword headers ──
            let keyword = headerKeyword(stripped)
            if ingredientHeaders.contains(keyword) {
                flushGroup(&currentGroupName, &currentGroupItems, &groups)
                currentSection = .ingredients
                continue
            }
            if directionHeaders.contains(keyword) {
                flushGroup(&currentGroupName, &currentGroupItems, &groups)
                currentSection = .directions
                continue
            }
            if noteHeaders.contains(keyword) {
                flushGroup(&currentGroupName, &currentGroupItems, &groups)
                currentSection = .notes
                continue
            }

            // ── Detect "Header: first-item" — header keyword and content on the same line ──
            // e.g. "Ingredients: 1 tsp yeast" (after bullet-splitting) or "Instructions: Mix..."
            let strippedLower = stripped.lowercased()
            if let match = ingredientHeaders.first(where: { strippedLower.hasPrefix($0 + ":") }) {
                let rest = String(stripped.dropFirst(match.count + 1)).trimmingCharacters(in: .whitespaces)
                flushGroup(&currentGroupName, &currentGroupItems, &groups)
                currentSection = .ingredients
                let cleaned = stripLeadingBullets(rest)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-–•*▪️✅☑️🟢▫️◾◽"))
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty { currentGroupItems.append(cleaned) }
                continue
            }
            if let match = directionHeaders.first(where: { strippedLower.hasPrefix($0 + ":") }) {
                let rest = String(stripped.dropFirst(match.count + 1)).trimmingCharacters(in: .whitespaces)
                flushGroup(&currentGroupName, &currentGroupItems, &groups)
                currentSection = .directions
                let dirText = stripDirectionPrefix(rest)
                if !dirText.isEmpty { directionLines.append(dirText) }
                continue
            }
            if let match = noteHeaders.first(where: { strippedLower.hasPrefix($0 + ":") }) {
                let rest = String(stripped.dropFirst(match.count + 1)).trimmingCharacters(in: .whitespaces)
                flushGroup(&currentGroupName, &currentGroupItems, &groups)
                currentSection = .notes
                if !rest.isEmpty { noteLines.append(rest) }
                continue
            }

            // ── Detect note/modifier emoji lines (e.g. "🌱Vegan Modification: ...") ──
            let noteEmojiPrefixes = ["🌱", "💡", "📝", "❗", "‼️", "⚠️"]
            if noteEmojiPrefixes.contains(where: { stripped.hasPrefix($0) }) {
                flushGroup(&currentGroupName, &currentGroupItems, &groups)
                noteLines.append(stripped)
                currentSection = .notes
                continue
            }

            // ── Detect numbered-emoji directions regardless of current section ──
            if isDirectionLine(stripped) {
                // Flush any open ingredient group first
                if currentSection == .ingredients || currentSection == .preamble {
                    flushGroup(&currentGroupName, &currentGroupItems, &groups)
                }
                currentSection = .directions
                let dirText = stripDirectionPrefix(stripped)
                if !dirText.isEmpty {
                    directionLines.append(dirText)
                }
                continue
            }

            // ── Detect ingredient group header: "GroupName:▪️..." becomes "GroupName:" after normalization ──
            // A short line ending with ":" that doesn't match a keyword header is likely a group name
            if stripped.hasSuffix(":") {
                let possibleName = String(stripped.dropLast()).trimmingCharacters(in: .whitespaces)
                let possibleKeyword = headerKeyword(possibleName)
                if possibleName.count < 50
                    && !ingredientHeaders.contains(possibleKeyword)
                    && !directionHeaders.contains(possibleKeyword)
                    && !noteHeaders.contains(possibleKeyword) {
                    // Treat as a new ingredient group header
                    flushGroup(&currentGroupName, &currentGroupItems, &groups)
                    currentGroupName = possibleName
                    currentSection = .ingredients
                    continue
                }
            }

            // ── Detect time info lines ──
            if stripped.hasPrefix("⏲") || stripped.hasPrefix("⏱") || stripped.hasPrefix("⏰") {
                if let (p, c) = parseInstagramTimeInfo(stripped) {
                    prepDuration = p; cookDuration = c
                }
                continue
            }

            // ── Detect "Recipe serves N" → notes ──
            if stripped.lowercased().hasPrefix("recipe serves") || stripped.lowercased().hasPrefix("serves ") {
                flushGroup(&currentGroupName, &currentGroupItems, &groups)
                noteLines.append(stripped)
                currentSection = .notes
                continue
            }

            // ── Skip promotional / boilerplate lines ──
            // Normalize Mathematical Bold/Italic Unicode letters (U+1D400-U+1D7FF) to ASCII
            // so "𝐋𝐈𝐍𝐊 𝐈𝐍 𝐌𝐘 𝐁𝐈𝐎" matches the same as "LINK IN MY BIO".
            let lower = flattenMathematicalUnicode(stripped).lowercased()
            if lower.contains("subscribe to my newsletter") || lower.contains("link in my bio")
                || lower.contains("link in bio") || lower.contains("delivered to your inbox")
                || lower.contains("printable pdf") || lower.contains("full recipe on my blog")
                || lower.contains("full recipe on my website") {
                continue
            }

            // ── Accumulate into the current section ──
            switch currentSection {
            case .preamble:
                preambleLines.append(stripped)
            case .ingredients:
                let cleaned = stripLeadingBullets(stripped)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-–•*▪️✅☑️🟢▫️◾◽"))
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty {
                    currentGroupItems.append(cleaned)
                }
            case .directions:
                if isHashtagLine(stripped) { continue }
                let cleaned = stripDirectionPrefix(stripped)
                if !cleaned.isEmpty {
                    directionLines.append(cleaned)
                }
            case .notes:
                noteLines.append(stripped)
            }
        }

        // Flush last ingredient group
        flushGroup(&currentGroupName, &currentGroupItems, &groups)

        // ── Title ──
        if let first = preambleLines.first {
            result.title = removeHashtags(first)
                // Strip trailing decorative emoji
                .trimmingCharacters(in: CharacterSet(charactersIn: "✨🔥💫⭐🍴🥘🍳"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if result.title.count > 80 {
                let truncated = String(result.title.prefix(80))
                if let lastSpace = truncated.lastIndex(of: " ") {
                    result.title = String(truncated[..<lastSpace]) + "…"
                }
            }
        }

        // Remaining preamble lines → notes
        if preambleLines.count > 1 {
            let extra = preambleLines.dropFirst().filter { !isHashtagLine($0) }
            if !extra.isEmpty { noteLines.insert(contentsOf: extra, at: 0) }
        }

        result.ingredientGroups = groups.map { ParsedIngredientGroup(name: $0.name, ingredients: $0.items) }
        result.directions = directionLines
        result.notes = noteLines.filter { !isHashtagLine($0) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        result.prepDuration = prepDuration
        result.cookDuration = cookDuration

        return result
    }

    /// Flush the current ingredient group into the groups array.
    private static func flushGroup(
        _ name: inout String,
        _ items: inout [String],
        _ groups: inout [(name: String, items: [String])]
    ) {
        if !items.isEmpty {
            groups.append((name: name, items: items))
            items = []
        }
        name = ""
    }

    /// Maps Mathematical Bold/Italic/Script Unicode characters (U+1D400-U+1D7FF) to their
    /// plain ASCII equivalents so boilerplate checks work regardless of Unicode styling.
    /// e.g. "𝐋𝐈𝐍𝐊 𝐈𝐍 𝐌𝐘 𝐁𝐈𝐎" → "LINK IN MY BIO"
    private static func flattenMathematicalUnicode(_ text: String) -> String {
        String(text.unicodeScalars.map { scalar -> Unicode.Scalar in
            let v = scalar.value
            guard v >= 0x1D400, v <= 0x1D7FF else { return scalar }
            // Each style group in the block has 26 capitals then 26 smalls (with a few
            // historical-compat exceptions we ignore). Offset within the 52-char group:
            let offset = (v - 0x1D400) % 52
            if offset < 26 {
                return Unicode.Scalar(UInt32(("A" as Unicode.Scalar).value) + offset)!
            } else {
                return Unicode.Scalar(UInt32(("a" as Unicode.Scalar).value) + (offset - 26))!
            }
        }.map(Character.init))
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
                return decodeHTMLEntities(String(html[contentRange]))
            }
        }

        let pattern2 = #"<meta[^>]*content\s*=\s*["']([^"']*)["'][^>]*(?:property|name)\s*=\s*["']\#(property)["'][^>]*>"#
        if let regex = try? NSRegularExpression(pattern: pattern2, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let contentRange = Range(match.range(at: 1), in: html) {
                return decodeHTMLEntities(String(html[contentRange]))
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
