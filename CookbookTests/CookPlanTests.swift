import XCTest

// CookPlan.swift and Recipe.swift are compiled directly into this target,
// so no module import is needed.

final class CookPlanTests: XCTestCase {

    /// The sample soup every new cookbook starts with (SampleRecipe.swift).
    private let soup = Recipe(
        title: "Caramelized Tomato and Shallot Soup",
        ingredients: [
            Ingredient(text: "1/4 cup extra-virgin olive oil, plus more for serving"),
            Ingredient(text: "1 pound shallots, halved and thinly sliced (about 4 cups)"),
            Ingredient(text: "3 pounds tomatoes, cored and chopped (about 6 cups)"),
            Ingredient(text: "Kosher salt and black pepper"),
            Ingredient(text: "3 large garlic cloves, minced"),
            Ingredient(text: "1 tsp sugar"),
            Ingredient(text: "1/4 cup tomato paste"),
            Ingredient(text: "1/2 packed cup fresh basil leaves, plus more for serving"),
            Ingredient(text: "1/4 cup heavy cream (optional)")
        ],
        directions: [
            Direction(text: "Warm the olive oil in a Dutch oven or heavy pot over medium heat. Add the shallots and cook until soft, jammy and caramelized, 20 to 25 minutes, stirring now and then and turning the heat down if the edges start to crisp.", order: 1),
            Direction(text: "While the shallots cook, set a colander over a large bowl and add the chopped tomatoes. Toss them with 1 teaspoon salt and leave them to drain, tossing again every so often to draw out as much liquid as they'll give. Keep the liquid in the bowl — you'll need it in step 6.", order: 2),
            Direction(text: "Once the shallots are caramelized, add the drained tomatoes to the pot along with the garlic and sugar.", order: 3),
            Direction(text: "Keep cooking over medium heat, stirring often and scraping the bottom, until the tomato juices in the pan have cooked down and the mixture starts to brown on the bottom, about 20 minutes.", order: 4),
            Direction(text: "Stir in the tomato paste and cook another 5 to 10 minutes, until everything is thick and caramelized and there are brown patches on the bottom of the pan.", order: 5),
            Direction(text: "Top up the reserved tomato liquid with water to make 3 cups total, then pour it into the pot. Stir in the basil and 1/2 teaspoon salt, scraping the caramelized bits off the bottom. Bring to a simmer, then purée with an immersion blender until it's as smooth as you like it.", order: 6),
            Direction(text: "Stir in the cream, if you're using it, and season with salt and pepper. Serve warm, with a drizzle of olive oil and a few basil leaves on top.", order: 7)
        ]
    )

    private func names(_ step: CookStep) -> [String] {
        step.items.map { [$0.amount, $0.name].filter { !$0.isEmpty }.joined(separator: " ") }
    }

    // MARK: - Ingredient lines

    func testParseIngredient_amountNameAndNote() {
        let shallots = CookPlanner.parseIngredient("1 pound shallots, halved and thinly sliced (about 4 cups)")
        XCTAssertEqual(shallots.amount, "1 lb")
        XCTAssertEqual(shallots.name, "shallots")
        XCTAssertEqual(shallots.note, "halved and thinly sliced")
        XCTAssertFalse(shallots.isReusable)
    }

    func testParseIngredient_plusMoreForServingIsReusable() {
        let oil = CookPlanner.parseIngredient("1/4 cup extra-virgin olive oil, plus more for serving")
        XCTAssertEqual(oil.amount, "¼ cup")
        XCTAssertEqual(oil.name, "extra-virgin olive oil")
        XCTAssertEqual(oil.note, "")
        XCTAssertTrue(oil.isReusable)
        XCTAssertEqual(oil.reuseNote, "for serving")
        XCTAssertTrue(oil.terms.contains("olive oil"))
    }

    func testParseIngredient_optionalParentheticalBecomesNote() {
        let cream = CookPlanner.parseIngredient("1/4 cup heavy cream (optional)")
        XCTAssertEqual(cream.amount, "¼ cup")
        XCTAssertEqual(cream.name, "heavy cream")
        XCTAssertEqual(cream.note, "optional")
        XCTAssertTrue(cream.terms.contains("cream"))
    }

