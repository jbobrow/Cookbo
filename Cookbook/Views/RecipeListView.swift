import SwiftUI
import UniformTypeIdentifiers

struct RecipeListView: View {
    @EnvironmentObject var store: RecipeStore
    @State private var searchText = ""
    @State private var showingAddRecipe = false
    @State private var showingImportSheet = false
    @State private var showingImportCookbookSheet = false
    @State private var showingURLImport = false
    @State private var showingSettings = false
    @State private var showingCookbookSwitcher = false
    @State private var importAlert: ImportAlert?
    @State private var recipesToDelete: IndexSet?
    @State private var showingDeleteConfirmation = false
    @State private var isSearching = false
    @State private var showingWelcome = false
    @State private var selectedCollection: RecipeCollection = .all
    @State private var showingWeekReview = false
    @AppStorage("recipeViewMode") private var viewMode: RecipeViewMode = .grid
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    /// Persisted across launches; the animated source of truth is
    /// `collapsedCategoryIDs` below, because @AppStorage writes land outside
    /// the withAnimation transaction and the rows would jump.
    @AppStorage("collapsedCategoryIDs") private var collapsedCategoryIDsRaw = ""
    @State private var collapsedCategoryIDs: Set<String> = []
    #if os(macOS)
    @Environment(\.textSizeMultiplier) private var textSizeMultiplier
    #endif

