import Foundation

/// Builds human-legible filenames for recipe files stored in iCloud.
///
/// Format: `<kebab-case-title>-<hash>.md`, e.g. `chipotle-chicken-burrito-bowls-3f2504.md`.
/// The hash is derived from the recipe's UUID so the name is stable across devices
/// and unique even when two recipes share a title.
struct RecipeFileNaming {

    static let hashLength = 6
    static let maxSlugLength = 60
    static let fallbackSlug = "untitled"
    private static let apostrophes = CharacterSet(charactersIn: "'\u{2019}")

    // MARK: - Building names

    /// Short, stable hash for a recipe: the first 6 hex characters of its UUID.
    static func shortHash(for id: UUID) -> String {
        let hex = id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String(hex.prefix(hashLength))
    }

    /// Filename (with extension) for a recipe's markdown file.
    static func fileName(title: String, id: UUID) -> String {
        "\(slug(for: title))-\(shortHash(for: id)).md"
    }

    /// kebab-case version of a title, safe for use in filenames.
    /// Diacritics are stripped (crème → creme), apostrophes are dropped (grandma's → grandmas),
    /// anything else that isn't a letter or digit becomes a hyphen, and runs of hyphens are collapsed.
    static func slug(for title: String) -> String {
        let folded = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        var result = ""
        var lastWasSeparator = true
        for scalar in folded.unicodeScalars {
            if apostrophes.contains(scalar) {
                continue
            } else if scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                result.append("-")
                lastWasSeparator = true
            }
        }
        while result.hasSuffix("-") { result.removeLast() }

        if result.count > maxSlugLength {
            result = String(result.prefix(maxSlugLength))
            while result.hasSuffix("-") { result.removeLast() }
        }

        return result.isEmpty ? fallbackSlug : result
    }

    /// Folder name for a cookbook, following the same pattern without an extension:
    /// `<kebab-case-name>-<hash>`, e.g. `family-recipes-5a391c`.
    static func cookbookFolderName(name: String, id: UUID) -> String {
        "\(slug(for: name))-\(shortHash(for: id))"
    }

    // MARK: - Reading names

    /// Extracts the short hash from an existing recipe filename.
    /// Handles both the current `<slug>-<hash>.md` form and legacy `<UUID>.md` / `<UUID>.json` files,
    /// so files for the same recipe can be matched regardless of which format they were written in.
    static func shortHash(fromFileName fileName: String) -> String? {
        let stem = (fileName as NSString).deletingPathExtension
        if let uuid = UUID(uuidString: stem) {
            return shortHash(for: uuid)
        }
        guard let hyphen = stem.lastIndex(of: "-") else { return nil }
        let suffix = stem[stem.index(after: hyphen)...]
        guard suffix.count == hashLength,
              suffix.allSatisfy({ $0.isHexDigit }) else { return nil }
        return String(suffix)
    }
}