    func testParseIngredient_noAmount() {
        let seasoning = CookPlanner.parseIngredient("Kosher salt and black pepper")
        XCTAssertEqual(seasoning.amount, "")
        XCTAssertEqual(seasoning.terms.sorted(), ["pepper", "salt"])
        XCTAssertTrue(seasoning.isReusable)
    }

    func testParseIngredient_containerWordsDropForMatching() {
        XCTAssertTrue(CookPlanner.parseIngredient("3 large garlic cloves, minced").terms.contains("garlic"))
        XCTAssertTrue(CookPlanner.parseIngredient("1/2 packed cup fresh basil leaves").terms.contains("basil"))
        XCTAssertTrue(CookPlanner.parseIngredient("1 tablespoon vanilla extract").terms.contains("vanilla"))
    }

    func testHeuristicPlan_vanillaExtractIsVanillaInTheSteps() {
        let clafoutis = Recipe(
            ingredients: ["1 and 1/4 cups whole or 2 percent milk", "2/3 cup granulated sugar, divided", "3 eggs",
                          "1 tablespoon vanilla extract", "1/8 teaspoon salt", "1 cup flour"].map { Ingredient(text: $0) },
            directions: [Direction(text: "Place the milk, 1/3 cup granulated sugar, eggs, vanilla, salt and flour in a blender. Blend at top speed until smooth and frothy, about 1 minute.", order: 1)]
        )
        let plan = CookPlanner.heuristicPlan(for: clafoutis)
        XCTAssertTrue(plan.steps[0].items.contains { $0.ingredientIndex == 3 }, "vanilla goes in with the rest")
    }

    func testParseIngredient_extrasAfterAPlusAreNotPartOfTheName() {
        XCTAssertTrue(CookPlanner.parseIngredient("¼ cup roughly chopped fresh basil + additional for garnish").terms.contains("basil"))
    }

    func testParseIngredient_mixedFraction() {
        XCTAssertEqual(CookPlanner.parseIngredient("1 1/2 cups flour").amount, "1½ cups")
    }

    // MARK: - Heuristic plan

    func testHeuristicPlan_soupStepsListWhatGoesIn() {
        let plan = CookPlanner.heuristicPlan(for: soup)
        XCTAssertEqual(plan.steps.count, 7)
        XCTAssertEqual(names(plan.steps[0]), ["¼ cup extra-virgin olive oil", "1 lb shallots"])
        XCTAssertEqual(names(plan.steps[1]), ["3 lb tomatoes", "1 tsp salt"])
        XCTAssertEqual(names(plan.steps[2]), ["3 large garlic cloves", "1 tsp sugar"])
        XCTAssertEqual(names(plan.steps[3]), [])
        XCTAssertEqual(names(plan.steps[4]), ["¼ cup tomato paste"])
    }

    func testHeuristicPlan_passingMentionsAreLeftOut() {
        // "While the shallots cook" isn't adding shallots, and "tomato juices" aren't the tomatoes
        let plan = CookPlanner.heuristicPlan(for: soup)
        XCTAssertFalse(plan.steps[1].items.contains { $0.ingredientIndex == 1 })
        XCTAssertTrue(plan.steps[3].items.isEmpty)
    }

    func testHeuristicPlan_secondMeasuredAdditionUsesTheStepsAmount() {
        let step6 = CookPlanner.heuristicPlan(for: soup).steps[5]
        XCTAssertTrue(names(step6).contains("½ tsp salt"))
        XCTAssertTrue(names(step6).contains("½ packed cup fresh basil leaves"))
    }

    func testHeuristicPlan_forwardReferenceShowsUpOnTheLaterStep() {
        let step6 = CookPlanner.heuristicPlan(for: soup).steps[5]
        let carried = step6.items.first { $0.ingredientIndex == nil }
        XCTAssertEqual(carried?.name, "The liquid in the bowl")
        XCTAssertEqual(carried?.preparedInStep, 1)
    }

    func testHeuristicPlan_servingAdditionsAreNotLeftovers() {
        let step7 = CookPlanner.heuristicPlan(for: soup).steps[6]
        let oil = step7.items.first { $0.ingredientIndex == 0 }
        XCTAssertNotNil(oil)
        XCTAssertNil(oil?.preparedInStep)
        XCTAssertEqual(oil?.note, "for serving")
        XCTAssertEqual(step7.items.first { $0.ingredientIndex == 8 }?.note, "optional")
    }

