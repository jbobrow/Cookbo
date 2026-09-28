import Foundation

struct RecipeMarkdownSerializer {

    // MARK: - Serialize

    static func serialize(_ recipe: Recipe) -> String {
        var lines: [String] = []

        // YAML front matter
        lines.append("---")
        lines.append("title: \(yamlEscape(recipe.title))")
        lines.append("id: \(recipe.id.uuidString)")
        if let imageName = recipe.imageName {
            lines.append("imageName: \(imageName)")
        }
        lines.append("dateCreated: \(formatDate(recipe.dateCreated))")
        if !recipe.datesCooked.isEmpty {
            lines.append("datesCooked:")
            for date in recipe.datesCooked {
                lines.append("  - \(formatDate(date))")
            }
        }
        lines.append("rating: \(recipe.rating)")
        lines.append("prepDuration: \(formatDuration(recipe.prepDuration))")
        lines.append("cookDuration: \(formatDuration(recipe.cookDuration))")
        if !recipe.sourceURL.isEmpty {
            lines.append("sourceURL: \(yamlEscape(recipe.sourceURL))")
        }
        if let categoryID = recipe.categoryID {
            lines.append("categoryID: \(categoryID.uuidString)")
        }
        if let lastViewed = recipe.dateLastViewed {
            lines.append("lastViewed: \(formatTimestamp(lastViewed))")
        }
        if recipe.isInThisWeek {
            lines.append("thisWeek: true")
        }
        lines.append("---")
        lines.append("")

        // Title
        lines.append("# \(recipe.title)")
        lines.append("")

        // Notes
        if !recipe.notes.isEmpty {
            lines.append("## Notes")
            lines.append("")
            lines.append(recipe.notes)
            lines.append("")
        }

        // Ingredients
        let allIngredients = recipe.allIngredients
        if !allIngredients.isEmpty {
            lines.append("## Ingredients")
            lines.append("")
            let hasMultipleSections = recipe.ingredientSections.count > 1
            let hasNamedSection = recipe.ingredientSections.contains { !$0.name.isEmpty }
            if hasMultipleSections || hasNamedSection {
                for section in recipe.ingredientSections {
                    let sectionName = section.name.isEmpty ? "Other" : section.name
                    lines.append("### \(sectionName)")
                    lines.append("")
                    for ingredient in section.ingredients {
                        let check = ingredient.isChecked ? "x" : " "
                        lines.append("- [\(check)] \(ingredient.text)")
                    }
                    lines.append("")
                }
            } else {
                for ingredient in allIngredients {
                    let check = ingredient.isChecked ? "x" : " "
                    lines.append("- [\(check)] \(ingredient.text)")
                }
                lines.append("")
            }
        }

        // Directions
        if !recipe.directions.isEmpty {
            lines.append("## Directions")
            lines.append("")
            for direction in recipe.directions.sorted(by: { $0.order < $1.order }) {
                let check = direction.isCompleted ? "x" : " "
                lines.append("- [\(check)] **Step \(direction.order):** \(direction.text)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Deserialize

    static func deserialize(_ content: String) -> Recipe? {
        guard let (frontMatter, body) = splitFrontMatter(content) else { return nil }

        let yaml = parseYAML(frontMatter)

        guard let idString = yaml["id"], let id = UUID(uuidString: idString) else { return nil }

        let title = yaml["title"] ?? ""
        let imageName = yaml["imageName"]
        let dateCreated = parseDate(yaml["dateCreated"] ?? "") ?? Date()
        let datesCooked = parseDateArray(frontMatter, key: "datesCooked")
        let rating = Int(yaml["rating"] ?? "0") ?? 0
        let prepDuration = parseDuration(yaml["prepDuration"] ?? "0")
        let cookDuration = parseDuration(yaml["cookDuration"] ?? "0")
        let sourceURL = yaml["sourceURL"] ?? ""
        let categoryID: UUID? = yaml["categoryID"].flatMap { UUID(uuidString: $0) }
        let dateLastViewed = yaml["lastViewed"].flatMap { parseTimestamp($0) }
        let isInThisWeek = (yaml["thisWeek"] ?? "") == "true"

        // Parse body sections
        let sections = parseSections(body)
        let notes = sections["Notes"] ?? sections["About"] ?? ""
        let ingredientSections = parseIngredientSections(sections["Ingredients"] ?? "")
        let directions = parseDirections(sections["Directions"] ?? "")

        return Recipe(
            id: id,
            title: title,
            imageName: imageName,
            ingredientSections: ingredientSections,
            directions: directions,
            dateCreated: dateCreated,
            datesCooked: datesCooked,
            sourceURL: sourceURL,
            rating: rating,
            prepDuration: prepDuration,
            cookDuration: cookDuration,
            notes: notes,
            categoryID: categoryID,
            dateLastViewed: dateLastViewed,
            isInThisWeek: isInThisWeek
        )
    }

    // MARK: - YAML Helpers

    private static func yamlEscape(_ string: String) -> String {
        if string.contains(":") || string.contains("#") || string.contains("\"")
            || string.hasPrefix(" ") || string.hasSuffix(" ") || string.hasPrefix("'") {
            let escaped = string.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return string
    }

    private static func splitFrontMatter(_ content: String) -> (String, String)? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return nil }

        let afterFirst = String(trimmed.dropFirst(3))
        guard let endRange = afterFirst.range(of: "\n---") else { return nil }

        let frontMatter = String(afterFirst[afterFirst.startIndex..<endRange.lowerBound])
        let body = String(afterFirst[endRange.upperBound...])

        return (frontMatter, body)
    }

    private static func parseYAML(_ yaml: String) -> [String: String] {
        var result: [String: String] = [:]

        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("- ") { continue }

            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colonIndex])
                .trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)

            // Remove surrounding quotes
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
                value = value.replacingOccurrences(of: "\\\"", with: "\"")
            }