    // Check if device is iPad or Mac (grid view enabled)
    private var isGridCapable: Bool {
        #if os(macOS)
        return true
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    /// Recipes in the selected collection, before the search field is applied.
    var collectionRecipes: [Recipe] {
        store.recipes(in: selectedCollection)
    }

    var filteredRecipes: [Recipe] {
        if searchText.isEmpty {
            return collectionRecipes
        }
        return collectionRecipes.filter { recipe in
            recipe.title.localizedCaseInsensitiveContains(searchText) ||
            recipe.allIngredients.contains { $0.text.localizedCaseInsensitiveContains(searchText) }
        }
    }

    /// Category grouping only applies to the All view; the smart collections
    /// and a single category are already one flat, sorted list.
    private var isGrouped: Bool {
        selectedCollection == .all
    }

    // MARK: - Collections

    /// Chips to offer: All, then whichever smart collections have something in
    /// them (a chip that filters to nothing is a dead end), then the categories.
    private var availableCollections: [RecipeCollection] {
        var collections: [RecipeCollection] = [.all]
        collections += RecipeCollection.smartCollections.filter { !store.recipes(in: $0).isEmpty }
        collections += store.categories.map { RecipeCollection.category($0.id) }
        return collections
    }

    private func title(for collection: RecipeCollection) -> String {
        if let fixed = collection.fixedTitle { return fixed }
        if case .category(let id) = collection {
            return store.categories.first(where: { $0.id == id })?.name ?? "Category"
        }
        return ""
    }

    private var collectionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableCollections) { collection in
                    CollectionChip(
                        title: title(for: collection),
                        icon: collection.icon,
                        tint: chipTint(for: collection),
                        isSelected: selectedCollection == collection
                    ) {
                        selectedCollection = collection
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func chipTint(for collection: RecipeCollection) -> Color {
        if case .category(let id) = collection,
           let category = store.categories.first(where: { $0.id == id }) {
            return category.color
        }
        return .accentColor
    }

    // MARK: - Just Viewed

    @ViewBuilder
    private var justViewedRow: some View {
        if let recipe = store.lastViewedRecipe {
            NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                JustViewedRow(recipe: recipe)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Category Collapsing

    private func isCollapsed(_ category: Category?) -> Bool {
        collapsedCategoryIDs.contains(key(for: category))
    }

    private func loadCollapsedCategories() {
        collapsedCategoryIDs = Set(collapsedCategoryIDsRaw.split(separator: ",").map(String.init))
    }

    private func toggleCollapsed(_ category: Category?) {
        let id = key(for: category)

        withAnimation(.easeInOut(duration: 0.28)) {
            if collapsedCategoryIDs.contains(id) {
                collapsedCategoryIDs.remove(id)
            } else {
                collapsedCategoryIDs.insert(id)
            }
        }

        collapsedCategoryIDsRaw = collapsedCategoryIDs.sorted().joined(separator: ",")
    }

    private func key(for category: Category?) -> String {
        category?.id.uuidString ?? "uncategorized"
    }

    var groupedRecipes: [(category: Category?, recipes: [Recipe])] {
        if !isGrouped || store.categories.isEmpty {
            return [(nil, filteredRecipes)]
        }

        var groups: [(Category?, [Recipe])] = []
        let categoryIDs = Set(store.categories.map { $0.id })

        // Group recipes by category
        for category in store.categories {
            let categoryRecipes = filteredRecipes.filter { $0.categoryID == category.id }
            if !categoryRecipes.isEmpty {
                groups.append((category, categoryRecipes))
            }
        }

        // Add uncategorized recipes (recipes with no category OR orphaned category references)
        let uncategorized = filteredRecipes.filter { recipe in
            recipe.categoryID == nil || !categoryIDs.contains(recipe.categoryID!)
        }
        if !uncategorized.isEmpty {
            groups.append((nil, uncategorized))
        }

        return groups
    }
    
    private var recipeList: some View {
        List {
            ForEach(Array(groupedRecipes.enumerated()), id: \.offset) { groupIndex, group in
                Section {
                    ForEach(isCollapsed(group.category) && isGrouped ? [] : group.recipes) { recipe in
                        NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                            RecipeRowView(recipe: recipe, showCategory: false)
                        }
                        .swipeActions(edge: .leading) {
                            // First action is also the full-swipe default
                            thisWeekButton(for: recipe)
                            Button(action: { shareRecipe(recipe) }) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            categoryMenuItems(for: recipe)
                            Divider()
                            thisWeekButton(for: recipe)
                            Button(action: { shareRecipe(recipe) }) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    .onDelete { offsets in
                        deleteRecipesInSection(at: offsets, in: groupIndex)
                    }
                } header: {
                    if isGrouped, group.category != nil || !store.categories.isEmpty {
                        CategorySectionHeader(
                            category: group.category,
                            count: group.recipes.count,
                            isCollapsed: isCollapsed(group.category)
                        ) {
                            toggleCollapsed(group.category)
                        }
                    }
                }
            }
        }
    }

    private var recipeGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                ForEach(Array(groupedRecipes.enumerated()), id: \.offset) { groupIndex, group in
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                            ForEach(isCollapsed(group.category) && isGrouped ? [] : group.recipes) { recipe in
                                NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                                    RecipeCardView(recipe: recipe, showCategory: false)
                                }
                                .buttonStyle(.plain)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                .contextMenu {
                                    categoryMenuItems(for: recipe)
                                    Divider()
                                    thisWeekButton(for: recipe)
                                    Button(action: { shareRecipe(recipe) }) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    Divider()
                                    Button(role: .destructive, action: {
                                        if let index = filteredRecipes.firstIndex(where: { $0.id == recipe.id }) {
                                            deleteRecipes(at: IndexSet([index]))
                                        }
                                    }) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    } header: {
                        if isGrouped, group.category != nil || !store.categories.isEmpty {
                            CategorySectionHeader(
                                category: group.category,
                                count: group.recipes.count,
                                isCollapsed: isCollapsed(group.category)
                            ) {
                                toggleCollapsed(group.category)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background)
                        }
                    }
                }
            }
            .padding(.top, 20)
        }
    }

    private var currentView: some View {
        Group {
            if store.recipes.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    justViewedRow
                    collectionBar
                    if filteredRecipes.isEmpty {
                        emptyCollectionState
                    } else if isGridCapable && viewMode == .grid {
                        recipeGrid
                    } else {
                        recipeList
                    }
                }
            }
        }
    }

    /// Shown when the cookbook has recipes but this collection or search has none.
    private var emptyCollectionState: some View {
        VStack {
            Spacer(minLength: 40)
            ContentUnavailableView {
                Label(emptyCollectionTitle, systemImage: selectedCollection.icon)
            } description: {
                Text(emptyCollectionMessage)
            }
            Spacer()
        }
    }