    func testFirstUseChecksOffEachIngredientOnce() {
        let plan = CookPlanner.heuristicPlan(for: soup)
        XCTAssertEqual(plan.ingredientsFirstUsed(inStep: 0), [0, 1])
        XCTAssertEqual(plan.ingredientsFirstUsed(inStep: 1), [2, 3])
        XCTAssertEqual(plan.ingredientsFirstUsed(inStep: 5), [7])
        XCTAssertEqual(plan.ingredientsFirstUsed(inStep: 6), [8])
        let all = (0..<7).flatMap { plan.ingredientsFirstUsed(inStep: $0) }
        XCTAssertEqual(all.sorted(), Array(0..<9))
    }

    // MARK: - Times

    func testDurations() {
        let ranged = CookPlanner.durations(in: soup.directions[0].text)
        XCTAssertEqual(ranged.map(\.label), ["20–25 min"])
        XCTAssertEqual(ranged.first?.seconds, 1200)
        XCTAssertEqual(ranged.first?.extraSeconds, 300, "the rest of the 20 to 25 minute range")

        let about = CookPlanner.durations(in: soup.directions[3].text)
        XCTAssertEqual(about.map(\.label), ["20 min"])
        XCTAssertEqual(CookPlanner.durations(in: "Bake 30 to 45 minutes.").first?.extraSeconds, 900)

        XCTAssertEqual(CookPlanner.durations(in: "Bake for 1 hour.").first?.seconds, 3600)
        // The tappable time is the time itself, not "for" or "another" before it
        let text = "Cook another 5 to 10 minutes, then bake for 1 hour, about 20 minutes more."
        XCTAssertEqual(CookPlanner.durations(in: text).map { String(text[$0.range]) }, ["5 to 10 minutes", "1 hour", "about 20 minutes"])
        XCTAssertTrue(CookPlanner.durations(in: "Add 3 cups of water.").isEmpty)
    }

    func testDurationsWithFractionsAndWords() {
        let osso = CookPlanner.durations(in: "Cook until the meat is tender, about 1 to 1 1/2 hours.")
        XCTAssertEqual(osso.count, 1, "never the 2 hours inside 1/2 hours")
        XCTAssertEqual(osso.first?.seconds, 3600)
        XCTAssertEqual(osso.first?.upperSeconds, 5400)
        XCTAssertEqual(osso.first?.label, "1–1½ hr")
        XCTAssertEqual(CookPlanner.durations(in: "Rest for 1½ hours.").first?.seconds, 5400)
        let burner = CookPlanner.durations(in: "Set the dish on the burner for a minute or two.")
        XCTAssertEqual(burner.first?.seconds, 60)
        XCTAssertEqual(burner.first?.upperSeconds, 120)
        XCTAssertEqual(CookPlanner.durations(in: "Refrigerate for at least an hour.").first?.seconds, 3600)
        XCTAssertEqual(CookPlanner.durations(in: "Chill for half an hour.").first?.seconds, 1800)
        let more = CookPlanner.durations(in: "Continue cooking for about 10 to 15 more minutes.")
        XCTAssertEqual(more.first?.label, "10–15 min")
        XCTAssertEqual(CookPlanner.durations(in: "Bake for 20 minutes, then broil a minute.").count, 2)
    }

    // MARK: - Checking the model's rewrite

    func testNumbersTreatFractionGlyphsAsTheSame() {
        XCTAssertEqual(CookPlanner.numbers(in: "Stir in 1/2 teaspoon salt"), CookPlanner.numbers(in: "Stir in ½ teaspoon salt"))
    }

    func testShortTextKeepingEveryNumberIsAccepted() {
        let original = soup.directions[5].text
        let short = "Add water to the saved tomato liquid to make 3 cups and pour it in. Stir in the basil and ½ teaspoon salt, scraping up the bits. Simmer, then purée until smooth."
        XCTAssertEqual(CookPlanner.acceptedShortText(short, original: original), short)
    }

    func testShortTextThatDropsANumberIsRejected() {
        let original = soup.directions[5].text
        let short = "Add water to the saved tomato liquid and pour it in. Stir in the basil and ½ teaspoon salt. Simmer, then purée until smooth."
        XCTAssertNil(CookPlanner.acceptedShortText(short, original: original))
    }

