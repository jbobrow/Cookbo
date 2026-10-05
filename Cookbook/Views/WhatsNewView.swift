import SwiftUI

/// What a version brings, shown once over the whole app to people who
/// updated to it. Most updates arrive on their own, so this is the only way
/// they'd hear about them.
struct WhatsNew {
    struct Item: Identifiable {
        let icon: String
        let title: String
        let detail: String

        var id: String { title }
    }

    let version: String
    let items: [Item]

    /// Every version with something to show. A version without an entry
    /// shows nothing.
    static let releases: [WhatsNew] = [
        WhatsNew(version: "1.5.1", items: [
            Item(icon: "sparkles", title: "A tour of Cookbo",
                 detail: "A quick look at how it all works, with a little help from some produce."),
            Item(icon: "square.and.arrow.up", title: "Cookbo up front",
                 detail: "Put Cookbo first in your share sheet, right from the tour, so saving a recipe is two taps away."),
            Item(icon: "checklist", title: "A clearer import",
                 detail: "Ingredients and steps come first, Save is up top, and links from more apps come in."),
            Item(icon: "flame", title: "Cook mode polish",
                 detail: "Smoother swiping between pages, amounts with their sizes, and long cooks timed in hours."),
        ]),
    ]

    static var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// This version's entry, if it has one.
    static var current: WhatsNew? {
        releases.first { $0.version == currentVersion }
    }
}

/// The version's highlights and a way into the tour. Taking the tour swaps
/// this screen for the walkthrough, so finishing it closes both.
struct WhatsNewView: View {
    let whatsNew: WhatsNew

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var takingTour = false

    var body: some View {
        Group {
            if takingTour {
                WelcomeView(isReplay: true)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                highlights
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 660)
        #endif
    }

    private var highlights: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ProduceTitle(title: "What's New", fontSize: sizeClass == .compact ? 36 : 44,
                                 perSide: sizeClass == .compact ? 2 : 3)
                        .padding(.top, 56)
                    Text("in Cookbo \(whatsNew.version)")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 26) {
                        ForEach(whatsNew.items) { item in
                            row(item)
                        }
                    }
                    .padding(.top, 40)
                    .frame(maxWidth: 420)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 6) {
                Button {
                    withAnimation(.snappy) { takingTour = true }
                } label: {
                    Text("Take the Tour")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Color.accentColor, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                Button("Continue") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .keyboardShortcut(.cancelAction)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    private func row(_ item: WhatsNew.Item) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: item.icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WhatsNewView(whatsNew: WhatsNew.releases[0])
}
