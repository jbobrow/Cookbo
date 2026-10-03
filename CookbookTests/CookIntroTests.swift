import XCTest

// CookIntro.swift, CookPlan.swift and Recipe.swift are compiled directly into
// this target, so no module import is needed.

final class CookIntroTests: XCTestCase {

    /// Best Vegetable Lasagna, which has the oven preheating and a sauce made
    /// "meanwhile" alongside the main line of work.
    private let lasagna = Recipe(
        title: "Best Vegetable Lasagna",
        ingredients: [
            Ingredient(text: "2 tablespoons extra-virgin olive oil"),
            Ingredient(text: "3 large carrots, chopped (about 1 cup)"),
            Ingredient(text: "1 red bell pepper, chopped"),
            Ingredient(text: "1 medium zucchini, chopped"),
            Ingredient(text: "1 medium yellow onion, chopped"),
            Ingredient(text: "¼ teaspoon salt"),
            Ingredient(text: "5 to 6 ounces baby spinach"),
            Ingredient(text: "1 large can (28 ounces) diced tomatoes"),
            Ingredient(text: "¼ cup roughly chopped fresh basil + additional for garnish"),
            Ingredient(text: "2 tablespoons extra-virgin olive oil"),
            Ingredient(text: "2 cloves garlic, pressed or minced"),
            Ingredient(text: "½ teaspoon salt"),
            Ingredient(text: "¼ teaspoon red pepper flakes"),
            Ingredient(text: "2 cups (16 ounces) low-fat cottage cheese, divided"),
            Ingredient(text: "¼ teaspoon salt, to taste"),
            Ingredient(text: "Freshly ground black pepper, to taste"),
            Ingredient(text: "9 no-boil lasagna noodles*"),
            Ingredient(text: "8 ounces (2 cups) freshly grated low-moisture, part-skim mozzarella cheese")
        ],
        directions: [
            Direction(text: "Preheat the oven to 425 degrees Fahrenheit.", order: 1),
            Direction(text: "To prepare the veggies: In a large skillet over medium heat, warm the olive oil. Once shimmering, add the carrots, bell pepper, zucchini, yellow onion, and salt. Cook, stirring every couple of minutes, until the veggies are golden on the edges, about 8 to 12 minutes.", order: 2),
            Direction(text: "Add a few large handfuls of spinach. Cook, stirring frequently, until the spinach has wilted. Repeat with remaining spinach and cook until all of the spinach has wilted, about 3 minutes. Remove the skillet from the heat and set aside.", order: 3),
            Direction(text: "Meanwhile, to prepare the tomato sauce: Pour the tomatoes into a mesh sieve or fine colander and drain off the excess juice for a minute. Then, transfer the drained tomatoes to the bowl of a food processor. Add the basil, olive oil, garlic, salt, and red pepper flakes.", order: 4),
            Direction(text: "Pulse the mixture about 10 times, until the tomatoes have broken down to an easily spreadable consistency. Pour the mixture into a bowl for later.", order: 5),
            Direction(text: "Spread ½ cup tomato sauce evenly over the bottom of a 9 by 9 baking dish. Layer 3 lasagna noodles on top. Spread half of the cottage cheese mixture evenly over the noodles. Top with ¾ cup tomato sauce, then sprinkle ½ cup shredded cheese on top.", order: 6),
            Direction(text: "Bake, covered, for 18 minutes, then remove the cover, rotate the pan by 180° and continue cooking for about 10 to 15 more minutes, until the top is turning spotty brown.", order: 7),
            Direction(text: "Remove from oven and let the lasagna cool for 15 to 20 minutes, so it has time to set. Sprinkle additional basil over the top, then slice and serve.", order: 8)
        ],
        prepDuration: 30 * 60
    )

    private let soup = Recipe(
        ingredients: [
            Ingredient(text: "1/4 cup extra-virgin olive oil, plus more for serving"),
            Ingredient(text: "1 pound shallots, halved and thinly sliced (about 4 cups)"),
            Ingredient(text: "3 pounds tomatoes, cored and chopped (about 6 cups)"),
            Ingredient(text: "Kosher salt and black pepper"),
            Ingredient(text: "3 large garlic cloves, minced"),
            Ingredient(text: "1 tsp sugar")
        ],
        directions: [
            Direction(text: "Warm the olive oil in a Dutch oven over medium heat. Add the shallots and cook until soft, jammy and caramelized, 20 to 25 minutes.", order: 1),
            Direction(text: "While the shallots cook, set a colander over a large bowl and add the chopped tomatoes. Toss them with 1 teaspoon salt and leave them to drain.", order: 2),
            Direction(text: "Once the shallots are caramelized, add the drained tomatoes to the pot along with the garlic and sugar.", order: 3)
        ]
    )

