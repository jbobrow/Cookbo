import Foundation

/// Keeps each cookbook's folder named after the cookbook, the way recipe files are:
/// `Cookbooks/<kebab-case-name>-<hash>/`.
///
/// A cookbook's identity is the `id` in its `cookbook.json`, never its folder name,
/// so folders are found by reading that file and can be renamed freely.
///
/// App versions before 1.4 open a cookbook at `Cookbooks/<UUID>/`. When one of those
/// runs on another device after the folder was renamed, it creates a fresh, empty
/// folder there with the same id. `consolidate()` folds that folder back into the
/// real one, so nothing saved on the older device is lost.
struct CookbookFolders {
    let baseURL: URL
    var fileManager: FileManager = .default

    struct Entry {
        let cookbook: Cookbook
        let url: URL
    }

    func expectedURL(for cookbook: Cookbook) -> URL {
        baseURL.appendingPathComponent(
            RecipeFileNaming.cookbookFolderName(name: cookbook.name, id: cookbook.id),
            isDirectory: true
        )
    }

    /// Every folder that holds a readable `cookbook.json`, duplicates included.
    func scan() -> [Entry] {
        let folders = (try? fileManager.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? []

        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("cookbook.json")),
                  let cookbook = try? JSONDecoder().decode(Cookbook.self, from: data) else { return nil }
            return Entry(cookbook: cookbook, url: folder)
        }
    }

    /// Finds a cookbook's folder by id, wherever it is now.
    func find(_ id: UUID) -> URL? {
        scan().first { $0.cookbook.id == id }?.url
    }

    /// Brings every folder in line: merges duplicate folders for the same cookbook,
    /// then renames each to match its cookbook's name. Returns one entry per cookbook.
    func consolidate() -> [Entry] {
        var result: [Entry] = []

        for copies in Dictionary(grouping: scan(), by: { $0.cookbook.id }).values {
            // Keep the correctly named folder if there is one, otherwise the one with the most recipes
            let ranked = copies.sorted { lhs, rhs in
                let lhsNamed = lhs.url.lastPathComponent == expectedURL(for: lhs.cookbook).lastPathComponent
                let rhsNamed = rhs.url.lastPathComponent == expectedURL(for: rhs.cookbook).lastPathComponent
                if lhsNamed != rhsNamed { return lhsNamed }
                return recipeFileCount(in: lhs.url) > recipeFileCount(in: rhs.url)
            }
            guard let keeper = ranked.first else { continue }

            for duplicate in ranked.dropFirst() {
                merge(duplicate.url, into: keeper.url)
            }

            result.append(Entry(cookbook: keeper.cookbook, url: rename(keeper.url, toMatch: keeper.cookbook)))
        }

        return result
    }

    /// Renames a cookbook's folder to match its name. Returns where the folder is afterwards.
    @discardableResult
    func rename(_ url: URL, toMatch cookbook: Cookbook) -> URL {
        let destination = expectedURL(for: cookbook)
        guard url.lastPathComponent != destination.lastPathComponent else { return url }
        // Something is already there (say, another device's rename synced first); leave both alone
        guard !fileManager.fileExists(atPath: destination.path) else { return url }

        do {
            try fileManager.moveItem(at: url, to: destination)
            return destination
        } catch {
            #if DEBUG
            print("Error renaming cookbook folder \(url.lastPathComponent): \(error)")
            #endif
            return url
        }
    }

    // MARK: - Merging duplicates

    /// Moves recipes, images and categories from `duplicate` into `keeper`, keeping the
    /// newer file when both have one. The duplicate is removed only once it's empty, so
    /// iCloud files that haven't downloaded yet are never deleted; a later pass picks them up.
    func merge(_ duplicate: URL, into keeper: URL) {
        for folder in ["Recipes", "Images"] {
            moveContents(of: duplicate.appendingPathComponent(folder), into: keeper.appendingPathComponent(folder))
        }
        mergeCategories(from: duplicate, into: keeper)

        for folder in ["Recipes", "Images"] {
            removeIfEmpty(duplicate.appendingPathComponent(folder))
        }
        let leftovers = contents(of: duplicate).filter {
            !["cookbook.json", "categories.json", "weekplan.json", ".DS_Store"].contains($0.lastPathComponent)
        }
        // Still holding something we couldn't move: keep its cookbook.json so it's found again next time
        guard leftovers.isEmpty else { return }
        try? fileManager.removeItem(at: duplicate)
    }

    private func moveContents(of source: URL, into destination: URL) {
        let files = (try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        guard !files.isEmpty else { return }
        try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        for file in files {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                guard modificationDate(of: file) > modificationDate(of: target) else {
                    try? fileManager.removeItem(at: file)
                    continue
                }
                try? fileManager.removeItem(at: target)
            }
            try? fileManager.moveItem(at: file, to: target)
        }
    }

    /// Adds any categories only the duplicate has; for ones both have, the keeper's win.
    private func mergeCategories(from duplicate: URL, into keeper: URL) {
        let keeperFile = keeper.appendingPathComponent("categories.json")
        guard let extra = readCategories(duplicate.appendingPathComponent("categories.json")), !extra.isEmpty else { return }

        var categories = readCategories(keeperFile) ?? []
        let known = Set(categories.map(\.id))
        let added = extra.filter { !known.contains($0.id) }
        guard !added.isEmpty else { return }

        categories += added
        if let data = try? JSONEncoder().encode(categories) {
            try? data.write(to: keeperFile, options: .atomic)
        }
    }

    private func readCategories(_ url: URL) -> [Category]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Category].self, from: data)
    }

    private func removeIfEmpty(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let remaining = contents(of: url).filter { $0.lastPathComponent != ".DS_Store" }
        if remaining.isEmpty { try? fileManager.removeItem(at: url) }
    }

    /// Everything in a folder, including hidden iCloud placeholders for files not yet downloaded.
    private func contents(of url: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
    }

    private func recipeFileCount(in folder: URL) -> Int {
        contents(of: folder.appendingPathComponent("Recipes")).count
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }
}