    private var emptyCollectionTitle: String {
        searchText.isEmpty ? "Nothing Here Yet" : "No Matches"
    }

    private var emptyCollectionMessage: String {
        if !searchText.isEmpty {
            return "No recipes in \(title(for: selectedCollection)) match '\(searchText)'."
        }
        switch selectedCollection {
        case .thisWeek:
            return "Add recipes to this week's plan from a recipe's menu."
        case .favorites:
            return "Recipes you rate \(RecipeCollectionRules.favoriteRating) stars or cook \(RecipeCollectionRules.favoriteCookCount) times show up here."
        case .recentlyAdded:
            return "Recipes you add or import will show up here."
        default:
            return "This category doesn't have any recipes yet."
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Recipes Yet", systemImage: "book.closed")
        } description: {
            Text("Add a recipe by hand, import one from a link, or start with a sample.")
        } actions: {
            VStack(spacing: 12) {
                Button("New Recipe") { showingAddRecipe = true }
                    .buttonStyle(.borderedProminent)
                Button("Add from URL") { showingURLImport = true }
                Button("Add Sample Recipe") { store.addSampleRecipe() }
            }
        }
    }

    #if os(macOS)
    private var macOSContent: some View {
        currentView
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search recipes")
            .navigationTitle("")
    }
    #endif