            if value.isEmpty { continue }

            result[key] = value
        }

        return result
    }

    private static func parseDateArray(_ yaml: String, key: String) -> [Date] {
        var dates: [Date] = []
        var inArray = false

        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("\(key):") {
                inArray = true
                continue
            }

            if inArray {
                if trimmed.hasPrefix("- ") {
                    let dateStr = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if let date = parseDate(dateStr) {
                        dates.append(date)
                    }
                } else if !trimmed.isEmpty {
                    break
                }
            }
        }

        return dates
    }

    // MARK: - Date / Duration Formatting

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Timestamps need the time of day, which the date-only format above drops.
    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static func formatTimestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    /// Reads a full timestamp, falling back to a plain `yyyy-MM-dd` so a
    /// hand-edited file still parses.
    private static func parseTimestamp(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        return timestampFormatter.date(from: trimmed) ?? parseDate(trimmed)
    }

    private static func parseDate(_ string: String) -> Date? {
        dateFormatter.date(from: string.trimmingCharacters(in: .whitespaces))
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        return "\(totalMinutes) minutes"
    }

    private static func parseDuration(_ string: String) -> TimeInterval {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        var totalMinutes = 0

        if let hourRange = trimmed.range(of: #"(\d+)\s*hours?"#, options: .regularExpression) {
            let hourStr = String(trimmed[hourRange]).filter { $0.isNumber }
            totalMinutes += (Int(hourStr) ?? 0) * 60
        }

        if let minRange = trimmed.range(of: #"(\d+)\s*minutes?"#, options: .regularExpression) {
            let minStr = String(trimmed[minRange]).filter { $0.isNumber }
            totalMinutes += Int(minStr) ?? 0
        }

        // Plain number with no unit — assume minutes
        if totalMinutes == 0, let n = Int(trimmed) {
            totalMinutes = n
        }

        return TimeInterval(totalMinutes * 60)
    }

    // MARK: - Markdown Body Parsing

    private static let knownSections: Set<String> = ["Notes", "About", "Ingredients", "Directions"]

    private static func parseSections(_ body: String) -> [String: String] {
        var sections: [String: String] = [:]
        var currentSection: String?
        var currentContent: [String] = []

        for line in body.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                let name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if knownSections.contains(name) {
                    if let section = currentSection {
                        sections[section] = currentContent.joined(separator: "\n")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    currentSection = name
                    currentContent = []
                    continue
                }
            }

            // Skip the top-level title heading
            if line.hasPrefix("# ") && currentSection == nil { continue }

            currentContent.append(line)
        }

        if let section = currentSection {
            sections[section] = currentContent.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return sections
    }

    private static func parseIngredientSections(_ text: String) -> [IngredientSection] {
        var sections: [IngredientSection] = []
        var currentName = ""
        var currentIngredients: [Ingredient] = []

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("### ") {
                // Flush current section if it has ingredients
                if !currentIngredients.isEmpty {
                    sections.append(IngredientSection(name: currentName, ingredients: currentIngredients))
                    currentIngredients = []
                }
                currentName = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                currentIngredients.append(Ingredient(text: String(trimmed.dropFirst(6)), isChecked: true))
            } else if trimmed.hasPrefix("- [ ] ") {
                currentIngredients.append(Ingredient(text: String(trimmed.dropFirst(6)), isChecked: false))
            }
        }

        // Flush final section
        if !currentIngredients.isEmpty {
            sections.append(IngredientSection(name: currentName, ingredients: currentIngredients))
        }

        return sections
    }

    private static func parseDirections(_ text: String) -> [Direction] {
        var directions: [Direction] = []
        var currentText: String?
        var currentChecked = false

        func flush() {
            guard let t = currentText else { return }
            let order = directions.count + 1
            directions.append(Direction(text: stripStepPrefix(t), order: order, isCompleted: currentChecked))
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                flush()
                currentText = String(trimmed.dropFirst(6))
                currentChecked = true
            } else if trimmed.hasPrefix("- [ ] ") {
                flush()
                currentText = String(trimmed.dropFirst(6))
                currentChecked = false
            } else if !trimmed.isEmpty, currentText != nil {
                currentText! += " " + trimmed
            }
        }

        flush()
        return directions
    }

    private static func stripStepPrefix(_ text: String) -> String {
        // Strip our standard format: **Step N:**
        if let range = text.range(of: #"^\*\*Step \d+:\*\*\s*"#, options: .regularExpression) {
            return String(text[range.upperBound...])
        }
        return text
    }
}
