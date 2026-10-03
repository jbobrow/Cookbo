import Foundation

// MARK: - Model

/// The whole cook at a glance: one block per step, in lanes. Lane 0 is the
/// main line of work; steps that happen at the same time (the oven
/// preheating, a sauce made "meanwhile") get lanes of their own.
nonisolated struct CookOverview: Equatable {
    enum Kind: Equatable {
        case prep
        case cook
        case alongside
    }

    struct Block: Equatable {
        /// One word: "Sauté", "Bake"
        var word: String
        /// 0-based step, or nil for the prep block
        var step: Int?
        var lane: Int
        /// Minutes from when the heat goes on; prep is negative
        var start: Double
        var end: Double
        /// "8–12 min" from the recipe, or "~3 min" when it's our estimate
        var timeLabel: String
        var kind: Kind
    }

    var blocks: [Block]

    var laneCount: Int { (blocks.map(\.lane).max() ?? 0) + 1 }

    var totalMinutes: Double {
        guard let first = blocks.map(\.start).min(), let last = blocks.map(\.end).max() else { return 0 }
        return last - first
    }

    /// "About 1 hr 30 min", rounded to 5 minutes.
    var totalLabel: String {
        let minutes = max(5, Int((totalMinutes / 5).rounded()) * 5)
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "About \(minutes) min" }
        return rest == 0 ? "About \(hours) hr" : "About \(hours) hr \(rest) min"
    }
}

/// Something to cut before the heat goes on.
nonisolated struct PrepTask: Equatable {
    /// "Chop the vegetables"
    var title: String
    /// "3 large carrots, 1 red bell pepper, …"
    var detail: String
    var ingredientIndices: [Int]
}

/// What the on-device model suggested for one step of the overview, checked
/// before use.
nonisolated struct OverviewHint: Codable, Equatable {
    var word: String
    /// Its estimate when the step gives no time; 0 when it doesn't know
    var minutes: Int
    /// 1-based step this one happens alongside; 0 when it doesn't
    var alongsideStep: Int
}

// MARK: - Planner

