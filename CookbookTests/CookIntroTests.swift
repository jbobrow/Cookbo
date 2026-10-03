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
        XCTAssertTrue(overview.blocks.filter { $0.step != nil }.allSatisfy { $0.lane == 0 })
    }

    func testOverview_modelEstimatesDontReplaceTheRecipesTimes() {
        let hints = [OverviewHint(word: "Roast", minutes: 12, alongsideStep: 0), OverviewHint(word: "Assemble", minutes: 4, alongsideStep: 0)]
        let overview = CookIntroPlanner.overview(for: salad, plan: CookPlanner.heuristicPlan(for: salad), hints: hints)
        XCTAssertEqual(overview.blocks.first { $0.step == 0 && $0.kind == .cook }?.timeLabel, "~17 min")
        XCTAssertEqual(overview.blocks.first { $0.step == 1 }?.timeLabel, "~4 min", "a step with no time takes the estimate")
    }

    func testOverview_modelWordsMustComeFromTheStep() {
        let hints = [
            OverviewHint(word: "Boil", minutes: 0, alongsideStep: 0),
            OverviewHint(word: "Add", minutes: 0, alongsideStep: 0),
            OverviewHint(word: "Cut", minutes: 0, alongsideStep: 0),
            OverviewHint(word: "Add", minutes: 0, alongsideStep: 0)
        ]
        let overview = CookIntroPlanner.overview(for: barleySoup, plan: CookPlanner.heuristicPlan(for: barleySoup), hints: hints)
        XCTAssertEqual(overview.blocks.first { $0.step == 0 }?.word, "Boil")
        XCTAssertNotEqual(overview.blocks.first { $0.step == 2 }?.word, "Cut", "step 3 cuts nothing")
        XCTAssertEqual(overview.blocks.first { $0.step == 3 }?.word, "Simmer", "step 4 never says add")
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
        XCTAssertEqual(preheat.start, -30, "the oven goes on at the start of prep")
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

    func testOverview_hintsReplaceWordsButOnlyGoodOnes() {
        let plan = CookPlanner.heuristicPlan(for: soup)
        let hints = [
            OverviewHint(word: "Caramelize", minutes: 0, alongsideStep: 0),
            OverviewHint(word: "drain the tomatoes", minutes: 0, alongsideStep: 1),
            OverviewHint(word: "Combine", minutes: 2, alongsideStep: 0)
        ]
        let overview = CookIntroPlanner.overview(for: soup, plan: plan, hints: hints)
        XCTAssertEqual(overview.blocks.first { $0.step == 0 }?.word, "Caramelize")
        XCTAssertEqual(overview.blocks.first { $0.step == 1 }?.word, "Add", "more than one word falls back to the text")
        XCTAssertEqual(overview.blocks.first { $0.step == 2 }?.timeLabel, "~2 min")
    }

    func testWords() {
        XCTAssertEqual(CookIntroPlanner.word(for: lasagna.directions[0].text), "Preheat")
        XCTAssertEqual(CookIntroPlanner.word(for: lasagna.directions[1].text), "Cook", "the main cooking action wins over the first verb")
        XCTAssertEqual(CookIntroPlanner.word(for: lasagna.directions[6].text), "Bake")
    }

    func testOverview_backToBackStepsWithTheSameWordAreOneBlock() {
        let plan = CookPlanner.heuristicPlan(for: soup)
        // Steps 1 and 3 both add things to the pot
        let hints = [
            OverviewHint(word: "Add", minutes: 0, alongsideStep: 0),
            OverviewHint(word: "Drain", minutes: 0, alongsideStep: 1),
            OverviewHint(word: "Add", minutes: 2, alongsideStep: 0)
        ]
        let overview = CookIntroPlanner.overview(for: soup, plan: plan, hints: hints)
        let main = overview.blocks.filter { $0.kind == .cook }
        XCTAssertEqual(main.map(\.word), ["Add"], "the drain alongside doesn't split them")
        XCTAssertEqual(main.first?.timeLabel, "~25 min")
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