    /// Simple Green Salad: the preheat is in the middle of the roasting step.
    private let salad = Recipe(
        ingredients: [
            Ingredient(text: "2 small heads of soft lettuce, butter lettuce or similar"),
            Ingredient(text: "1 Persian cucumber, thinly sliced"),
            Ingredient(text: "¼ cup shaved Parmesan cheese"),
            Ingredient(text: "1 avocado, thinly sliced"),
            Ingredient(text: "½ cup raw almonds"),
            Ingredient(text: "½ tablespoon tamari")
        ],
        directions: [
            Direction(text: "Roast the almonds: Preheat the oven to 350°F and line a baking sheet with parchment paper. Place the almonds on the sheet and toss with tamari. Bake for 10 to 14 minutes or until browned. Remove from the oven and let cool for 5 minutes.", order: 1),
            Direction(text: "Assemble the salad. In a large bowl toss the lettuce with a few spoonfuls of the lemon vinaigrette. Add the cucumber, parmesan, avocado, and tamari almonds.", order: 2)
        ],
        prepDuration: 15 * 60
    )

    /// Julia Child's Berry Clafoutis: "Heat oven", a minute on the burner,
    /// then a long bake.
    private let clafoutis = Recipe(
        ingredients: [
            Ingredient(text: "1 1/4 cups milk"),
            Ingredient(text: "2/3 cup granulated sugar, divided"),
            Ingredient(text: "3 eggs"),
            Ingredient(text: "1 tablespoon vanilla extract"),
            Ingredient(text: "1/8 teaspoon salt"),
            Ingredient(text: "1/2 cup flour"),
            Ingredient(text: "2 cups berries"),
            Ingredient(text: "Powdered sugar")
        ],
        directions: [
            Direction(text: "Heat oven to 350 degrees. Lightly butter a medium-size flameproof baking dish at least 1 1/2 inches deep.", order: 1),
            Direction(text: "Place the milk, 1/3 cup granulated sugar, eggs, vanilla, salt and flour in a blender. Blend at top speed until smooth and frothy, about 1 minute.", order: 2),
            Direction(text: "Pour a 1/4-inch layer of batter in the baking dish. Turn on a stove burner to low and set dish on top for a minute or two, until a film of batter has set in the bottom of the dish. Remove from heat.", order: 3),
            Direction(text: "Spread berries over the batter and sprinkle on the remaining 1/3 cup granulated sugar. Pour on the rest of the batter and smooth with the back of a spoon. Place in the center of the oven and bake about 50 minutes, until top is puffed and browned and a tester plunged into its center comes out clean.", order: 4),
            Direction(text: "Sprinkle with powdered sugar just before serving. (Clafoutis need not be served hot, but should still be warm. It will sink slightly as it cools.)", order: 5)
        ]
    )

    /// Shakshuka: a handful of stovetop steps that are all one Cook.
    private let shakshuka = Recipe(
        ingredients: [
            Ingredient(text: "2 tablespoons olive oil"),
            Ingredient(text: "1 medium onion (diced)"),
            Ingredient(text: "1 red bell pepper (seeded and diced)"),
            Ingredient(text: "4 garlic cloves (finely chopped)"),
            Ingredient(text: "1 (28-ounce can) whole peeled tomatoes"),
            Ingredient(text: "6 large eggs"),
            Ingredient(text: "1 small bunch fresh cilantro (chopped)")
        ],
        directions: [
            Direction(text: "Heat olive oil in a large sauté pan on medium heat. Add the chopped bell pepper and onion and cook for 5 minutes or until the onion becomes translucent.", order: 1),
            Direction(text: "Add garlic and spices and cook an additional minute.", order: 2),
            Direction(text: "Pour the can of tomatoes and juice into the pan and break down the tomatoes using a large spoon. Season with salt and pepper and bring the sauce to a simmer.", order: 3),
            Direction(text: "Use your large spoon to make small wells in the sauce and crack the eggs into each well. Cook the eggs for 5 to 8 minutes, or until the eggs are done to your liking.", order: 4),
            Direction(text: "Garnish with chopped cilantro and parsley before serving.", order: 5)
        ],
        prepDuration: 10 * 60
    )

