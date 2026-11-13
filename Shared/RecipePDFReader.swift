import Foundation
import CoreGraphics
import PDFKit

/// Reads a recipe saved as a PDF: a printed web page, a recipe card, a
/// handout. The text comes off the page in reading order, so step numbers
/// set in a column of their own rejoin their steps, lines that wrap rejoin
/// their sentence, and side-by-side columns read one after the other. The
/// caption parser then sorts it into ingredients, steps and notes.
enum RecipePDFReader {

    typealias ParsedRecipe = RecipeParserCore.ParsedRecipe

    enum ReadError: LocalizedError {
        case unreadable
        case noText
        case noRecipe

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "This file couldn't be opened as a PDF."
            case .noText:
                return "This PDF has no text to read. It may be a scan or a photo of a page."
            case .noRecipe:
                return "Couldn't find ingredients or steps in this PDF."
            }
        }
    }

    /// One run of text on a page, in page points with y running up.
    struct Fragment: Equatable {
        var text: String
        var minX: CGFloat
        var maxX: CGFloat
        var midY: CGFloat
        var height: CGFloat
    }

    struct Page {
        var height: CGFloat
        var fragments: [Fragment]
    }

    // MARK: - Entry points

    static func importRecipe(from data: Data, fileName: String, sourceURL: String = "") throws -> ParsedRecipe {
        guard let document = PDFDocument(data: data) else { throw ReadError.unreadable }
        return try importRecipe(from: document, fileName: fileName, sourceURL: sourceURL)
    }

    static func importRecipe(from document: PDFDocument, fileName: String, sourceURL: String = "") throws -> ParsedRecipe {
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }.map(page(from:))
        let documentTitle = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        return try recipe(from: pages, fallbackTitle: documentTitle ?? title(fromFileName: fileName), sourceURL: sourceURL)
    }

    /// The text PDFKit finds on a page, a fragment per run.
    static func page(from pdfPage: PDFPage) -> Page {
        let box = pdfPage.bounds(for: .mediaBox)
        let lines = pdfPage.selection(for: box)?.selectionsByLine() ?? []
        let fragments = lines.compactMap { line -> Fragment? in
            let text = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let bounds = line.bounds(for: pdfPage)
            return Fragment(text: text, minX: bounds.minX, maxX: bounds.maxX,
                            midY: bounds.midY - box.minY, height: bounds.height)
        }
        return Page(height: box.height, fragments: fragments)
    }

    static func recipe(from pages: [Page], fallbackTitle: String, sourceURL: String) throws -> ParsedRecipe {
        let (pages, printedURL) = withoutRunningHeads(pages)
        let text = self.text(from: pages)
        guard !text.isEmpty else { throw ReadError.noText }

        let parsed = RecipeParserCore.parseInstagramCaption(text)
        guard !parsed.ingredientGroups.isEmpty || !parsed.directions.isEmpty else { throw ReadError.noRecipe }

        let fallbackTitle = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedRecipe(
            title: parsed.title.isEmpty ? (fallbackTitle.isEmpty ? "Untitled Recipe" : fallbackTitle) : parsed.title,
            ingredientGroups: parsed.ingredientGroups,
            directions: parsed.directions,
            sourceURL: sourceURL.isEmpty ? (printedURL ?? "") : sourceURL,
            imageURL: nil,
            prepDuration: parsed.prepDuration,
            cookDuration: parsed.cookDuration,
            notes: parsed.notes
        )
    }

    /// "Lentil Mushroom Sliders__66897234….pdf" → "Lentil Mushroom Sliders".
    static func title(fromFileName fileName: String) -> String {
        fileName
            .replacingOccurrences(of: #"\.pdf$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"_*[0-9a-f]{16,}$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Running heads

    /// A browser's printout carries the date, the page's title, its address
    /// and "1/3" in the margins of every page. They aren't the recipe, but
    /// the address is where it came from.
    static func withoutRunningHeads(_ pages: [Page]) -> (pages: [Page], url: String?) {
        var url: String?
        var counts: [String: Int] = [:]
        for page in pages {
            for text in Set(page.fragments.filter { inMargin($0, pageHeight: page.height) }.map(\.text)) {
                counts[text, default: 0] += 1
            }
        }
        let cleaned = pages.map { page in
            var page = page
            let height = page.height
            page.fragments.removeAll { fragment in
                guard inMargin(fragment, pageHeight: height) else { return false }
                if isWebAddress(fragment.text) {
                    if url == nil { url = fragment.text }
                    return true
                }
                return isPageNumber(fragment.text) || isTimestamp(fragment.text)
                    || (pages.count > 1 && counts[fragment.text, default: 0] > 1)
            }
            return page
        }
        return (cleaned, url)
    }

    private static func inMargin(_ fragment: Fragment, pageHeight: CGFloat) -> Bool {
        let band = pageHeight * 0.06
        return fragment.midY < band || fragment.midY > pageHeight - band
    }

    private static func isWebAddress(_ text: String) -> Bool {
        text.range(of: #"^https?://\S+$"#, options: .regularExpression) != nil
    }

    private static func isPageNumber(_ text: String) -> Bool {
        text.range(of: #"^(?:page\s*)?\d{1,3}(?:\s*(?:/|of)\s*\d{1,3})?$"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isTimestamp(_ text: String) -> Bool {
        text.range(of: #"^\d{1,2}/\d{1,2}/\d{2,4},?\s+\d{1,2}:\d{2}(?:\s*[AP]M)?"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Reading order

    /// A line of text across the page: the fragments that share a baseline.
    struct Row {
        var fragments: [Fragment]

        var text: String { fragments.map(\.text).joined(separator: " ") }
        var minX: CGFloat { fragments.first?.minX ?? 0 }
        var maxX: CGFloat { fragments.map(\.maxX).max() ?? 0 }
        var midY: CGFloat { fragments.first?.midY ?? 0 }
        var height: CGFloat { fragments.map(\.height).max() ?? 0 }

        /// Where the words start, past a number or bullet set apart from them.
        var bodyX: CGFloat {
            if fragments.count > 1, isMarker(fragments[0].text) { return fragments[1].minX }
            return minX
        }

        /// Roughly how wide the first word is, to tell whether it would
        /// have fit at the end of the line before.
        var firstWordWidth: CGFloat {
            let text = self.text
            guard !text.isEmpty else { return 0 }
            let width = maxX - minX
            let word = text.prefix { !$0.isWhitespace }
            return width / CGFloat(text.count) * CGFloat(word.count + 1)
        }
    }

    /// The pages' text, a line per paragraph, step, ingredient or heading.
    static func text(from pages: [Page]) -> String {
        var paragraphs: [String] = []
        var last: (row: Row, room: CGFloat)?
        for page in pages {
            for block in blocks(page.fragments) {
                let rows = self.rows(block)
                let right = rows.map(\.maxX).max() ?? 0
                for row in rows {
                    if let last, continues(row, after: last.row, room: last.room), let previous = paragraphs.popLast() {
                        paragraphs.append(join(previous, row.text))
                    } else {
                        paragraphs.append(row.text)
                    }
                    last = (row, right - row.maxX)
                }
                // A new column or page starts its own paragraph
                last = nil
            }
        }
        return paragraphs.joined(separator: "\n")
    }

    /// Fragments grouped into lines, top to bottom and left to right.
    static func rows(_ fragments: [Fragment]) -> [Row] {
        var rows: [Row] = []
        for fragment in fragments.sorted(by: { $0.midY > $1.midY }) {
            if let index = rows.indices.last,
               abs(rows[index].midY - fragment.midY) < min(rows[index].height, fragment.height) * 0.5 {
                rows[index].fragments.append(fragment)
            } else {
                rows.append(Row(fragments: [fragment]))
            }
        }
        for index in rows.indices {
            rows[index].fragments.sort { $0.minX < $1.minX }
        }
        return rows
    }

    /// The page split into the stretches read one after another: text that
    /// runs across the page, and between those, a left column and then a
    /// right one when the page has two.
    static func blocks(_ fragments: [Fragment]) -> [[Fragment]] {
        let rows = self.rows(fragments)
        guard let gutter = gutter(rows) else { return [fragments] }

        var blocks: [[Fragment]] = []
        var across: [Fragment] = []
        var left: [Fragment] = []
        var right: [Fragment] = []
        func flushColumns() {
            if !left.isEmpty { blocks.append(left) }
            if !right.isEmpty { blocks.append(right) }
            left = []; right = []
        }
        for row in rows {
            if row.fragments.contains(where: { $0.minX < gutter.lowerBound && $0.maxX > gutter.upperBound }) {
                flushColumns()
                across.append(contentsOf: row.fragments)
            } else {
                if !across.isEmpty { blocks.append(across); across = [] }
                for fragment in row.fragments {
                    if fragment.maxX <= gutter.upperBound { left.append(fragment) } else { right.append(fragment) }
                }
            }
        }
        flushColumns()
        if !across.isEmpty { blocks.append(across) }
        return blocks
    }

    /// The gap two columns keep down the page, if at least three lines
    /// sit side by side across it.
    private static func gutter(_ rows: [Row]) -> ClosedRange<CGFloat>? {
        var gutter: ClosedRange<CGFloat>?
        var sideBySide = 0
        for row in rows {
            for (a, b) in zip(row.fragments, row.fragments.dropFirst()) {
                let charWidth = (a.maxX - a.minX) / CGFloat(max(a.text.count, 1))
                let gap = b.minX - a.maxX
                guard gap > max(12, charWidth * 3), !isMarker(a.text) else { continue }
                let range = a.maxX...b.minX
                if let current = gutter {
                    let lower = max(current.lowerBound, range.lowerBound)
                    let upper = min(current.upperBound, range.upperBound)
                    guard lower < upper else { return nil }
                    gutter = lower...upper
                } else {
                    gutter = range
                }
                sideBySide += 1
            }
        }
        return sideBySide >= 3 ? gutter : nil
    }

    /// Whether `row` carries on the paragraph `previous` started, rather
    /// than starting its own line.
    private static func continues(_ row: Row, after previous: Row, room: CGFloat) -> Bool {
        let gap = previous.midY - row.midY
        guard gap < min(previous.height, row.height) * 1.4 else { return false }   // a blank line
        guard !startsItem(row.text), !previous.text.hasSuffix(":") else { return false }
        guard row.minX < previous.bodyX + 10 else { return false }                 // indented further in
        // Two lines that each open with an amount are two ingredients, however
        // full a narrow column makes the first look
        if startsWithAmount(row.text), startsWithAmount(previous.text), !endsMidPhrase(previous.text) {
            return false
        }
        // A line only wraps when the next line's first word wouldn't fit after it
        return row.firstWordWidth > room - 2
    }

    private static func startsWithAmount(_ text: String) -> Bool {
        text.range(of: #"^[\d½¼¾⅓⅔⅛⅜⅝⅞]"#, options: .regularExpression) != nil
    }

    /// "…cut into" or "…drained," before "1/2-inch pieces" on the next line.
    private static func endsMidPhrase(_ text: String) -> Bool {
        if let last = text.last, ",(-–".contains(last) { return true }
        let word = text.split(separator: " ").last?.lowercased() ?? ""
        return ["and", "or", "into", "of", "plus", "about", "to", "for", "with", "a", "the"].contains(word)
    }

    private static func join(_ paragraph: String, _ line: String) -> String {
        if paragraph.hasSuffix("-"), paragraph.dropLast().last?.isLetter == true {
            return paragraph + line
        }
        return paragraph + " " + line
    }

    /// A number or bullet on its own: "1.", "2)", "•".
    static func isMarker(_ text: String) -> Bool {
        text.range(of: #"^(?:\d{1,2}[.)]|[•●▪◦‣·■□–—\-*])$"#, options: .regularExpression) != nil
    }

    /// A line that opens a numbered step or a bullet.
    private static func startsItem(_ text: String) -> Bool {
        text.range(of: #"^(?:\d{1,2}[.)]|[•●▪◦‣·■□–—\-*]|step\s*\d+[.:)]?)\s"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }
}
