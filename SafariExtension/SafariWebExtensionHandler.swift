import Foundation
import ImageIO
import SafariServices
import UniformTypeIdentifiers

/// The native half of the Save to Cookbo browser extension (BrowserExtension/).
///
/// Safari can't write files the way Chrome does, so the extension's popup parses
/// the recipe and sends its Markdown here, and this writes it into Cookbo's iCloud
/// container, where the app (on every device) finds it like any recipe it saved.
///
/// Messages:
/// - `{action: "cookbooks"}` → `{cookbooks: [{id, name}]}`
/// - `{action: "save", cookbookID, fileName, markdown, imageName?, imageURL?}` → `{ok: true}`
///
/// Anything that goes wrong comes back as `{error: "…"}` for the popup to show.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]

        Task {
            let reply: [String: Any]
            do {
                reply = try await CookboFolder().handle(message)
            } catch {
                reply = ["error": (error as? LocalizedError)?.errorDescription ?? error.localizedDescription]
            }
            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: reply]
            context.completeRequest(returningItems: [response])
        }
    }
}

private struct SaveError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// `iCloud Drive/Cookbo/Cookbooks`, as RecipeStore and CookbookFolders lay it out.
private struct CookboFolder {
    private let fileManager = FileManager.default

    /// Only the cookbook's own id and name are needed from its `cookbook.json`.
    private struct CookbookFile: Decodable {
        let id: UUID
        let name: String
        let dateModified: Date?
    }

    func handle(_ message: [String: Any]) async throws -> [String: Any] {
        switch message["action"] as? String {
        case "cookbooks":
            let cookbooks = try scan().map { ["id": $0.cookbook.id.uuidString, "name": $0.cookbook.name] }
            return ["cookbooks": cookbooks]
        case "save":
            try await save(message)
            return ["ok": true]
        default:
            throw SaveError("Cookbo didn’t understand the extension. Update the app and try again.")
        }
    }

    private func cookbooksURL() throws -> URL {
        guard let container = fileManager.url(forUbiquityContainerIdentifier: "iCloud.com.jonbobrow.Cookbook") else {
            throw SaveError("iCloud Drive isn’t on. Turn it on in Settings to save recipes to Cookbo.")
        }
        return container.appendingPathComponent("Documents/Cookbooks", isDirectory: true)
    }

    /// Every cookbook folder, found by its `cookbook.json` since folders are named after
    /// their cookbook and can be renamed. Most recently changed first, like the app's list.
    private func scan() throws -> [(cookbook: CookbookFile, url: URL)] {
        let folders = (try? fileManager.contentsOfDirectory(
            at: try cookbooksURL(),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? []

        let found = folders.compactMap { folder -> (CookbookFile, URL)? in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("cookbook.json")),
                  let cookbook = try? JSONDecoder().decode(CookbookFile.self, from: data) else { return nil }
            return (cookbook, folder)
        }
        // Two folders can briefly hold one cookbook while the app merges them; offer it once
        var seen: Set<UUID> = []
        return found
            .sorted { ($0.0.dateModified ?? .distantPast) > ($1.0.dateModified ?? .distantPast) }
            .filter { seen.insert($0.0.id).inserted }
    }

    private func save(_ message: [String: Any]) async throws {
        guard let cookbookID = (message["cookbookID"] as? String).flatMap(UUID.init(uuidString:)),
              let fileName = message["fileName"] as? String, isPlainName(fileName, extension: "md"),
              var markdown = message["markdown"] as? String else {
            throw SaveError("The recipe didn’t come through. Try again.")
        }
        guard let cookbook = try scan().first(where: { $0.cookbook.id == cookbookID }) else {
            throw SaveError("That cookbook isn’t in Cookbo anymore.")
        }

        // The photo goes first, so the app never finds the recipe before its picture
        if let imageName = message["imageName"] as? String, isPlainName(imageName, extension: "jpg") {
            if let address = message["imageURL"] as? String, let jpeg = await jpeg(from: address) {
                try write(jpeg, to: cookbook.url.appendingPathComponent("Images/\(imageName)"))
            } else {
                markdown = markdown.replacingOccurrences(of: "\nimageName: \(imageName)\n", with: "\n")
            }
        }
        try write(Data(markdown.utf8), to: cookbook.url.appendingPathComponent("Recipes/\(fileName)"))
    }

    /// A file name with no path in it, so a message can't write outside the cookbook.
    private func isPlainName(_ name: String, extension ext: String) -> Bool {
        !name.contains("/") && !name.hasPrefix(".") && (name as NSString).pathExtension == ext
    }

    private func write(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    /// The recipe's photo as a JPEG, as the app stores it, no bigger than it needs to be.
    private func jpeg(from address: String) async -> Data? {
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased()),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2000,
              ] as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
