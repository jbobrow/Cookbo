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
            // On iOS: appears as "iCloud Drive/Cookbook/Cookbooks"
            // On macOS: appears as "iCloud Drive/Cookbook/Cookbooks"
            guard let iCloudDriveURL = fileManager.url(forUbiquityContainerIdentifier: nil) else {
                return nil
            }

            return iCloudDriveURL
                .appendingPathComponent("Documents")
                .appendingPathComponent("Cookbooks")
        }
    }

    private var currentCookbookURL: URL? {
        guard let baseURL = baseURL else { return nil }
        return baseURL.appendingPathComponent(cookbook.id.uuidString)
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
            self.loadRecipes()
        }
    }

    // MARK: - Cookbook Management

    func loadAllCookbooks() {
        guard let baseURL = baseURL else { return }

        do {
            let cookbookDirs = try fileManager.contentsOfDirectory(
                at: baseURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )

            var cookbooks: [Cookbook] = []
            for dir in cookbookDirs {
                let metadataURL = dir.appendingPathComponent("cookbook.json")
                if fileManager.fileExists(atPath: metadataURL.path),
                   let data = try? Data(contentsOf: metadataURL),
                   let cookbook = try? JSONDecoder().decode(Cookbook.self, from: data) {
                    cookbooks.append(cookbook)
                }
            }

            // Sort and assign synchronously - don't dispatch to main queue yet
            availableCookbooks = cookbooks.sorted { $0.name < $1.name }
        } catch {
            #if DEBUG
            print("Error loading cookbooks: \(error)")
            #endif
            availableCookbooks = []
        }
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
        guard let url = cookbookMetadataURL else { return }

        // Ensure directory exists
        if let cookbookDir = currentCookbookURL {
            try? fileManager.createDirectory(at: cookbookDir, withIntermediateDirectories: true)
        }

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
        loadRecipes()
    }

    func switchToCookbook(_ targetCookbook: Cookbook) {
        cookbook = targetCookbook
        userDefaults.set(targetCookbook.id.uuidString, forKey: currentCookbookKey)

        // Reload all data for the new cookbook
        loadCookbook()
        loadCategories()
        loadRecipes()
    }

    func deleteCookbook(_ cookbookToDelete: Cookbook) {
        guard let baseURL = baseURL else { return }
        let cookbookDir = baseURL.appendingPathComponent(cookbookToDelete.id.uuidString)

        do {
            try fileManager.removeItem(at: cookbookDir)
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
            for fileURL in mdFiles {
                do {
                    let content = try String(contentsOf: fileURL, encoding: .utf8)
                    if var recipe = RecipeMarkdownSerializer.deserialize(content) {
                        // Load image from file if available
                        if let imageName = recipe.imageName {
                            recipe.imageData = loadImageFile(fileName: imageName)
                        }
                        loadedRecipes.append(recipe)
                        loadedIDs.insert(recipe.id)
                    }
                } catch {
                    #if DEBUG
                    print("Error loading recipe from \(fileURL.lastPathComponent): \(error)")
                    #endif
                }
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
                    let mdURL = url.appendingPathComponent("\(recipe.id.uuidString).md")
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

        let fileURL = url.appendingPathComponent("\(recipe.id.uuidString).md")

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

            // Remove legacy JSON file if it exists
            let jsonURL = url.appendingPathComponent("\(recipe.id.uuidString).json")
            if fileManager.fileExists(atPath: jsonURL.path) {
                try? fileManager.removeItem(at: jsonURL)
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
        guard let url = iCloudURL else { return }

        let mdURL = url.appendingPathComponent("\(recipe.id.uuidString).md")
        let jsonURL = url.appendingPathComponent("\(recipe.id.uuidString).json")

        // Remove markdown file (current format)
        try? fileManager.removeItem(at: mdURL)
        // Remove legacy JSON file if it still exists
        try? fileManager.removeItem(at: jsonURL)

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
        guard let baseURL = baseURL else { return 0 }
        let cookbookDir = baseURL.appendingPathComponent(cookbook.id.uuidString)
        let recipesDir = cookbookDir.appendingPathComponent("Recipes")

        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: recipesDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ).filter { $0.pathExtension == "md" || $0.pathExtension == "json" }

            // Deduplicate by UUID stem (a recipe may exist as both .json and .md during migration)
            let uniqueIDs = Set(fileURLs.map { $0.deletingPathExtension().lastPathComponent })
            return uniqueIDs.count
        } catch {
            return 0
        }
    }

    func categoryCount(for cookbook: Cookbook) -> Int {
        guard let baseURL = baseURL else { return 0 }
        let cookbookDir = baseURL.appendingPathComponent(cookbook.id.uuidString)
        let categoriesFile = cookbookDir.appendingPathComponent("categories.json")

        guard fileManager.fileExists(atPath: categoriesFile.path),
              let data = try? Data(contentsOf: categoriesFile),
              let loadedCategories = try? JSONDecoder().decode([Category].self, from: data) else {
            return 0
        }

        return loadedCategories.count
    }
}
