import SwiftUI

/// First-launch onboarding. Introduces what the app does and points at the
/// sample recipe that every new cookbook starts with.
struct WelcomeView: View {
    @EnvironmentObject var store: RecipeStore
    @Environment(\.dismiss) private var dismiss

    /// Called when onboarding finishes, whichever way it was dismissed.
    var onFinish: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.top, 32)
                    .padding(.bottom, 36)

                VStack(alignment: .leading, spacing: 28) {
                    ForEach(features) { feature in
                        FeatureRow(feature: feature)
                    }
                }
                .padding(.horizontal, 8)

                Spacer(minLength: 40)

                actions
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        #if os(macOS)
        .frame(width: 520, height: 620)
        #endif
        .onDisappear(perform: onFinish)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 4)

            Text("Welcome to Cookbo")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Every recipe you cook, in one place.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var features: [Feature] {
        [
            Feature(
                icon: "square.and.arrow.down",
                title: "Save from anywhere",
                detail: "Share a recipe from Safari or Instagram and Cookbo pulls out the ingredients and steps."
            ),
            Feature(
                icon: "checklist",
                title: "Cook without losing your place",
                detail: "Check off ingredients and steps as you go, then mark the recipe as cooked to keep a history."
            ),
            store.useLocalStorage
                ? Feature(
                    icon: "internaldrive",
                    title: "Stored on this device",
                    detail: "Your recipes are plain Markdown files you own. Turn on iCloud any time to sync them."
                )
                : Feature(
                    icon: "icloud",
                    title: "Synced with iCloud",
                    detail: "Your recipes are plain Markdown files in iCloud Drive, up to date on every device."
                )
        ]
    }

    private var actions: some View {
        VStack(spacing: 16) {
            Button(action: finish) {
                Text("Start Cooking")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Text("\(SampleRecipe.title) is waiting in your cookbook, so there's something to try tonight.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func finish() {
        // onFinish runs from onDisappear, which also covers a swipe-to-dismiss
        dismiss()
    }

    fileprivate struct Feature: Identifiable {
        let icon: String
        let title: String
        let detail: String

        var id: String { title }
    }
}

private struct FeatureRow: View {
    let feature: WelcomeView.Feature

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: feature.icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.headline)
                Text(feature.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    WelcomeView()
        .environmentObject(RecipeStore())
}
