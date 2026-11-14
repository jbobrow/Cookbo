import XCTest
import CoreText
import PDFKit

// RecipePDFReader and RecipeParserCore are compiled directly into this target,
// so no module import is needed.

final class RecipePDFReaderTests: XCTestCase {

    typealias Fragment = RecipePDFReader.Fragment

    /// A run of text about as wide as 11pt Helvetica sets it, unless a width is given.
    private func text(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat? = nil, height: CGFloat = 12.8) -> Fragment {
        Fragment(text: text, minX: x, maxX: x + (width ?? CGFloat(text.count) * 5.2), midY: y, height: height)
    }

    private func read(_ pages: [[Fragment]], title: String = "") throws -> RecipePDFReader.ParsedRecipe {
        try RecipePDFReader.recipe(from: pages.map { RecipePDFReader.Page(height: 792, fragments: $0) },
                                   fallbackTitle: title, sourceURL: "")
    }

    /// Laid out like a word processor's numbered list: the numbers in a
    /// column of their own, each step wrapping under its first word.
    private var handout: [Fragment] {
        [
            text("Cheddar Scones", x: 72, y: 710, height: 19),
            text("Makes 8 scones", x: 72, y: 690),
            text("Ingredients:", x: 72, y: 666),
            text("2 cups flour", x: 72, y: 642),
            text("1 cup grated cheddar*", x: 72, y: 630),
            text("3/4 cup milk", x: 72, y: 618),
            text("Directions:", x: 72, y: 594),
            text("1.", x: 72, y: 570, width: 9),
            text("2.", x: 72, y: 546, width: 9),
            text("3.", x: 72, y: 522, width: 9),
            text("Whisk the flour and cheddar in a large bowl until the cheese is coated all over,", x: 90, y: 570, width: 440),
            text("then make a well in the middle.", x: 90, y: 558, width: 160),
            text("Pour in the milk and stir until it just comes together.", x: 90, y: 546, width: 280),
            text("Pat into a round, cut into wedges and bake on a lined tray, leaving room for", x: 90, y: 522, width: 437),
            text("3-4 cm between each, for 15 minutes until golden.", x: 90, y: 510, width: 250),
            text("*sharp cheddar works best.", x: 72, y: 474),
        ]
    }

    func testStepNumbersInTheirOwnColumnRejoinTheirSteps() throws {
        let recipe = try read([handout])
        XCTAssertEqual(recipe.directions, [
            "Whisk the flour and cheddar in a large bowl until the cheese is coated all over, then make a well in the middle.",
            "Pour in the milk and stir until it just comes together.",
            "Pat into a round, cut into wedges and bake on a lined tray, leaving room for 3-4 cm between each, for 15 minutes until golden.",
        ])
    }

    func testShortLinesStayTheirOwnIngredients() throws {
        let recipe = try read([handout])
        XCTAssertEqual(recipe.title, "Cheddar Scones")
        XCTAssertEqual(recipe.ingredients, ["2 cups flour", "1 cup grated cheddar*", "3/4 cup milk"],
                       "the * stays to point at its footnote")
    }

    func testFootnotesAfterTheStepsAreNotes() throws {
        let recipe = try read([handout])
        XCTAssertEqual(recipe.notes, "Makes 8 scones\n*sharp cheddar works best.")
    }

    /// A browser prints a numbered list with the number and the first line
    /// in one run, and the lines that wrap starting under the words.
    func testWrappedStepsUnderTheirWordsRejoin() throws {
        let printed = [
            text("Directions:", x: 78, y: 400),
            text("1. Season the chicken and brown it in the oil for 4 minutes per side over", x: 87, y: 373, width: 431),
            text("medium-high heat, then move it to a plate.", x: 98, y: 356, width: 230),
            text("2. Simmer the orzo in the broth for 12 minutes.", x: 85, y: 334, width: 260),
        ]
        let recipe = try read([[text("Lemon Orzo", x: 78, y: 700, height: 19), text("Ingredients:", x: 78, y: 660),
                                text("1 cup orzo", x: 78, y: 640)] + printed])
        XCTAssertEqual(recipe.directions, [
            "Season the chicken and brown it in the oil for 4 minutes per side over medium-high heat, then move it to a plate.",
            "Simmer the orzo in the broth for 12 minutes.",
        ])
    }