    #if os(iOS)
    private var iOSContent: some View {
        Group {
            if isGridCapable {
                if isSearching {
                    currentView
                        .searchable(text: $searchText, isPresented: $isSearching, prompt: "Search recipes")
                        .navigationTitle(store.cookbook.name)
                        .navigationBarTitleDisplayMode(.inline)
                } else {
                    currentView
                        .navigationTitle(store.cookbook.name)
                        .navigationBarTitleDisplayMode(.inline)
                }
            } else {
                currentView
                    .searchable(text: $searchText, prompt: "Search recipes")
                    .navigationTitle(store.cookbook.name)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
    #endif

    private var mainContent: some View {
        #if os(macOS)
        macOSContent
        #else
        iOSContent
        #endif
    }

    var body: some View {
        NavigationStack {
            if store.isICloudAvailable || store.useLocalStorage {
                mainContent
                    .toolbar {
                        toolbarContent
                    }
                    .background(
                        Button("", action: { showingAddRecipe = true })
                            .keyboardShortcut("n", modifiers: .command)
                            .hidden()
                    )
            } else {
                ICloudSetupView()
            }
        }
        .sheet(isPresented: $showingAddRecipe) {
            RecipeEditView(recipe: Recipe())
        }
        .sheet(isPresented: $showingURLImport) {
            ImportRecipeFromURLView(initialURL: store.pendingImportURL ?? "")
                .onDisappear {
                    store.pendingImportURL = nil
                }
        }
        .onChange(of: store.pendingImportURL) { _, newValue in
            if newValue != nil {
                showingURLImport = true
            }
        }
        .sheet(isPresented: $showingCookbookSwitcher) {
            CookbookSwitcherView()
        }
        .sheet(isPresented: $showingWelcome) {
            WelcomeView(onFinish: { hasSeenWelcome = true })
        }
        .onAppear {
            loadCollapsedCategories()
            showWelcomeIfNeeded()
            showWeekReviewIfDue()
        }
        .onChange(of: store.recipes.count) { _, _ in
            showWeekReviewIfDue()
            resetCollectionIfUnavailable()
        }
        .onChange(of: store.categories) { _, _ in resetCollectionIfUnavailable() }
        .alert("Plan for Next Week?", isPresented: $showingWeekReview) {
            Button("Keep for Next Week") { store.rollOverThisWeek() }
            Button("Clear It", role: .destructive) { store.clearThisWeek() }
            // Leaves the plan untouched, so the prompt returns on the next launch
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("This week's plan has \(store.recipes(in: .thisWeek).count) recipe\(store.recipes(in: .thisWeek).count == 1 ? "" : "s"). Clear it out, or keep it going for next week?")
        }
        .onChange(of: store.isICloudAvailable) { _, _ in showWelcomeIfNeeded() }
        .onChange(of: store.useLocalStorage) { _, _ in showWelcomeIfNeeded() }
        .onChange(of: store.shouldShowNewRecipe) { oldValue, newValue in
            if newValue {
                showingAddRecipe = true
                store.shouldShowNewRecipe = false
            }
        }
        .onChange(of: store.shouldShowURLImport) { _, newValue in
            if newValue {
                showingURLImport = true
                store.shouldShowURLImport = false
            }
        }
        .fileImporter(
            isPresented: $showingImportSheet,
            allowedContentTypes: [.json, UTType(filenameExtension: "cookbook.json") ?? .json],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result: result)
        }
        .fileImporter(
            isPresented: $showingImportCookbookSheet,
            allowedContentTypes: [UTType(filenameExtension: "cookbook") ?? .json],
            allowsMultipleSelection: false
        ) { result in
            handleCookbookImport(result: result)
        }
        .alert(item: $importAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("Delete Recipe\(deleteCount > 1 ? "s" : "")", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                recipesToDelete = nil
            }
            Button("Delete", role: .destructive, action: confirmDelete)
        } message: {
            Text(deleteMessage)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .navigation) {
            Button(action: { showingCookbookSwitcher = true }) {
                Image(systemName: "books.vertical")
            }
        }
        ToolbarItem(placement: .navigation) {
            CookbookTitleView(cookbookName: store.cookbook.name, showingSettings: $showingSettings)
                .padding(.trailing, 8)
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("View Mode", selection: $viewMode) {
                ForEach(RecipeViewMode.allCases) { mode in
                    Image(systemName: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Switch between grid and list view")
        }
        #else
        ToolbarItem(placement: .topBarLeading) {
            Button(action: { showingCookbookSwitcher = true }) {
                Image(systemName: "books.vertical")
            }
        }
        #endif

        #if os(iOS)
        ToolbarItem(placement: .principal) {
            Button(action: { showingSettings = true }) {
                Text(store.cookbook.name)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .popover(isPresented: $showingSettings) {
                SettingsView()
                    .presentationCompactAdaptation(.popover)
                    .frame(width: 350)
            }
        }
        #endif

        #if os(iOS)
        if isGridCapable && !isSearching {
            ToolbarItem(placement: .topBarTrailing) {
                HStack (spacing: 12) {
                    Menu {
                        Button(action: { showingAddRecipe = true }) {
                            Label("New Recipe", systemImage: "plus")
                        }
                        Button(action: { showingURLImport = true }) {
                            Label("Add from URL", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.button)
                
                    Picker("View Mode", selection: $viewMode) {
                        ForEach(RecipeViewMode.allCases) { mode in
                            Image(systemName: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: CGFloat(RecipeViewMode.allCases.count * 48)) // icon-hugging width
                    .help("Switch between grid and list view")
                
                    Button(action: { isSearching.toggle() }) {
                        Label("Search", systemImage: "magnifyingglass")
                            .labelStyle(.iconOnly)
                    }
                }
                .fixedSize()
            }
        }

        if !isGridCapable {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button(action: { showingAddRecipe = true }) {
                        Label("New Recipe", systemImage: "plus")
                    }
                    Button(action: { showingURLImport = true }) {
                        Label("Add from URL", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        #else
        ToolbarItem(placement: .automatic) {
            Menu {
                Button(action: { showingAddRecipe = true }) {
                    Label("New Recipe", systemImage: "plus")
                }
                Button(action: { showingURLImport = true }) {
                    Label("Add from URL", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "plus")
            }
        }
        #endif
    }

    /// Shows onboarding once, on the first launch of an empty cookbook, and
    /// seeds the sample recipe so no one starts out staring at an empty shelf.
    /// Skipped for anyone who already has recipes, and until storage is ready
    /// (the iCloud setup screen comes first).
    private func showWelcomeIfNeeded() {
        guard !hasSeenWelcome else { return }
        guard store.isICloudAvailable || store.useLocalStorage else { return }

        // Checks the folder, not store.recipes, which can still be loading at
        // launch; an empty list then would seed a second sample recipe
        if store.recipes.isEmpty && !store.hasRecipeFiles {
            store.addSampleRecipe()
            showingWelcome = true
        } else {
            // An existing cookbook, so there's nothing to introduce
            hasSeenWelcome = true
        }
    }

    private func showWeekReviewIfDue() {
        guard store.isWeekPlanReviewDue else { return }
        showingWeekReview = true
    }

    /// Falls back to All if the selected chip disappears — its category was
    /// deleted, or its smart collection emptied out.
    private func resetCollectionIfUnavailable() {
        guard selectedCollection != .all else { return }
        if !availableCollections.contains(selectedCollection) {
            selectedCollection = .all
        }
    }

    private var deleteCount: Int {
        recipesToDelete?.count ?? 0
    }

    private var deleteMessage: String {
        guard let offsets = recipesToDelete else { return "" }

        // Bounds-checked: body can be recomputed after the recipes are gone but
        // before the alert finishes dismissing
        if offsets.count == 1, let index = offsets.first, filteredRecipes.indices.contains(index) {
            let recipe = filteredRecipes[index]
            return "Are you sure you want to delete '\(recipe.title)'? This action cannot be undone."
        } else {
            return "Are you sure you want to delete \(offsets.count) recipes? This action cannot be undone."
        }
    }
    
    /// Toggles a recipe in and out of the This Week plan. Used by both the
    /// leading swipe and the context menus.
    @ViewBuilder
    private func thisWeekButton(for recipe: Recipe) -> some View {
        Button {
            store.setInThisWeek(recipe, !recipe.isInThisWeek)
        } label: {
            if recipe.isInThisWeek {
                Label("Remove from Week", systemImage: "calendar.badge.minus")
            } else {
                Label("This Week", systemImage: "calendar.badge.plus")
            }
        }
        .tint(recipe.isInThisWeek ? .orange : .green)
    }

    @ViewBuilder
    private func categoryMenuItems(for recipe: Recipe) -> some View {
        if !store.categories.isEmpty {
            if recipe.categoryID != nil {
                Button(action: { assignCategory(nil, to: recipe) }) {
                    Label("Remove from Category", systemImage: "xmark.circle")
                }
            }
            Menu("Move to Category") {
                ForEach(store.categories) { category in
                    Button(action: { assignCategory(category, to: recipe) }) {
                        if recipe.categoryID == category.id {
                            Label(category.name, systemImage: "checkmark")
                        } else {
                            Text(category.name)
                        }
                    }
                }
            }
        }
    }

    private func assignCategory(_ category: Category?, to recipe: Recipe) {
        var updated = recipe
        updated.categoryID = category?.id
        store.saveRecipe(updated)
    }

    private func deleteRecipesInSection(at offsets: IndexSet, in sectionIndex: Int) {
        let group = groupedRecipes[sectionIndex]
        let recipesToDeleteList = offsets.map { group.recipes[$0] }

        // Show confirmation with recipe names
        recipesToDelete = IndexSet(recipesToDeleteList.compactMap { recipe in
            filteredRecipes.firstIndex(where: { $0.id == recipe.id })
        })
        showingDeleteConfirmation = true
    }

    private func deleteRecipes(at offsets: IndexSet) {
        recipesToDelete = offsets
        showingDeleteConfirmation = true
    }

    private func confirmDelete() {
        guard let offsets = recipesToDelete else { return }

        // Resolve the recipes before deleting any of them: each delete shifts
        // the indices that the remaining offsets refer to
        let targets = offsets.compactMap { index in
            filteredRecipes.indices.contains(index) ? filteredRecipes[index] : nil
        }

        recipesToDelete = nil
        targets.forEach { store.deleteRecipe($0) }
    }
    
    private func shareRecipe(_ recipe: Recipe) {
        // Create temporary Markdown file for sharing
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(recipe.title.replacingOccurrences(of: " ", with: "_")).md"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            let markdown = RecipeMarkdownSerializer.serialize(recipe)
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Present share sheet
            #if os(iOS)
            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)

            // Configure popover presentation for iPad
            if UIDevice.current.userInterfaceIdiom == .pad {
                if let popover = activityVC.popoverPresentationController {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first {
                        popover.sourceView = window
                        popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }
                }
            }

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                var topVC = rootVC
                while let presentedVC = topVC.presentedViewController {
                    topVC = presentedVC
                }
                topVC.present(activityVC, animated: true)
            }
            #elseif os(macOS)
            let picker = NSSharingServicePicker(items: [fileURL])
            if let view = NSApplication.shared.keyWindow?.contentView {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
            #endif
        } catch {
            #if DEBUG
            print("Error sharing recipe: \(error)")
            #endif
        }
    }
    
    private func handleCookbookImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            let importResult = store.importCookbook(from: url)

            switch importResult {
            case .success(let cookbook):
                importAlert = ImportAlert(
                    title: "Import Successful",
                    message: "Successfully imported '\(cookbook.name)' with all its recipes and categories!"
                )
            case .failure(let error):
                importAlert = ImportAlert(
                    title: "Import Failed",
                    message: "Could not import cookbook: \(error.localizedDescription)"
                )
            }

        case .failure(let error):
            #if DEBUG
            print("Error selecting file: \(error)")
            #endif
            importAlert = ImportAlert(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var successCount = 0
            var errorCount = 0
            
            for url in urls {
                do {
                    // Ensure we have access to the file
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    
                    let data = try Data(contentsOf: url)
                    var recipe = try JSONDecoder().decode(Recipe.self, from: data)
                    
                    // Generate new ID to avoid conflicts
                    recipe.id = UUID()
                    recipe.dateCreated = Date()
                    
                    // Reset checked ingredients for fresh cooking
                    recipe.ingredientSections = recipe.ingredientSections.map { section in
                        var newSection = section
                        newSection.ingredients = section.ingredients.map { ingredient in
                            var newIngredient = ingredient
                            newIngredient.isChecked = false
                            return newIngredient
                        }
                        return newSection
                    }
                    
                    store.saveRecipe(recipe)
                    successCount += 1
                } catch {
                    #if DEBUG
                    print("Error importing recipe from \(url.lastPathComponent): \(error)")
                    #endif
                    errorCount += 1
                }
            }
            
            // Show result
            if successCount > 0 {
                let message = errorCount > 0
                    ? "Imported \(successCount) recipe\(successCount == 1 ? "" : "s"). Failed to import \(errorCount)."
                    : "Successfully imported \(successCount) recipe\(successCount == 1 ? "" : "s")!"
                
                importAlert = ImportAlert(
                    title: "Import Complete",
                    message: message
                )
            } else if errorCount > 0 {
                importAlert = ImportAlert(
                    title: "Import Failed",
                    message: "Could not import any recipes. Please check the file format."
                )
            }
            
        case .failure(let error):
            #if DEBUG
            print("Error selecting files: \(error)")
            #endif
            importAlert = ImportAlert(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }
}

struct RecipeRowView: View {
    let recipe: Recipe
    var showCategory: Bool = true
    @EnvironmentObject var store: RecipeStore
    #if os(macOS)
    @Environment(\.textSizeMultiplier) private var textSizeMultiplier
    #endif

    var body: some View {
        HStack(spacing: 12) {
            // Recipe image thumbnail
            if let imageData = recipe.imageData,
               let image = createPlatformImage(from: imageData) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                #if os(macOS)
                Text(recipe.title)
                    .font(.system(size: 17 * textSizeMultiplier, weight: .semibold))
                #else
                Text(recipe.title)
                    .font(.headline)
                #endif

                HStack(spacing: 8) {
                    if showCategory, let category = store.category(for: recipe) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(category.color)
                                .frame(width: 8, height: 8)
                            Text(category.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if recipe.rating > 0 {
                        HStack(spacing: 2) {
                            ForEach(0..<recipe.rating, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                        }
                    }

                    if recipe.prepDuration > 0 || recipe.cookDuration > 0 {
                        Text(formatTotalTime(prep: recipe.prepDuration, cook: recipe.cookDuration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !recipe.datesCooked.isEmpty {
                    Text("Cooked \(recipe.datesCooked.count) time\(recipe.datesCooked.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func createPlatformImage(from data: Data) -> Image? {
        #if os(iOS)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #elseif os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #endif
    }

    private func formatTotalTime(prep: TimeInterval, cook: TimeInterval) -> String {
        let total = Int((prep + cook) / 60)
        if total < 60 {
            return "\(total) min"
        } else {
            let hours = total / 60
            let minutes = total % 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
    }
}

struct RecipeCardView: View {
    let recipe: Recipe
    var showCategory: Bool = true
    @EnvironmentObject var store: RecipeStore
    #if os(macOS)
    @Environment(\.textSizeMultiplier) private var textSizeMultiplier
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Recipe image
            if let imageData = recipe.imageData,
               let image = createPlatformImage(from: imageData) {
                Color.clear
                    .frame(height: 160)
                    .overlay(
                        image
                            .resizable()
                            .scaledToFill()
                    )
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 160)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                #if os(macOS)
                Text(recipe.title)
                    .font(.system(size: 17 * textSizeMultiplier, weight: .semibold))
                    .lineLimit(2)
                #else
                Text(recipe.title)
                    .font(.headline)
                    .lineLimit(2)
                #endif

                if showCategory, let category = store.category(for: recipe) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(category.color)
                            .frame(width: 8, height: 8)
                        Text(category.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    if recipe.rating > 0 {
                        HStack(spacing: 2) {
                            ForEach(0..<recipe.rating, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                        }
                    }

                    if recipe.prepDuration > 0 || recipe.cookDuration > 0 {
                        Text(formatTotalTime(prep: recipe.prepDuration, cook: recipe.cookDuration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !recipe.datesCooked.isEmpty {
                    Text("Cooked \(recipe.datesCooked.count) time\(recipe.datesCooked.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
        }
        #if os(macOS)
        .background(Color(.controlBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private func createPlatformImage(from data: Data) -> Image? {
        #if os(iOS)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #elseif os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #endif
    }

    private func formatTotalTime(prep: TimeInterval, cook: TimeInterval) -> String {
        let total = Int((prep + cook) / 60)
        if total < 60 {
            return "\(total) min"
        } else {
            let hours = total / 60
            let minutes = total % 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
    }
}

/// A single filter chip in the collection bar.
struct CollectionChip: View {
    let title: String
    let icon: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? tint : Color.gray.opacity(0.15))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A category section header that folds its recipes away.
struct CategorySectionHeader: View {
    let category: Category?
    let count: Int
    let isCollapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))

                if let category = category {
                    Circle()
                        .fill(category.color)
                        .frame(width: 12, height: 12)
                    Text(category.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                } else {
                    Text("Uncategorized")
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Spacer()

                Text("\(count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category?.name ?? "Uncategorized")
        .accessibilityHint(isCollapsed ? "Expand section" : "Collapse section")
    }
}

/// The slim "pick up where you left off" row above the list.
struct JustViewedRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text("Just Viewed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(recipe.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            Spacer()

            // Matches the disclosure chevron the list rows get from NavigationLink
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let imageData = recipe.imageData, let image = platformImage(from: imageData) {
            image
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.25))
                .frame(width: 38, height: 38)
                .overlay(Image(systemName: "photo").font(.caption).foregroundStyle(.secondary))
        }
    }

    private func platformImage(from data: Data) -> Image? {
        #if os(iOS)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #elseif os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #endif
    }
}

// Helper struct for import alerts
struct ImportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#if os(macOS)
struct CookbookTitleView: View {
    let cookbookName: String
    @Binding var showingSettings: Bool
    @State private var isHovered = false
    @EnvironmentObject var store: RecipeStore

    var body: some View {
        Text(cookbookName)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundStyle(isHovered ? Color.accentColor : Color.primary)
            .contentShape(Rectangle())
            .onTapGesture {
                showingSettings = true
            }
            .popover(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(store)
            }
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
#endif

#Preview {
    RecipeListView()
        .environmentObject(RecipeStore())
}