    /// Chicken, Vegetable and Barley Soup: the cutting is in the steps.
    private let barleySoup = Recipe(
        ingredients: [
            Ingredient(text: "1 (3- to 6-inch) piece fresh ginger, scrubbed or peeled"),
            Ingredient(text: "1 small yellow onion"),
            Ingredient(text: "2 carrots"),
            Ingredient(text: "4 chicken drumsticks (1 1/2 pounds; see Tips)"),
            Ingredient(text: "Salt and freshly ground black pepper"),
            Ingredient(text: "1/2 small napa cabbage"),
            Ingredient(text: "1/2 cup pearled barley (see Tips)")
        ],
        directions: [
            Direction(text: "Bring 8 cups of water to a boil in a large saucepan. While the water comes to a boil, cut the ginger into 1/2-inch slices and gently smash. Cut the onion into a 1/2-inch dice. Peel the carrots and cut a 1/2-inch chunk at an angle. Roll the carrot a quarter turn and cut another chunk; repeat.", order: 1),
            Direction(text: "Add the ginger, then the chicken, to the boiling water and cook for 5 minutes over high, skimming and discarding any foam that rises to the surface. While the chicken boils, cut the cabbage in thirds lengthwise, then crosswise into 1-inch-thick ribbons.", order: 2),
            Direction(text: "Add the onion, carrots and a few pinches of salt to the saucepan. When the water returns to a boil, adjust the heat to maintain a steady simmer and cook until the carrot is bright orange, about 10 minutes.", order: 3),
            Direction(text: "Stir in the cabbage and barley, adjust the heat to maintain a steady simmer and cook until the barley and vegetables are tender, 10 to 15 minutes more.", order: 4)
        ],
        prepDuration: 5 * 60
    )

    /// Caesar's Caesar Salad, imported with no space after the amounts.
    private let caesar = Recipe(
        ingredients: [
            Ingredient(text: "1large head romaine lettuce (about 1 pound)"),
            Ingredient(text: "4 to 6anchovy fillets, minced"),
            Ingredient(text: "1large garlic clove, minced"),
            Ingredient(text: "½cup extra-virgin olive oil"),
            Ingredient(text: "¼cup finely grated Parmesan, plus more for garnish"),
            Ingredient(text: "¼cup olive oil"),
            Ingredient(text: "4garlic cloves, minced"),
            Ingredient(text: "20thin baguette slices (each about ¼-inch thick)")
        ],
        directions: [
            Direction(text: "Make the croutons: In a small bowl, mix the olive oil and the garlic until well combined. Heat the oven to 375 degrees and set a rack in the middle.", order: 1),
            Direction(text: "Place the baguette slices on a large baking sheet in a single layer. Generously brush the tops with the garlic oil, then swipe the slices around the pan to make sure their sides underneath soak up the olive oil mixture that soaks through to the bottom.", order: 2),
            Direction(text: "In a large wooden bowl, mash the anchovies with the garlic. Slowly, pour in the 1/2 cup olive oil, whisking vigorously. Add the grated Parmesan.", order: 3)
        ]
    )

    func testOverview_preheatInsideAStepGetsItsOwnBar() {
        let overview = CookIntroPlanner.overview(for: salad, plan: CookPlanner.heuristicPlan(for: salad))
        let preheat = overview.blocks.first { $0.word == "Preheat" }
        XCTAssertNotNil(preheat)
        XCTAssertEqual(preheat?.kind, .alongside)
        XCTAssertEqual(preheat?.start, -15, "it heats while you prep")
        let roast = overview.blocks.first { $0.step == 0 && $0.kind == .cook }
        XCTAssertEqual(roast?.word, "Bake", "the rest of the step is still there")
        XCTAssertEqual(roast?.timeLabel, "~17 min", "10 to 14 minutes in the oven, then 5 to cool")
    }

    func testOverview_stepsInOrderStayInOneLane() {
        // The model put most of these side by side; none of them says so
        let hints = (1...4).map { OverviewHint(word: "Simmer", minutes: 0, alongsideStep: $0 > 1 ? $0 - 1 : 0) }
        let overview = CookIntroPlanner.overview(for: barleySoup, plan: CookPlanner.heuristicPlan(for: barleySoup), hints: hints)
        let steps = overview.blocks.filter { $0.step != nil && CookStage(rawValue: $0.word)?.isHeadStart != true }
        XCTAssertTrue(steps.allSatisfy { $0.lane == 0 })
    }

