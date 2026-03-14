import Foundation

struct RecipeURLImporter {

    typealias ParsedRecipe = RecipeParserCore.ParsedRecipe

    enum ImportError: LocalizedError {
        case invalidURL
        case networkError(Error)
        case parsingFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The URL is not valid."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .parsingFailed:
                return "Could not find recipe data on this page."
            }
        }
    }

    static func importRecipe(from urlString: String) async throws -> ParsedRecipe {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw ImportError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, _): (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw ImportError.networkError(error)
        }

        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii) else {
            throw ImportError.parsingFailed
        }

        if var recipe = RecipeParserCore.parseRecipe(html: html, sourceURL: urlString) {
            // og:image is often absent from Instagram's HTML response; fill in the
            // thumbnail from oEmbed if we didn't get one from the page itself.
            if RecipeParserCore.isInstagramURL(urlString), recipe.imageURL == nil {
                recipe.imageURL = await fetchInstagramThumbnailURL(urlString: urlString)
            }
            return recipe
        }

        // For Instagram URLs, try the oEmbed API as a fallback
        if RecipeParserCore.isInstagramURL(urlString) {
            if let recipe = await fetchInstagramOEmbed(urlString: urlString, html: html) {
                return recipe
            }
        }

        throw ImportError.parsingFailed
    }

    /// Fetches only the thumbnail_url from Instagram's oEmbed endpoint.
    private static func fetchInstagramThumbnailURL(urlString: String) async -> String? {
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let oembedURL = URL(string: "https://www.instagram.com/api/v1/oembed/?url=\(encoded)"),
              let (data, _) = try? await URLSession.shared.data(from: oembedURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["thumbnail_url"] as? String
    }

    /// Fallback: use Instagram's oEmbed endpoint to get post metadata.
    private static func fetchInstagramOEmbed(urlString: String, html: String) async -> ParsedRecipe? {
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let oembedURL = URL(string: "https://www.instagram.com/api/v1/oembed/?url=\(encoded)") else {
            return nil
        }

        guard let (data, _) = try? await URLSession.shared.data(from: oembedURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var caption = json["title"] as? String ?? ""
        let authorName = json["author_name"] as? String ?? ""
        let thumbnailURL = json["thumbnail_url"] as? String

        guard !caption.isEmpty else { return nil }

        // The oEmbed title sometimes includes an "Author on Instagram: \"caption\"" wrapper.
        // Strip it so we parse only the actual caption text.
        caption = RecipeParserCore.stripInstagramOEmbedWrapper(caption)

        let parsed = RecipeParserCore.parseInstagramCaption(caption)

        let title: String
        if !parsed.title.isEmpty {
            title = parsed.title
        } else if !authorName.isEmpty {
            title = "Recipe by \(authorName)"
        } else {
            return nil
        }

        // Also try to get og:image from the HTML if thumbnail is missing
        let imageURL = thumbnailURL ?? RecipeParserCore.extractMetaContent(html: html, property: "og:image")

        // If structured parsing found sections, use them; otherwise store the
        // full caption in notes so the user still gets the recipe text.
        let notes: String
        if parsed.ingredientGroups.isEmpty && parsed.directions.isEmpty {
            notes = caption
        } else {
            notes = parsed.notes
        }

        return ParsedRecipe(
            title: title,
            ingredientGroups: parsed.ingredientGroups.isEmpty ? nil : parsed.ingredientGroups,
            ingredients: [],
            directions: parsed.directions,
            sourceURL: urlString,
            imageURL: imageURL,
            prepDuration: parsed.prepDuration,
            cookDuration: parsed.cookDuration,
            notes: notes
        )
    }

    // MARK: - Image Download

    static func downloadImage(from urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        } catch {
            return nil
        }
    }
}
