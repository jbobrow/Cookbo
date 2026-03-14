import XCTest

// RecipeParserCore is compiled directly into this target (same as the app and share extension),
// so no module import is needed.

final class InstagramParserTests: XCTestCase {

    // MARK: - stripInstagramOEmbedWrapper

    func testStripOEmbedWrapper_standard() {
        let input = #"maxiskitchen on Instagram: "Chipotle chicken burrito bowls■1 lb chicken""#
        let result = RecipeParserCore.stripInstagramOEmbedWrapper(input)
        XCTAssertFalse(result.hasPrefix("maxiskitchen"))
        XCTAssertTrue(result.hasPrefix("Chipotle"))
    }

    func testStripOEmbedWrapper_noWrapper() {
        let input = "Chipotle chicken burrito bowls"
        let result = RecipeParserCore.stripInstagramOEmbedWrapper(input)
        XCTAssertEqual(result, input)
    }

    // MARK: - @maxiskitchen inline bullet format (DEvYdeDT_JM — Chipotle Chicken Burrito Bowls)

    // Representative caption in the format @maxiskitchen uses:
    // inline ■ bullets for ingredients, numbered emoji for directions,
    // ⏰ for timing, 🌱 for vegan modifications.
    static let maxisKitchenCaption = """
        Chipotle chicken burrito bowls 🌯

        Chicken marinade:■1 lb boneless skinless chicken thighs■1 lime (juice)■2 Tbsp fresh cilantro (finely chopped)■1.5 tsp chili powder■1.5 tsp cumin■1 tsp kosher salt■0.25 tsp pepper■2 Tbsp olive oil
        Beans:■15 oz can black beans (drained)■0.5 tsp cumin■0.25 tsp chili powder■0.25 tsp kosher salt
        Rice:■1 cup long grain white rice■1.5 cups water■0.5 tsp kosher salt■3 Tbsp fresh cilantro (finely chopped)■1 lime (juice)■1 Tbsp butter
        Bowl toppings:■Romaine lettuce■Shredded cheese■Salsa■Guacamole or avocado■Sour cream

        ⏰10 minute prep + 45 minute cook

        1️⃣Mix the marinade ingredients and toss with chicken. Let rest for 15-30 minutes.
        2️⃣Season the black beans with cumin, chili powder, and salt in a saucepan. Warm over low heat.
        3️⃣Cook rice: bring water to a boil, add rice and salt, cover and simmer 18 minutes. Fluff and stir in cilantro, lime juice, and butter.
        4️⃣Heat a skillet over medium-high heat with oil. Cook chicken 5-7 minutes per side until cooked through. Slice thin.
        5️⃣Assemble bowls: rice, beans, sliced chicken, romaine, cheese, salsa, guac, sour cream.

        🌱Vegan Modification: Replace chicken with 1 lb crumbled firm tofu or add extra beans.

        Subscribe to my newsletter for a printable PDF of this recipe, delivered to your inbox! Link in bio.

        #chipotlechicken #burritobowl #mealprep #chickenrecipes
        """

    func testMaxisKitchen_title() {
        let result = RecipeParserCore.parseInstagramCaption(Self.maxisKitchenCaption)
        // Parser preserves food emojis in the title; 🌯 is intentionally kept
        XCTAssertEqual(result.title, "Chipotle chicken burrito bowls 🌯")
    }

    func testMaxisKitchen_ingredientGroupCount() {
        let result = RecipeParserCore.parseInstagramCaption(Self.maxisKitchenCaption)
        XCTAssertEqual(result.ingredientGroups.count, 4, "Expected 4 groups: marinade, beans, rice, toppings")
    }

    func testMaxisKitchen_ingredientGroupNames() {
        let result = RecipeParserCore.parseInstagramCaption(Self.maxisKitchenCaption)
        let names = result.ingredientGroups.map { $0.name }
        XCTAssertEqual(names[0], "Chicken marinade")
        XCTAssertEqual(names[1], "Beans")
        XCTAssertEqual(names[2], "Rice")
        XCTAssertEqual(names[3], "Bowl toppings")
    }

    func testMaxisKitchen_ingredientCounts() {
        let result = RecipeParserCore.parseInstagramCaption(Self.maxisKitchenCaption)
        XCTAssertEqual(result.ingredientGroups[0].ingredients.count, 8, "Chicken marinade should have 8 items")
        XCTAssertEqual(result.ingredientGroups[1].ingredients.count, 4, "Beans should have 4 items")
        XCTAssertEqual(result.ingredientGroups[2].ingredients.count, 6, "Rice should have 6 items")
        XCTAssertEqual(result.ingredientGroups[3].ingredients.count, 5, "Bowl toppings should have 5 items")
    }

