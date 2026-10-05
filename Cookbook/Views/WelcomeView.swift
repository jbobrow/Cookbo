import SwiftUI

/// How Cookbo works, a page at a time: saving recipes, cook mode, the plan
/// before step 1, and the week. Shown on first launch, pointing at
/// the sample recipe every new cookbook starts with, and again from About.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Seen again from About, so it ends with Done rather than the sample recipe.
    var isReplay = false
    /// Called when onboarding finishes, whichever way it was dismissed.
    var onFinish: () -> Void = {}

    @State private var page: Page = .welcome
    /// Which way the last move went, so a Mac page slides in from that side.
    @State private var forward = true

    enum Page: Int, CaseIterable {
        case welcome, save, shareFirst, cook, plan, week
    }

    /// The Mac's Share menu lists every extension by name, so there's no
    /// row of apps to move Cookbo to the front of.
    private static var pages: [Page] {
        #if os(macOS)
        Page.allCases.filter { $0 != .shareFirst }
        #else
        Page.allCases
        #endif
    }

    private var index: Int { Self.pages.firstIndex(of: page) ?? 0 }
    private var isLast: Bool { page == Self.pages.last }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            pages
            controls
        }
        #if os(macOS)
        .frame(width: 520, height: 660)
        #endif
        .onDisappear(perform: onFinish)
    }

    // MARK: - Pages

    @ViewBuilder
    private var pages: some View {
        #if os(macOS)
        ZStack {
            content(for: page)
                .id(page)
                .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        #else
        TabView(selection: $page) {
            ForEach(Self.pages, id: \.self) { page in
                content(for: page).tag(page)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
    }

    @ViewBuilder
    private func content(for page: Page) -> some View {
        // Produce drops in as each page comes into view, not while it waits
        // beside the one showing
        let showing = self.page == page
        switch page {
        case .welcome:
            WelcomePage(compact: sizeClass == .compact, showing: showing)
        case .save:
            WalkthroughPage(title: "Save from anywhere", message: saveMessage) {
                SaveArt(showing: showing)
            }
        case .shareFirst:
            WalkthroughPage(title: "Keep Cookbo up front",
                            message: "Move Cookbo to the start of your share sheet once, and every recipe after that is two taps away.") {
                ShareFirstArt(showing: showing)
            } detail: {
                ShareFirstSteps()
            } accessory: {
                ShareFirstButton()
            }
        case .cook:
            WalkthroughPage(title: Self.turnsToCook ? "Turn sideways to cook" : "One step at a time",
                            message: cookMessage) {
                CookArt(showing: showing)
            }
        case .plan:
            WalkthroughPage(title: "See the whole cook",
                            message: "Before step 1, see how long it all takes, what happens at the same time, and what to chop first.") {
                PlanArt(showing: showing)
            }
        case .week:
            WalkthroughPage(title: "Plan your week",
                            message: "Add recipes to This Week to plan what's for dinner. Mark one cooked when you're done, and the ones you love become Favorites.") {
                WeekArt(showing: showing)
            }
        }
    }

    // MARK: - Words

    /// An iPhone enters cook mode by turning on its side; everything else
    /// has the Start Cooking button.
    private static var turnsToCook: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private var saveMessage: String {
        #if os(macOS)
        "Share a recipe from Safari, or paste a link. Cookbo keeps the recipe and leaves the rest."
        #else
        "Share a recipe from Safari or Instagram, or paste a link. Cookbo keeps the recipe and leaves the rest."
        #endif
    }

    private var cookMessage: String {
        let start = Self.turnsToCook ? "Turn your phone on its side on any recipe" : "Tap Start Cooking on any recipe"
        return start + " for one step at a time, with just what that step needs. Tap a cooking time to start a timer."
    }

    // MARK: - Controls

    private var topBar: some View {
        HStack {
            Spacer()
            if isReplay {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .modifier(TopBarButton())
            } else if !isLast {
                Button("Skip") { go(to: Self.pages.last!) }
                    .keyboardShortcut(.cancelAction)
                    .modifier(TopBarButton())
            }
        }
        .frame(height: 44)
        #if os(macOS)
        .padding(.top, 8)
        #endif
    }

    private var controls: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            HStack {
                Button("Back") { step(-1) }
                    .buttonStyle(.plain)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .opacity(page == .welcome ? 0 : 1)
                    .disabled(page == .welcome)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Spacer()
                dots
                Spacer()
                Button("Back") {}.font(.headline).hidden()   // balances Back, so the dots stay centered
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 16)
            #else
            dots.padding(.bottom, 20)
            #endif

            Button(action: advance) {
                Text(isLast ? (isReplay ? "Done" : "Start Cooking") : "Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color.accentColor, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)

            // Where to start, once the walkthrough is done
            Text(isLast && !isReplay ? "\(SampleRecipe.title) is waiting in your cookbook, so there's something to try tonight." : " ")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: 360)
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .opacity(isLast && !isReplay ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isLast)
                .accessibilityHidden(!(isLast && !isReplay))
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(Self.pages, id: \.self) { dot in
                Capsule()
                    .fill(dot == page ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: dot == page ? 20 : 7, height: 7)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1) of \(Self.pages.count)")
    }

    private func advance() {
        if isLast {
            // onFinish runs from onDisappear, which also covers a swipe-to-dismiss
            dismiss()
        } else {
            step(1)
        }
    }

    private func step(_ by: Int) {
        guard Self.pages.indices.contains(index + by) else { return }
        let next = Self.pages[index + by]
        go(to: next)
    }

    private func go(to next: Page) {
        forward = (Self.pages.firstIndex(of: next) ?? 0) > index
        withAnimation(.snappy) { page = next }
    }
}

extension View {
    /// Shows the walkthrough over everything on iPhone and iPad, and as a
    /// sheet on the Mac, which has no full-screen cover.
    func welcomeCover(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> WelcomeView) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented, content: content)
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }
}

