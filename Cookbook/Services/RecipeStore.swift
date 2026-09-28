import Foundation
import Combine

class RecipeStore: ObservableObject {
    @Published var recipes: [Recipe] = []
    @Published var categories: [Category] = []
    @Published var cookbook: Cookbook
    @Published var availableCookbooks: [Cookbook] = []
    @Published var isICloudAvailable: Bool = false
    @Published var useLocalStorage: Bool = false
    @Published var shouldShowNewRecipe: Bool = false
    @Published var shouldShowURLImport: Bool = false
    @Published var pendingImportURL: String?
    /// The week-closing Friday the This Week plan was last reviewed for.
    @Published var weekPlanLastHandled: Date?

    private let fileManager = FileManager.default
    private let userDefaults = UserDefaults.standard
    private let currentCookbookKey = "currentCookbookID"
    private let storagePreferenceKey = "useLocalStorage"

    private var baseURL: URL? {
        // Check if user prefers local storage or if iCloud is unavailable
        if useLocalStorage || !isICloudAvailable {
            // Use local Documents directory
            guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            return documentsURL.appendingPathComponent("Cookbooks")
        } else {
            // Use visible iCloud Drive Documents folder
            // The Documents folder inside the ubiquity container is visible in iCloud Drive
            // On iOS: appears as "iCloud Drive/Cookbo/Cookbooks"
            // On macOS: appears as "iCloud Drive/Cookbo/Cookbooks"
            guard let iCloudDriveURL = fileManager.url(forUbiquityContainerIdentifier: nil) else {
                return nil
            }

            return iCloudDriveURL
                .appendingPathComponent("Documents")
                .appendingPathComponent("Cookbooks")
        }
    }

    /// Where each cookbook's folder was last found. A folder is named after its cookbook
    /// (see `CookbookFolders`), so the id is the only stable way to find it.
    private var cookbookDirectories: [UUID: URL] = [:]
    private var pendingFolderRename: DispatchWorkItem?

    private var cookbookFolders: CookbookFolders? {
        baseURL.map { CookbookFolders(baseURL: $0, fileManager: fileManager) }
    }

    private var currentCookbookURL: URL? {
        directory(for: cookbook)
    }

    /// A cookbook's folder: where it was last seen, found again by id if it has moved since
    /// (renamed on another device), or where it should go if it hasn't been created yet.
    private func directory(for cookbook: Cookbook) -> URL? {
        guard let folders = cookbookFolders else { return nil }

        if let known = cookbookDirectories[cookbook.id], fileManager.fileExists(atPath: known.path) {
            return known
        }
        if let found = folders.find(cookbook.id) {
            cookbookDirectories[cookbook.id] = found
            return found
        }
        return folders.expectedURL(for: cookbook)
    }

    private var iCloudURL: URL? {
        currentCookbookURL?.appendingPathComponent("Recipes")
    }

    private var imagesURL: URL? {
        currentCookbookURL?.appendingPathComponent("Images")
    }

    private var categoriesURL: URL? {
        currentCookbookURL?.appendingPathComponent("categories.json")
    }

    private var weekPlanURL: URL? {
        currentCookbookURL?.appendingPathComponent("weekplan.json")
    }

    private var cookbookMetadataURL: URL? {
        currentCookbookURL?.appendingPathComponent("cookbook.json")
    }
    
