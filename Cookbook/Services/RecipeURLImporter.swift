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

        if let recipe = RecipeParserCore.parseRecipe(html: html, sourceURL: urlString) {
            return recipe
        }

        throw ImportError.parsingFailed
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
