import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(iOS)
/// A UITextField wrapper that renders the placeholder in tertiary grey,
/// bypassing SwiftUI Form's tint color which otherwise colours it blue.
struct URLTextField: UIViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.attributedPlaceholder = NSAttributedString(
            string: "https://example.com/recipe",
            attributes: [.foregroundColor: UIColor.tertiaryLabel]
        )
        field.textContentType = .URL
        field.keyboardType = .webSearch
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .go
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text { uiView.text = text }
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: URLTextField
        init(_ parent: URLTextField) { self.parent = parent }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            parent.onSubmit()
            return true
        }
    }
}
#endif

struct ImportRecipeFromURLView: View {
    @EnvironmentObject var store: RecipeStore
    @Environment(\.dismiss) private var dismiss

    @State private var urlString: String
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var parsedRecipe: RecipeURLImporter.ParsedRecipe?
    @State private var previewImageData: Data?
    @State private var showingPDFPicker = false
    private let initialPDF: URL?

    /// `initialPDF` is a file already picked, from Add from PDF.
    init(initialURL: String = "", initialPDF: URL? = nil) {
        _urlString = State(initialValue: initialURL)
        self.initialPDF = initialPDF
    }

    var body: some View {
        NavigationStack {
            Form {
                urlInputSection
                pdfSection
                if let error = errorMessage {
                    errorSection(error)
                }
                if let parsed = parsedRecipe {
                    previewSection(parsed)
                    ingredientsPreview(parsed)
                    directionsPreview(parsed)
                    #if os(iOS)
                    saveSection
                    #endif
                }
            }
            #if os(macOS)
            // The Mac draws the same sections as grouped boxes, as Settings does
            .formStyle(.grouped)
            .frame(minWidth: 520, idealWidth: 560, minHeight: 380, idealHeight: 520)
            #endif
            .navigationTitle("Import Recipe")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                #if os(macOS)
                // A Mac sheet keeps its confirm button beside Cancel, not below the fold
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Recipe", action: saveRecipe)
                        .disabled(parsedRecipe == nil)
                }
                #endif
            }
            .onAppear {
                if !urlString.isEmpty && parsedRecipe == nil {
                    fetchRecipe()
                } else if let initialPDF, parsedRecipe == nil {
                    importPDF(.success(initialPDF))
                }
            }
            .fileImporter(isPresented: $showingPDFPicker, allowedContentTypes: [.pdf]) { result in
                importPDF(result)
            }
        }
    }

    // MARK: - Sections

    private var urlInputSection: some View {
        Section {
            #if os(macOS)
            TextField("Recipe URL", text: $urlString, prompt: Text("https://example.com/recipe"))
                .labelsHidden()
                .onSubmit(fetchRecipe)
            #else
            URLTextField(text: $urlString, onSubmit: fetchRecipe)
            #endif
            fetchButton
        } header: {
            Text("Recipe URL")
        } footer: {
            Text("Paste a URL from a recipe website to automatically import the ingredients and steps.")
        }
    }

    private var pdfSection: some View {
        Section {
            pdfButton
        } header: {
            Text("PDF")
        } footer: {
            Text("A recipe card, a handout, or a page saved as a PDF.")
        }
    }

    private var pdfButton: some View {
        Button(action: { showingPDFPicker = true }) {
            Label("Choose a PDF", systemImage: "doc.text")
        }
        .disabled(isLoading)
    }

    private var fetchButton: some View {
        Button(action: fetchRecipe) {
            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Fetching recipe...")
                }
            } else {
                Label("Fetch Recipe", systemImage: "arrow.down.circle")
            }
        }
        .disabled(urlString.isEmpty || isLoading)
    }

    private func errorSection(_ error: String) -> some View {
        Section {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundColor(.red)
        }
    }

    private func previewSection(_ parsed: RecipeURLImporter.ParsedRecipe) -> some View {
        Section("Preview") {
            if let image = previewImage {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .listRowInsets(EdgeInsets())
            }
            LabeledContent("Title", value: parsed.title)
            LabeledContent("Ingredients", value: "\(parsed.ingredients.count)")
            LabeledContent("Steps", value: "\(parsed.directions.count)")
            if parsed.prepDuration > 0 {
                LabeledContent("Prep Time", value: formatDuration(parsed.prepDuration))
            }
            if parsed.cookDuration > 0 {
                LabeledContent("Cook Time", value: formatDuration(parsed.cookDuration))
            }
        }
    }

    private var previewImage: Image? {
        guard let previewImageData else { return nil }
        #if os(macOS)
        return NSImage(data: previewImageData).map(Image.init(nsImage:))
        #else
        return UIImage(data: previewImageData).map(Image.init(uiImage:))
        #endif
    }

    @ViewBuilder
    private func ingredientsPreview(_ parsed: RecipeURLImporter.ParsedRecipe) -> some View {
        if !parsed.ingredients.isEmpty {
            let hasGroupNames = parsed.ingredientGroups.contains { !$0.name.isEmpty }
            Section("Ingredients") {
                ForEach(Array(parsed.ingredientGroups.enumerated()), id: \.offset) { _, group in
                    if hasGroupNames && !group.name.isEmpty {
                        Text(group.name)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    ForEach(group.ingredients, id: \.self) { ingredient in
                        Text(ingredient)
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func directionsPreview(_ parsed: RecipeURLImporter.ParsedRecipe) -> some View {
        if !parsed.directions.isEmpty {
            Section("Directions") {
                ForEach(Array(parsed.directions.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .foregroundColor(.secondary)
                        Text(step)
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var saveSection: some View {
        Section {
            Button(action: saveRecipe) {
                Label("Save Recipe", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .font(.headline)
        }
    }

    // MARK: - Actions

    private func fetchRecipe() {
        guard !urlString.isEmpty else { return }

        // Add https:// if no scheme is present
        if !urlString.contains("://") {
            urlString = "https://" + urlString
        }

        isLoading = true
        errorMessage = nil
        parsedRecipe = nil
        previewImageData = nil

        Task {
            do {
                let parsed = try await RecipeURLImporter.importRecipe(from: urlString)
                parsedRecipe = parsed
                isLoading = false

                // Load preview image in background
                if let imageURL = parsed.imageURL {
                    if let imageData = await RecipeURLImporter.downloadImage(from: imageURL) {
                        previewImageData = imageData
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func importPDF(_ result: Result<URL, Error>) {
        errorMessage = nil
        parsedRecipe = nil
        previewImageData = nil
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            parsedRecipe = try RecipePDFReader.importRecipe(from: data, fileName: url.lastPathComponent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveRecipe() {
        guard let parsed = parsedRecipe else { return }

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

        // Use already-downloaded preview image if available, otherwise fetch in background
        if let previewImageData {
            recipe.imageData = previewImageData
        }

        let savedID = recipe.id
        store.saveRecipe(recipe)

        if previewImageData == nil, let imageURL = parsed.imageURL {
            Task.detached {
                if let imageData = await RecipeURLImporter.downloadImage(from: imageURL) {
                    await MainActor.run {
                        if var latest = store.recipes.first(where: { $0.id == savedID }) {
                            latest.imageData = imageData
                            store.saveRecipe(latest)
                        }
                    }
                }
            }
        }

        // Asks after a pause, once the sheet has gone
        ReviewPrompter.shared.recordSignificantEvent(promptIfAppropriate: true)
        dismiss()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        if totalMinutes < 60 {
            return "\(totalMinutes) min"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }
}

#Preview {
    ImportRecipeFromURLView()
        .environmentObject(RecipeStore())
}