    func testMaxisKitchen_directionCount() {
        let result = RecipeParserCore.parseInstagramCaption(Self.maxisKitchenCaption)
        XCTAssertEqual(result.directions.count, 5)
    }

    func testMaxisKitchen_directionsHaveNoNumberPrefix() {
        let result = RecipeParserCore.parseInstagramCaption(Self.maxisKitchenCaption)
        for direction in result.directions {
            XCTAssertFalse(direction.hasPrefix("1️⃣"), "Direction prefix should be stripped: \(direction)")
            XCTAssertFalse(direction.hasPrefix("2️⃣"), "Direction prefix should be stripped: \(direction)")
        }
    }

    func testMaxisKitchen_timing() {
        let result = RecipeParserCore.parseInstagramCaption(Self.maxisKitchenCaption)
        XCTAssertEqual(result.prepDuration, 600,  "10 min prep = 600s")
        XCTAssertEqual(result.cookDuration, 2700, "45 min cook = 2700s")
    }

    func testMaxisKitchen_veganModInNotes() {
        let result = RecipeParserCore.parseInstagramCaption(Self.maxisKitchenCaption)
        XCTAssertTrue(result.notes.contains("Vegan"), "Vegan modification should be in notes")
    }

    func testMaxisKitchen_noBoilerplate() {
        let result = RecipeParserCore.parseInstagramCaption(Self.maxisKitchenCaption)
        let allText = ([result.title, result.notes]
            + result.directions
            + result.ingredientGroups.flatMap { $0.ingredients }).joined(separator: " ").lowercased()
        XCTAssertFalse(allText.contains("subscribe"), "Boilerplate should be filtered")
        XCTAssertFalse(allText.contains("link in bio"), "Boilerplate should be filtered")
        XCTAssertFalse(allText.contains("#"), "Hashtags should be filtered")
    }

    // MARK: - @dr.vegan line-per-item format (DVO0yF_CDmD — No Knead Bread Rolls)

    // Real format from the live oEmbed response: ingredients on one line with • bullets,
    // "Instructions:" header inline with the first step, subsequent steps on separate lines.
    static let drVeganCaption = """
        No Knead Bread Rolls 🍞

        Ingredients: 1 tsp yeast • 1 tbsp sugar • 2⅓ cups water • 4½ cups flour • ½ tsp salt • 2 tbsp olive oil

        Instructions: Mix yeast, sugar, water, flour, and salt. Rest 30 min.
        Fold in olive oil, rest 30 min. Do three more folds with 30 min rests between each.
        Shape into 6 rolls, score the tops, rest 15 min.
        Bake at 400°F with iced water in a tray below for steam.

        Golden, crusty, and works EVERY time.

        #bread #breadmaking #nokneadbread #baking #bake
        """

    func testDrVegan_title() {
        let result = RecipeParserCore.parseInstagramCaption(Self.drVeganCaption)
        XCTAssertEqual(result.title, "No Knead Bread Rolls 🍞")
    }

    func testDrVegan_ingredientCount() {
        let result = RecipeParserCore.parseInstagramCaption(Self.drVeganCaption)
        XCTAssertEqual(result.ingredientGroups.count, 1)
        XCTAssertEqual(result.ingredientGroups[0].ingredients.count, 6)
    }

    func testDrVegan_directionCount() {
        let result = RecipeParserCore.parseInstagramCaption(Self.drVeganCaption)
        // 4 real steps + the trailing tip line ("Golden, crusty...") which has no Notes: header
        XCTAssertEqual(result.directions.count, 5)
    }

    func testDrVegan_tipTextInOutput() {
        // "Golden, crusty..." falls into directions (no Notes: header in this format).
        // Verify it surfaces somewhere in the parsed output rather than being silently dropped.
        let result = RecipeParserCore.parseInstagramCaption(Self.drVeganCaption)
        let allText = ([result.title, result.notes]
            + result.directions
            + result.ingredientGroups.flatMap { $0.ingredients }).joined(separator: " ")
        XCTAssertTrue(allText.contains("Golden"), "Tip text should appear somewhere in parsed output")
    }

    func testDrVegan_noHashtagsInOutput() {
        let result = RecipeParserCore.parseInstagramCaption(Self.drVeganCaption)
        let allText = ([result.title, result.notes]
            + result.directions
            + result.ingredientGroups.flatMap { $0.ingredients }).joined(separator: " ")
        XCTAssertFalse(allText.contains("#"), "Hashtags should be filtered")
    }

