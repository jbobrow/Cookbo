import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

struct ShareExtensionView: View {
    let urlString: String
    let onSave: (RecipeParser.ParsedRecipe) -> Void
    let onCancel: () -> Void

    @State private var viewState: ViewState = .loading
    @State private var parsedRecipe: RecipeParser.ParsedRecipe?
    @State private var imageData: Data?

    private enum ViewState {
        case loading
        case preview
        case error(String)
        case saved
    }

    var body: some View {
        NavigationView {
            content
                .navigationTitle("Import Recipe")
                #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onCancel() }
                    }
                    // The same as Save to Cookbo, within reach without
                    // scrolling past the recipe
                    if case .preview = viewState, parsedRecipe != nil {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save", action: save)
                        }
                    }
                }
        }
        .task {
            await fetchRecipe()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewState {
        case .loading:
            loadingView
        case .preview:
            if let recipe = parsedRecipe {
                recipePreview(recipe)
            }
        case .error(let message):
            errorView(message)
        case .saved:
            savedView
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Fetching recipe...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Recipe Preview

    private func recipePreview(_ recipe: RecipeParser.ParsedRecipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Header with image and title
                headerSection(recipe)

                // Time info
                if recipe.prepDuration > 0 || recipe.cookDuration > 0 {
                    timeSection(recipe)
                }

                // Ingredients
                if !recipe.ingredients.isEmpty {
                    ingredientsSection(recipe)
                }

                // Directions
                if !recipe.directions.isEmpty {
                    directionsSection(recipe)
                }

                // Notes last, as on the recipe page, so the ingredients and
                // steps it found come first
                if !recipe.notes.isEmpty {
                    notesSection(recipe)
                }

                // Save button
                saveButton

                // Source link
                Text(recipe.sourceURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headerSection(_ recipe: RecipeParser.ParsedRecipe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let imageData, let platformImage = PlatformImage(data: imageData) {
                #if os(macOS)
                Image(nsImage: platformImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                #else
                Image(uiImage: platformImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                #endif
            }

            Text(recipe.title)
                .font(.title2.bold())
                .padding(.horizontal)
        }
        .padding(.top, 8)
    }

    private func timeSection(_ recipe: RecipeParser.ParsedRecipe) -> some View {
        HStack(spacing: 16) {
            if let prep = RecipeParser.formatDuration(recipe.prepDuration) {
                Label(prep, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("prep")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if recipe.prepDuration > 0 && recipe.cookDuration > 0 {
                Divider().frame(height: 16)
            }
            if let cook = RecipeParser.formatDuration(recipe.cookDuration) {
                Label(cook, systemImage: "flame")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("cook")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
    }

    private func notesSection(_ recipe: RecipeParser.ParsedRecipe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)

            Text(recipe.notes)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal)
    }

    private func ingredientsSection(_ recipe: RecipeParser.ParsedRecipe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ingredients")
                .font(.headline)

            ForEach(Array(recipe.ingredients.prefix(8).enumerated()), id: \.offset) { _, ingredient in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(ingredient)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if recipe.ingredients.count > 8 {
                Text("+ \(recipe.ingredients.count - 8) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private func directionsSection(_ recipe: RecipeParser.ParsedRecipe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Directions")
                .font(.headline)

            ForEach(Array(recipe.directions.prefix(4).enumerated()), id: \.offset) { index, direction in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(direction)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if recipe.directions.count > 4 {
                Text("+ \(recipe.directions.count - 4) more steps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private var saveButton: some View {
        Button(action: save) {
            Label("Save to Cookbo", systemImage: "book.closed")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 40/255, green: 156/255, blue: 255/255))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func save() {
        guard let recipe = parsedRecipe else { return }
        onSave(recipe)
        withAnimation {
            viewState = .saved
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Couldn't Load Recipe")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Done") {
                onCancel()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Saved

    private var savedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Saved to Cookbo!")
                .font(.headline)
            Text("Open the Cookbo app to see your recipe.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                onCancel()
            }
        }
    }

    // MARK: - Fetch

    private func fetchRecipe() async {
        do {
            let recipe = try await RecipeParser.fetchAndParse(urlString: urlString)
            parsedRecipe = recipe
            viewState = .preview

            // Load image in background
            if let imageURL = recipe.imageURL, let url = URL(string: imageURL) {
                if let (data, _) = try? await URLSession.shared.data(from: url) {
                    imageData = data
                }
            }
        } catch {
            viewState = .error(error.localizedDescription)
        }
    }
}