    func testOverview_modelEstimatesDontReplaceTheRecipesTimes() {
        let hints = [OverviewHint(word: "Roast", minutes: 12, alongsideStep: 0), OverviewHint(word: "Assemble", minutes: 4, alongsideStep: 0)]
        let overview = CookIntroPlanner.overview(for: salad, plan: CookPlanner.heuristicPlan(for: salad), hints: hints)
        XCTAssertEqual(overview.blocks.first { $0.step == 0 && $0.kind == .cook }?.timeLabel, "~17 min")
        XCTAssertEqual(overview.blocks.first { $0.step == 1 }?.timeLabel, "~4 min", "a step with no time takes the estimate")
    }

    func testOverview_theStepsOwnWordsBeatTheModel() {
        let hints = ["Serve", "Bake", "Bake", "Bake"].map { OverviewHint(word: $0, minutes: 0, alongsideStep: 0) }
        let overview = CookIntroPlanner.overview(for: barleySoup, plan: CookPlanner.heuristicPlan(for: barleySoup), hints: hints)
        XCTAssertEqual(overview.blocks.filter { $0.lane == 0 }.map(\.word), ["Prep", "Simmer"],
                       "the cutting in step 1 is prep, and the rest simmers in the pot")
    }

    func testOverview_waterBoilsBeforeTheStepThatNeedsIt() {
        let overview = CookIntroPlanner.overview(for: barleySoup, plan: CookPlanner.heuristicPlan(for: barleySoup))
        let boil = overview.blocks.first { $0.word == "Boil" }
        let simmer = overview.blocks.first { $0.word == "Simmer" }
        XCTAssertEqual(boil?.kind, .alongside)
        XCTAssertNotNil(simmer)
        XCTAssertEqual(boil?.end ?? 0, simmer?.start ?? -1, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(simmer?.start ?? 0, 5, "10 minutes for the water, 5 of them during prep")
    }

    func testOverview_modelCantNameAStepPrep() {
        let hints = [OverviewHint(word: "Prep", minutes: 0, alongsideStep: 0)] + (2...4).map { _ in OverviewHint(word: "", minutes: 0, alongsideStep: 0) }
        let overview = CookIntroPlanner.overview(for: barleySoup, plan: CookPlanner.heuristicPlan(for: barleySoup), hints: hints)
        XCTAssertEqual(overview.blocks.filter { $0.word == "Prep" }.count, 1)
    }

    // MARK: - Prep

    func testPrep_cutsWrittenInTheSteps() {
        let tasks = CookIntroPlanner.prepTasks(for: barleySoup, plan: CookPlanner.heuristicPlan(for: barleySoup))
        XCTAssertEqual(tasks.map(\.title), ["Slice the ginger", "Dice the yellow onion", "Cut the carrots", "Cut the napa cabbage"])
    }

    func testPrep_saladSlicesTogether() {
        let tasks = CookIntroPlanner.prepTasks(for: salad, plan: CookPlanner.heuristicPlan(for: salad))
        XCTAssertEqual(tasks.map(\.title), ["Slice the cucumber and avocado"])
    }

    func testPrep_groupsTheCutsByWhenTheyreNeeded() {
        let tasks = CookIntroPlanner.prepTasks(for: lasagna, plan: CookPlanner.heuristicPlan(for: lasagna))
        XCTAssertEqual(tasks.map(\.title), [
            "Chop the vegetables",
            "Chop the basil",
            "Mince the garlic",
            "Grate the mozzarella cheese"
        ])
        XCTAssertEqual(tasks[0].ingredientIndices, [1, 2, 3, 4])
        XCTAssertEqual(tasks[0].detail, "3 large carrots, 1 red bell pepper, 1 medium zucchini, 1 medium yellow onion")
    }

    func testMeasure_whatIsntCutInTheOrderItsNeeded() {
        let measures = CookIntroPlanner.measureTasks(for: soup, plan: CookPlanner.heuristicPlan(for: soup))
        XCTAssertEqual(measures.map(\.amount), ["¼ cup", "1 tsp"], "the shallots, tomatoes and garlic are on cut cards; salt has no amount")
        XCTAssertEqual(measures.first?.name, "extra-virgin olive oil")
    }

    func testMeasure_cansAndCountsArentMeasuring() {
        let measures = CookIntroPlanner.measureTasks(for: shakshuka, plan: CookPlanner.heuristicPlan(for: shakshuka))
        XCTAssertEqual(measures.map(\.name), ["olive oil"], "not the can of tomatoes or the 6 eggs")
    }

    func testPrep_skipsTheCanned() {
        let tasks = CookIntroPlanner.prepTasks(for: lasagna, plan: CookPlanner.heuristicPlan(for: lasagna))
        XCTAssertFalse(tasks.contains { $0.ingredientIndices.contains(7) }, "a can of diced tomatoes is already cut")
    }

    func testPrep_cutFirstNamesComeFromWhatFollows() {
        let tasks = CookIntroPlanner.prepTasks(for: lasagna, plan: CookPlanner.heuristicPlan(for: lasagna))
        XCTAssertEqual(tasks.first { $0.ingredientIndices == [8] }?.detail, "¼ cup fresh basil")
    }

    func testPrep_soup() {
        let tasks = CookIntroPlanner.prepTasks(for: soup, plan: CookPlanner.heuristicPlan(for: soup))
        XCTAssertEqual(tasks.map(\.title), ["Slice the shallots", "Chop the tomatoes", "Mince the garlic"])
    }

    func testPrep_gluedAmountsReadAsAmounts() {
        let tasks = CookIntroPlanner.prepTasks(for: caesar, plan: CookPlanner.heuristicPlan(for: caesar))
        let garlic = tasks.first { $0.ingredientIndices == [2] }
        XCTAssertEqual(garlic?.title, "Mince the garlic")
        XCTAssertEqual(garlic?.detail, "1 large garlic clove")
    }

    func testPrep_slicesAsANounArentACut() {
        let tasks = CookIntroPlanner.prepTasks(for: caesar, plan: CookPlanner.heuristicPlan(for: caesar))
        let cut = Set(tasks.flatMap(\.ingredientIndices))
        XCTAssertFalse(cut.contains(3), "swiping the slices through the olive oil doesn't slice the oil")
        XCTAssertFalse(cut.contains(5))
        XCTAssertFalse(cut.contains(7), "the baguette comes sliced")
        XCTAssertNil(CookIntroPlanner.cutsInSteps(of: caesar)[3])
    }

    func testCutsInSteps_aCutMustBeTheAction() {
        let recipe = Recipe(
            ingredients: [
                Ingredient(text: "1 lemon"),
                Ingredient(text: "1 pound asparagus"),
                Ingredient(text: "1 knob ginger"),
                Ingredient(text: "4 slices bread"),
                Ingredient(text: "1 onion")
            ],
            directions: [
                Direction(text: "Place the lemon slices between the asparagus spears.", order: 1),
                Direction(text: "Cut the ginger into 1/2-inch slices and smash. Toast the bread slices.", order: 2),
                Direction(text: "Thinly slice the onion.", order: 3)
            ]
        )
        XCTAssertEqual(CookIntroPlanner.cutsInSteps(of: recipe), [2: "Slice", 4: "Slice"])
    }

    func testPrep_comesInPiecesAlready() {
        let recipe = Recipe(
            ingredients: [Ingredient(text: "20 thin baguette slices"), Ingredient(text: "1 cup bread cubes")],
            directions: [Direction(text: "Slice the baguette slices. Cube the bread cubes.", order: 1)]
        )
        XCTAssertEqual(CookIntroPlanner.prepTasks(for: recipe, plan: CookPlanner.heuristicPlan(for: recipe)), [])
    }

    /// The card for a single ingredient line, as "title | detail".
    private func prepCard(_ line: String) -> String? {
        let recipe = Recipe(ingredients: [Ingredient(text: line)])
        return CookIntroPlanner.prepTasks(for: recipe, plan: CookPlanner.heuristicPlan(for: recipe)).first
            .map { "\($0.title) | \($0.detail)" }
    }

    func testPrep_namesWhatsActuallyCut() {
        XCTAssertEqual(prepCard("Fresh parsley, chopped, optional"), "Chop the parsley | Fresh parsley")
        XCTAssertEqual(prepCard("1 clove garlic finely grated or crushed with a press"), "Grate the garlic | 1 clove garlic")
        XCTAssertEqual(prepCard("4 cups cooked, shredded chicken"), "Shred the chicken | 4 cups chicken")
        XCTAssertEqual(prepCard("2 bell peppers diced, any color"), "Dice the bell peppers | 2 bell peppers")
        XCTAssertEqual(prepCard("1-2 tbsp jalapeno , (optional) finely diced"), "Dice the jalapeno | 1–2 tbsp jalapeno")
        XCTAssertEqual(prepCard("1 large carrot, peeled, halved lengthwise, sliced 1/8\" thick"), "Slice the carrot | 1 large carrot")
        XCTAssertEqual(prepCard("2 tablespoons chopped fresh Italian parsley, (for serving (optional))"),
                       "Chop the italian parsley | 2 tbsp fresh Italian parsley")
        XCTAssertEqual(prepCard("1 small white or yellow onion (diced)"), "Dice the white onion | 1 small white or yellow onion")
    }

    func testPrep_inAListItsTheOneThatsCut() {
        XCTAssertEqual(prepCard("Any combination of lime wedges, sour cream, queso fresco and sliced avocado, for topping"),
                       "Slice the avocado | avocado")
        XCTAssertEqual(prepCard("Shredded cheddar, sour cream, and fresh cilantro, for serving"), "Shred the cheddar | cheddar")
        XCTAssertEqual(prepCard("1 handful of chopped parsley, za’atar, thinly sliced radishes, olive oil"),
                       "Chop the parsley | 1 handful parsley")
    }

    func testPrep_anAlternativeIsntCut() {
        XCTAssertNil(prepCard("1 teaspoon Aleppo pepper (or use paprika and crushed red pepper to taste)"))
    }

    func testPrep_theSameThingTwiceIsNamedOnce() {
        let recipe = Recipe(ingredients: [
            Ingredient(text: "2 Tbsp Fresh Ginger, minced"),
            Ingredient(text: "1 Tbsp Ginger, minced"),
            Ingredient(text: "2 Cloves Garlic, minced")
        ])
        XCTAssertEqual(CookIntroPlanner.prepTasks(for: recipe, plan: CookPlanner.heuristicPlan(for: recipe)).map(\.title),
                       ["Mince the ginger and garlic"])
    }

    func testPrep_jalapenosAreVegetables() {
        let recipe = Recipe(ingredients: [
            Ingredient(text: "5 green onions diced"),
            Ingredient(text: "1 jalapeño finely diced, optional")
        ])
        XCTAssertEqual(CookIntroPlanner.prepTasks(for: recipe, plan: CookPlanner.heuristicPlan(for: recipe)).map(\.title),
                       ["Dice the vegetables"])
    }

    func testKnifeVerbPrefersTheFinalCut() {
        XCTAssertEqual(CookIntroPlanner.knifeVerb(in: "1 pound shallots, halved and thinly sliced"), "Slice")
        XCTAssertEqual(CookIntroPlanner.knifeVerb(in: "2 cloves garlic, pressed or minced"), "Mince")
        XCTAssertNil(CookIntroPlanner.knifeVerb(in: "1 tsp sugar"))
    }

    // MARK: - Overview

    func testOverview_preheatAndMeanwhileGetTheirOwnLanes() {
        let overview = CookIntroPlanner.overview(for: lasagna, plan: CookPlanner.heuristicPlan(for: lasagna))
        let preheat = overview.blocks.first { $0.step == 0 }!
        let sauce = overview.blocks.first { $0.step == 3 }!
        XCTAssertEqual(preheat.kind, .alongside)
        XCTAssertEqual(sauce.kind, .alongside)
        XCTAssertNotEqual(preheat.lane, 0)
        XCTAssertNotEqual(sauce.lane, 0)
        let bake = overview.blocks.first { $0.word == "Bake" }!
        XCTAssertEqual(preheat.end, bake.start, accuracy: 0.001, "the oven is hot just as the bake starts, not an hour early")
        XCTAssertFalse(overview.blocks.contains { $0.step == 0 && $0.kind == .cook }, "a preheat-only step has no other block")
    }

    func testOverview_mainLaneRunsInOrderAfterPrep() {
        let overview = CookIntroPlanner.overview(for: lasagna, plan: CookPlanner.heuristicPlan(for: lasagna))
        let main = overview.blocks.filter { $0.lane == 0 }
        XCTAssertEqual(main.first?.word, "Prep")
        XCTAssertEqual(main.first?.timeLabel, "30 min")
        for (a, b) in zip(main, main.dropFirst()) {
            XCTAssertEqual(a.end, b.start, accuracy: 0.001)
        }
    }

    func testOverview_usesTheRecipesTimesAndMarksEstimates() {
        let overview = CookIntroPlanner.overview(for: lasagna, plan: CookPlanner.heuristicPlan(for: lasagna))
        XCTAssertEqual(overview.blocks.first { $0.step == 7 }?.timeLabel, "15–20 min")
        XCTAssertEqual(overview.blocks.first { $0.step == 0 }?.timeLabel, "~15 min")
        XCTAssertTrue(overview.blocks.first { $0.step == 5 }?.timeLabel.hasPrefix("~") ?? false)
    }

    func testOverview_whileRunsAlongsideThePreviousStep() {
        let overview = CookIntroPlanner.overview(for: soup, plan: CookPlanner.heuristicPlan(for: soup))
        let caramelize = overview.blocks.first { $0.step == 0 }!
        let drain = overview.blocks.first { $0.step == 1 }!
        XCTAssertEqual(drain.kind, .alongside)
        XCTAssertEqual(drain.start, caramelize.start)
    }

    func testOverview_theModelOnlyNamesStepsTheTextDoesnt() {
        let recipe = Recipe(directions: [
            Direction(text: "Heat the oil in a pan and cook the onions for 5 minutes.", order: 1),
            Direction(text: "Pour everything into the dish and let it go.", order: 2)
        ])
        let hints = [
            OverviewHint(word: "Serve", minutes: 0, alongsideStep: 0),
            OverviewHint(word: "Bake", minutes: 25, alongsideStep: 0)
        ]
        let overview = CookIntroPlanner.overview(for: recipe, plan: CookPlanner.heuristicPlan(for: recipe), hints: hints)
        XCTAssertEqual(overview.blocks.first { $0.step == 0 }?.word, "Cook", "the step says cook")
        XCTAssertEqual(overview.blocks.first { $0.step == 1 }?.word, "Bake", "this one names nothing")
        XCTAssertEqual(overview.blocks.first { $0.step == 1 }?.timeLabel, "~25 min")
    }

    func testOverview_theModelCantUseWordsOutsideTheStages() {
        let recipe = Recipe(directions: [
            Direction(text: "Heat the oil in a pan and cook the onions for 5 minutes.", order: 1),
            Direction(text: "Pour everything into the dish and let it go.", order: 2)
        ])
        let hints = [OverviewHint(word: "", minutes: 0, alongsideStep: 0), OverviewHint(word: "Pour", minutes: 0, alongsideStep: 0)]
        let overview = CookIntroPlanner.overview(for: recipe, plan: CookPlanner.heuristicPlan(for: recipe), hints: hints)
        XCTAssertEqual(overview.blocks.filter { $0.lane == 0 }.map(\.word), ["Cook"], "a step that names nothing goes with the one before")
    }

    func testStages() {
        XCTAssertEqual(CookIntroPlanner.stage(for: lasagna.directions[1].text), .cook)
        XCTAssertEqual(CookIntroPlanner.stage(for: lasagna.directions[6].text), .bake)
        XCTAssertEqual(CookIntroPlanner.stage(for: lasagna.directions[4].text), .mix)
        XCTAssertEqual(CookIntroPlanner.stage(for: lasagna.directions[5].text), .assemble, "layering")
        XCTAssertEqual(CookIntroPlanner.stage(for: clafoutis.directions[3].text), .bake, "the batter is poured, but the 50 minutes are in the oven")
        XCTAssertEqual(CookIntroPlanner.stage(for: clafoutis.directions[4].text), .serve, "\"as it cools\" is an aside")
        XCTAssertEqual(CookIntroPlanner.stage(for: shakshuka.directions[2].text), .cook, "bringing it to a simmer isn't simmering yet")
        XCTAssertEqual(CookIntroPlanner.stage(for: "Stir occasionally, until softened and lightly browned, about 10 minutes."), .cook)
        let cutting = CookIntroPlanner.withoutSentences(barleySoup.directions[0].text, where: CookIntroPlanner.isWaterBoiling)
        XCTAssertEqual(CookIntroPlanner.stage(for: cutting), .prep, "cut, dice, peel and cut beat one roll")
        XCTAssertEqual(CookIntroPlanner.stage(for: "Drain the pasta, then allow to cool slightly. Add the vegetables and stir to combine."), .mix,
                       "an untimed cool doesn't outweigh the stirring")
        XCTAssertEqual(CookIntroPlanner.stage(for: "Brown the chicken for 4 to 5 minutes per side. Let the pan cool for 5 minutes."), .cook)
        XCTAssertEqual(CookIntroPlanner.stage(for: "Cook the chickpeas: Stir the shallot until it starts to turn color, 2 to 3 minutes."), .cook, "the heading says so")
        XCTAssertEqual(CookIntroPlanner.stage(for: "Mix the brown sugar into the batter."), .mix, "brown sugar isn't browning")
        XCTAssertNil(CookIntroPlanner.stage(for: "Golden, crusty, and works every time."))
    }

    func testOverview_clafoutisIsPreheatMixBakeServe() {
        let overview = CookIntroPlanner.overview(for: clafoutis, plan: CookPlanner.heuristicPlan(for: clafoutis))
        XCTAssertEqual(overview.blocks.filter { $0.lane == 0 }.map(\.word), ["Prep", "Mix", "Bake", "Serve"],
                       "buttering the dish is prep, and the minute or two on the burner goes with the mixing")
        let preheat = overview.blocks.first { $0.word == "Preheat" }
        let bake = overview.blocks.first { $0.word == "Bake" }
        XCTAssertEqual(preheat?.kind, .alongside, "\"Heat oven to 350\" is a preheat")
        XCTAssertEqual(preheat?.end ?? 0, bake?.start ?? -1, accuracy: 0.001, "the bake waits for the oven")
        XCTAssertEqual(bake?.timeLabel, "50 min")
    }

    func testOverview_shakshukaIsCookThenServe() {
        let overview = CookIntroPlanner.overview(for: shakshuka, plan: CookPlanner.heuristicPlan(for: shakshuka))
        XCTAssertEqual(overview.blocks.map(\.word), ["Prep", "Cook", "Serve"])
        XCTAssertEqual(overview.laneCount, 1)
    }

    func testOverview_notesAreNotSteps() {
        let recipe = Recipe(directions: [
            Direction(text: "Simmer the soup for 20 minutes.", order: 1),
            Direction(text: "Ladle into bowls and serve.", order: 2),
            Direction(text: "Make Ahead: The soup can be refrigerated for 5 days.", order: 3)
        ])
        let overview = CookIntroPlanner.overview(for: recipe, plan: CookPlanner.heuristicPlan(for: recipe))
        XCTAssertEqual(overview.blocks.map(\.word), ["Simmer", "Serve"])
    }

    func testOverview_meltingAheadIsAHeadStart() {
        let recipe = Recipe(directions: [
            Direction(text: "Melt the butter in the microwave. Cool for about 5 minutes before using.", order: 1),
            Direction(text: "Whisk the flour, eggs, milk and melted butter until smooth.", order: 2),
            Direction(text: "Cook the crepes in a hot skillet for 1 to 2 minutes per side.", order: 3)
        ])
        let overview = CookIntroPlanner.overview(for: recipe, plan: CookPlanner.heuristicPlan(for: recipe))
        XCTAssertEqual(overview.blocks.first { $0.word == "Melt" }?.kind, .alongside)
        XCTAssertEqual(overview.blocks.filter { $0.lane == 0 }.map(\.word), ["Mix", "Cook"])
    }

    func testOverview_backToBackStepsInTheSameStageAreOneBlock() {
        let overview = CookIntroPlanner.overview(for: soup, plan: CookPlanner.heuristicPlan(for: soup))
        let main = overview.blocks.filter { $0.kind == .cook }
        XCTAssertEqual(main.map(\.word), ["Cook"], "the drain alongside doesn't split them")
        XCTAssertTrue(main.first?.timeLabel.hasPrefix("~") ?? false)
    }

    func testLayoutSqueezesWhenThereAreTooManyBlocks() {
        let main = (0..<12).map { (start: Double($0) * 5, end: Double($0) * 5 + 5, minimum: 46.0) }
        let (spans, _) = CookIntroPlanner.layout(main: main, length: 400, gap: 5)
        XCTAssertLessThanOrEqual(spans.last?.1 ?? 0, 400.5)
    }

    func testTotalLabel() {
        let overview = CookOverview(blocks: [
            .init(word: "Prep", step: nil, lane: 0, start: -30, end: 0, timeLabel: "30 min", kind: .prep),
            .init(word: "Bake", step: 0, lane: 0, start: 0, end: 61, timeLabel: "~61 min", kind: .cook)
        ])
        XCTAssertEqual(overview.totalLabel, "About 1 hr 30 min")
    }

    // MARK: - Layout

    func testLayoutKeepsMinimumsAndFillsTheLength() {
        let (spans, position) = CookIntroPlanner.layout(
            main: [(0, 30, 60), (30, 32, 60), (32, 62, 60)],
            length: 400, gap: 10
        )
        XCTAssertEqual(spans.last?.1 ?? 0, 400, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(spans[1].1 - spans[1].0, 60)
        XCTAssertEqual(position(30), spans[1].0, accuracy: 0.01, "a boundary belongs to the block that starts there")
    }
}
