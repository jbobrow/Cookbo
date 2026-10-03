import Foundation

// MARK: - Model

/// What cook mode knows about each step of a recipe: which ingredients go in
/// and how much, what was set aside in an earlier step, and an optional
/// shorter rewrite of the step.
///
/// Built from the recipe text by `CookPlanner.heuristicPlan(for:)`, then
/// refined by the on-device model where Apple Intelligence is available
/// (`OnDeviceCookPlanner`). It's derived data, so it lives in a cache and is
/// never written into the recipe's Markdown file.
nonisolated struct CookPlan: Codable, Equatable {
    enum Source: String, Codable {
        case heuristic
        case onDevice
    }

    var source: Source
    var steps: [CookStep]
    /// The on-device model's one-word names, estimates and overlaps for the
    /// overview, one per step; nil until it has run.
    var overviewHints: [OverviewHint]? = nil

    /// The step where an ingredient (an index into `Recipe.allIngredients`)
    /// first goes in. Next checks it off there.
    func firstUseStep(ofIngredient index: Int) -> Int? {
        steps.firstIndex { step in
            step.items.contains { $0.ingredientIndex == index && !$0.isPrepared }
        }
    }

    /// The ingredients that first go in at `step`.
    func ingredientsFirstUsed(inStep step: Int) -> [Int] {
        guard steps.indices.contains(step) else { return [] }
        let indices = steps[step].items.compactMap { $0.isPrepared ? nil : $0.ingredientIndex }
        return Array(Set(indices)).filter { firstUseStep(ofIngredient: $0) == step }.sorted()
    }
}

nonisolated struct CookStep: Codable, Equatable {
    /// A shorter rewrite that kept every number from the original.
    var shortText: String?
    /// What to have on hand for this step, in the order the step mentions it.
    var items: [CookStepItem]
}

nonisolated struct CookStepItem: Codable, Equatable {
    /// Index into `Recipe.allIngredients`; nil for something made in an earlier step.
    var ingredientIndex: Int?
    /// "¼ cup", or empty when the step doesn't say.
    var amount: String
    /// "olive oil"
    var name: String
    /// "halved and thinly sliced", "optional", "for serving"; may be empty.
    var note: String
    /// Set when this was already prepared in an earlier step (0-based). It
    /// shows as done, with "From step N".
    var preparedInStep: Int?
    /// Words to highlight in the step text.
    var highlightTerms: [String]

    var isPrepared: Bool { preparedInStep != nil }
}

/// A cooking time mentioned in a step, like "20 to 25 minutes".
nonisolated struct CookDuration: Equatable {
    var range: Range<String.Index>
    /// "20–25 min"
    var label: String
    /// The low end, so a timer never runs past the earliest check.
    var seconds: Int
    /// The high end of a range ("20 to 25 minutes"), if there is one.
    var upperSeconds: Int? = nil

    /// How long "More Minutes" adds once the timer goes off: the rest of the
    /// recipe's range, or 5 minutes.
    var extraSeconds: Int {
        if let upper = upperSeconds, upper > seconds { return upper - seconds }
        return 300
    }
}

/// What the on-device model suggested for one step, before it's checked
/// against the recipe text. Kept free of FoundationModels so it can be tested.
nonisolated struct SuggestedStep {
    struct Use {
        var ingredientNumber: Int   // 1-based, as numbered in the prompt
        var amount: String
        var name: String
    }

    struct CarryOver {
        var name: String
        var stepNumber: Int         // 1-based
    }

    var shortText: String
    var uses: [Use]
    var carryOvers: [CarryOver]
}

// MARK: - Recipe progress helpers

extension Recipe {
    var orderedDirections: [Direction] {
        directions.sorted { $0.order < $1.order }
    }

    /// Where cook mode picks up: the first step not yet checked off, or
    /// `directions.count` when every step is done.
    var firstIncompleteStepIndex: Int {
        orderedDirections.firstIndex { !$0.isCompleted } ?? directions.count
    }

    mutating func setStepCompleted(_ step: Int, _ completed: Bool) {
        let ordered = orderedDirections
        guard ordered.indices.contains(step),
              let index = directions.firstIndex(where: { $0.id == ordered[step].id }) else { return }
        directions[index].isCompleted = completed
    }