    func testTwoColumnsReadLeftThenRight() throws {
        let card = [
            text("Cheddar Scones", x: 40, y: 700, height: 19),
            text("Ingredients:", x: 40, y: 650),
            text("2 cups flour", x: 40, y: 630),
            text("1 tsp salt", x: 40, y: 618),
            text("1 cup milk", x: 40, y: 606),
            text("Directions:", x: 320, y: 650),
            text("1. Mix the flour and salt.", x: 320, y: 630),
            text("2. Stir in the milk until it comes", x: 320, y: 618, width: 250),
            text("together, then bake.", x: 320, y: 606),
        ]
        let recipe = try read([card])
        XCTAssertEqual(recipe.ingredients, ["2 cups flour", "1 tsp salt", "1 cup milk"])
        XCTAssertEqual(recipe.directions, ["Mix the flour and salt.", "Stir in the milk until it comes together, then bake."])
    }

    func testABrowsersPrintedMarginsAreDropped() throws {
        func margins(_ page: Int) -> [Fragment] {
            [
                text("11/13/26, 9:41 AM", x: 20, y: 780),
                text("Cheddar Scones | Example Kitchen", x: 300, y: 780),
                text("https://example.com/cheddar-scones", x: 20, y: 12),
                text("\(page)/2", x: 570, y: 12),
            ]
        }
        let second = [
            text("4.", x: 72, y: 700, width: 9),
            text("Cool on a rack.", x: 90, y: 700),
        ]
        let pages = [handout + margins(1), second + margins(2)]
        let recipe = try RecipePDFReader.recipe(from: pages.map { RecipePDFReader.Page(height: 792, fragments: $0) },
                                                fallbackTitle: "", sourceURL: "")
        XCTAssertEqual(recipe.title, "Cheddar Scones")
        XCTAssertEqual(recipe.sourceURL, "https://example.com/cheddar-scones", "the printed address is where it came from")
        XCTAssertEqual(recipe.directions.count, 4)
        XCTAssertEqual(recipe.directions.last, "Cool on a rack.")
        XCTAssertFalse(recipe.notes.contains("Example Kitchen"))
        XCTAssertFalse(recipe.notes.contains("9:41"))
    }

    func testAPageWithoutARecipeSaysSo() {
        XCTAssertThrowsError(try read([[]])) { error in
            XCTAssertEqual(error as? RecipePDFReader.ReadError, .noText)
        }
        XCTAssertThrowsError(try read([[text("Dear neighbours, the bake sale is on Friday.", x: 72, y: 700)]])) { error in
            XCTAssertEqual(error as? RecipePDFReader.ReadError, .noRecipe)
        }
    }

    func testTitleFromFileName() {
        XCTAssertEqual(RecipePDFReader.title(fromFileName: "Lentil Mushroom Sliders__6689723402f34a00b6506f7a72bcdeeb.pdf"),
                       "Lentil Mushroom Sliders")
        XCTAssertEqual(RecipePDFReader.title(fromFileName: "grandmas_apple_pie.PDF"), "grandmas apple pie")
        XCTAssertEqual(RecipePDFReader.title(fromFileName: "Pie v1.2"), "Pie v1.2")
    }

    // MARK: - A real PDF

    /// Sets each line with Core Text at its position on a letter-size page.
    private func makePDF(_ lines: [(String, CGFloat, CGFloat)]) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
        for (string, x, y) in lines {
            let attributed = NSAttributedString(string: string, attributes: [.init(kCTFontAttributeName as String): font])
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    func testReadsAPDF() throws {
        let data = makePDF([
            ("Cheddar Scones", 72, 700),
            ("Ingredients:", 72, 670),
            ("2 cups flour", 72, 646),
            ("3/4 cup milk", 72, 634),
            ("Directions:", 72, 610),
            ("1.", 72, 586),
            ("Whisk the flour in a large bowl, then pour in the milk and stir until the dough", 90, 586),
            ("just comes together.", 90, 574),
            ("2.", 72, 562),
            ("Bake for 15 minutes.", 90, 562),
        ])
        let recipe = try RecipePDFReader.importRecipe(from: data, fileName: "scones.pdf")
        XCTAssertEqual(recipe.title, "Cheddar Scones")
        XCTAssertEqual(recipe.ingredients, ["2 cups flour", "3/4 cup milk"])
        XCTAssertEqual(recipe.directions, [
            "Whisk the flour in a large bowl, then pour in the milk and stir until the dough just comes together.",
            "Bake for 15 minutes.",
        ])
    }

    func testNotAPDF() {
        XCTAssertThrowsError(try RecipePDFReader.importRecipe(from: Data("<html></html>".utf8), fileName: "page.pdf")) { error in
            XCTAssertEqual(error as? RecipePDFReader.ReadError, .unreadable)
        }
    }

    // MARK: - The caption parser, as PDFs need it

    func testARangeIsntAStepNumber() {
        let parts = RecipeParserCore.parseInstagramCaption("Directions:\n1. Shape the dough.\n3-4 at a time, fry until golden.")
        XCTAssertEqual(parts.directions.last, "3-4 at a time, fry until golden.")
    }
}