    func testShortTextThatInventsANumberIsRejected() {
        let original = soup.directions[0].text
        let short = "Warm the olive oil over medium heat. Add the shallots and cook until jammy, 20 to 25 minutes, on heat 4."
        XCTAssertNil(CookPlanner.acceptedShortText(short, original: original))
    }

    func testShortTextThatDropsAnIngredientIsRejected() {
        // Seen from the on-device model: the oil and basil for serving went missing
        let ingredients = soup.allIngredients.map(\.text)
        let original = soup.directions[6].text
        XCTAssertNil(CookPlanner.acceptedShortText(
            "Stir in the cream, if using, and season with salt and pepper. Serve warm.",
            original: original, ingredientTexts: ingredients
        ))
        XCTAssertNotNil(CookPlanner.acceptedShortText(
            "Stir in the cream if using. Season with salt and pepper. Serve with olive oil and basil on top.",
            original: original, ingredientTexts: ingredients
        ))
    }

    func testNumberingTheModelAddsIsStripped() {
        let original = soup.directions[1].text
        let short = "1. Toss the chopped tomatoes with 1 teaspoon salt in a colander over a bowl. Let them drain. Save the liquid for step 6."
        XCTAssertEqual(
            CookPlanner.acceptedShortText(short, original: original),
            "Toss the chopped tomatoes with 1 teaspoon salt in a colander over a bowl. Let them drain. Save the liquid for step 6."
        )
    }

    func testShortStepsAreNotRewritten() {
        XCTAssertNil(CookPlanner.acceptedShortText("Add the tomatoes, garlic and sugar.", original: soup.directions[2].text))
    }

    // MARK: - Merging the model's suggestion

    func testMerge_keepsValidUsesAndDropsBadOnes() {
        let heuristic = CookPlanner.heuristicPlan(for: soup)
        var firstUse: [Int: Int] = [0: 0, 1: 0, 2: 1, 3: 1]
        let suggestion = SuggestedStep(
            shortText: "",
            uses: [
                .init(ingredientNumber: 3, amount: "", name: "drained tomatoes"),
                .init(ingredientNumber: 5, amount: "3", name: "garlic"),
                .init(ingredientNumber: 6, amount: "2 tsp", name: "sugar"),   // the recipe says 1
                .init(ingredientNumber: 42, amount: "", name: "saffron")      // not an ingredient
            ],
            carryOvers: [.init(name: "drained tomatoes", stepNumber: 2)]
        )
        let step = CookPlanner.merge(
            suggestion, into: heuristic.steps[2], stepIndex: 2,
            stepTexts: soup.directions.map(\.text),
            ingredientTexts: soup.allIngredients.map(\.text),
            firstUse: &firstUse
        )

        let tomatoes = step.items.first { $0.ingredientIndex == 2 }
        XCTAssertEqual(tomatoes?.name, "drained tomatoes")
        XCTAssertEqual(tomatoes?.preparedInStep, 1)
        XCTAssertFalse(step.items.contains { $0.ingredientIndex == nil }, "the tomatoes already have a row")

        let garlic = step.items.first { $0.ingredientIndex == 4 }
        XCTAssertEqual(garlic?.amount, "3")
        XCTAssertEqual(garlic?.name, "large garlic cloves", "a bare count keeps the full name")
        // The invented amount falls back to the ingredient line's
        XCTAssertEqual(step.items.first { $0.ingredientIndex == 5 }?.amount, "1 tsp")
        XCTAssertFalse(step.items.contains { $0.name == "saffron" })
        XCTAssertEqual(firstUse[4], 2)
        XCTAssertNil(step.shortText)
    }

    func testMerge_carryOverFromAnEarlierStep() {
        let heuristic = CookPlanner.heuristicPlan(for: soup)
        var firstUse: [Int: Int] = [:]
        let suggestion = SuggestedStep(
            shortText: "",
            uses: [],
            carryOvers: [
                .init(name: "reserved tomato liquid", stepNumber: 2),
                .init(name: "something from the future", stepNumber: 7)
            ]
        )
        let step = CookPlanner.merge(
            suggestion, into: heuristic.steps[5], stepIndex: 5,
            stepTexts: soup.directions.map(\.text),
            ingredientTexts: soup.allIngredients.map(\.text),
            firstUse: &firstUse
        )
        let carried = step.items.filter { $0.ingredientIndex == nil }
        XCTAssertEqual(carried.map(\.name), ["Reserved tomato liquid"])
        XCTAssertEqual(carried.first?.preparedInStep, 1)
        XCTAssertTrue(carried.first?.highlightTerms.contains("tomato liquid") ?? false)
        // The model left out the basil; the text-only plan still has it
        XCTAssertTrue(step.items.contains { $0.ingredientIndex == 7 })
    }