    func isIngredientChecked(_ flatIndex: Int) -> Bool {
        guard let (s, i) = sectionPosition(ofIngredient: flatIndex) else { return false }
        return ingredientSections[s].ingredients[i].isChecked
    }

    mutating func setIngredientChecked(_ flatIndex: Int, _ checked: Bool) {
        guard let (s, i) = sectionPosition(ofIngredient: flatIndex) else { return }
        ingredientSections[s].ingredients[i].isChecked = checked
    }

    private func sectionPosition(ofIngredient flatIndex: Int) -> (Int, Int)? {
        var remaining = flatIndex
        for (s, section) in ingredientSections.enumerated() {
            if remaining < section.ingredients.count { return (s, remaining) }
            remaining -= section.ingredients.count
        }
        return nil
    }
}

// MARK: - Planner

/// Builds a `CookPlan` from recipe text alone, and checks what the on-device
/// model suggests before it's used.
nonisolated enum CookPlanner {

    /// An ingredient line split into what cook mode shows and the words used
    /// to find it in the steps.
    struct ParsedIngredient: Equatable {
        var amount: String
        var name: String
        var note: String
        var terms: [String]
        /// Used more than once on purpose: "plus more for serving", "divided",
        /// salt and pepper. Later mentions are new additions, not leftovers.
        var isReusable: Bool
        /// "for serving" or "to taste", shown on those later additions.
        var reuseNote: String
    }

    // MARK: Building a plan

    static func heuristicPlan(for recipe: Recipe) -> CookPlan {
        let parsed = recipe.allIngredients.map { parseIngredient($0.text) }
        let texts = recipe.orderedDirections.map { $0.text.sanitizedForDisplay }
        var firstUse: [Int: Int] = [:]
        var steps: [CookStep] = []

        for (stepIndex, text) in texts.enumerated() {
            var items: [CookStepItem] = []
            var seen = Set<Int>()

            for match in ingredientMatches(in: text, parsed: parsed) where !seen.contains(match.ingredient) {
                let ingredient = parsed[match.ingredient]
                let matchedText = String(text[match.range])
                let stepAmount = amount(before: match.range, in: text)

                if firstUse[match.ingredient] == nil {
                    firstUse[match.ingredient] = stepIndex
                    seen.insert(match.ingredient)
                    items.append(CookStepItem(
                        ingredientIndex: match.ingredient,
                        amount: stepAmount ?? ingredient.amount,
                        name: stepAmount == nil ? ingredient.name : matchedText,
                        note: ingredient.note,
                        preparedInStep: nil,
                        highlightTerms: ingredient.terms
                    ))
                } else if stepAmount != nil || ingredient.isReusable {
                    // Another measured addition, like "½ teaspoon salt" or oil for serving
                    seen.insert(match.ingredient)
                    items.append(CookStepItem(
                        ingredientIndex: match.ingredient,
                        amount: stepAmount ?? "",
                        name: stepAmount == nil ? ingredient.name : matchedText,
                        note: stepAmount == nil ? ingredient.reuseNote : "",
                        preparedInStep: nil,
                        highlightTerms: ingredient.terms
                    ))
                }
                // Otherwise it's a passing mention ("while the shallots cook"): leave it out.
            }
            steps.append(CookStep(shortText: nil, items: items))
        }

        // "Keep the liquid — you'll need it in step 6" shows up on step 6 as well
        for (stepIndex, text) in texts.enumerated() {
            for reference in stepReferences(in: text) where reference.step != stepIndex && steps.indices.contains(reference.step) {
                if reference.step > stepIndex {
                    let label = setAsideLabel(from: reference.sentence) ?? "What you set aside"
                    steps[reference.step].items.append(CookStepItem(
                        ingredientIndex: nil, amount: "", name: label, note: "",
                        preparedInStep: stepIndex, highlightTerms: []
                    ))
                } else if !steps[stepIndex].items.contains(where: { $0.preparedInStep == reference.step }) {
                    steps[stepIndex].items.append(CookStepItem(
                        ingredientIndex: nil, amount: "", name: "What you made",
                        note: "", preparedInStep: reference.step, highlightTerms: []
                    ))
                }
            }
        }

        return CookPlan(source: .heuristic, steps: steps)
    }

    /// Folds a model suggestion for one step into the plan, keeping only what
    /// holds up against the recipe text: the model can choose among the
    /// ingredients a step mentions and name them, but never add one the step
    /// doesn't mention. `firstUse` carries which step each ingredient first
    /// went in, across calls.
    static func merge(
        _ suggestion: SuggestedStep,
        into heuristic: CookStep,
        stepIndex: Int,
        stepTexts: [String],
        ingredientTexts: [String],
        firstUse: inout [Int: Int]
    ) -> CookStep {
        let original = stepTexts[stepIndex]
        let parsed = ingredientTexts.map { parseIngredient($0) }
        let mentioned = Set(ingredientMatches(in: original, parsed: parsed).map { $0.ingredient })
        var items: [CookStepItem] = []
        var seen = Set<Int>()

        for use in suggestion.uses {
            guard let index = resolveIngredient(use, parsed: parsed, mentioned: mentioned),
                  !seen.contains(index) else { continue }
            seen.insert(index)
            let ingredient = parsed[index]

            let amount = use.amount.trimmingCharacters(in: .whitespaces)
            let allowedNumbers = numbers(in: original).union(numbers(in: ingredientTexts[index]))
            let trustedAmount = amount.isEmpty || !numbers(in: amount).isSubset(of: allowedNumbers) ? nil : prettyQuantity(amount)

            let suggestedName = use.name.trimmingCharacters(in: .whitespaces)
            let nameFits = suggestedName.count <= 40 && !highlightRanges(in: suggestedName, terms: ingredient.terms).isEmpty
            // A bare count needs the full name to read right: "3 large garlic cloves", not "3 garlic"
            let amountShown = trustedAmount ?? ingredient.amount
            let isBareCount = !amountShown.isEmpty && amountShown.allSatisfy { $0.isNumber || "½¼¾⅓⅔⅛–/. ".contains($0) }
            let name = nameFits && !isBareCount ? suggestedName : ingredient.name
            let terms = uniqued(ingredient.terms + (nameFits ? [suggestedName.lowercased()] : []))

            if let first = firstUse[index], first < stepIndex {
                if trustedAmount != nil || ingredient.isReusable {
                    items.append(CookStepItem(
                        ingredientIndex: index, amount: trustedAmount ?? "", name: name,
                        note: trustedAmount == nil ? ingredient.reuseNote : "",
                        preparedInStep: nil, highlightTerms: terms
                    ))
                } else {
                    // "the drained tomatoes": already done in an earlier step
                    items.append(CookStepItem(
                        ingredientIndex: index, amount: "", name: name, note: "",
                        preparedInStep: first, highlightTerms: terms
                    ))
                }
            } else {
                firstUse[index] = stepIndex
                items.append(CookStepItem(
                    ingredientIndex: index, amount: trustedAmount ?? ingredient.amount, name: name,
                    note: ingredient.note, preparedInStep: nil, highlightTerms: terms
                ))
            }
        }

        // Keep anything the text plainly names that the model missed
        for item in heuristic.items {
            if let index = item.ingredientIndex {
                guard !seen.contains(index) else { continue }
                seen.insert(index)
                if item.isPrepared == false, firstUse[index] == nil { firstUse[index] = stepIndex }
                items.append(item)
            }
        }

        var carried = Set(items.compactMap { $0.ingredientIndex == nil ? $0.preparedInStep : nil })
        for carry in suggestion.carryOvers {
            let from = carry.stepNumber - 1
            let name = carry.name.trimmingCharacters(in: .whitespaces)
            guard from >= 0, from < stepIndex, !name.isEmpty, name.count <= 40, !carried.contains(from),
                  isMentioned(name, in: stepTexts[from]), isMentioned(name, in: original),
                  // "drained tomatoes" when the tomatoes already have a row
                  !items.contains(where: { $0.ingredientIndex != nil && !highlightRanges(in: name, terms: $0.highlightTerms).isEmpty })
            else { continue }
            carried.insert(from)
            items.append(CookStepItem(
                ingredientIndex: nil, amount: "", name: capitalizedFirst(name), note: "",
                preparedInStep: from, highlightTerms: carryOverTerms(name)
            ))
        }
        for item in heuristic.items where item.ingredientIndex == nil {
            guard let from = item.preparedInStep, !carried.contains(from) else { continue }
            carried.insert(from)
            items.append(item)
        }

        return CookStep(
            shortText: acceptedShortText(suggestion.shortText, original: original, ingredientTexts: ingredientTexts),
            items: items
        )
    }

    /// Which ingredient the model meant. Its numbering isn't reliable, so the
    /// name it gave wins when that names an ingredient; either way the
    /// ingredient has to be mentioned in the step.
    private static func resolveIngredient(_ use: SuggestedStep.Use, parsed: [ParsedIngredient], mentioned: Set<Int>) -> Int? {
        let name = use.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            var best: (index: Int, length: Int)?
            for (index, ingredient) in parsed.enumerated() {
                for term in ingredient.terms where term.count > (best?.length ?? 0) {
                    if !highlightRanges(in: name, terms: [term]).isEmpty { best = (index, term.count) }
                }
            }
            if let best { return mentioned.contains(best.index) ? best.index : nil }
        }
        let index = use.ingredientNumber - 1
        return mentioned.contains(index) ? index : nil
    }

    /// Whether a carried-over thing ("reserved tomato liquid") is talked about
    /// in a step, judged by its main words.
    private static func isMentioned(_ name: String, in text: String) -> Bool {
        let words = name.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count > 2 && !carryOverStopWords.contains($0) }
        let variants = words.flatMap { word in [word] + (singular(of: word).map { [$0] } ?? []) }
        return !highlightRanges(in: text, terms: variants).isEmpty
    }

    /// The rewrite, if it's worth showing: meaningfully shorter, with exactly
    /// the same numbers as the original, and still naming every ingredient the
    /// original does ("Serve warm." isn't a shorter "serve with a drizzle of
    /// olive oil and basil on top").
    static func acceptedShortText(_ rewrite: String, original: String, ingredientTexts: [String] = []) -> String? {
        // The model sometimes numbers its answer ("1. Set a colander…")
        let rewrite = rewrite
            .replacingOccurrences(of: #"^\s*\d+[.)]\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard original.count > 120,
              !rewrite.isEmpty,
              Double(rewrite.count) <= Double(original.count) * 0.85,
              keepsNumbers(original: original, rewrite: rewrite) else { return nil }
        let parsed = ingredientTexts.map { parseIngredient($0) }
        let named = Set(ingredientMatches(in: original, parsed: parsed).map { $0.ingredient })
        let kept = Set(ingredientMatches(in: rewrite, parsed: parsed).map { $0.ingredient })
        guard named.isSubset(of: kept) else { return nil }
        return rewrite
    }

    static func keepsNumbers(original: String, rewrite: String) -> Bool {
        numbers(in: original) == numbers(in: rewrite)
    }

    /// Every number in the text, with fraction glyphs spelled out so "½" and
    /// "1/2" count as the same.
    static func numbers(in text: String) -> Set<String> {
        var normalized = text
        for (plain, glyph) in fractionGlyphs {
            normalized = normalized.replacingOccurrences(of: glyph, with: " \(plain)")
        }
        let pattern = try! NSRegularExpression(pattern: #"\d+(?:\.\d+)?(?:/\d+)?"#)
        let ns = normalized as NSString
        return Set(pattern.matches(in: normalized, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range)
        })
    }

    // MARK: Ingredient lines

    static func parseIngredient(_ line: String) -> ParsedIngredient {
        var text = line.sanitizedForDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        var notes: [String] = []
        var reuseNote = ""
        var isReusable = false

        // Parentheticals: keep "optional", drop "(about 4 cups)"
        let parenthetical = try! NSRegularExpression(pattern: #"\s*\(([^)]*)\)"#)
        for match in parenthetical.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            if let inner = Range(match.range(at: 1), in: text), text[inner].lowercased().contains("optional") {
                notes.insert("optional", at: 0)
            }
            if let whole = Range(match.range, in: text) { text.removeSubrange(whole) }
        }

        var head = text
        if let comma = text.firstIndex(of: ",") {
            head = String(text[..<comma])
            let tail = text[text.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            let lowered = tail.lowercased()
            if lowered.contains("plus more") || lowered.contains("divided") || lowered.contains("for serving") || lowered.contains("to taste") {
                isReusable = true
                reuseNote = lowered.contains("to taste") ? "to taste" : lowered.contains("serving") ? "for serving" : ""
                let kept = tail.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { part in
                        let p = part.lowercased()
                        return !p.isEmpty && !p.hasPrefix("plus more") && p != "divided" && !p.contains("for serving") && p != "to taste"
                    }
                if !kept.isEmpty { notes.insert(kept.joined(separator: ", "), at: 0) }
            } else if !tail.isEmpty {
                notes.insert(tail, at: 0)
            }
        }

        var amount = ""
        var name = head.trimmingCharacters(in: .whitespaces)
        let amountPattern = try! NSRegularExpression(
            pattern: "^\\s*(\(quantityPattern))(?:((?:\\s+(?:packed|heaping|heaped|level|scant|generous|large|small|medium))*)\\s+(\(unitPattern))\\b\\.?)?\\s+",
            options: [.caseInsensitive]
        )
        let nsName = name as NSString
        if let match = amountPattern.firstMatch(in: name, range: NSRange(location: 0, length: nsName.length)) {
            var parts = [prettyQuantity(nsName.substring(with: match.range(at: 1)))]
            if match.range(at: 3).location != NSNotFound {
                let adjectives = nsName.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                if !adjectives.isEmpty { parts.append(adjectives) }
                let unit = nsName.substring(with: match.range(at: 3))
                parts.append(unitAbbreviations[unit.lowercased()] ?? unit)
            }
            amount = parts.joined(separator: " ")
            name = nsName.substring(from: match.range.location + match.range.length)
            if name.lowercased().hasPrefix("of ") { name = String(name.dropFirst(3)) }
        }

        let lowered = name.lowercased()
        if lowered.contains("salt") || lowered.contains("pepper") || lowered == "water" {
            isReusable = true
        }

        return ParsedIngredient(
            amount: amount,
            name: name.trimmingCharacters(in: .whitespaces),
            note: notes.joined(separator: ", "),
            terms: searchTerms(for: name),
            isReusable: isReusable,
            reuseNote: reuseNote
        )
    }

    /// "fresh basil leaves" → ["basil leaves", "basil"]; "Kosher salt and
    /// black pepper" → ["salt", "pepper"]; "olive oil" → ["olive oil", "oil"].
    static func searchTerms(for name: String) -> [String] {
        // "fresh basil + additional for garnish" is basil
        var name = name
        for extra in [" + ", "+", " plus "] {
            if let range = name.range(of: extra, options: .caseInsensitive) { name = String(name[..<range.lowerBound]) }
        }
        let parts = name.lowercased()
            .replacingOccurrences(of: " or ", with: " and ")
            .components(separatedBy: " and ")
        var terms: [String] = []
        for part in parts {
            var words = part
                .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
                .filter { !$0.isEmpty && !descriptorWords.contains($0) }
            guard !words.isEmpty else { continue }
            terms.append(words.joined(separator: " "))
            if words.count > 1, let last = words.last, containerWords.contains(last) {
                words.removeLast()
                terms.append(words.joined(separator: " "))
            }
            if words.count > 2 {
                // "red bell pepper" is also a "bell pepper"
                terms.append(words.suffix(2).joined(separator: " "))
            }
            if words.count > 1, let last = words.last {
                terms.append(last)
            }
        }
        var withVariants: [String] = []
        for term in terms {
            withVariants.append(term)
            if let singular = singular(of: term) { withVariants.append(singular) }
        }
        return uniqued(withVariants)
    }

    // MARK: Finding things in step text

    struct IngredientMatch {
        var range: Range<String.Index>
        var ingredient: Int
    }

    /// Where each ingredient is mentioned, longest terms first so "tomato
    /// paste" wins over "tomato", in the order they appear.
    static func ingredientMatches(in text: String, parsed: [ParsedIngredient]) -> [IngredientMatch] {
        let terms = parsed.enumerated().flatMap { index, ingredient in
            ingredient.terms.map { (term: $0, ingredient: index) }
        }
        return matches(in: text, terms: terms).map { IngredientMatch(range: $0.range, ingredient: $0.tag) }
    }

    /// Ranges to highlight in a step for the given words.
    static func highlightRanges(in text: String, terms: [String]) -> [Range<String.Index>] {
        matches(in: text, terms: uniqued(terms).map { (term: $0, ingredient: 0) }).map { $0.range }
    }

    private static func matches(in text: String, terms: [(term: String, ingredient: Int)]) -> [(range: Range<String.Index>, tag: Int)] {
        var claimed: [Range<String.Index>] = []
        var found: [(range: Range<String.Index>, tag: Int)] = []
        let ns = text as NSString

        for (term, tag) in terms.sorted(by: { $0.term.count > $1.term.count }) where !term.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: term)
            guard let regex = try? NSRegularExpression(pattern: "(?<![\\w-])\(escaped)(?![\\w-])", options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let range = Range(match.range, in: text),
                      !claimed.contains(where: { $0.overlaps(range) }) else { continue }
                // "tomato juices" and "tomato liquid" aren't the tomatoes
                let after = text[range.upperBound...].drop { $0 == " " }.prefix { $0.isLetter }.lowercased()
                if !term.contains(" "), rejectedFollowers.contains(String(after)) { continue }
                claimed.append(range)
                found.append((range, tag))
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// "1 teaspoon" in "toss with 1 teaspoon salt", formatted as "1 tsp".
    static func amount(before range: Range<String.Index>, in text: String) -> String? {
        let before = String(text[..<range.lowerBound])
        let regex = try! NSRegularExpression(
            pattern: "(?<![\\w/])(\(quantityPattern))(?:\\s+(\(unitPattern))\\.?)?\\s+(?:of\\s+)?$",
            options: [.caseInsensitive]
        )
        let ns = before as NSString
        guard let match = regex.firstMatch(in: before, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var parts = [prettyQuantity(ns.substring(with: match.range(at: 1)))]
        if match.range(at: 2).location != NSNotFound {
            let unit = ns.substring(with: match.range(at: 2))
            parts.append(unitAbbreviations[unit.lowercased()] ?? unit)
        }
        return parts.joined(separator: " ")
    }

    /// Cooking times like "about 20 minutes" or "5 to 10 minutes".
    static func durations(in text: String) -> [CookDuration] {
        // "20 to 25 minutes", "1 1/2 hours", "about 1½ hours"; never the "2
        // hours" inside "1/2 hours"
        let number = #"(\d+(?:\.\d+)?(?:\s+\d/\d|\s*[½¼¾⅓⅔])?|\d/\d|[½¼¾⅓⅔])"#
        let regex = try! NSRegularExpression(
            pattern: #"(?<![\w/.])(?:(?:about|around|roughly)\s+)?"# + number + #"(?:\s*(?:to|-|–|or)\s*"# + number
                + #")?(?:\s+(?:more|additional|longer))?\s*(minutes?|mins?|hours?|hrs?|seconds?|secs?)\b"#,
            options: [.caseInsensitive]
        )
        // "a minute or two", "an hour", "half an hour"
        let words = try! NSRegularExpression(
            pattern: #"(?<![\w])(?:(?:about|around|roughly)\s+)?(?:(half)\s+an\s+hour|an?\s+(minute|hour)(?:\s+or\s+(two))?)\b"#,
            options: [.caseInsensitive]
        )
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        let numbered: [CookDuration] = regex.matches(in: text, range: all).compactMap { match in
            guard let range = Range(match.range, in: text),
                  let low = amount(ns.substring(with: match.range(at: 1))) else { return nil }
            let high = match.range(at: 2).location == NSNotFound ? nil : amount(ns.substring(with: match.range(at: 2)))
            let unit = ns.substring(with: match.range(at: 3)).lowercased()
            let (short, multiplier): (String, Double) = unit.hasPrefix("h") ? ("hr", 3600) : unit.hasPrefix("s") ? ("sec", 1) : ("min", 60)
            let label = high.map { "\(amountLabel(low))–\(amountLabel($0)) \(short)" } ?? "\(amountLabel(low)) \(short)"
            return CookDuration(range: range, label: label, seconds: Int(low * multiplier), upperSeconds: high.map { Int($0 * multiplier) })
        }
        let worded: [CookDuration] = words.matches(in: text, range: all).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            if match.range(at: 1).location != NSNotFound {
                return CookDuration(range: range, label: "30 min", seconds: 1800)
            }
            let hour = ns.substring(with: match.range(at: 2)).lowercased() == "hour"
            let (short, multiplier) = hour ? ("hr", 3600) : ("min", 60)
            if match.range(at: 3).location != NSNotFound {
                return CookDuration(range: range, label: "1–2 \(short)", seconds: multiplier, upperSeconds: 2 * multiplier)
            }
            return CookDuration(range: range, label: "1 \(short)", seconds: multiplier)
        }
        return (numbered + worded.filter { word in !numbered.contains { $0.range.overlaps(word.range) } })
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// "1 1/2" → 1.5, "½" → 0.5, "2.5" → 2.5
    private static func amount(_ text: String) -> Double? {
        let fractions: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3]
        var rest = text.trimmingCharacters(in: .whitespaces)
        var total = 0.0
        if let last = rest.last, let fraction = fractions[last] {
            total += fraction
            rest = String(rest.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        for part in rest.split(separator: " ") {
            let pieces = part.split(separator: "/")
            if pieces.count == 2, let top = Double(pieces[0]), let bottom = Double(pieces[1]), bottom > 0 {
                total += top / bottom
            } else if let value = Double(part) {
                total += value
            } else {
                return nil
            }
        }
        return total
    }

    /// 1.5 → "1½", 0.5 → "½", 2.5 → "2½", 20 → "20"
    private static func amountLabel(_ value: Double) -> String {
        let whole = Int(value)
        let fraction = value - Double(whole)
        let symbol: String? = switch fraction {
        case 0.24...0.26: "¼"
        case 0.32...0.34: "⅓"
        case 0.49...0.51: "½"
        case 0.65...0.67: "⅔"
        case 0.74...0.76: "¾"
        default: nil
        }
        if fraction < 0.01 { return "\(whole)" }
        guard let symbol else { return String(format: "%g", value) }
        return whole == 0 ? symbol : "\(whole)\(symbol)"
    }

    /// "step 6" mentions, with the sentence they're in.
    static func stepReferences(in text: String) -> [(step: Int, sentence: String)] {
        let regex = try! NSRegularExpression(pattern: #"\bsteps?\s+(\d+)\b"#, options: [.caseInsensitive])
        var references: [(Int, String)] = []
        for sentence in sentences(in: text) {
            let ns = sentence as NSString
            for match in regex.matches(in: sentence, range: NSRange(location: 0, length: ns.length)) {
                if let number = Int(ns.substring(with: match.range(at: 1))), number > 0 {
                    references.append((number - 1, sentence))
                }
            }
        }
        return references
    }

    /// "Keep the liquid in the bowl — you'll need it in step 6." → "The liquid in the bowl"
    static func setAsideLabel(from sentence: String) -> String? {
        let clauses = sentence
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!? "))
            .components(separatedBy: CharacterSet(charactersIn: "—–;,"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.range(of: #"\bsteps?\s+\d+"#, options: [.regularExpression, .caseInsensitive]) == nil }
        guard var label = clauses.first else { return nil }
        for verb in ["set aside", "keep", "save", "reserve", "hold", "leave"] where label.lowercased().hasPrefix(verb + " ") {
            label = String(label.dropFirst(verb.count + 1))
            break
        }
        guard label.count <= 40 else { return nil }
        return capitalizedFirst(label)
    }

    // MARK: Helpers

    static func prettyQuantity(_ quantity: String) -> String {
        var out = quantity
        for (plain, glyph) in fractionGlyphs {
            out = out.replacingOccurrences(of: #"(?<![\d/])"# + NSRegularExpression.escapedPattern(for: plain) + #"(?![\d/])"#, with: glyph, options: .regularExpression)
        }
        out = out.replacingOccurrences(of: #"(\d) ([½¼¾⅓⅔⅛])"#, with: "$1$2", options: .regularExpression)
        return out.replacingOccurrences(of: #"\s*-\s*"#, with: "–", options: .regularExpression)
    }

    private static func sentences(in text: String) -> [String] {
        text.replacingOccurrences(of: #"([.!?])\s+"#, with: "$1\n", options: .regularExpression)
            .components(separatedBy: "\n")
    }

    private static func carryOverTerms(_ name: String) -> [String] {
        let lowered = name.lowercased()
        var trimmed = lowered
        for word in ["the ", "reserved ", "saved ", "drained ", "cooked ", "set-aside "] where trimmed.hasPrefix(word) {
            trimmed = String(trimmed.dropFirst(word.count))
        }
        return uniqued([lowered, trimmed])
    }

    private static func singular(of term: String) -> String? {
        if term.hasSuffix("oes") || term.hasSuffix("shes") || term.hasSuffix("ches") || term.hasSuffix("xes") {
            return String(term.dropLast(2))
        }
        if term.hasSuffix("ies") { return String(term.dropLast(3)) + "y" }
        if term.hasSuffix("s"), !term.hasSuffix("ss"), term.count > 3 { return String(term.dropLast()) }
        return nil
    }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func uniqued(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    private static let quantityPattern = #"\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?[½¼¾⅓⅔⅛]?|[½¼¾⅓⅔⅛](?:\s*(?:-|–|to)\s*(?:\d+/\d+|\d+(?:\.\d+)?))?"#
    private static let unitPattern = "cups?|tablespoons?|tbsps?|tbs|teaspoons?|tsps?|pounds?|lbs?|ounces?|oz|grams?|g|kilograms?|kg|ml|milliliters?|liters?|pinch(?:es)?|dash(?:es)?|cans?|sticks?|bunch(?:es)?|sprigs?|quarts?|pints?|cloves?|heads?|slices?"

    private static let unitAbbreviations: [String: String] = [
        "pound": "lb", "pounds": "lb", "lbs": "lb",
        "tablespoon": "tbsp", "tablespoons": "tbsp", "tbsps": "tbsp", "tbs": "tbsp",
        "teaspoon": "tsp", "teaspoons": "tsp", "tsps": "tsp",
        "ounce": "oz", "ounces": "oz",
        "gram": "g", "grams": "g", "kilogram": "kg", "kilograms": "kg",
        "milliliter": "ml", "milliliters": "ml", "liter": "l", "liters": "l"
    ]

    private static let fractionGlyphs: [(String, String)] = [
        ("1/2", "½"), ("1/4", "¼"), ("3/4", "¾"), ("1/3", "⅓"), ("2/3", "⅔"), ("1/8", "⅛")
    ]

    private static let descriptorWords: Set<String> = [
        "fresh", "freshly", "large", "small", "medium", "extra-virgin", "extra", "virgin",
        "kosher", "sea", "flaky", "packed", "chopped", "minced", "sliced", "diced", "grated",
        "ground", "finely", "coarsely", "thinly", "roughly", "boneless", "skinless", "unsalted",
        "salted", "whole", "dried", "black", "softened", "melted", "ripe", "raw", "peeled",
        "good", "quality", "good-quality", "plain", "a", "an", "of", "piece", "pieces"
    ]

    private static let containerWords: Set<String> = [
        "cloves", "clove", "leaves", "leaf", "sprigs", "sprig", "stalks", "stalk",
        "heads", "head", "bunch", "pieces", "piece"
    ]

    private static let carryOverStopWords: Set<String> = [
        "the", "and", "with", "from", "step", "reserved", "saved", "drained", "cooked",
        "set", "aside", "some", "all", "any", "your", "that", "this"
    ]

    private static let rejectedFollowers: Set<String> = [
        "paste", "juice", "juices", "liquid", "sauce", "water", "stock", "broth",
        "purée", "puree", "mixture", "seeds", "skins", "powder"
    ]
}