    // MARK: - Live network tests (hit the real Instagram oEmbed API)
    //
    // These print the raw caption and parsed result so you can see exactly what
    // the parser receives and produces from each real post. Run them with Cmd+U
    // or individually by clicking the diamond next to the test name.

    func testLiveOEmbed_DEvYdeDT_JM_chipotleBurritoBowls() async throws {
        let url = "https://www.instagram.com/reel/DEvYdeDT_JM/"
        let json = try await fetchOEmbed(for: url)

        let rawTitle = try XCTUnwrap(json["title"] as? String, "oEmbed title should be present")
        XCTAssertFalse(rawTitle.isEmpty)

        let caption = RecipeParserCore.stripInstagramOEmbedWrapper(rawTitle)
        let parsed = RecipeParserCore.parseInstagramCaption(caption)

        print("\n=== DEvYdeDT_JM (@maxiskitchen — Chipotle Chicken Burrito Bowls) ===")
        printParsed(caption: caption, parsed: parsed)

        XCTAssertFalse(parsed.title.isEmpty, "Should extract a title")
        XCTAssertFalse(
            parsed.ingredientGroups.isEmpty && parsed.directions.isEmpty,
            "Should parse recipe content.\nRaw caption:\n\(caption)"
        )
    }

    func testLiveOEmbed_DVO0yF_CDmD_breadRolls() async throws {
        let url = "https://www.instagram.com/reel/DVO0yF_CDmD/"
        let json = try await fetchOEmbed(for: url)

        let rawTitle = try XCTUnwrap(json["title"] as? String, "oEmbed title should be present")
        XCTAssertFalse(rawTitle.isEmpty)

        let caption = RecipeParserCore.stripInstagramOEmbedWrapper(rawTitle)
        let parsed = RecipeParserCore.parseInstagramCaption(caption)

        print("\n=== DVO0yF_CDmD (@dr.vegan — No Knead Bread Rolls) ===")
        printParsed(caption: caption, parsed: parsed)

        XCTAssertFalse(parsed.title.isEmpty, "Should extract a title")
        XCTAssertFalse(
            parsed.ingredientGroups.isEmpty && parsed.directions.isEmpty,
            "Should parse recipe content.\nRaw caption:\n\(caption)"
        )
    }

    // MARK: - Image debugging

    func testLiveImageURL_DVO0yF_CDmD() async throws {
        let url = "https://www.instagram.com/reel/DVO0yF_CDmD/"

        // 1. Check oEmbed thumbnail_url
        let json = try await fetchOEmbed(for: url)
        let thumbnailURL = json["thumbnail_url"] as? String
        print("\noEmbed thumbnail_url: \(thumbnailURL ?? "nil")")
        print("Full oEmbed keys: \(json.keys.sorted())")

        // 2. Check og:image in the HTML page
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let html = String(data: data, encoding: .utf8) ?? ""
        let ogImage = RecipeParserCore.extractMetaContent(html: html, property: "og:image")
        print("HTTP status: \(status), HTML length: \(html.count)")
        print("og:image: \(ogImage ?? "nil")")

        // 3. Check what parseInstagramPage returns for imageURL
        let parsed = RecipeParserCore.parseInstagramPage(html: html, sourceURL: url)
        print("parseInstagramPage imageURL: \(parsed?.imageURL ?? "nil")")
    }

    // MARK: - Helpers

    private func fetchOEmbed(for urlString: String) async throws -> [String: Any] {
        let encoded = try XCTUnwrap(
            urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        )
        let oembedURL = try XCTUnwrap(
            URL(string: "https://www.instagram.com/api/v1/oembed/?url=\(encoded)")
        )
        let (data, response) = try await URLSession.shared.data(from: oembedURL)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        XCTAssertEqual(status, 200, "oEmbed request failed with status \(status)")
        return try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "oEmbed response should be a JSON object"
        )
    }

    private func printParsed(caption: String, parsed: RecipeParserCore.InstagramRecipeParts) {
        print("Raw caption (\(caption.count) chars):")
        print(caption.prefix(500))
        if caption.count > 500 { print("… [truncated]") }
        print("\nParsed:")
        print("  title:      \(parsed.title)")
        print("  groups:     \(parsed.ingredientGroups.map { "\($0.name.isEmpty ? "(unnamed)" : $0.name): \($0.ingredients.count) items" })")
        print("  directions: \(parsed.directions.count)")
        print("  notes:      \(parsed.notes.prefix(120))")
        print("  prep:       \(Int(parsed.prepDuration / 60)) min")
        print("  cook:       \(Int(parsed.cookDuration / 60)) min")
    }
}
