import XCTest

// RecipeFileNaming is compiled directly into this target (same as the app),
// so no module import is needed.

final class RecipeFileNamingTests: XCTestCase {

    let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    // MARK: - shortHash

    func testShortHash_isFirstSixHexCharsOfUUID() {
        XCTAssertEqual(RecipeFileNaming.shortHash(for: id), "3f2504")
    }

    func testShortHash_isStable() {
        XCTAssertEqual(RecipeFileNaming.shortHash(for: id), RecipeFileNaming.shortHash(for: id))
    }

    // MARK: - slug

    func testSlug_basicTitle() {
        XCTAssertEqual(RecipeFileNaming.slug(for: "Chipotle Chicken Burrito Bowls"), "chipotle-chicken-burrito-bowls")
    }

    func testSlug_stripsPunctuationAndCollapsesHyphens() {
        XCTAssertEqual(RecipeFileNaming.slug(for: "Grandma's  Mac & Cheese!!"), "grandmas-mac-cheese")
    }

    func testSlug_dropsCurlyApostrophes() {
        XCTAssertEqual(RecipeFileNaming.slug(for: "Mom\u{2019}s Chili"), "moms-chili")
    }

    func testSlug_stripsDiacritics() {
        XCTAssertEqual(RecipeFileNaming.slug(for: "Crème Brûlée"), "creme-brulee")
    }

    func testSlug_stripsEmoji() {
        XCTAssertEqual(RecipeFileNaming.slug(for: "Chipotle chicken burrito bowls 🌯"), "chipotle-chicken-burrito-bowls")
    }

    func testSlug_keepsDigits() {
        XCTAssertEqual(RecipeFileNaming.slug(for: "5-Minute Salsa"), "5-minute-salsa")
    }

    func testSlug_emptyTitleFallsBack() {
        XCTAssertEqual(RecipeFileNaming.slug(for: ""), "untitled")
        XCTAssertEqual(RecipeFileNaming.slug(for: "  ✨  "), "untitled")
    }

    func testSlug_truncatesLongTitles() {
        let long = String(repeating: "pancakes ", count: 20)
        let slug = RecipeFileNaming.slug(for: long)
        XCTAssertLessThanOrEqual(slug.count, RecipeFileNaming.maxSlugLength)
        XCTAssertFalse(slug.hasSuffix("-"))
    }

    // MARK: - fileName

    func testFileName_format() {
        XCTAssertEqual(
            RecipeFileNaming.fileName(title: "Chipotle Chicken Burrito Bowls", id: id),
            "chipotle-chicken-burrito-bowls-3f2504.md"
        )
    }

    func testFileName_sameTitleDifferentIDsAreUnique() {
        let a = RecipeFileNaming.fileName(title: "Pancakes", id: UUID())
        let b = RecipeFileNaming.fileName(title: "Pancakes", id: UUID())
        XCTAssertNotEqual(a, b)
    }

    // MARK: - shortHash(fromFileName:)

    func testHashFromFileName_currentFormat() {
        XCTAssertEqual(RecipeFileNaming.shortHash(fromFileName: "chipotle-chicken-burrito-bowls-3f2504.md"), "3f2504")
    }

    func testHashFromFileName_legacyUUIDFormats() {
        XCTAssertEqual(RecipeFileNaming.shortHash(fromFileName: "\(id.uuidString).md"), "3f2504")
        XCTAssertEqual(RecipeFileNaming.shortHash(fromFileName: "\(id.uuidString).json"), "3f2504")
    }

    func testHashFromFileName_roundTrips() {
        let name = RecipeFileNaming.fileName(title: "Grandma's Mac & Cheese", id: id)
        XCTAssertEqual(RecipeFileNaming.shortHash(fromFileName: name), RecipeFileNaming.shortHash(for: id))
    }

    func testHashFromFileName_unrelatedFile() {
        XCTAssertNil(RecipeFileNaming.shortHash(fromFileName: "categories.json"))
        XCTAssertNil(RecipeFileNaming.shortHash(fromFileName: "notes.md"))
        XCTAssertNil(RecipeFileNaming.shortHash(fromFileName: "my-recipe-notes.md"))
    }
}
