import XCTest

// RecipeParserCore is compiled directly into this target (same as the app and share extension),
// so no module import is needed.

final class RecipeParserTests: XCTestCase {

    /// Half Baked Harvest's Cider Braised Pot Roast, as its JSON-LD publishes
    /// it: the oven method numbered inline in one step, and the Crockpot
    /// method in a section of its own.
    static let potRoastHTML = #"""
        <html><head><script type="application/ld+json">
        {"@context":"https://schema.org","@graph":[{"@type":"Recipe",
        "name":"Cider Braised Pot Roast with Parmesan Sweet Potatoes",
        "description":"Cider Braised Pot Roast with tender beef, apple cider, caramelized onions, and crispy Parmesan sweet potatoes. A cozy fall dinner!",
        "prepTime":"PT30M","cookTime":"PT210M",
        "recipeIngredient":["1 (4 pound)  beef chuck roast","3  yellow onions, thinly sliced"],
        "recipeInstructions":[
          {"@type":"HowToStep","text":"1. Preheat the oven to 325° F. Season the roast with salt and pepper, then coat with flour.2. Arrange the onions and shallots in a large Dutch oven and dot with butter. Set the roast on top. Spread with apple butter. Pour the cider and wine around the roast. Add the carrots and thyme, then arrange the sweet potatoes around and over the roast. 3. Cover and roast for 2 1\/2 to 3 hours, until the beef is fork tender. Remove the sweet potatoes to a baking sheet and increase the oven temperature to 425° F.4. Toss the potatoes with the butter, garlic powder, Parmesan, and sage. Roast for 20 minutes, until crisp.5.  At the same time, return the roast to the oven, uncovered, for 10-15 minutes, until caramelized on top. Add a splash of broth, cider, wine, or water if the pan juices are getting low.6. Spoon the onions and gravy over the roast. Finish with fresh thyme and flaky sea salt. Serve with the crispy sweet potatoes and sage, spooning the browned butter from the baking sheet over the potatoes."},
          {"@type":"HowToSection","name":"The Crockpot","itemListElement":[
            {"@type":"HowToStep","text":"1. Season the roast with salt and pepper, then coat with flour. Add the onions and shallots to the Crockpot and dot with butter. Set the roast on top and spread with apple butter. Pour the cider and wine around the roast. Add the carrots, thyme, and sweet potatoes. 2. Cover and cook on LOW for 6-8 hours or HIGH for 3-4 hours, until the beef is fork tender.3. Remove the sweet potatoes to a baking sheet. Toss with the butter, garlic powder, Parmesan, and sage. Roast at 425° F for 20 minutes, until golden and crisp.4. Spoon the onions and gravy over the roast. Finish with fresh thyme and sea salt. Serve with the crispy sweet potatoes and sage alongside."}
          ]}
        ]}]}
        </script></head><body></body></html>
        """#

    func testInlineNumberedStepsAreSplit() {
        let recipe = RecipeParserCore.parseRecipe(html: Self.potRoastHTML, sourceURL: "https://www.halfbakedharvest.com/x/")
        XCTAssertEqual(recipe?.directions.count, 6)
        XCTAssertEqual(recipe?.directions.first, "Preheat the oven to 325° F. Season the roast with salt and pepper, then coat with flour.")
        XCTAssertEqual(recipe?.directions[2].hasPrefix("Cover and roast for 2 1/2 to 3 hours"), true, "the 2 in \"2 1/2\" isn't a step")
        XCTAssertEqual(recipe?.directions[4].hasPrefix("At the same time, return the roast"), true)
    }

    func testAnotherMethodGoesInTheNotes() {
        let recipe = RecipeParserCore.parseRecipe(html: Self.potRoastHTML, sourceURL: "https://www.halfbakedharvest.com/x/")
        XCTAssertFalse(recipe?.directions.contains { $0.contains("Crockpot") } ?? true, "the Crockpot method isn't more steps")
        let notes = recipe?.notes ?? ""
        XCTAssertTrue(notes.hasPrefix("Cider Braised Pot Roast with tender beef"), "the description comes first")
        XCTAssertTrue(notes.contains("\n\nThe Crockpot\n1. Season the roast"))
        XCTAssertTrue(notes.contains("\n2. Cover and cook on LOW for 6-8 hours"))
        XCTAssertTrue(notes.hasSuffix("4. Spoon the onions and gravy over the roast. Finish with fresh thyme and sea salt. Serve with the crispy sweet potatoes and sage alongside."))
    }

    func testSplitNumberedSteps_onlyWhenTheyCountUpFromTheStart() {
        let split = RecipeParserCore.splitNumberedSteps
        XCTAssertEqual(split(["1. Mix the dough. 2. Let it rise."]), ["Mix the dough.", "Let it rise."])
        XCTAssertEqual(split(["Mix the dough. 2. Let it rise."]), ["Mix the dough. 2. Let it rise."], "doesn't start at 1")
        XCTAssertEqual(split(["1. Mix the dough with 1.5 cups flour."]), ["1. Mix the dough with 1.5 cups flour."], "one number is one step")
        XCTAssertEqual(split(["1. Mix. 3. Bake for 20 minutes. 2. Cool."]), ["Mix. 3. Bake for 20 minutes.", "Cool."], "numbers out of order stay in the text")
        XCTAssertEqual(split(["Simmer 10 minutes.", "Serve."]), ["Simmer 10 minutes.", "Serve."])
    }

    func testIsOtherMethod() {
        XCTAssertTrue(RecipeParserCore.isOtherMethod("The Crockpot"))
        XCTAssertTrue(RecipeParserCore.isOtherMethod("Instant Pot"))
        XCTAssertTrue(RecipeParserCore.isOtherMethod("Slow Cooker Directions"))
        XCTAssertTrue(RecipeParserCore.isOtherMethod("Stovetop Method"))
        XCTAssertFalse(RecipeParserCore.isOtherMethod("For the sauce"))
        XCTAssertFalse(RecipeParserCore.isOtherMethod("Oven"))
    }

    func testAMethodNamedFirstIsTheRecipe() {
        let html = #"""
            <script type="application/ld+json">{"@type":"Recipe","name":"Chili","recipeInstructions":[
              {"@type":"HowToSection","name":"Slow Cooker","itemListElement":[
                {"@type":"HowToStep","text":"Add everything to the slow cooker."},
                {"@type":"HowToStep","text":"Cook on low for 8 hours."}]}]}</script>
            """#
        let recipe = RecipeParserCore.parseRecipe(html: html, sourceURL: "https://example.com/chili")
        XCTAssertEqual(recipe?.directions, ["Add everything to the slow cooker.", "Cook on low for 8 hours."])
    }
}
