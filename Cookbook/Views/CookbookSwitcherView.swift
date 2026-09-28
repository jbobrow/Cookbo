import SwiftUI

struct CookbookSwitcherView: View {
    @EnvironmentObject var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingCreateCookbook = false
    @State private var showingDeleteAlert = false
    @State private var cookbookToDelete: Cookbook?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.availableCookbooks) { cookbook in
                    Button(action: {
                        if cookbook.id != store.cookbook.id {
                            store.switchToCookbook(cookbook)
                        }
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cookbook.name)
                                    .font(.headline)

                                HStack(spacing: 16) {
                                    let recipeCount = store.recipeCount(for: cookbook)
                                    HStack(spacing: 4) {
                                        Image(systemName: "book.closed")
                                        Text("\(recipeCount) \(recipeCount == 1 ? "recipe" : "recipes")")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                    let categoryCount = store.categoryCount(for: cookbook)
                                    HStack(spacing: 4) {
                                        Image(systemName: "paperclip")
                                        Text("\(categoryCount) \(categoryCount == 1 ? "category" : "categories")")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            if cookbook.id == store.cookbook.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .contextMenu {
                        Button(action: {
                            shareCookbook(cookbook)
                        }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        if store.availableCookbooks.count > 1 {
                            Button(role: .destructive) {
                                cookbookToDelete = cookbook
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    #else
                    .swipeActions(edge: .leading) {
                        Button(action: {
                            shareCookbook(cookbook)
                        }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if store.availableCookbooks.count > 1 {
                            Button(role: .destructive) {
                                cookbookToDelete = cookbook
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    #endif
                }

                AboutSection()
            }
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 300)
            #endif
            .navigationTitle("Cookbooks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showingCreateCookbook = true
                    }) {
                        Label("New Cookbook", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreateCookbook) {
                CreateCookbookView()
            }
            .alert("Delete Cookbook", isPresented: $showingDeleteAlert, presenting: cookbookToDelete) { cookbook in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    store.deleteCookbook(cookbook)
                }
            } message: { cookbook in
                Text("Are you sure you want to delete '\(cookbook.name)'? This will permanently delete all recipes and categories in this cookbook.")
            }
        }
    }

    private func shareCookbook(_ cookbook: Cookbook) {
        guard let fileURL = store.exportCookbook(cookbook) else {
            print("Failed to export cookbook")
            return
        }

        #if os(iOS)
        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)

        // Configure popover presentation for iPad only
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
    }
}

/// A short "what this app is" section at the bottom of the cookbooks list.
struct AboutSection: View {
    @EnvironmentObject var store: RecipeStore

    private let compatibleSites = URL(string: "https://cookbo.app/compatible-sites")!
    private let support = URL(string: "https://cookbo.app/support")!
    private let privacy = URL(string: "https://cookbo.app/privacy")!

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "book.closed.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cookbo")
                        .font(.headline)
                    Text("Save recipes from anywhere, cook without losing your place, and keep them as plain Markdown files you own.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(storageDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)

            Link(destination: compatibleSites) {
                Label("Sites You Can Import From", systemImage: "globe")
            }
            Link(destination: support) {
                Label("Support", systemImage: "questionmark.circle")
            }
            Link(destination: privacy) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
        } header: {
            Text("About")
        } footer: {
            Text("\(appVersion) · cookbo.app")
        }
    }

    private var storageDescription: String {
        if store.useLocalStorage || !store.isICloudAvailable {
            return "Your recipes are stored on this device."
        }
        return "Your recipes sync across your devices through iCloud Drive."
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        guard let version else { return "Cookbo" }
        guard let build, !build.isEmpty else { return "Version \(version)" }
        return "Version \(version) (\(build))"
    }
}

struct CreateCookbookView: View {
    @EnvironmentObject var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    @State private var cookbookName: String = ""

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            // Title
            HStack {
                Text("New Cookbook")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cookbook Name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("", text: $cookbookName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !cookbookName.trimmingCharacters(in: .whitespaces).isEmpty {
                                createCookbook()
                            }
                        }
                }

                Text("Create a new cookbook to organize your recipes separately.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding()

            Divider()

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    createCookbook()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(cookbookName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 220)
        #else
        NavigationStack {
            Form {
                Section {
                    TextField("Cookbook Name", text: $cookbookName)
                        .textInputAutocapitalization(.words)
                        .onSubmit {
                            if !cookbookName.trimmingCharacters(in: .whitespaces).isEmpty {
                                createCookbook()
                            }
                        }
                } header: {
                    Text("New Cookbook")
                } footer: {
                    Text("Create a new cookbook to organize your recipes separately.")
                }
            }
            .navigationTitle("New Cookbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createCookbook()
                    }
                    .disabled(cookbookName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #endif
    }

    private func createCookbook() {
        let trimmedName = cookbookName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let newCookbook = Cookbook(name: trimmedName)
        store.createCookbook(newCookbook)
        dismiss()
    }
}

#Preview("Cookbook Switcher") {
    CookbookSwitcherView()
        .environmentObject(RecipeStore())
}

#Preview("Create Cookbook") {
    CreateCookbookView()
        .environmentObject(RecipeStore())
}
