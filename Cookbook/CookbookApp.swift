//
//  CookbookApp.swift
//  Cookbook
//
//  Created by Jonathan Bobrow on 1/4/26.
//

import SwiftUI

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
#endif

@main
struct CookbookApp: App {
    @StateObject private var recipeStore = RecipeStore()
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("textSizeMultiplier") private var textSizeMultiplier: Double = 1.0
    #endif

    private let appGroupID = "group.com.jonbobrow.Cookbook"
    private let pendingURLKey = "pendingImportURL"
    private let pendingRecipesFolder = "PendingRecipes"

    var body: some Scene {
        WindowGroup {
            RecipeListView()
                .environmentObject(recipeStore)
                #if os(macOS)
                .preferredColorScheme(appearanceMode.colorScheme)
                .environment(\.textSizeMultiplier, textSizeMultiplier)
                #endif
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                checkForSharedURL()
            }
        }
        .commands {
            #if os(macOS)
            CommandGroup(replacing: .newItem) {
                Button("New Recipe") {
                    recipeStore.shouldShowNewRecipe = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Recipe from URL") {
                    recipeStore.shouldShowURLImport = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandMenu("View") {
                Button("Increase Text Size") {
                    textSizeMultiplier = min(textSizeMultiplier + 0.1, 2.0)
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Decrease Text Size") {
                    textSizeMultiplier = max(textSizeMultiplier - 0.1, 0.5)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Text Size") {
                    textSizeMultiplier = 1.0
                }
                .keyboardShortcut("0", modifiers: .command)
            }
            #endif
        }

        #if os(macOS)
        Settings {
            AppPreferencesView()
        }
        #endif
    }

    private func handleIncomingURL(_ url: URL) {
        // Handle cookbook://import?url=<encoded-url>
        guard url.scheme == "cookbook",
              url.host == "import",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let urlParam = components.queryItems?.first(where: { $0.name == "url" })?.value else {
            return
        }
        recipeStore.pendingImportURL = urlParam
    }

    private func checkForSharedURL() {
        // Import all pending recipes saved by the Share Extension
        importPendingRecipes()

        // Fall back to URL-only import (e.g. from cookbook:// scheme)
        if let sharedDefaults = UserDefaults(suiteName: appGroupID),
           let urlString = sharedDefaults.string(forKey: pendingURLKey) {
            sharedDefaults.removeObject(forKey: pendingURLKey)
            sharedDefaults.synchronize()
            recipeStore.pendingImportURL = urlString
        }
    }

    private func importPendingRecipes() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else { return }

        let folder = containerURL.appendingPathComponent(pendingRecipesFolder)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ).filter({ $0.pathExtension == "json" }) else { return }

        let decoder = JSONDecoder()

        for fileURL in files {
            guard let data = try? Data(contentsOf: fileURL),
                  let parsed = try? decoder.decode(RecipeParserCore.ParsedRecipe.self, from: data) else {
                try? FileManager.default.removeItem(at: fileURL)
                continue
            }

            // Remove the file immediately so we don't re-import
            try? FileManager.default.removeItem(at: fileURL)

            let sections = parsed.ingredientGroups.map { group in
                IngredientSection(name: group.name, ingredients: group.ingredients.map { Ingredient(text: $0) })
            }
            var recipe = Recipe(
                title: parsed.title,
                ingredientSections: sections,
                directions: parsed.directions.enumerated().map { Direction(text: $1, order: $0 + 1) },
                sourceURL: parsed.sourceURL,
                prepDuration: parsed.prepDuration,
                cookDuration: parsed.cookDuration,
                notes: parsed.notes
            )

            let savedID = recipe.id
            recipeStore.saveRecipe(recipe)

            // Download image in background; look up by ID so we don't overwrite user edits
            if let imageURL = parsed.imageURL {
                Task.detached {
                    if let url = URL(string: imageURL),
                       let (imageData, _) = try? await URLSession.shared.data(from: url) {
                        await MainActor.run {
                            if var latest = recipeStore.recipes.first(where: { $0.id == savedID }) {
                                latest.imageData = imageData
                                recipeStore.saveRecipe(latest)
                            }
                        }
                    }
                }
            }
        }
    }
}

enum RecipeViewMode: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case list = "List"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .grid:
            return "square.grid.2x2"
        case .list:
            return "list.bullet"
        }
    }
}

#if os(macOS)
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

struct AppPreferencesView: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("textSizeMultiplier") private var textSizeMultiplier: Double = 1.0

    var body: some View {
        TabView {
            Form {
                Section {
                    Picker("Appearance", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Theme")
                } footer: {
                    Text("Choose how the app should appear.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Text Size")
                            Spacer()
                            Text("\(Int(textSizeMultiplier * 100))%")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $textSizeMultiplier, in: 0.5...2.0, step: 0.1)
                        HStack {
                            Text("Small")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Large")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("Adjust the text size throughout the app. You can also use ⌘+ and ⌘- to adjust text size.")
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            .frame(width: 450)
        }
        .padding(20)
    }
}

// Environment key for text size multiplier
private struct TextSizeMultiplierKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var textSizeMultiplier: Double {
        get { self[TextSizeMultiplierKey.self] }
        set { self[TextSizeMultiplierKey.self] = newValue }
    }
}

// Font extension to apply text size multiplier
extension Font {
    func scaledFont(multiplier: Double) -> Font {
        // This is a helper that can be used to scale fonts
        return self
    }
}

// View extension to easily apply scaled fonts
extension View {
    func scaledFont(_ font: Font, multiplier: Double) -> some View {
        let scaledSize: CGFloat
        switch font {
        case .largeTitle:
            scaledSize = 34 * multiplier
        case .title:
            scaledSize = 28 * multiplier
        case .title2:
            scaledSize = 22 * multiplier
        case .title3:
            scaledSize = 20 * multiplier
        case .headline:
            scaledSize = 17 * multiplier
        case .body:
            scaledSize = 17 * multiplier
        case .callout:
            scaledSize = 16 * multiplier
        case .subheadline:
            scaledSize = 15 * multiplier
        case .footnote:
            scaledSize = 13 * multiplier
        case .caption:
            scaledSize = 12 * multiplier
        case .caption2:
            scaledSize = 11 * multiplier
        default:
            scaledSize = 17 * multiplier
        }
        return self.font(.system(size: scaledSize))
    }
}
#endif