private struct TopBarButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
    }
}

// MARK: - Page layouts

/// The app icon, "Cookbo" with produce dropped either side, and what it's for.
private struct WelcomePage: View {
    let compact: Bool
    let showing: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                .accessibilityHidden(true)
            ProduceTitle(title: "Cookbo", fontSize: compact ? 40 : 48, perSide: compact ? 2 : 3, dropped: showing)
                .padding(.top, 32)
            Text("Every recipe you cook, in one place.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
    }
}

/// Illustration on top, then a title and a short explanation. A page can add
/// a detail under the illustration that VoiceOver reads, unlike the
/// illustration itself, and something to do under the explanation.
private struct WalkthroughPage<Art: View, Detail: View, Accessory: View>: View {
    let title: String
    let message: String
    @ViewBuilder let art: Art
    @ViewBuilder var detail: Detail
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            VStack(spacing: 14) {
                art.accessibilityHidden(true)
                detail
            }
            .frame(maxWidth: 340)
            Spacer(minLength: 28)
            Text(title.noWidow)
                .font(.system(size: 30, weight: .bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message.noWidow)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
                .padding(.top, 10)
            accessory
                .padding(.top, 18)
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
    }
}

extension WalkthroughPage where Detail == EmptyView, Accessory == EmptyView {
    init(title: String, message: String, @ViewBuilder art: () -> Art) {
        self.init(title: title, message: message, art: art, detail: { EmptyView() }, accessory: { EmptyView() })
    }
}

/// A rounded card for the illustrations, the same fill as cook mode's.
private extension View {
    func artCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Sets produce on the top edge of a card, as if it was put down there.
    func produce(_ pieces: [(Produce, CGFloat)], em: CGFloat, showing: Bool, inset: CGFloat = 20,
                 alignment: HorizontalAlignment = .trailing) -> some View {
        overlay(alignment: Alignment(horizontal: alignment, vertical: .top)) {
            HStack(alignment: .bottom, spacing: -em * 0.1) {
                ForEach(Array(pieces.enumerated()), id: \.offset) { index, piece in
                    ProduceView(produce: piece.0, em: em, delay: piece.1, dropped: showing)
                }
            }
            .alignmentGuide(.top) { $0[.bottom] - 2 }
            .padding(alignment == .trailing ? .trailing : .leading, inset)
        }
    }
}

// MARK: - Illustrations

/// A recipe blog, ads and life story included, and the share sheet that
/// brings just the recipe into Cookbo.
private struct SaveArt: View {
    let showing: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                    Text("example.com/coziest-tomato-soup")
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(.fill.tertiary, in: Capsule())

                ad

                Text("The Coziest Tomato Soup (Seriously!)")
                    .font(.system(size: 16, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Posted in Soups · 2,481 words · 47 comments")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    storyLine(1)
                    storyLine(0.92)
                    storyLine(0.6)
                }
                ad
            }
            .artCard(padding: 14)
            .produce([(.tomato, 0.05), (.garlic, 0.2)], em: 54, showing: showing)