nonisolated enum CookIntroPlanner {

    // MARK: Overview

    static func overview(for recipe: Recipe, plan: CookPlan, hints: [OverviewHint]? = nil) -> CookOverview {
        let texts = recipe.orderedDirections.map { $0.text.sanitizedForDisplay }
        var blocks: [CookOverview.Block] = []
        var clock = 0.0
        var lastMain: CookOverview.Block?
        var mainBlockForStep: [Int: CookOverview.Block] = [:]

        // Prep comes first, as long as there's something to prep
        let prepMinutes = recipe.prepDuration > 0 ? recipe.prepDuration / 60 : Double(prepTasks(for: recipe, plan: plan).count * 4)
        var preheated = false

        for (index, fullText) in texts.enumerated() {
            let hint = hints.flatMap { $0.indices.contains(index) ? $0[index] : nil }

            // The oven goes on first thing, so it heats while you prep. A step
            // that also does other work ("Preheat the oven… Bake 10 to 14
            // minutes") carries on as its own block without the preheat.
            var text = fullText
            if isPreheat(fullText) {
                if !preheated {
                    blocks.append(.init(word: "Preheat", step: index, lane: 1, start: -prepMinutes, end: -prepMinutes + 15,
                                        timeLabel: "~15 min", kind: .alongside))
                    preheated = true
                }
                text = withoutPreheat(fullText)
                if text.split(whereSeparator: \.isWhitespace).count < 4 { continue }
            }

            var timing = stepTiming(text)
            // The model only estimates steps that give no time at all
            if CookPlanner.durations(in: text).isEmpty, !isPreheat(text),
               let minutes = hint?.minutes, (1...240).contains(minutes) {
                timing = (Double(minutes), Double(minutes), "~\(minutes) min", true)
            }
            let length = (timing.low + timing.high) / 2
            let word = acceptedWord(hint?.word, in: text) ?? word(for: text)

            // Side by side only when the step says so ("Meanwhile…", "While
            // the shallots cook…"); the model can say which step it's beside
            var anchor: CookOverview.Block?
            if runsAlongside(text) {
                if let hint, hint.alongsideStep >= 1, hint.alongsideStep - 1 < index,
                   let named = mainBlockForStep[hint.alongsideStep - 1] {
                    anchor = named
                } else {
                    anchor = lastMain
                }
            }

            if let anchor {
                blocks.append(.init(word: word, step: index, lane: 1, start: anchor.start, end: anchor.start + length,
                                    timeLabel: timing.label, kind: .alongside))
            } else {
                let block = CookOverview.Block(word: word, step: index, lane: 0, start: clock, end: clock + length,
                                               timeLabel: timing.label, kind: .cook)
                blocks.append(block)
                mainBlockForStep[index] = block
                lastMain = block
                clock += length
            }
        }

        if prepMinutes > 0 {
            let label = recipe.prepDuration > 0 ? "\(Int(prepMinutes)) min" : "~\(Int(prepMinutes)) min"
            blocks.insert(.init(word: "Prep", step: nil, lane: 0, start: -prepMinutes, end: 0, timeLabel: label, kind: .prep), at: 0)
        }

        return CookOverview(blocks: assignLanes(mergeRepeats(blocks.sorted { $0.start < $1.start })))
    }

    /// The step without its preheating sentences.
    static func withoutPreheat(_ text: String) -> String {
        text.replacingOccurrences(of: #"([.!?])\s+"#, with: "$1\n", options: .regularExpression)
            .components(separatedBy: "\n")
            .filter { !isPreheat($0) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Back-to-back steps with the same word are one action ("Layer" three
    /// times is layering): one block, with their times added up.
    private static func mergeRepeats(_ blocks: [CookOverview.Block]) -> [CookOverview.Block] {
        var merged: [CookOverview.Block] = []
        for block in blocks {
            if block.kind == .cook,
               let last = merged.lastIndex(where: { $0.kind == .cook }),
               merged[last].word == block.word, merged[last].end == block.start,
               merged[(last + 1)...].allSatisfy({ $0.kind != .cook }) {
                let minutes = Int((block.end - merged[last].start).rounded())
                merged[last].end = block.end
                merged[last].timeLabel = "~\(minutes) min"
            } else {
                merged.append(block)
            }
        }
        return merged
    }

    /// Side blocks take the first lane that's free when they start.
    private static func assignLanes(_ blocks: [CookOverview.Block]) -> [CookOverview.Block] {
        var laneEnds: [Double] = []
        return blocks.map { block in
            guard block.kind == .alongside else { return block }
            var placed = block
            if let lane = laneEnds.firstIndex(where: { $0 <= block.start + 0.01 }) {
                placed.lane = lane + 1
                laneEnds[lane] = block.end
            } else {
                laneEnds.append(block.end)
                placed.lane = laneEnds.count
            }
            return placed
        }
    }

    /// How long a step takes: the recipe's own times when it gives any,
    /// otherwise an estimate.
    static func stepTiming(_ text: String) -> (low: Double, high: Double, label: String, estimated: Bool) {
        let durations = CookPlanner.durations(in: text)
        if durations.count == 1, let only = durations.first {
            let low = Double(only.seconds) / 60
            let high = Double(only.upperSeconds ?? only.seconds) / 60
            return (low, high, only.label, false)
        }
        if durations.count > 1 {
            let low = Double(durations.reduce(0) { $0 + $1.seconds }) / 60
            let high = Double(durations.reduce(0) { $0 + ($1.upperSeconds ?? $1.seconds) }) / 60
            return (low, high, "~\(Int(((low + high) / 2).rounded())) min", true)
        }
        if isPreheat(text) { return (15, 15, "~15 min", true) }
        let words = text.split(whereSeparator: \.isWhitespace).count
        let minutes = Double(min(max(Int((Double(words) / 12).rounded()), 1), 10))
        return (minutes, minutes, "~\(Int(minutes)) min", true)
    }

    static func isPreheat(_ text: String) -> Bool {
        text.range(of: #"\bpre-?heat"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "Meanwhile, …" or "While the shallots cook, …"
    static func runsAlongside(_ text: String) -> Bool {
        text.range(of: #"^\s*(meanwhile|in the meantime|while\b)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// One word for a step: its first cooking verb.
    static func word(for text: String) -> String {
        var rest = text.trimmingCharacters(in: .whitespaces)
        // "To prepare the veggies: …"
        if let colon = rest.firstIndex(of: ":"), rest.distance(from: rest.startIndex, to: colon) < 60 {
            rest = String(rest[rest.index(after: colon)...])
        }
        // "Meanwhile, …", "While the shallots cook, …", "In a large skillet over medium heat, …"
        rest = rest.replacingOccurrences(
            of: #"^\s*(meanwhile|in the meantime|while|once|when|after|as soon as|in|on|using|with)\b[^,.]*,\s*"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        let words = rest.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        // The main cooking action wins anywhere in the step ("Wrap the dish
        // in foil… Bake for 18 minutes" is Bake); otherwise the first verb
        let pick = words.first(where: { mainActions.contains($0) })
            ?? words.prefix(10).first(where: { cookingVerbs.contains($0) })
            ?? words.first ?? "Cook"
        return pick.prefix(1).uppercased() + pick.dropFirst()
    }

    /// The model's word, if it's one word and the step actually uses it
    /// ("Cut" for a step that simmers the vegetables is made up).
    private static func acceptedWord(_ word: String?, in text: String) -> String? {
        guard let word = word?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.lowercased().contains(String(word.lowercased().prefix(max(3, word.count - 1)))),
              !word.isEmpty, word.count <= 14,
              word.allSatisfy({ $0.isLetter || $0 == "-" }),
              !["prep", "preheat"].contains(word.lowercased()) else { return nil }
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    private static let mainActions: Set<String> = [
        "preheat", "bake", "roast", "simmer", "boil", "braise", "fry", "sauté", "saute", "grill", "broil",
        "steam", "poach", "toast", "rest", "chill", "marinate", "cool", "reduce", "caramelize", "sear",
        "brown", "cook", "knead", "rise", "proof"
    ]

    private static let cookingVerbs: Set<String> = [
        "preheat", "heat", "warm", "bring", "boil", "simmer", "sauté", "saute", "cook", "bake", "roast", "broil",
        "fry", "sear", "brown", "toast", "stir", "add", "mix", "whisk", "combine", "toss", "pour", "drain", "season",
        "serve", "layer", "spread", "top", "chop", "slice", "dice", "blend", "pulse", "purée", "puree", "knead",
        "rest", "cool", "chill", "marinate", "wilt", "reduce", "assemble", "coat", "dredge", "pound", "fold",
        "beat", "melt", "grate", "garnish", "transfer", "cover", "steam", "grill", "poach", "caramelize",
        "thicken", "strain", "shred", "roll", "shape", "flip", "divide", "plate", "drizzle", "sprinkle"
    ]

    // MARK: Prep

    /// The knife work, grouped into one card per cut and the step that first
    /// needs it, in the order it's needed. Measuring stays in the steps.
    static func prepTasks(for recipe: Recipe, plan: CookPlan) -> [PrepTask] {
        struct Cut { var verb: String; var step: Int; var index: Int; var amount: String; var name: String; var noun: String }
        var cuts: [Cut] = []
        let stepCuts = cutsInSteps(of: recipe)
        for (index, ingredient) in recipe.allIngredients.enumerated() {
            let text = ingredient.text.sanitizedForDisplay
            // A can of diced tomatoes is already cut
            guard let verb = knifeVerb(in: text) ?? stepCuts[index],
                  text.range(of: #"\b(cans?|canned|jars?|jarred|store-bought|pre-\w+)\b"#, options: [.regularExpression, .caseInsensitive]) == nil
            else { continue }
            let parsed = CookPlanner.parseIngredient(text)
            let name = cutIngredientName(parsed)
            let noun = titleNoun(for: name)
            let step = plan.firstUseStep(ofIngredient: index) ?? Int.max
            cuts.append(Cut(verb: verb, step: step, index: index, amount: parsed.amount, name: name, noun: noun))
        }

        var groups: [[Cut]] = []
        for cut in cuts.sorted(by: { ($0.step, $0.index) < ($1.step, $1.index) }) {
            if let i = groups.firstIndex(where: { $0[0].verb == cut.verb && $0[0].step == cut.step }) {
                groups[i].append(cut)
            } else {
                groups.append([cut])
            }
        }

        return groups.map { group in
            let verb = group[0].verb
            let title: String
            if group.count == 1 {
                title = "\(verb) the \(group[0].noun)"
            } else if group.allSatisfy({ isProduce($0.noun) }) {
                title = "\(verb) the vegetables"
            } else {
                title = "\(verb) the \(naturalList(group.map { $0.noun.split(separator: " ").last.map(String.init) ?? $0.noun }))"
            }
            let detail = group.map { [$0.amount, $0.name].filter { !$0.isEmpty }.joined(separator: " ") }
                .joined(separator: ", ")
            return PrepTask(title: title, detail: detail, ingredientIndices: group.map(\.index))
        }
    }

    /// Cuts the steps ask for instead of the ingredient list ("Cut the onion
    /// into a ½-inch dice"): the cut and the ingredient have to be in the same
    /// clause, so "sprinkle the basil, then slice and serve" isn't one.
    static func cutsInSteps(of recipe: Recipe) -> [Int: String] {
        let parsed = recipe.allIngredients.map { CookPlanner.parseIngredient($0.text) }
        var found: [Int: String] = [:]
        for step in recipe.orderedDirections {
            let clauses = step.text.sanitizedForDisplay.components(separatedBy: CharacterSet(charactersIn: ".,;:!?"))
            for clause in clauses {
                let lowered = clause.lowercased()
                guard let verb = stepKnifeWords.first(where: {
                    lowered.range(of: #"\b"# + $0.0 + #"\b"#, options: .regularExpression) != nil
                })?.1 else { continue }
                for match in CookPlanner.ingredientMatches(in: clause, parsed: parsed) where found[match.ingredient] == nil {
                    found[match.ingredient] = verb
                }
            }
        }
        return found
    }

    private static let stepKnifeWords: [(String, String)] = [
        ("mince", "Mince"), ("dice", "Dice"), ("chop", "Chop"), ("slice", "Slice"), ("slices", "Slice"),
        ("cube", "Cube"), ("julienne", "Julienne"), ("grate", "Grate"), ("shred", "Shred"),
        ("halve", "Halve"), ("cut", "Cut")
    ]

    /// The cut an ingredient line asks for, as an instruction. "halved and
    /// thinly sliced" is a slice; "pressed or minced" is a mince.
    static func knifeVerb(in text: String) -> String? {
        let lowered = text.lowercased()
        for (word, verb) in knifeWords where lowered.range(of: #"\b"# + word + #"\b"#, options: .regularExpression) != nil {
            return verb
        }
        return nil
    }

    private static let knifeWords: [(String, String)] = [
        ("minced", "Mince"), ("diced", "Dice"), ("chopped", "Chop"), ("sliced", "Slice"), ("cubed", "Cube"),
        ("julienned", "Julienne"), ("grated", "Grate"), ("shredded", "Shred"), ("quartered", "Quarter"),
        ("halved", "Halve"), ("crushed", "Crush")
    ]

    /// What's being cut. Usually the name ("garlic" from "2 cloves garlic,
    /// minced"), but when the cut comes first ("freshly grated low-moisture,
    /// part-skim mozzarella cheese") it's what follows the cut.
    private static func cutIngredientName(_ parsed: CookPlanner.ParsedIngredient) -> String {
        let lowered = parsed.name.lowercased()
        for (word, _) in knifeWords {
            guard let range = lowered.range(of: #"\b"# + word + #"\b"#, options: .regularExpression) else { continue }
            let offset = lowered.distance(from: lowered.startIndex, to: range.upperBound)
            var after = String(parsed.name.dropFirst(offset))
            if !parsed.note.isEmpty, !after.contains("+") { after += " " + parsed.note }
            let name = cleanedName(after.replacingOccurrences(of: ",", with: ""))
            if !name.isEmpty { return name }
        }
        return cleanedName(parsed.name)
    }

    /// A short name for a card's title: "garlic" rather than "garlic cloves",
    /// "mozzarella cheese" rather than every descriptor before it.
    private static func titleNoun(for name: String) -> String {
        let terms = CookPlanner.searchTerms(for: name)
        var words = (terms.first ?? name.lowercased()).split(separator: " ").map(String.init)
        if words.count > 1, let last = words.last,
           ["cloves", "clove", "leaves", "leaf", "sprigs", "sprig", "stalks", "stalk", "heads", "head", "bunch"].contains(last) {
            words.removeLast()
        }
        return words.suffix(2).joined(separator: " ")
    }

    /// "roughly chopped fresh basil + additional for garnish" → "fresh basil"
    private static func cleanedName(_ name: String) -> String {
        var result = name
        for stop in [" + ", " plus "] {
            if let range = result.range(of: stop, options: .caseInsensitive) { result = String(result[..<range.lowerBound]) }
        }
        let drop: Set<String> = ["roughly", "finely", "thinly", "coarsely", "freshly", "minced", "diced", "chopped",
                                 "sliced", "cubed", "julienned", "grated", "shredded", "quartered", "halved", "crushed"]
        return result.split(separator: " ").filter { !drop.contains($0.lowercased()) }.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
    }

    private static func isProduce(_ noun: String) -> Bool {
        let produce: Set<String> = ["onion", "onions", "carrot", "carrots", "celery", "pepper", "peppers", "zucchini",
                                    "squash", "potato", "potatoes", "tomato", "tomatoes", "mushroom", "mushrooms",
                                    "cabbage", "leek", "leeks", "shallot", "shallots", "eggplant", "broccoli",
                                    "cauliflower", "kale", "spinach", "cucumber", "fennel", "scallions", "corn"]
        return noun.split(separator: " ").contains { produce.contains(String($0)) }
    }

    private static func naturalList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }

    // MARK: Layout

    /// Sizes for blocks laid out along time: proportional to minutes, never
    /// smaller than each block's minimum. Returns each block's start and end
    /// position for the given main-lane blocks, plus a time → position map
    /// for blocks in the other lanes.
    static func layout(
        main: [(start: Double, end: Double, minimum: Double)],
        length: Double,
        gap: Double
    ) -> (spans: [(Double, Double)], position: (Double) -> Double) {
        guard !main.isEmpty else { return ([], { _ in 0 }) }
        let durations = main.map { max($0.end - $0.start, 0.01) }
        let space = max(length - gap * Double(main.count - 1), 1)
        // Too many blocks for their minimums: shrink them all to fit
        let squeeze = min(1, space / max(main.reduce(0) { $0 + $1.minimum }, 1))
        let shrink = squeeze < 1 ? squeeze * 0.9 : 1
        let main = main.map { (start: $0.start, end: $0.end, minimum: $0.minimum * shrink) }
        var scale = space / durations.reduce(0, +)
        for _ in 0..<20 {
            let fixed = zip(main, durations).filter { scale * $1 <= $0.minimum }.reduce(0) { $0 + $1.0.minimum }
            let free = zip(main, durations).filter { scale * $1 > $0.minimum }.reduce(0) { $0 + $1.1 }
            guard free > 0 else { break }
            scale = max((space - fixed) / free, 0)
        }
        var spans: [(Double, Double)] = []
        var x = 0.0
        for (block, duration) in zip(main, durations) {
            let size = max(block.minimum, scale * duration)
            spans.append((x, x + size))
            x += size + gap
        }
        let knots = zip(main, spans).map { ($0.start, $0.end, $1.0, $1.1) }
        let position: (Double) -> Double = { time in
            // A time on a boundary belongs to the block that starts there
            for (start, end, from, to) in knots where time < end {
                return from + (to - from) * (max(time, start) - start) / (end - start)
            }
            return knots.last?.3 ?? 0
        }
        return (spans, position)
    }
}
