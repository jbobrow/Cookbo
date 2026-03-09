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
    @AppStorage("recipeViewMode") private var viewMode: RecipeViewMode = .grid
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

    var filteredRecipes: [Recipe] {
        if searchText.isEmpty {
            return store.recipes
        }
        return store.recipes.filter { recipe in
            recipe.title.localizedCaseInsensitiveContains(searchText) ||
            recipe.allIngredients.contains { $0.text.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var groupedRecipes: [(category: Category?, recipes: [Recipe])] {
        if store.categories.isEmpty {
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
                    ForEach(group.recipes) { recipe in
                        NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                            RecipeRowView(recipe: recipe, showCategory: false)
                        }
                        .swipeActions(edge: .leading) {
                            Button(action: { shareRecipe(recipe) }) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            categoryMenuItems(for: recipe)
                            Divider()
                            Button(action: { shareRecipe(recipe) }) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    .onDelete { offsets in
                        deleteRecipesInSection(at: offsets, in: groupIndex)
                    }
                } header: {
                    if let category = group.category {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(category.color)
                                .frame(width: 12, height: 12)
                            Text(category.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                    } else if !store.categories.isEmpty {
                        Text("Uncategorized")
                            .font(.headline)
                            .foregroundColor(.primary)
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
                            ForEach(group.recipes) { recipe in
                                NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                                    RecipeCardView(recipe: recipe, showCategory: false)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    categoryMenuItems(for: recipe)
                                    Divider()
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
                        if let category = group.category {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(category.color)
                                    .frame(width: 12, height: 12)
                                Text(category.name)
                                    .font(.headline)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background)
                        } else if !store.categories.isEmpty {
                            Text("Uncategorized")
                                .font(.headline)
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
            if isGridCapable && viewMode == .grid {
                recipeGrid
            } else {
                recipeList
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
        .onChange(of: store.shouldShowNewRecipe) { oldValue, newValue in
            if newValue {
                showingAddRecipe = true
                store.shouldShowNewRecipe = false
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

    private var deleteCount: Int {
        recipesToDelete?.count ?? 0
    }

    private var deleteMessage: String {
        guard let offsets = recipesToDelete else { return "" }

        if offsets.count == 1, let index = offsets.first {
            let recipe = filteredRecipes[index]
            return "Are you sure you want to delete '\(recipe.title)'? This action cannot be undone."
        } else {
            return "Are you sure you want to delete \(offsets.count) recipes? This action cannot be undone."
        }
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

        offsets.forEach { index in
            let recipe = filteredRecipes[index]
            store.deleteRecipe(recipe)
        }

        recipesToDelete = nil
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
            print("Error sharing recipe: \(error)")
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
            print("Error selecting file: \(error)")
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
                    print("Error importing recipe from \(url.lastPathComponent): \(error)")
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
            print("Error selecting files: \(error)")
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