            #if os(macOS)
            shareMenuRow
                .padding(.top, -26)
                .padding(.horizontal, 22)
            #else
            ShareSheetApps(order: [.cookbo, .messages, .mail, .notes, .more], highlightsCookbo: true)
                .padding(.top, -34)
                .padding(.horizontal, 6)
            #endif
        }
    }

    private var ad: some View {
        Text("Advertisement")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func storyLine(_ fraction: CGFloat) -> some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.fill.secondary)
                .frame(width: geometry.size.width * fraction, height: 6)
        }
        .frame(height: 6)
    }

    /// Cookbo as the Mac's Share menu lists it.
    private var shareMenuRow: some View {
        HStack(spacing: 12) {
            Image("AppIconImage")
                .resizable()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Import to Cookbo")
                .font(.system(size: 16, weight: .semibold))
            Spacer(minLength: 0)
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

/// The share sheet's row of apps, Cookbo among them. The others are
/// stand-ins rather than anyone's real icons.
private struct ShareSheetApps: View {
    enum App: Hashable {
        case cookbo, messages, mail, notes, more
    }

    let order: [App]
    var highlightsCookbo = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(order, id: \.self) { app in
                tile(app)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private func tile(_ app: App) -> some View {
        VStack(spacing: 5) {
            icon(app)
                .frame(width: 48, height: 48)
                .overlay {
                    if app == .cookbo && highlightsCookbo {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2.5)
                            .padding(-4)
                    }
                }
            Text(label(app))
                .font(.system(size: 10, weight: app == .cookbo ? .semibold : .regular))
                .foregroundStyle(app == .cookbo ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func icon(_ app: App) -> some View {
        switch app {
        case .cookbo:
            Image("AppIconImage")
                .resizable()
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        case .messages: symbol("message.fill", on: .green)
        case .mail: symbol("envelope.fill", on: .blue)
        case .notes: symbol("note.text", on: .orange)
        case .more:
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(.fill.secondary, in: Circle())
        }
    }

    private func symbol(_ name: String, on color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    /// What the share sheet calls Cookbo: the app's name from iOS 26, and
    /// the extension's own name before that.
    static var cookboLabel: String {
        if #available(iOS 26, *) { return "Cookbo" }
        return "Import to Cookbo"
    }

    private func label(_ app: App) -> String {
        switch app {
        case .cookbo: Self.cookboLabel
        case .messages: "Messages"
        case .mail: "Mail"
        case .notes: "Notes"
        case .more: "More"
        }
    }
}

/// Cookbo hopping from the end of the share sheet's row to the front.
private struct ShareFirstArt: View {
    let showing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var moved = false

    var body: some View {
        ShareSheetApps(order: moved ? [.cookbo, .messages, .mail, .notes, .more]
                                    : [.messages, .mail, .notes, .cookbo, .more],
                       highlightsCookbo: moved)
            .produce([(.peapod, 0.05), (.radish, 0.18)], em: 48, showing: showing, inset: 24)
        // Moves each time the page comes into view, after a moment to see
        // where Cookbo started
        .task(id: showing) {
            moved = false
            guard showing else { return }
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.72)) { moved = true }
        }
    }
}

/// The taps that move Cookbo to the front, as the share sheet words them.
private struct ShareFirstSteps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            step(1, "Tap **More** at the end of the row of apps")
            step(2, "Tap **Edit**")
            step(3, "Tap **+** beside **\(ShareSheetApps.cookboLabel)**, then drag it to the top of Favorites")
        }
        .artCard()
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            Text(.init(text))
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Opens the real share sheet, with Cookbo in it, to make the change right
/// there. It shares the sample recipe's page, so tapping Cookbo instead
/// imports a recipe like any other.
private struct ShareFirstButton: View {
    var body: some View {
        ShareLink(item: URL(string: SampleRecipe.sourceURL)!,
                  preview: SharePreview(SampleRecipe.title, image: Image("AppIconImage"))) {
            Label("Try It Now", systemImage: "square.and.arrow.up")
                .font(.headline)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
                .contentShape(Capsule())
        }
        .accessibilityHint("Opens the share sheet")
    }
}

/// Cook mode on a phone turned on its side: the step, what goes in, a
/// cooking time to tap, and Next.
private struct CookArt: View {
    let showing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { index in
                    Capsule()
                        .fill(index == 0 ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.secondary))
                        .frame(height: 4)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Step 1")
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    stepText
                        .font(.system(size: 14, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("For This Step")
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    (Text("¼ cup ").bold() + Text("olive oil"))
                    (Text("1 pound ").bold() + Text("shallots"))
                }
                .font(.system(size: 12))
                .frame(width: 96, alignment: .leading)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Text("Next Step")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor, in: Capsule())
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(height: 176)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.85), lineWidth: 7)
        }
        .produce([(.mushroom, 0.08), (.radish, 0.22)], em: 50, showing: showing, inset: 34, alignment: .leading)
    }

    /// The sample recipe's first step, with its cooking time as a timer to tap.
    private var stepText: Text {
        let timer = Text("\(Image(systemName: "timer")) 20 to 25 minutes")
            .foregroundColor(.accentColor)
            .bold()
        return Text("Add the shallots and cook until soft, jammy and caramelized, ") + timer + Text(".")
    }
}