    init() {
        // Initialize with default cookbook
        self.cookbook = Cookbook()

        // Load storage preference
        useLocalStorage = userDefaults.bool(forKey: storagePreferenceKey)

        // Check iCloud availability
        checkICloudAvailability()

        // Initialize storage (works for both iCloud and local)
        setupBaseDirectory()
        loadAllCookbooks()
        loadCurrentCookbook()
        setupiCloudDirectory()
        loadCookbook()
        loadCategories()
        loadWeekPlan()
        loadRecipes()

        // Watch for iCloud changes (only if using iCloud)
        if !useLocalStorage && isICloudAvailable {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(iCloudDataChanged),
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: nil
            )
        }
    }

    func checkICloudAvailability() {
        isICloudAvailable = fileManager.url(forUbiquityContainerIdentifier: nil) != nil
    }

    func enableLocalStorage() {
        useLocalStorage = true
        userDefaults.set(true, forKey: storagePreferenceKey)

        // Reload data from local storage
        setupBaseDirectory()
        loadAllCookbooks()
        loadCurrentCookbook()
        setupiCloudDirectory()
        loadCookbook()
        loadCategories()
        loadWeekPlan()
        loadRecipes()
    }

    private func setupBaseDirectory() {
        guard let url = baseURL else { return }

        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    private func setupiCloudDirectory() {
        guard let url = iCloudURL else { return }

        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }

        // Also ensure Images directory exists
        if let imagesDir = imagesURL, !fileManager.fileExists(atPath: imagesDir.path) {
            try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        }
    }
    
    @objc private func iCloudDataChanged() {
        DispatchQueue.main.async {
            self.loadCookbook()
            self.loadCategories()
            self.loadWeekPlan()
            self.loadRecipes()
        }
    }

    // MARK: - Cookbook Management

    func loadAllCookbooks() {
        guard let folders = cookbookFolders else { return }

        // Migration: renames legacy `<UUID>` folders to `<name>-<hash>`, and folds in any
        // duplicate folder an older app version created (see CookbookFolders)
        let entries = folders.consolidate()
        cookbookDirectories = Dictionary(uniqueKeysWithValues: entries.map { ($0.cookbook.id, $0.url) })

        // Sort and assign synchronously - don't dispatch to main queue yet
        availableCookbooks = entries.map(\.cookbook).sorted { $0.name < $1.name }
    }

    func loadCurrentCookbook() {
        // Try to load the saved current cookbook ID
        if let savedID = userDefaults.string(forKey: currentCookbookKey),
           let uuid = UUID(uuidString: savedID),
           let savedCookbook = availableCookbooks.first(where: { $0.id == uuid }) {
            cookbook = savedCookbook
        } else if let firstCookbook = availableCookbooks.first {
            // Use first available cookbook
            cookbook = firstCookbook
            userDefaults.set(firstCookbook.id.uuidString, forKey: currentCookbookKey)
        } else {
            // Only create default cookbook if no cookbooks exist
            cookbook = Cookbook()
            createCookbook(cookbook)
        }
    }

    func loadCookbook() {
        guard let url = cookbookMetadataURL else { return }

        guard fileManager.fileExists(atPath: url.path) else {
            // Create default cookbook if it doesn't exist
            saveCookbook()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let loadedCookbook = try JSONDecoder().decode(Cookbook.self, from: data)
            DispatchQueue.main.async {
                self.cookbook = loadedCookbook
            }
        } catch {
            #if DEBUG
            print("Error loading cookbook: \(error)")
            #endif
        }
    }

    func saveCookbook() {
        guard let cookbookDir = currentCookbookURL else { return }
        let url = cookbookDir.appendingPathComponent("cookbook.json")

        // Ensure directory exists
        try? fileManager.createDirectory(at: cookbookDir, withIntermediateDirectories: true)
        cookbookDirectories[cookbook.id] = cookbookDir
        scheduleFolderRename(for: cookbook.id)

        var updatedCookbook = cookbook
        updatedCookbook.dateModified = Date()

        do {
            let data = try JSONEncoder().encode(updatedCookbook)
            try data.write(to: url, options: .atomic)
            DispatchQueue.main.async {
                self.cookbook = updatedCookbook
                // Update in available cookbooks
                if let index = self.availableCookbooks.firstIndex(where: { $0.id == updatedCookbook.id }) {
                    self.availableCookbooks[index] = updatedCookbook
                }
            }
        } catch {
            #if DEBUG
            print("Error saving cookbook: \(error)")
            #endif
        }
    }

    /// Renames a cookbook's folder to match its name once the name stops changing.
    /// Settings saves on every keystroke, and renaming a folder full of synced files
    /// that often would churn iCloud for nothing.
    private func scheduleFolderRename(for id: UUID) {
        pendingFolderRename?.cancel()
        let rename = DispatchWorkItem { [weak self] in
            guard let self,
                  let folders = self.cookbookFolders,
                  let target = self.cookbook.id == id ? self.cookbook : self.availableCookbooks.first(where: { $0.id == id }),
                  let current = self.directory(for: target),
                  self.fileManager.fileExists(atPath: current.path) else { return }
            self.cookbookDirectories[id] = folders.rename(current, toMatch: target)
        }
        pendingFolderRename = rename
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: rename)
    }

    func createCookbook(_ newCookbook: Cookbook) {
        cookbook = newCookbook

        // Create cookbook directory and save metadata
        saveCookbook()
        setupiCloudDirectory()

        // Add to available cookbooks synchronously
        availableCookbooks.append(newCookbook)
        availableCookbooks.sort { $0.name < $1.name }

        // Set as current
        userDefaults.set(newCookbook.id.uuidString, forKey: currentCookbookKey)

        // Reload data for new cookbook
        loadCategories()
        loadWeekPlan()
        loadRecipes()
    }

    func switchToCookbook(_ targetCookbook: Cookbook) {
        cookbook = targetCookbook
        userDefaults.set(targetCookbook.id.uuidString, forKey: currentCookbookKey)

        // Reload all data for the new cookbook
        loadCookbook()
        loadCategories()
        loadWeekPlan()
        loadRecipes()
    }

    func deleteCookbook(_ cookbookToDelete: Cookbook) {
        guard let cookbookDir = directory(for: cookbookToDelete) else { return }

        do {
            try fileManager.removeItem(at: cookbookDir)
            cookbookDirectories[cookbookToDelete.id] = nil
            availableCookbooks.removeAll { $0.id == cookbookToDelete.id }

            // If we deleted the current cookbook, switch to another one
            if cookbookToDelete.id == cookbook.id {
                if let firstCookbook = availableCookbooks.first {
                    switchToCookbook(firstCookbook)
                } else {
                    // Create a new default cookbook
                    let newCookbook = Cookbook()
                    createCookbook(newCookbook)
                }
            }
        } catch {
            #if DEBUG
            print("Error deleting cookbook: \(error)")
            #endif
        }
    }

    // MARK: - Cookbook Import/Export

    func exportCookbook(_ cookbookToExport: Cookbook) -> URL? {
        // Collect images for export
        var images: [String: Data] = [:]
        for recipe in recipes {
            if let imageName = recipe.imageName, let imageData = recipe.imageData {
                images[imageName] = imageData
            }
        }

        // Create export data
        let export = CookbookExport(
            cookbook: cookbookToExport,
            recipes: recipes,
            categories: categories,
            images: images
        )

        // Create temporary file
        let tempDir = fileManager.temporaryDirectory
        let fileName = "\(cookbookToExport.name.replacingOccurrences(of: " ", with: "_")).cookbook"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(export)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            #if DEBUG
            print("Error exporting cookbook: \(error)")
            #endif
            return nil
        }
    }

    func importCookbook(from url: URL) -> Result<Cookbook, Error> {
        do {
            // Ensure we have access to the file
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let export = try decoder.decode(CookbookExport.self, from: data)

            // Create new cookbook with a new ID to avoid conflicts
            var newCookbook = export.cookbook
            newCookbook.id = UUID()
            newCookbook.dateCreated = Date()
            newCookbook.dateModified = Date()

            // Create the cookbook
            createCookbook(newCookbook)

            // Import categories with new IDs, maintaining a mapping
            var categoryIDMapping: [UUID: UUID] = [:]
            for category in export.categories {
                let oldID = category.id
                let newID = UUID()
                categoryIDMapping[oldID] = newID

                var newCategory = category
                newCategory.id = newID
                saveCategory(newCategory)
            }

            // Import recipes with new IDs and updated category references
            for recipe in export.recipes {
                var newRecipe = recipe
                newRecipe.id = UUID()
                newRecipe.dateCreated = Date()

                // Update category reference if it exists
                if let oldCategoryID = recipe.categoryID,
                   let newCategoryID = categoryIDMapping[oldCategoryID] {
                    newRecipe.categoryID = newCategoryID
                } else {
                    newRecipe.categoryID = nil
                }

                // Reset cooking history for imported recipes
                newRecipe.datesCooked = []

                // Reset checked ingredients
                newRecipe.ingredientSections = newRecipe.ingredientSections.map { section in
                    var newSection = section
                    newSection.ingredients = section.ingredients.map { ingredient in
                        var newIngredient = ingredient
                        newIngredient.isChecked = false
                        return newIngredient
                    }
                    return newSection
                }

                // Restore image data from export images dictionary
                if let imageName = recipe.imageName, let imageData = export.images[imageName] {
                    newRecipe.imageData = imageData
                    newRecipe.imageName = nil  // Will get a new name via saveRecipe
                }

                saveRecipe(newRecipe)
            }

            return .success(newCookbook)
        } catch {
            #if DEBUG
            print("Error importing cookbook: \(error)")
            #endif
            return .failure(error)
        }
    }
    
    func loadRecipes() {
        guard let url = iCloudURL else { return }

        do {
            let allFiles = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )

            let mdFiles = allFiles.filter { $0.pathExtension == "md" }
            let jsonFiles = allFiles.filter { $0.pathExtension == "json" }

            var loadedRecipes: [Recipe] = []
            var loadedIDs: Set<UUID> = []

            // Load markdown files (current format)
            var parsedMarkdown: [(fileURL: URL, recipe: Recipe)] = []
            for fileURL in mdFiles {
                do {
                    let content = try String(contentsOf: fileURL, encoding: .utf8)
                    if let recipe = RecipeMarkdownSerializer.deserialize(content) {
                        parsedMarkdown.append((fileURL, recipe))
                    }
                } catch {
                    #if DEBUG
                    print("Error loading recipe from \(fileURL.lastPathComponent): \(error)")
                    #endif
                }
            }

            // A recipe can end up in more than one file: a legacy `<UUID>.md` next to its
            // renamed copy, a stale-title copy, or one an older app version on another
            // device saved under the old name. Keep whichever was saved most recently, so
            // an edit made elsewhere isn't thrown away; on a tie, keep the correctly named one.
            parsedMarkdown.sort { lhs, rhs in
                let lhsMatches = lhs.fileURL.lastPathComponent == recipeFileName(for: lhs.recipe)
                let rhsMatches = rhs.fileURL.lastPathComponent == recipeFileName(for: rhs.recipe)
                return lhsMatches && !rhsMatches
            }
            var newestCopies: [(fileURL: URL, recipe: Recipe)] = []
            for copies in Dictionary(grouping: parsedMarkdown, by: { $0.recipe.id }).values {
                // max(by:) keeps the first of equal elements, so a tie goes to the correctly named file
                guard let newest = copies.max(by: { modificationDate(of: $0.fileURL) < modificationDate(of: $1.fileURL) }) else { continue }
                for copy in copies where copy.fileURL != newest.fileURL {
                    try? fileManager.removeItem(at: copy.fileURL)
                }
                newestCopies.append(newest)
            }

            for (fileURL, parsedRecipe) in newestCopies {
                var recipe = parsedRecipe

                // Migration: rename legacy `<UUID>.md` (or stale-title) files to `<title>-<hash>.md`
                renameIfNeeded(fileURL, for: recipe)

                // Load image from file if available
                if let imageName = recipe.imageName {
                    recipe.imageData = loadImageFile(fileName: imageName)
                }
                loadedRecipes.append(recipe)
                loadedIDs.insert(recipe.id)
            }

            // Migrate legacy JSON files
            for fileURL in jsonFiles {
                do {
                    let data = try Data(contentsOf: fileURL)
                    var recipe = try JSONDecoder().decode(Recipe.self, from: data)

                    // Skip if already loaded from .md
                    guard !loadedIDs.contains(recipe.id) else {
                        // Clean up the duplicate JSON file
                        try? fileManager.removeItem(at: fileURL)
                        continue
                    }

                    // Migration: extract inline imageData to a separate file
                    if recipe.imageData != nil && recipe.imageName == nil {
                        let imageName = "\(recipe.id.uuidString).jpg"
                        if let imageData = recipe.imageData {
                            saveImageFile(imageData, fileName: imageName)
                        }
                        recipe.imageName = imageName
                    }

                    // Write as markdown
                    let mdURL = url.appendingPathComponent(recipeFileName(for: recipe))
                    let markdown = RecipeMarkdownSerializer.serialize(recipe)
                    try markdown.write(to: mdURL, atomically: true, encoding: .utf8)

                    // Remove old JSON file
                    try fileManager.removeItem(at: fileURL)

                    // Load image from file if not already in memory
                    if recipe.imageData == nil, let imageName = recipe.imageName {
                        recipe.imageData = loadImageFile(fileName: imageName)
                    }

                    loadedRecipes.append(recipe)
                    loadedIDs.insert(recipe.id)
                } catch {
                    #if DEBUG
                    print("Error migrating recipe from \(fileURL.lastPathComponent): \(error)")
                    #endif
                }
            }

            DispatchQueue.main.async {
                self.recipes = loadedRecipes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                self.cleanupOrphanedCategoryReferences()
            }
        } catch {
            #if DEBUG
            print("Error loading recipes: \(error)")
            #endif
        }
    }
    
    func saveRecipe(_ recipe: Recipe) {
        guard let url = iCloudURL else { return }

        let fileURL = url.appendingPathComponent(recipeFileName(for: recipe))

        do {
            var recipeToSave = recipe

            // Save image to separate file if present
            if let imageData = recipe.imageData {
                let imageName = recipe.imageName ?? "\(recipe.id.uuidString).jpg"
                saveImageFile(imageData, fileName: imageName)
                recipeToSave.imageName = imageName
            }

            // Write as markdown
            let markdown = RecipeMarkdownSerializer.serialize(recipeToSave)
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)

            // Remove any other files for this recipe: a legacy `<UUID>.json`/`<UUID>.md`,
            // or a `.md` written under the previous title
            for staleURL in recipeFileURLs(for: recipe.id) where staleURL.lastPathComponent != fileURL.lastPathComponent {
                try? fileManager.removeItem(at: staleURL)
            }

            // Keep imageData in the in-memory copy
            recipeToSave.imageData = recipe.imageData

            // Update local array
            if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
                recipes[index] = recipeToSave
            } else {
                recipes.append(recipeToSave)
            }
            recipes.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        } catch {
            #if DEBUG
            print("Error saving recipe: \(error)")
            #endif
        }
    }
    
    func deleteRecipe(_ recipe: Recipe) {
        guard iCloudURL != nil else { return }

        // Remove the markdown file plus any legacy JSON or stale-title copies
        for fileURL in recipeFileURLs(for: recipe.id) {
            try? fileManager.removeItem(at: fileURL)
        }

        // Also remove the image file
        if let imageName = recipe.imageName {
            deleteImageFile(fileName: imageName)
        }
        recipes.removeAll { $0.id == recipe.id }
    }
    
    func addCookedDate(_ recipe: Recipe) {
        var updatedRecipe = recipe
        updatedRecipe.datesCooked.append(Date())
        saveRecipe(updatedRecipe)
    }

    // MARK: - Collections

    /// The recipe to offer in the "Just viewed" row.
    var lastViewedRecipe: Recipe? {
        recipes
            .filter { $0.dateLastViewed != nil }
            .max { ($0.dateLastViewed ?? .distantPast) < ($1.dateLastViewed ?? .distantPast) }
    }

    func recipes(in collection: RecipeCollection) -> [Recipe] {
        RecipeCollectionRules.apply(collection, to: recipes)
    }

    /// Records that a recipe was opened. Reads the stored copy rather than
    /// trusting the caller's, so a stale view doesn't overwrite newer edits.
    func markViewed(_ recipe: Recipe) {
        guard var current = recipes.first(where: { $0.id == recipe.id }) else { return }
        current.dateLastViewed = Date()
        saveRecipe(current)
    }

    // MARK: - This Week Plan

    func setInThisWeek(_ recipe: Recipe, _ isInPlan: Bool) {
        guard var current = recipes.first(where: { $0.id == recipe.id }) else { return }
        guard current.isInThisWeek != isInPlan else { return }
        current.isInThisWeek = isInPlan
        saveRecipe(current)
    }

    /// Empties the plan and marks this week reviewed.
    func clearThisWeek() {
        for recipe in recipes where recipe.isInThisWeek {
            var updated = recipe
            updated.isInThisWeek = false
            saveRecipe(updated)
        }
        markWeekPlanReviewed()
    }

    /// Keeps the plan as-is and marks this week reviewed, so the prompt comes
    /// back at the close of next week.
    func rollOverThisWeek() {
        markWeekPlanReviewed()
    }

    var isWeekPlanReviewDue: Bool {
        guard recipes.contains(where: { $0.isInThisWeek }) else { return false }
        return WeekPlan.isReviewDue(lastHandled: weekPlanLastHandled)
    }

    private func markWeekPlanReviewed() {
        weekPlanLastHandled = WeekPlan.weekClose(onOrBefore: Date())
        saveWeekPlan()
    }

    private func loadWeekPlan() {
        guard let url = weekPlanURL, fileManager.fileExists(atPath: url.path) else {
            weekPlanLastHandled = nil
            return
        }

        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(WeekPlanState.self, from: data) else { return }

        DispatchQueue.main.async {
            self.weekPlanLastHandled = state.lastHandled
        }
    }

    private func saveWeekPlan() {
        guard let url = weekPlanURL else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(WeekPlanState(lastHandled: weekPlanLastHandled)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Sample Recipe

    /// Adds the sample recipe, for a cookbook that has never had one.
    func addSampleRecipe() {
        saveRecipe(SampleRecipe.make())

        // Setup may have a loadRecipes() still in flight: it read the folder
        // before the sample existed, and its result would replace the in-memory
        // list and drop it again. Re-reading now queues a newer snapshot behind
        // that one, so the sample survives either ordering.
        loadRecipes()
    }

    // MARK: - Recipe File Naming

    /// Human-legible filename for a recipe: `<kebab-case-title>-<hash>.md`
    private func recipeFileName(for recipe: Recipe) -> String {
        RecipeFileNaming.fileName(title: recipe.title, id: recipe.id)
    }

    /// All `.md`/`.json` files in the Recipes folder that belong to this recipe, in any naming format.
    private func recipeFileURLs(for id: UUID) -> [URL] {
        guard let url = iCloudURL,
              let files = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
              ) else { return [] }

        let hash = RecipeFileNaming.shortHash(for: id)
        return files.filter {
            ($0.pathExtension == "md" || $0.pathExtension == "json")
                && RecipeFileNaming.shortHash(fromFileName: $0.lastPathComponent) == hash
        }
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    /// Renames a recipe file to match the current naming convention, if it doesn't already.
    private func renameIfNeeded(_ fileURL: URL, for recipe: Recipe) {
        let expectedName = recipeFileName(for: recipe)
        guard fileURL.lastPathComponent != expectedName else { return }

        let destination = fileURL.deletingLastPathComponent().appendingPathComponent(expectedName)
        // Another device may have already renamed it and synced the result; don't clobber it
        guard !fileManager.fileExists(atPath: destination.path) else { return }

        do {
            try fileManager.moveItem(at: fileURL, to: destination)
        } catch {
            #if DEBUG
            print("Error renaming \(fileURL.lastPathComponent) to \(expectedName): \(error)")
            #endif
        }
    }

    // MARK: - Image File Management

    private func saveImageFile(_ data: Data, fileName: String) {
        guard let imagesDir = imagesURL else { return }

        if !fileManager.fileExists(atPath: imagesDir.path) {
            try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        }

        let fileURL = imagesDir.appendingPathComponent(fileName)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func loadImageFile(fileName: String) -> Data? {
        guard let imagesDir = imagesURL else { return nil }
        let fileURL = imagesDir.appendingPathComponent(fileName)
        return try? Data(contentsOf: fileURL)
    }

    private func deleteImageFile(fileName: String) {
        guard let imagesDir = imagesURL else { return }
        let fileURL = imagesDir.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: fileURL)
    }

    // MARK: - Category Management

    func loadCategories() {
        guard let url = categoriesURL else { return }

        guard fileManager.fileExists(atPath: url.path) else {
            categories = []
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let loadedCategories = try JSONDecoder().decode([Category].self, from: data)
            DispatchQueue.main.async {
                self.categories = loadedCategories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        } catch {
            #if DEBUG
            print("Error loading categories: \(error)")
            #endif
            categories = []
        }
    }

    func saveCategory(_ category: Category) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        } else {
            categories.append(category)
        }
        categories.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveCategories()
    }

    func deleteCategory(_ category: Category) {
        categories.removeAll { $0.id == category.id }

        // Remove category from all recipes
        for recipe in recipes where recipe.categoryID == category.id {
            var updatedRecipe = recipe
            updatedRecipe.categoryID = nil
            saveRecipe(updatedRecipe)
        }

        saveCategories()
    }

    private func saveCategories() {
        guard let url = categoriesURL else { return }

        do {
            let data = try JSONEncoder().encode(categories)
            try data.write(to: url, options: .atomic)
        } catch {
            #if DEBUG
            print("Error saving categories: \(error)")
            #endif
        }
    }

    func category(for recipe: Recipe) -> Category? {
        guard let categoryID = recipe.categoryID else { return nil }
        return categories.first { $0.id == categoryID }
    }

    private func cleanupOrphanedCategoryReferences() {
        let categoryIDs = Set(categories.map { $0.id })

        for recipe in recipes {
            if let categoryID = recipe.categoryID, !categoryIDs.contains(categoryID) {
                // Recipe has a reference to a deleted category, clean it up
                var updatedRecipe = recipe
                updatedRecipe.categoryID = nil
                saveRecipe(updatedRecipe)
            }
        }
    }

    // MARK: - Cookbook Statistics

    func recipeCount(for cookbook: Cookbook) -> Int {
        guard let cookbookDir = directory(for: cookbook) else { return 0 }
        let recipesDir = cookbookDir.appendingPathComponent("Recipes")

        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: recipesDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ).filter { $0.pathExtension == "md" || $0.pathExtension == "json" }

            // Deduplicate by recipe hash (a recipe may exist as both .json and .md during migration)
            let uniqueIDs = Set(fileURLs.map {
                RecipeFileNaming.shortHash(fromFileName: $0.lastPathComponent) ?? $0.lastPathComponent
            })
            return uniqueIDs.count
        } catch {
            return 0
        }
    }

    func categoryCount(for cookbook: Cookbook) -> Int {
        guard let cookbookDir = directory(for: cookbook) else { return 0 }
        let categoriesFile = cookbookDir.appendingPathComponent("categories.json")

        guard fileManager.fileExists(atPath: categoriesFile.path),
              let data = try? Data(contentsOf: categoriesFile),
              let loadedCategories = try? JSONDecoder().decode([Category].self, from: data) else {
            return 0
        }

        return loadedCategories.count
    }
}
