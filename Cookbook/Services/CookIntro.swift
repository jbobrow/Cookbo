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

/// An ingredient to measure out before the heat goes on: "¼ cup" of "olive oil".
nonisolated struct MeasureTask: Equatable {
    var amount: String
    var name: String
    var ingredientIndex: Int
}

/// The stages every overview is told in. A small, fixed set, so every recipe
/// reads the same way: the oven heating while you prep, then Mix, Bake, Serve.
nonisolated enum CookStage: String, CaseIterable, Codable {
    /// The oven or grill heating up
    case preheat = "Preheat"
    /// A pot of water coming to the boil
    case boil = "Boil"
    /// Butter or chocolate melted ahead of time
    case melt = "Melt"
    case prep = "Prep"
    case mix = "Mix"
    /// Putting it together: layering, filling, shaping
    case assemble = "Assemble"
    /// On the stove: sauté, fry, sear, brown, heat through
    case cook = "Cook"
    /// Hands-off on the stove: simmer, braise, poach, boil
    case simmer = "Simmer"
    /// In the oven: bake, roast, broil
    case bake = "Bake"
    case grill = "Grill"
    /// Waiting: rest, cool, rise, marinate, soak
    case rest = "Rest"
    case chill = "Chill"
    /// The finish: garnish, top, assemble, serve
    case serve = "Serve"

    /// Things to start before anything else, so they're ready when needed.
    var isHeadStart: Bool { self == .preheat || self == .boil || self == .melt }
}

// MARK: - Planner