    func testMerge_wrongNumberOrUnmentionedIngredientIsDropped() {
        let heuristic = CookPlanner.heuristicPlan(for: soup)
        var firstUse: [Int: Int] = [:]
        // Seen from the on-device model: the tomatoes' number with the name "garlic"
        let suggestion = SuggestedStep(
            shortText: "",
            uses: [
                .init(ingredientNumber: 1, amount: "", name: "olive oil"),
                .init(ingredientNumber: 3, amount: "3 lb", name: "garlic"),
                .init(ingredientNumber: 2, amount: "", name: "")
            ],
            carryOvers: [.init(name: "drained tomatoes", stepNumber: 1)]
        )
        let step = CookPlanner.merge(
            suggestion, into: heuristic.steps[0], stepIndex: 0,
            stepTexts: soup.directions.map(\.text),
            ingredientTexts: soup.allIngredients.map(\.text),
            firstUse: &firstUse
        )
        XCTAssertEqual(step.items.compactMap(\.ingredientIndex), [0, 1])
        XCTAssertEqual(firstUse, [0: 0, 1: 0])
    }

    func testMerge_nameWinsOverAMismatchedNumber() {
        let heuristic = CookPlanner.heuristicPlan(for: soup)
        var firstUse: [Int: Int] = [0: 0, 1: 0]
        let suggestion = SuggestedStep(
            shortText: "",
            uses: [.init(ingredientNumber: 5, amount: "1 tsp", name: "kosher salt")],
            carryOvers: [.init(name: "drained tomatoes", stepNumber: 1)]
        )
        let step = CookPlanner.merge(
            suggestion, into: heuristic.steps[1], stepIndex: 1,
            stepTexts: soup.directions.map(\.text),
            ingredientTexts: soup.allIngredients.map(\.text),
            firstUse: &firstUse
        )
        let salt = step.items.filter { $0.ingredientIndex == 3 }
        XCTAssertEqual(salt.count, 1)
        XCTAssertEqual(salt.first?.name, "kosher salt")
        XCTAssertFalse(step.items.contains { $0.ingredientIndex == 4 })
        // Step 1 never mentions tomatoes, so nothing carries over from it
        XCTAssertFalse(step.items.contains { $0.ingredientIndex == nil })
        XCTAssertEqual(firstUse[2], 1)
    }

    // MARK: - Highlighting

    func testHighlightPrefersTheLongerName() {
        let text = "Stir in the tomato paste and the tomatoes."
        let ranges = CookPlanner.highlightRanges(in: text, terms: ["tomato", "tomato paste", "tomatoes"])
        XCTAssertEqual(ranges.map { String(text[$0]) }, ["tomato paste", "tomatoes"])
    }

    // MARK: - Recipe progress

    func testStepsFollowTheirOrderNotArrayPosition() {
        var recipe = Recipe(directions: [
            Direction(text: "Second", order: 2),
            Direction(text: "First", order: 1)
        ])
        recipe.setStepCompleted(0, true)
        XCTAssertTrue(recipe.directions.first { $0.text == "First" }!.isCompleted)
        XCTAssertEqual(recipe.firstIncompleteStepIndex, 1)
        recipe.setStepCompleted(1, true)
        XCTAssertEqual(recipe.firstIncompleteStepIndex, 2)
    }

    func testIngredientIndexSpansSections() {
        var recipe = Recipe(ingredientSections: [
            IngredientSection(name: "Dough", ingredients: [Ingredient(text: "flour"), Ingredient(text: "water")]),
            IngredientSection(name: "Filling", ingredients: [Ingredient(text: "apples")])
        ])
        recipe.setIngredientChecked(2, true)
        XCTAssertTrue(recipe.ingredientSections[1].ingredients[0].isChecked)
        XCTAssertTrue(recipe.isIngredientChecked(2))
        XCTAssertFalse(recipe.isIngredientChecked(1))
    }
}