/// The real overview and first prep card cook mode shows for the sample
/// recipe, worked out the same way it would be.
private struct PlanArt: View {
    let showing: Bool

    private static let intro: (overview: CookOverview, prep: PrepTask?) = {
        let recipe = SampleRecipe.make()
        let plan = CookPlanner.heuristicPlan(for: recipe)
        return (CookIntroPlanner.overview(for: recipe, plan: plan),
                CookIntroPlanner.prepTasks(for: recipe, plan: plan).first)
    }()

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text(Self.intro.overview.totalLabel)
                    .font(.system(size: 18, weight: .bold))
                CookOverviewTimeline(overview: Self.intro.overview, accentColor: .accentColor, isLandscape: true)
                    .frame(height: CGFloat(Self.intro.overview.laneCount) * 46)
                    .environment(\.dynamicTypeSize, .large)
            }
            .artCard()
            .produce([(.carrot, 0.1)], em: 50, showing: showing, inset: 26)

            if let prep = Self.intro.prep {
                HStack(spacing: 12) {
                    Image(systemName: "circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prep.title)
                            .font(.system(size: 16, weight: .bold))
                        Text(prep.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .artCard(padding: 14)
            }
        }
    }
}

/// The This Week chip, a recipe that's been cooked a few times, and another
/// waiting for its turn.
private struct WeekArt: View {
    let showing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                chip("All", icon: "square.grid.2x2", selected: false)
                chip("This Week", icon: "calendar", selected: true)
                chip("Favorites", icon: "star", selected: false)
            }
            VStack(spacing: 0) {
                row(thumbnail: Self.samplePhoto, color: .orange,
                    title: SampleRecipe.title, detail: "Cooked 3 times", stars: 5, cooked: true)
                Divider().padding(.leading, 70)
                row(thumbnail: nil, color: .green,
                    title: "Weeknight Pesto Pasta", detail: "25 min", stars: 4, cooked: false)
            }
            .artCard(padding: 0)
            .produce([(.strawberry, 0.05), (.avocado, 0.18)], em: 48, showing: showing, inset: 22)
        }
    }

    private static let samplePhoto: Image? = {
        guard let url = Bundle.main.url(forResource: "sample-recipe", withExtension: "jpg"),
              let image = PlatformImage(contentsOfFile: url.path) else { return nil }
        #if os(macOS)
        return Image(nsImage: image)
        #else
        return Image(uiImage: image)
        #endif
    }()

    private func chip(_ title: String, icon: String, selected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor : Color.gray.opacity(0.15), in: Capsule())
        .foregroundStyle(selected ? Color.white : Color.primary)
    }

    private func row(thumbnail: Image?, color: Color, title: String, detail: String, stars: Int, cooked: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    thumbnail.resizable().scaledToFill()
                } else {
                    color.opacity(0.55)
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(String(repeating: "★", count: stars))
                        .foregroundStyle(.orange)
                    Text("· " + detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
            if cooked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

private extension Color {
    /// The face of the phone in the cook mode illustration.
    static var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}

private extension String {
    /// Joins the last two words with a non-breaking space so a line never ends
    /// with a single word on its own.
    var noWidow: String {
        guard let space = range(of: " ", options: .backwards) else { return self }
        return replacingCharacters(in: space, with: "\u{00A0}")
    }
}

#Preview {
    WelcomeView()
}