nonisolated enum CookIntroPlanner {

    // MARK: Overview

    /// Worked out from the recipe's own words, so it's ready at once and the
    /// same on every device.
    static func overview(for recipe: Recipe, plan: CookPlan) -> CookOverview {
        let texts = recipe.orderedDirections.map { $0.text.sanitizedForDisplay }
        let declaredPrep = recipe.prepDuration > 0 ? recipe.prepDuration / 60 : 0

        struct Step {
            var index: Int
            var stage: CookStage
            var timing: (low: Double, high: Double, label: String, estimated: Bool)
            var alongside: Bool
            var waitsForWater = false
            var servesHere = false
            var length: Double { (timing.low + timing.high) / 2 }
        }
        var headStarts: [(stage: CookStage, step: Int, minutes: Double)] = []
        var steps: [Step] = []
        var waterComing = false

        for (index, fullText) in texts.enumerated() where !isNote(fullText) {
            let alongside = runsAlongside(fullText)

            // The oven and the pasta water go on early, so they heat while you
            // work; the rest of the step carries on as its own block
            var text = fullText
            if isPreheat(text) {
                if !headStarts.contains(where: { $0.stage == .preheat }) {
                    headStarts.append((.preheat, index, 15))
                }
                text = withoutSentences(text, where: isPreheat)
            }
            if !alongside, isWaterBoiling(text) {
                headStarts.append((.boil, index, 10))
                text = withoutSentences(text, where: isWaterBoiling)
                waterComing = true
            }
            if isMeltingAhead(text) {
                headStarts.append((.melt, index, 3))
                continue
            }
            text = withoutLeadIns(text)
            if text.split(whereSeparator: \.isWhitespace).count < 4 { continue }

            // A step that names nothing goes with the one before
            let stage = stage(for: text) ?? steps.last(where: { !$0.alongside })?.stage ?? .prep
            let timing = stepTiming(text, stage: stage)
            var step = Step(index: index, stage: stage, timing: timing, alongside: alongside,
                            servesHere: matches(.serve, in: text))
            if waterComing, !alongside, stage != .prep {
                step.waitsForWater = true
                waterComing = false
            }
            steps.append(step)
        }

        // The last step is serving it, if it's a light step that says so or
        // lays out the plate
        if let last = steps.lastIndex(where: { !$0.alongside }),
           steps[last].stage == .assemble || (steps[last].servesHere && [.mix, .prep].contains(steps[last].stage)) {
            steps[last].stage = .serve
        }

        // Prep steps before any cooking ("Butter a baking dish") are part of
        // the prep block
        var prepMinutes = declaredPrep > 0 ? declaredPrep : Double(prepTasks(for: recipe, plan: plan).count * 4)
        while let first = steps.first, first.stage == .prep, !first.alongside {
            if declaredPrep == 0 { prepMinutes += first.length }
            steps.removeFirst()
        }
        prepMinutes = prepMinutes.rounded(.up)
        let startTime = -prepMinutes
        let readyAt: [CookStage: Double] = Dictionary(headStarts.map { ($0.stage, startTime + $0.minutes) },
                                                      uniquingKeysWith: { first, _ in first })

        var blocks: [CookOverview.Block] = []
        var clock = 0.0
        var lastMain: CookOverview.Block?
        var neededAt: [CookStage: Double] = [:]
        for step in steps {
            let word = step.stage.rawValue

            // Side by side only when the step says so ("Meanwhile…", "While
            // the shallots cook…"), beside the step before it
            if step.alongside, let anchor = lastMain {
                blocks.append(.init(word: word, step: step.index, lane: 1, start: anchor.start,
                                    end: anchor.start + step.length, timeLabel: step.timing.label, kind: .alongside))
                continue
            }

            // Into the oven once it's hot; into the pot once it boils
            var start = clock
            if step.stage == .bake || step.stage == .grill, let hot = readyAt[.preheat], neededAt[.preheat] == nil {
                start = max(start, hot)
                neededAt[.preheat] = start
            }
            if step.waitsForWater, let boiling = readyAt[.boil] {
                start = max(start, boiling)
                neededAt[.boil] = start
            }
            let block = CookOverview.Block(word: word, step: step.index, lane: 0, start: start, end: start + step.length,
                                           timeLabel: step.timing.label, kind: step.stage == .prep ? .prep : .cook)
            blocks.append(block)
            lastMain = block
            clock = block.end
        }

        // Head starts finish just as they're needed: the oven comes on 15
        // minutes before the bake, not an hour early
        for start in headStarts {
            let end = neededAt[start.stage] ?? startTime + start.minutes
            let from = max(startTime, end - start.minutes)
            blocks.append(.init(word: start.stage.rawValue, step: start.step, lane: 1, start: from, end: end,
                                timeLabel: "~\(Int(start.minutes)) min", kind: .alongside))
        }

        if prepMinutes > 0 {
            let label = declaredPrep > 0 ? "\(Int(prepMinutes)) min" : "~\(Int(prepMinutes)) min"
            blocks.insert(.init(word: CookStage.prep.rawValue, step: nil, lane: 0, start: startTime, end: 0,
                                timeLabel: label, kind: .prep), at: 0)
        }

        return CookOverview(blocks: assignLanes(mergeRepeats(blocks.sorted { $0.start < $1.start })))
    }

    /// The step without the sentences that match.
    static func withoutSentences(_ text: String, where matches: (String) -> Bool) -> String {
        sentences(of: text)
            .filter { !matches($0) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func sentences(of text: String) -> [String] {
        text.replacingPattern(#"([.!?;])\s+"#, with: "$1\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Back-to-back steps in the same stage are one block (three steps of
    /// layering are one Assemble), and a quick step joins the one before it
    /// ("Stir in the garlic, 1 minute" is part of the Cook), so the overview
    /// stays a handful of bars.
    private static func mergeRepeats(_ blocks: [CookOverview.Block]) -> [CookOverview.Block] {
        let isMain: (CookOverview.Block) -> Bool = { $0.kind != .alongside && $0.step != nil }
        let finalStart = blocks.filter(isMain).map(\.start).max()
        let minor: Set<CookStage> = [.prep, .mix, .assemble, .cook, .simmer, .serve]
        let waiting: Set<CookStage> = [.rest, .chill]
        var merged: [CookOverview.Block] = []
        for block in blocks {
            let length = block.end - block.start
            let quick = (length <= 2 || (block.timeLabel.hasPrefix("~") && length <= 3))
                && block.start != finalStart
                && CookStage(rawValue: block.word).map(minor.contains) == true
            if isMain(block),
               let last = merged.lastIndex(where: isMain),
               abs(merged[last].end - block.start) < 0.01,
               merged[last].word == block.word
                || (quick && CookStage(rawValue: merged[last].word).map(waiting.contains) != true) {
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
    /// otherwise an estimate for its stage.
    static func stepTiming(_ text: String, stage: CookStage? = nil) -> (low: Double, high: Double, label: String, estimated: Bool) {
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
        if text.hasPattern(#"\bovernight\b"#, caseInsensitive: true) {
            return (480, 480, "Overnight", false)
        }
        // "a couple of minutes", "a few more minutes"
        if text.hasPattern(#"\ba (couple|few)( of)?( more)? minutes\b"#, caseInsensitive: true) {
            return (3, 3, "~3 min", true)
        }
        let typical: Double? = switch stage {
        case .bake: 20
        case .grill, .simmer, .rest: 10
        case .chill: 30
        default: nil
        }
        let words = text.split(whereSeparator: \.isWhitespace).count
        let minutes = typical ?? Double(min(max(Int((Double(words) / 12).rounded()), 1), 10))
        return (minutes, minutes, "~\(Int(minutes)) min", true)
    }

    /// "Make Ahead: …", "Leftovers keep…", "Review my tips before beginning."
    static func isNote(_ text: String) -> Bool {
        text.hasPattern(#"^\s*(make[- ]ahead|leftovers?|storage|to store|store\b|notes?\b|tips?\b|review\b|watch\b|to reheat|reheat\b)"#,
                        caseInsensitive: true)
    }

    /// The step without its "Meanwhile," "Once the water boils," and "After
    /// 2 hours," openings, which say when, not what.
    static func withoutLeadIns(_ text: String) -> String {
        sentences(of: text)
            .map { $0.replacingPattern(#"^\s*(meanwhile|in the meantime|while|once|when|after|as soon as|if)\b[^,.]*,\s*"#,
                                       with: "", caseInsensitive: true) }
            .joined(separator: " ")
    }

    /// "Preheat the oven to 425°F", "Heat oven to 350 degrees", "Heat a grill"
    static func isPreheat(_ text: String) -> Bool {
        text.hasPattern(#"\bpre-?heat\b(?=[^.]{0,40}(oven|grill|broiler|°|degrees|\b\d{3}\b))|\b(heat|set|turn on)\s+(the\s+|your\s+|an?\s+)?(oven|grill|broiler)\b"#,
                        caseInsensitive: true)
    }

    /// "Bring a large pot of salted water to a boil"
    static func isWaterBoiling(_ text: String) -> Bool {
        text.hasPattern(#"\bbring\b[^.]{0,40}\bwater\b[^.]{0,20}\bto\s+(a\s+)?(rolling\s+|full\s+)?boil\b"#,
                        caseInsensitive: true)
    }

    /// A step that only melts something for later: "Melt the butter and let
    /// it cool slightly."
    static func isMeltingAhead(_ text: String) -> Bool {
        text.hasPattern(#"^\s*melt\b"#, caseInsensitive: true)
            && text.rangeOfPattern(#"\b(add|adding|stir in|whisk in|cook|sauté|saute|pour)\b"#, caseInsensitive: true) == nil
            && text.split(whereSeparator: \.isWhitespace).count <= 35
    }

    /// "Meanwhile, …" or "While the shallots cook, …"
    static func runsAlongside(_ text: String) -> Bool {
        text.hasPattern(#"^\s*(meanwhile|in the meantime|while\b)"#, caseInsensitive: true)
    }

    /// Which stage a step belongs to. The action that takes the longest
    /// decides ("Pour on the batter… bake about 50 minutes" is Bake); a step
    /// with no times goes by its strongest action, heat first.
    static func stage(for text: String) -> CookStage? {
        var plain = text.replacingPattern(#"\([^)]*\)"#, with: " ")
        // Coming up to temperature is cooking, not yet simmering
        plain = plain.replacingPattern(
            #"\b(bring|return)\b[^.]{0,60}?\bto\s+(a\s+)?(gentle\s+|low\s+|rolling\s+|full\s+|bare\s+)?(simmer|boil)\b"#,
            with: "heat it", caseInsensitive: true)
        plain = plain.replacingPattern(ignoredPhrases, with: " ", caseInsensitive: true)

        // A heading names it outright: "Cook the chickpeas: …", "Assemble: …"
        if let colon = plain.firstIndex(of: ":"), plain.distance(from: plain.startIndex, to: colon) <= 40 {
            let heading = String(plain[..<colon])
            if !heading.lowercased().hasPrefix("to "),
               let named = timedPriority.first(where: { matches($0, in: heading) }) {
                return named
            }
        }

        let parts = sentences(of: withoutLeadIns(plain))
        var minutes: [CookStage: Int] = [:]
        for part in parts {
            var longest = CookPlanner.durations(in: part).map { $0.upperSeconds ?? $0.seconds }.reduce(0, +)
            if part.hasPattern(#"\bovernight\b"#, caseInsensitive: true) { longest += 8 * 3600 }
            if longest > 0, let stage = timedPriority.first(where: { matches($0, in: part) }) {
                minutes[stage, default: 0] += longest
            }
        }
        if let most = minutes.values.max() {
            return timedPriority.first { minutes[$0] == most }
        }
        let text = parts.joined(separator: "\n")
        if let heat = heatStages.first(where: { matches($0, in: text) }) {
            return heat
        }
        let counts = lightStages.map { stage in
            (stage, Patterns.regex(stagePatterns[stage]!, caseInsensitive: true)
                .numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)))
        }
        guard let best = counts.map(\.1).max(), best > 0 else { return nil }
        return counts.first { $0.1 == best }?.0
    }

    private static func matches(_ stage: CookStage, in text: String) -> Bool {
        text.hasPattern(stagePatterns[stage]!, caseInsensitive: true)
    }

    /// Where a time is given, the stage that takes the most of it ("Bake 50
    /// minutes" over "a minute or two" on the burner; two sears over a cool).
    private static let timedPriority: [CookStage] = [.bake, .grill, .simmer, .cook, .chill, .rest, .mix, .serve, .assemble, .prep]
    /// Otherwise heat comes first (a step that mixes and then bakes is a
    /// bake)…
    private static let heatStages: [CookStage] = [.bake, .grill, .simmer, .cook]
    /// …and then whatever the step does most ("Cut… dice… peel… roll" is
    /// prep); an untimed "let it cool slightly" doesn't outweigh the stirring.
    private static let lightStages: [CookStage] = [.serve, .mix, .assemble, .chill, .rest, .prep]

    private static let stagePatterns: [CookStage: String] = [
        .bake: #"\b(bake|bakes|baking|roast|roasts|roasting|broil|broils|broiling|in(to)?\s+the\s+(hot\s+|preheated\s+)?oven)\b"#,
        .grill: #"\b(grill|grills|grilling|barbecue)\b"#,
        .simmer: #"\b(simmer|simmers|simmering|braise|braises|braising|poach|poaches|poaching|blanch|blanches|blanching|boil|boils|boiling)\b"#,
        .cook: #"\b(cook|cooks|cooking|saut[ée]|saut[ée]s|saut[ée]ing|fry|fries|frying|stir-fry|sear|sears|searing|brown|browns|browning|toast|toasts|toasting|heats|heating|caramelize|caramelizes|caramelizing|wilt|wilts|scramble|melt|melts|melting|microwave|burner|stovetop|stove)\b|\bheat\s+(the|a|an|some|oil|olive|butter|vegetable|canola|your|it|them|until|through|over|in|on)\b|(^|\n)\s*heat\b|\bheated\b|\bwarm\s+(the|a|an|some|it|them|up|through)\b|\buntil\b[^.,]{0,30}\b(golden|browned|translucent|fragrant|crispy|crisp|charred|softened|caramelized|shimmering)\b"#,
        .chill: #"\b(chill|chills|chilling|refrigerate|refrigerating|freeze|freezing|fridge|freezer)\b"#,
        .rest: #"\b(rest|rests|resting|cool|cools|cooling|rise|rises|rising|proof|proofs|proofing|stand|stands|sit|sits|marinate|marinates|marinating|soak|soaks|soaking|steep|steeps)\b"#,
        .mix: #"\b(mix|mixes|mixing|whisk|whisks|whisking|blend|blends|blending|beat|beats|beating|combine|combines|stir|stirs|stirring|fold|folds|folding|knead|kneads|kneading|toss|tosses|tossing|pur[ée]e|pulse|process|emulsify|batter|dough|dressing)\b"#,
        .serve: #"\b(serve|serves|serving|garnish|garnishes|enjoy|dig in)\b|\b(transfer|divide|ladle|spoon)\b[^.]*\b(bowls|plates|platter)\b"#,
        .assemble: #"\b(assemble|assembling|layer|layers|layering|spread|spreads|arrange|arranges|fill|fills|roll|rolls|shape|shapes|stuff|stuffs|wrap|wraps|sprinkle|sprinkles|drizzle|drizzles|scatter|build)\b|\btop\s+(with|each|it|them|the)\b"#,
        .prep: #"\b(chop|chops|dice|dices|slice|slices|mince|cut|cuts|peel|peels|grate|grates|shred|trim|trims|grease|greases|spray|measure|rinse|rinses|wash|halve|zest|season|seasons|prepare|prep|drain|smash|dredge)\b|\b(butter|line|oil|pit|core|juice)\s+(a|the)\b|\bpat\s+(dry|the|it|them)\b"#,
    ]

    /// Words that look like actions but aren't: "baking dish", "brown sugar",
    /// "the rest of the batter", "reduce the heat".
    private static let ignoredPhrases = #"\b(brown sugar|brown rice|cooking spray|cooking oil|baking soda|baking powder|frying pan|saut[ée] pan|serving (bowl|dish|plate|platter|spoon)s?|plastic wrap|baking (dish|sheet|pan|tray|paper|stone|tin|mat)|roasting (pan|tray|rack)|grill pan|heat-?proof|heavy cream|stand mixer|(the )?rest of|cool water|cool,? dry|((reduce|lower|raise|increase|adjust)( the)?|turn (the )?(heat )?(down|up|off)|remove from( the)?|off the) heat|(over|on) (low|medium|medium-low|medium-high|high|moderate) heat)\b"#


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
                  text.rangeOfPattern(#"\b(cans?|canned|jars?|jarred|store-bought|pre-\w+)\b"#, caseInsensitive: true) == nil
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

    /// Everything with a measured amount that isn't already on a cut card, in
    /// the order it's needed. Opening a can or counting cloves isn't measuring.
    static func measureTasks(for recipe: Recipe, plan: CookPlan) -> [MeasureTask] {
        let cut = Set(prepTasks(for: recipe, plan: plan).flatMap(\.ingredientIndices))
        return recipe.allIngredients.enumerated()
            .compactMap { index, ingredient -> (step: Int, task: MeasureTask)? in
                guard !cut.contains(index) else { return nil }
                let parsed = CookPlanner.parseIngredient(ingredient.text)
                guard let unit = parsed.amount.split(separator: " ").last?.lowercased(),
                      measuringUnits.contains(unit), !parsed.name.isEmpty else { return nil }
                let step = plan.firstUseStep(ofIngredient: index) ?? Int.max
                return (step, MeasureTask(amount: parsed.amount, name: parsed.name, ingredientIndex: index))
            }
            .sorted { ($0.step, $0.task.ingredientIndex) < ($1.step, $1.task.ingredientIndex) }
            .map(\.task)
    }

    private static let measuringUnits: Set<String> = [
        "cup", "cups", "tbsp", "tsp", "lb", "oz", "g", "kg", "ml", "l", "quart", "quarts", "pint", "pints"
    ]

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
                    lowered.hasPattern(#"\b"# + $0.0 + #"\b"#)
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
        for (word, verb) in knifeWords where lowered.hasPattern(#"\b"# + word + #"\b"#) {
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
            guard let range = lowered.rangeOfPattern(#"\b"# + word + #"\b"#) else { continue }
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
