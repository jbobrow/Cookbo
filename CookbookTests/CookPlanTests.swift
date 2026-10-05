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

    private let clafoutis = Recipe(
        ingredients: ["Butter for pan", "1 and 1/4 cups whole or 2 percent milk", "2/3 cup granulated sugar, divided", "3 eggs",
                      "1 tablespoon vanilla extract", "1/8 teaspoon salt", "1 cup flour",
                      "1 pint (2 generous cups) blackberries or blueberries, rinsed and well drained",
                      "Powdered sugar in a shaker"].map { Ingredient(text: $0) },
        directions: [
            Direction(text: "Place the milk, 1/3 cup granulated sugar, eggs, vanilla, salt and flour in a blender. Blend at top speed until smooth and frothy, about 1 minute.", order: 1),
            Direction(text: "Spread berries over the batter and sprinkle on the remaining 1/3 cup granulated sugar. Pour on the rest of the batter and smooth with the back of a spoon.", order: 2)
        ]
    )

    func testHeuristicPlan_clafoutisListsEverythingThatGoesIn() {
        let plan = CookPlanner.heuristicPlan(for: clafoutis)
        XCTAssertEqual(names(plan.steps[0]), ["1¼ cups whole or 2 percent milk", "⅓ cup granulated sugar", "3 eggs",
                                              "1 tbsp vanilla extract", "⅛ tsp salt", "1 cup flour"],
                       "vanilla is the vanilla extract, and \"1 and 1/4\" is 1¼")
        XCTAssertTrue(plan.steps[1].items.contains { $0.ingredientIndex == 7 }, "the berries are the blackberries or blueberries")
    }

    func testHighlightIsJustTheIngredient() {
        let plan = CookPlanner.heuristicPlan(for: clafoutis)
        let text = clafoutis.directions[0].text
        let highlighted = CookPlanner.highlightRanges(in: text, terms: plan.steps[0].items.flatMap(\.highlightTerms)).map { String(text[$0]) }
        XCTAssertTrue(highlighted.contains("granulated sugar"))
        XCTAssertFalse(highlighted.contains("cup"), "the milk's \"cups\" isn't a name")
        XCTAssertTrue(highlighted.contains("vanilla"))
    }

    func testOrSharesTheNoun() {
        let terms = CookPlanner.parseIngredient("4 cups chicken or vegetable broth").terms
        XCTAssertTrue(terms.contains("chicken broth"))
        XCTAssertFalse(terms.contains("chicken"), "chicken here is a kind of broth")
        XCTAssertTrue(CookPlanner.parseIngredient("salt and black pepper").terms.contains("salt"))
        XCTAssertFalse(CookPlanner.parseIngredient("1 cup almond milk").terms.contains("nuts"))
        XCTAssertTrue(CookPlanner.parseIngredient("1/2 cup chopped pecans").terms.contains("nuts"))
    }

    func testTidyAmountsAndFractions() {
        XCTAssertEqual(CookPlanner.tidyAmount("1 and 1/4 cups"), "1¼ cups")
        XCTAssertEqual(CookPlanner.tidyAmount("1/8 teaspoon"), "⅛ tsp")
        XCTAssertEqual(CookPlanner.tidyAmount("1.5 tablespoons"), "1½ tbsp")
        XCTAssertEqual(CookPlanner.tidyAmount("0.5 cup"), "½ cup")
        XCTAssertEqual(CookPlanner.prettyFractions(in: "Add 1/3 cup sugar and 1 1/2 cups milk; cut into 3/4-inch pieces."),
                       "Add ⅓ cup sugar and 1½ cups milk; cut into ¾-inch pieces.")
        XCTAssertEqual(CookPlanner.prettyFractions(in: "Use 3/16 inch and 1.5 cups."), "Use 3/16 inch and 1½ cups.", "no glyph, no change")
        XCTAssertEqual(CookPlanner.durations(in: "Bake for 1 and 1/2 hours.").first?.seconds, 5400)
    }

    func testParseIngredient_extrasAfterAPlusAreNotPartOfTheName() {
        XCTAssertTrue(CookPlanner.parseIngredient("¼ cup roughly chopped fresh basil + additional for garnish").terms.contains("basil"))
    }

    func testParseIngredient_mixedFraction() {
        XCTAssertEqual(CookPlanner.parseIngredient("1 1/2 cups flour").amount, "1½ cups")
    }

    func testParseIngredient_numberGluedToTheNextWord() {
        let garlic = CookPlanner.parseIngredient("1large garlic clove, minced")
        XCTAssertEqual(garlic.amount, "1")
        XCTAssertEqual(garlic.name, "large garlic clove")
        XCTAssertTrue(garlic.terms.contains("garlic"))

        let mustard = CookPlanner.parseIngredient("¾teaspoon Dijon mustard")
        XCTAssertEqual(mustard.amount, "¾ tsp")
        XCTAssertEqual(mustard.name, "Dijon mustard")

        XCTAssertEqual(CookPlanner.parseIngredient("1½teaspoons Worcestershire sauce").amount, "1½ tsp")
        XCTAssertEqual(CookPlanner.parseIngredient("1/2cup skin-on almonds").amount, "½ cup")
        XCTAssertEqual(CookPlanner.parseIngredient("1large head romaine lettuce").amount, "1 large head")
        XCTAssertEqual(CookPlanner.parseIngredient("20thin baguette slices").name, "thin baguette slices")
        XCTAssertEqual(CookPlanner.parseIngredient("475g bread flour").amount, "475 g")
        XCTAssertEqual(CookPlanner.parseIngredient("4 to 6anchovy fillets, minced").name, "anchovy fillets")
    }

    func testParseIngredient_ranges() {
        let anchovies = CookPlanner.parseIngredient("4 to 6 anchovy fillets, minced")
        XCTAssertEqual(anchovies.amount, "4 to 6")
        XCTAssertEqual(anchovies.name, "anchovy fillets")
        XCTAssertEqual(CookPlanner.parseIngredient("12-16 oz fresh mozzarella").amount, "12–16 oz")
        XCTAssertEqual(CookPlanner.parseIngredient("5 to 6 ounces baby spinach").amount, "5 to 6 oz")
        XCTAssertEqual(CookPlanner.parseIngredient("¼ to ½ teaspoon red pepper flakes").amount, "¼ to ½ tsp")
        XCTAssertEqual(CookPlanner.parseIngredient("4 15-ounce cans black beans").amount, "4", "a count, then the can size")
    }

    func testParseIngredient_checkboxesAndNestedParentheses() {
        let tomatoes = CookPlanner.parseIngredient("▢ ½ cup cherry tomatoes, sliced (95g)")
        XCTAssertEqual(tomatoes.amount, "½ cup")
        XCTAssertEqual(tomatoes.name, "cherry tomatoes")
        XCTAssertEqual(CookPlanner.parseIngredient("2½ cups shredded whole milk mozzarella cheese ((12 ounces))").name,
                       "shredded whole milk mozzarella cheese")
        let parsley = CookPlanner.parseIngredient("2 tablespoons chopped fresh Italian parsley, (for serving (optional))")
        XCTAssertEqual(parsley.name, "chopped fresh Italian parsley")
        XCTAssertEqual(parsley.note, "optional")
    }

    func testParseIngredient_moreUnits() {
        XCTAssertEqual(CookPlanner.parseIngredient("1/4 c. finely chopped fresh parsley").amount, "¼ cup")
        XCTAssertEqual(CookPlanner.parseIngredient("8 c. low-sodium chicken stock").amount, "8 cups")
        let ginger = CookPlanner.parseIngredient("1 thumb ginger, grated")
        XCTAssertEqual(ginger.amount, "1 thumb")
        XCTAssertEqual(ginger.name, "ginger")
        XCTAssertEqual(CookPlanner.parseIngredient("1  handfull  chopped herbs").amount, "1 handful")
        XCTAssertEqual(CookPlanner.parseIngredient("2 carrots").amount, "2", "c isn't the start of carrots")
    }

    func testOrSharesTheNounWithAColor() {
        XCTAssertTrue(CookPlanner.parseIngredient("1 small white or yellow onion (diced)").terms.contains("white onion"))
        XCTAssertTrue(CookPlanner.parseIngredient("2 pounds baby red or gold potatoes").terms.contains("red potatoes"))
    }

    func testSpacingGluedNumbersLeavesEverythingElseAlone() {
        XCTAssertEqual(CookPlanner.spacingGluedNumbers(in: "4 to 6anchovy fillets"), "4 to 6 anchovy fillets")
        for text in ["1/2 cup", "1½ cups", "1 1/2 cups", "350°F", "a 9x13 pan", "the 2nd rack", "vitamin B12", "1/2-inch slices", "1.5 cups", "12-16 oz"] {
            XCTAssertEqual(CookPlanner.spacingGluedNumbers(in: text), text)
        }
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

    func testFirstUseStepOfEachIngredient() {
        let plan = CookPlanner.heuristicPlan(for: soup)
        XCTAssertEqual((0..<9).map { plan.firstUseStep(ofIngredient: $0) }.map { $0 ?? -1 }.prefix(4), [0, 0, 1, 1])
        XCTAssertEqual(plan.firstUseStep(ofIngredient: 7), 5)
        XCTAssertEqual(plan.firstUseStep(ofIngredient: 8), 6)
        XCTAssertTrue((0..<9).allSatisfy { plan.firstUseStep(ofIngredient: $0) != nil }, "every ingredient goes in somewhere")
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

    func testMerge_aPlaceholderIsntAnAmount() {
        let heuristic = CookPlanner.heuristicPlan(for: soup)
        var firstUse: [Int: Int] = [0: 0, 1: 0, 2: 1, 3: 1]
        let suggestion = SuggestedStep(
            shortText: "",
            uses: [
                .init(ingredientNumber: 5, amount: "none", name: "garlic"),
                .init(ingredientNumber: 6, amount: "N/A", name: "sugar")
            ],
            carryOvers: []
        )
        let step = CookPlanner.merge(
            suggestion, into: heuristic.steps[2], stepIndex: 2,
            stepTexts: soup.directions.map(\.text),
            ingredientTexts: soup.allIngredients.map(\.text),
            firstUse: &firstUse
        )
        XCTAssertEqual(step.items.first { $0.ingredientIndex == 4 }?.amount, "3", "falls back to the ingredient line")
        XCTAssertEqual(step.items.first { $0.ingredientIndex == 5 }?.amount, "1 tsp")
        XCTAssertFalse(step.items.contains { $0.amount.localizedCaseInsensitiveContains("none") })
    }

    /// The pot roast from halfbakedharvest.com, where the model answered
    /// "none" and "seasalt" for amounts.
    private let potRoast = Recipe(
        title: "Cider Braised Pot Roast",
        ingredients: [
            Ingredient(text: "1 (4 pound)  beef chuck roast"),
            Ingredient(text: "seasalt and black pepper"),
            Ingredient(text: "2 tablespoons all-purpose or gluten flour")
        ],
        directions: [
            Direction(text: "Preheat the oven to 325° F. Season the roast with salt and pepper, then coat with flour.", order: 1),
            Direction(text: "At the same time, return the roast to the oven, uncovered, for 10-15 minutes, until caramelized on top.", order: 2)
        ]
    )

    func testMerge_potRoastAmountsComeFromTheRecipe() {
        let heuristic = CookPlanner.heuristicPlan(for: potRoast)
        let texts = potRoast.directions.map(\.text), lines = potRoast.allIngredients.map(\.text)
        var firstUse: [Int: Int] = [:]
        let first = CookPlanner.merge(
            SuggestedStep(shortText: "", uses: [
                .init(ingredientNumber: 1, amount: "1", name: "beef chuck roast"),
                .init(ingredientNumber: 2, amount: "seasalt", name: "seasalt and black pepper"),
                .init(ingredientNumber: 3, amount: "2 tablespoons", name: "flour")
            ], carryOvers: []),
            into: heuristic.steps[0], stepIndex: 0, stepTexts: texts, ingredientTexts: lines, firstUse: &firstUse
        )
        XCTAssertEqual(first.items.first { $0.ingredientIndex == 0 }?.amount, "1 (4 lb)", "the count of a fuller amount gets the size")
        XCTAssertEqual(first.items.first { $0.ingredientIndex == 1 }?.amount, "", "a word from the name isn't an amount")
        XCTAssertEqual(first.items.first { $0.ingredientIndex == 2 }?.amount, "2 tbsp")

        let second = CookPlanner.merge(
            SuggestedStep(shortText: "", uses: [.init(ingredientNumber: 1, amount: "none", name: "beef chuck roast")], carryOvers: []),
            into: heuristic.steps[1], stepIndex: 1, stepTexts: texts, ingredientTexts: lines, firstUse: &firstUse
        )
        let roast = second.items.first { $0.ingredientIndex == 0 }
        XCTAssertEqual(roast?.amount, "")
        XCTAssertEqual(roast?.preparedInStep, 0, "the roast went in at step 1")
    }

    func testMerge_aWordedAmountFromTheRecipeIsKept() {
        let recipe = Recipe(
            ingredients: [Ingredient(text: "Kosher salt")],
            directions: [Direction(text: "Add a pinch of salt and stir.", order: 1)]
        )
        var firstUse: [Int: Int] = [:]
        let step = CookPlanner.merge(
            SuggestedStep(shortText: "", uses: [.init(ingredientNumber: 1, amount: "a pinch", name: "salt")], carryOvers: []),
            into: CookPlanner.heuristicPlan(for: recipe).steps[0], stepIndex: 0,
            stepTexts: recipe.directions.map(\.text), ingredientTexts: recipe.allIngredients.map(\.text), firstUse: &firstUse
        )
        XCTAssertEqual(step.items.first?.amount, "a pinch")
    }

    func testParseIngredient_sizeInParenthesesIsPartOfTheAmount() {
        let roast = CookPlanner.parseIngredient("1 (4 pound)  beef chuck roast")
        XCTAssertEqual(roast.amount, "1 (4 lb)")
        XCTAssertEqual(roast.name, "beef chuck roast")
        let chickpeas = CookPlanner.parseIngredient("2 (14-ounce) cans chickpeas, drained")
        XCTAssertEqual(chickpeas.amount, "2 (14 oz) cans")
        XCTAssertEqual(chickpeas.name, "chickpeas")
        XCTAssertEqual(chickpeas.note, "drained")
        let tomatoes = CookPlanner.parseIngredient("3 pounds tomatoes, cored and chopped (about 6 cups)")
        XCTAssertEqual(tomatoes.amount, "3 lb", "an aside after the name still goes")
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
