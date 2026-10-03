import XCTest

// CookbookFolders, Cookbook and Category are compiled directly into this target,
// so no module import is needed.

/// Every test works on real folders in a temporary directory.
final class CookbookFoldersTests: XCTestCase {

    private var base: URL!
    private var folders: CookbookFolders!
    private let fm = FileManager.default

    private let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    override func setUpWithError() throws {
        base = fm.temporaryDirectory.appendingPathComponent("CookbookFoldersTests-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        folders = CookbookFolders(baseURL: base)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: base)
    }

    // MARK: - Helpers

    /// Creates `Cookbooks/<folder>/` with a cookbook.json and whatever else is asked for.
    @discardableResult
    private func makeFolder(
        _ name: String,
        for cookbook: Cookbook,
        recipes: [String: String] = [:],
        categories: [Category]? = nil
    ) throws -> URL {
        let folder = base.appendingPathComponent(name)
        try fm.createDirectory(at: folder.appendingPathComponent("Recipes"), withIntermediateDirectories: true)
        try JSONEncoder().encode(cookbook).write(to: folder.appendingPathComponent("cookbook.json"))
        for (file, contents) in recipes {
            try contents.write(to: folder.appendingPathComponent("Recipes/\(file)"), atomically: true, encoding: .utf8)
        }
        if let categories {
            try JSONEncoder().encode(categories).write(to: folder.appendingPathComponent("categories.json"))
        }
        return folder
    }

    private func setModified(_ url: URL, secondsAgo: TimeInterval) throws {
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-secondsAgo)], ofItemAtPath: url.path)
    }

    private func folderNames() throws -> [String] {
        try fm.contentsOfDirectory(atPath: base.path).filter { !$0.hasPrefix(".") }.sorted()
    }

    private func recipeFiles(in folder: String) throws -> [String] {
        try fm.contentsOfDirectory(atPath: base.appendingPathComponent("\(folder)/Recipes").path).sorted()
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: base.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - Naming

    func testFolderName_isSlugPlusHash() {
        XCTAssertEqual(RecipeFileNaming.cookbookFolderName(name: "Family Recipes", id: id), "family-recipes-3f2504")
        XCTAssertEqual(RecipeFileNaming.cookbookFolderName(name: "Mom’s Kitchen", id: id), "moms-kitchen-3f2504")
        XCTAssertEqual(RecipeFileNaming.cookbookFolderName(name: "", id: id), "untitled-3f2504")
    }

    func testFolderName_sameNameDifferentCookbooksDontCollide() {
        let a = RecipeFileNaming.cookbookFolderName(name: "My Cookbook", id: UUID())
        let b = RecipeFileNaming.cookbookFolderName(name: "My Cookbook", id: UUID())
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Scanning

    func testScan_ignoresFoldersWithoutCookbookJSON() throws {
        try makeFolder("family-recipes-3f2504", for: Cookbook(id: id, name: "Family Recipes"))
        try fm.createDirectory(at: base.appendingPathComponent("stray"), withIntermediateDirectories: true)

        XCTAssertEqual(folders.scan().map(\.url.lastPathComponent), ["family-recipes-3f2504"])
    }

    func testFind_locatesAFolderByIDWhateverItsName() throws {
        try makeFolder("some-old-name-3f2504", for: Cookbook(id: id, name: "Family Recipes"))
        XCTAssertEqual(folders.find(id)?.lastPathComponent, "some-old-name-3f2504")
        XCTAssertNil(folders.find(UUID()))
    }

    // MARK: - Migration and renaming

    func testConsolidate_renamesLegacyUUIDFolderAndKeepsContents() throws {
        try makeFolder(id.uuidString, for: Cookbook(id: id, name: "Family Recipes"), recipes: ["soup-aaaaaa.md": "soup"])

        let entries = folders.consolidate()

        XCTAssertEqual(try folderNames(), ["family-recipes-3f2504"])
        XCTAssertEqual(entries.map(\.url.lastPathComponent), ["family-recipes-3f2504"])
        XCTAssertEqual(try read("family-recipes-3f2504/Recipes/soup-aaaaaa.md"), "soup")
    }

    func testConsolidate_followsARenamedCookbook() throws {
        try makeFolder("my-cookbook-3f2504", for: Cookbook(id: id, name: "Family Recipes"))
        _ = folders.consolidate()
        XCTAssertEqual(try folderNames(), ["family-recipes-3f2504"])
    }

    func testConsolidate_leavesCorrectlyNamedFoldersAlone() throws {
        try makeFolder("family-recipes-3f2504", for: Cookbook(id: id, name: "Family Recipes"), recipes: ["a-111111.md": "a"])
        _ = folders.consolidate()
        XCTAssertEqual(try folderNames(), ["family-recipes-3f2504"])
        XCTAssertEqual(try recipeFiles(in: "family-recipes-3f2504"), ["a-111111.md"])
    }

    func testRename_doesNotOverwriteAnExistingFolder() throws {
        let cookbook = Cookbook(id: id, name: "Family Recipes")
        let old = try makeFolder("old-name-3f2504", for: cookbook)
        try fm.createDirectory(at: base.appendingPathComponent("family-recipes-3f2504"), withIntermediateDirectories: true)

        XCTAssertEqual(folders.rename(old, toMatch: cookbook), old)
        XCTAssertEqual(try folderNames(), ["family-recipes-3f2504", "old-name-3f2504"])
    }

    // MARK: - Merging a folder an older app version recreated

    func testConsolidate_mergesAnOlderVersionsDuplicateFolder() throws {
        let cookbook = Cookbook(id: id, name: "Family Recipes")
        let keeper = try makeFolder(
            "family-recipes-3f2504", for: cookbook,
            recipes: ["cake.md": "cake: current", "stew.md": "stew: current"],
            categories: [Category(name: "Baking")]
        )
        let desserts = Category(name: "Desserts")
        let duplicate = try makeFolder(
            id.uuidString, for: cookbook,
            recipes: ["cake.md": "cake: edited on the iPad", "stew.md": "stew: stale", "new.md": "new on the iPad"],
            categories: [desserts]
        )
        // The iPad's cake edit is newer than ours; its copy of the stew is older
        try setModified(keeper.appendingPathComponent("Recipes/cake.md"), secondsAgo: 600)
        try setModified(duplicate.appendingPathComponent("Recipes/cake.md"), secondsAgo: 60)
        try setModified(keeper.appendingPathComponent("Recipes/stew.md"), secondsAgo: 60)
        try setModified(duplicate.appendingPathComponent("Recipes/stew.md"), secondsAgo: 600)

        let entries = folders.consolidate()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(try folderNames(), ["family-recipes-3f2504"], "the duplicate folder should be gone")
        XCTAssertEqual(try recipeFiles(in: "family-recipes-3f2504"), ["cake.md", "new.md", "stew.md"])
        XCTAssertEqual(try read("family-recipes-3f2504/Recipes/cake.md"), "cake: edited on the iPad")
        XCTAssertEqual(try read("family-recipes-3f2504/Recipes/stew.md"), "stew: current")
        XCTAssertEqual(try read("family-recipes-3f2504/Recipes/new.md"), "new on the iPad")

        let categories = try JSONDecoder().decode(
            [Category].self,
            from: Data(contentsOf: keeper.appendingPathComponent("categories.json"))
        )
        XCTAssertEqual(categories.map(\.name), ["Baking", "Desserts"])
    }

    func testMerge_keepsTheKeepersVersionOfASharedCategory() throws {
        let cookbook = Cookbook(id: id, name: "Family Recipes")
        let shared = Category(name: "Baking", colorHex: "#111111")
        var renamed = shared
        renamed.name = "Renamed elsewhere"
        let keeper = try makeFolder("family-recipes-3f2504", for: cookbook, categories: [shared])
        try makeFolder(id.uuidString, for: cookbook, categories: [renamed])

        _ = folders.consolidate()

        let categories = try JSONDecoder().decode(
            [Category].self,
            from: Data(contentsOf: keeper.appendingPathComponent("categories.json"))
        )
        XCTAssertEqual(categories.map(\.name), ["Baking"])
    }

    func testMerge_keepsAFolderThatStillHasUndownloadedFiles() throws {
        let cookbook = Cookbook(id: id, name: "Family Recipes")
        try makeFolder("family-recipes-3f2504", for: cookbook)
        let duplicate = try makeFolder(id.uuidString, for: cookbook, recipes: ["ready.md": "ready"])
        // How iCloud represents a file that hasn't downloaded yet
        try "".write(to: duplicate.appendingPathComponent("Recipes/.pending.md.icloud"), atomically: true, encoding: .utf8)

        _ = folders.consolidate()

        XCTAssertEqual(try recipeFiles(in: "family-recipes-3f2504"), ["ready.md"], "downloaded files still move over")
        XCTAssertTrue(fm.fileExists(atPath: duplicate.appendingPathComponent("Recipes/.pending.md.icloud").path))
        XCTAssertTrue(
            fm.fileExists(atPath: duplicate.appendingPathComponent("cookbook.json").path),
            "keeps cookbook.json so the folder is found and merged again once the file arrives"
        )
    }

    func testConsolidate_prefersTheFolderWithMoreRecipesWhenNeitherIsCorrectlyNamed() throws {
        let cookbook = Cookbook(id: id, name: "Family Recipes")
        try makeFolder("old-name-3f2504", for: cookbook, recipes: ["a.md": "a", "b.md": "b", "c.md": "c"])
        try makeFolder(id.uuidString, for: cookbook, recipes: ["d.md": "d"])

        _ = folders.consolidate()

        XCTAssertEqual(try folderNames(), ["family-recipes-3f2504"])
        XCTAssertEqual(try recipeFiles(in: "family-recipes-3f2504"), ["a.md", "b.md", "c.md", "d.md"])
    }

    func testConsolidate_keepsDifferentCookbooksSeparate() throws {
        let other = UUID(uuidString: "9B7F4C2A-0000-0000-0000-000000000000")!
        try makeFolder(id.uuidString, for: Cookbook(id: id, name: "Weeknight"))
        try makeFolder(other.uuidString, for: Cookbook(id: other, name: "Weeknight"))

        let entries = folders.consolidate()

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(try folderNames(), ["weeknight-3f2504", "weeknight-9b7f4c"])
    }
}
