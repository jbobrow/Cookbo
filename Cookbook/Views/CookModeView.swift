import SwiftUI

/// One step at a time, in big type, with the ingredients that step needs.
/// Next is the only control you need: it checks off the step, so the recipe
/// page can offer to resume there. The ingredient checkmarks on the recipe
/// page are for gathering what you need, so cooking leaves them alone.
/// After the last step, Mark as Cooked.
///
/// On iPhone it opens when you turn the phone sideways on a recipe page and
/// closes when you turn it back; Start Cooking opens it anywhere.
///
/// On an iPhone Duo opened sideways, the ingredients are the left-hand page
/// and the step the right; stood up like a laptop, the step is on the
/// upright half and the buttons on the half lying on the counter.
struct CookModeView: View {
    @EnvironmentObject private var store: RecipeStore
    @ObservedObject private var plans = CookPlanProvider.shared
    @ObservedObject private var timerStore = CookTimerStore.shared
    @Binding var recipe: Recipe
    let accentColor: Color
    let enteredByRotation: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @Environment(\.duoPose) private var duoPose
    @Environment(\.cameraStrip) private var cameraStrip
    @Environment(\.controlsRailed) private var controlsRailed
    @AppStorage("cookModeShowsShortSteps") private var prefersShortSteps = true
    @AppStorage("cookModeNextTaps") private var nextTaps = 0
    @AppStorage("cookModeStartedTimer") private var hasStartedTimer = false

    @State private var stepIndex: Int
    @State private var isCooked = false
    @State private var timerToStop: CookTimer?
    /// Which way the step text slides: in from the right going forward,
    /// from the left going back.
    @State private var movingBack = false
    /// The overview or prep screen before step 1, on a fresh start.
    @State private var introPage: CookIntroView.Page?
    /// Prep cards checked off, by position in the prep list.
    @State private var prepped: Set<Int> = []
    /// Measured ingredients checked off, by position in the measure list.
    @State private var measured: Set<Int> = []
    /// Whether the cook is on screen. Turning the phone sideways opens cook
    /// mode empty, so the screen turns with nothing on it and the cook fades
    /// in sideways; closing sideways fades it out before turning back.
    @State private var contentShown: Bool
    /// The screen is wider than it is tall.
    @State private var screenIsLandscape = false
    /// Waiting for the screen to turn upright before going away.
    @State private var closingUpright = false
    /// Gave back the permission to turn sideways.
    @State private var releasedOrientation = false

    init(recipe: Binding<Recipe>, accentColor: Color, enteredByRotation: Bool, startStep: Int? = nil) {
        _recipe = recipe
        self.accentColor = accentColor
        self.enteredByRotation = enteredByRotation
        let steps = recipe.wrappedValue.directions.count
        let start = startStep.map { min(max($0, 0), max(steps - 1, 0)) }
        _stepIndex = State(initialValue: start ?? recipe.wrappedValue.firstIncompleteStepIndex)
        // Only a fresh start opens on the overview; resuming or a timer's
        // link goes straight to the step
        let fresh = startStep == nil && steps > 0 && !recipe.wrappedValue.directions.contains(where: \.isCompleted)
        _introPage = State(initialValue: fresh ? .overview : nil)
        #if os(iOS)
        _contentShown = State(initialValue: !(enteredByRotation && OrientationLock.phoneTurnsToCook))
        #else
        _contentShown = State(initialValue: true)
        #endif
    }

    @State private var introCache = IntroCache()
    @State private var drag = PageDrag()

    /// A finger was just swiping between steps. Whatever it lifts off isn't
    /// being tapped: a swipe across a row doesn't check it off.
    private var isSwiping: Bool { drag.justMoved }

    /// Which page is showing, so a swipe moves that page and not the next.
    private var pageKey: String {
        switch introPage {
        case .overview: "overview"
        case .prep: "prep"
        case nil: isCooked ? "cooked" : isFinished ? "finish" : "step \(stepIndex)"
        }
    }

    /// The overview, prep and measure lists, worked out once for this recipe
    /// and plan rather than on every redraw (turning the screen redraws
    /// several times).
    private var intro: IntroCache.Content { introCache.content(for: recipe, plan: plan) }
    private var overview: CookOverview { intro.overview }
    private var prepTasks: [PrepTask] { intro.prepTasks }
    private var measureTasks: [MeasureTask] { intro.measureTasks }

    /// The prep screen shows when there's anything to cut or measure.
    private var hasPrepPage: Bool { !prepTasks.isEmpty || !measureTasks.isEmpty }

    private var directions: [Direction] { recipe.orderedDirections }
    private var plan: CookPlan { plans.plan(for: recipe) }
    private var isFinished: Bool { stepIndex >= directions.count }

    private var currentStep: CookStep {
        plan.steps.indices.contains(stepIndex) ? plan.steps[stepIndex] : CookStep(shortText: nil, items: [])
    }

    private var currentText: String {
        guard directions.indices.contains(stepIndex) else { return "" }
        if prefersShortSteps, let short = currentStep.shortText { return CookPlanner.prettyFractions(in: short) }
        return CookPlanner.prettyFractions(in: directions[stepIndex].text.sanitizedForDisplay)
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            // An iPhone Duo opened up has the room of an iPad but is read at a
            // phone's distance, and a book's page is only a phone wide
            let scale = min(max((isLandscape ? geometry.size.height / 390 : geometry.size.width / 390), 1), duoPose == .open ? 1.2 : 1.6)
            let laptopFold = isLandscape ? nil : geometry.laptopFold
            let spine = isLandscape ? geometry.spine(minimumPage: 280) : nil
            // Opened flat there's no fold to work around, and the step takes
            // two thirds of the glass
            let stepSpine = spine.map {
                geometry.fold == nil ? CGRect(x: geometry.size.width / 3, y: $0.minY, width: 0, height: $0.height) : $0
            }

            // The pages before them split down the middle of the glass, as
            // close together as they like
            let introSpine = spine.map {
                geometry.fold == nil ? CGRect(x: geometry.size.width / 2, y: $0.minY, width: 0, height: $0.height) : $0
            }

            Group {
                if let laptopFold, introPage == nil, !isCooked {
                    if isFinished {
                        laptopFinish(fold: laptopFold)
                            .followsSwipe(drag, page: pageKey)
                    } else {
                        laptopStep(fold: laptopFold, scale: scale)
                    }
                } else {
                    VStack(spacing: 12) {
                        // Held like a book, a long name stops short of the crease
                        topBar(titleWidth: geometry.fold == nil ? nil : spine.map(bookColumnWidth))
                        progressBar
                        if let page = introPage {
                            CookIntroView(
                                page: page,
                                overview: overview,
                                prepTasks: prepTasks,
                                prepped: $prepped,
                                measureTasks: measureTasks,
                                measured: $measured,
                                accentColor: accentColor,
                                isLandscape: isLandscape,
                                spine: introSpine,
                                sideMargin: sideMargin(isLandscape: isLandscape),
                                drag: drag,
                                pageKey: pageKey,
                                onNext: { if !isSwiping { introNext() } },
                                onBack: { if !isSwiping { withAnimation(.snappy) { introPage = .overview } } },
                                onSkip: { withAnimation(.snappy) { introPage = nil } }
                            )
                            .id(page)
                            .transition(.opacity)
                        } else if isCooked {
                            cookedView(spine: spine)
                                .centeredAboveFold(laptopFold)
                                .followsSwipe(drag, page: pageKey)
                        } else if isFinished {
                            finishView(isLandscape: isLandscape, spine: spine)
                                .followsSwipe(drag, page: pageKey)
                        } else if isLandscape {
                            landscapeStep(scale: scale, spine: stepSpine)
                        } else {
                            portraitStep(scale: scale, pageHeight: geometry.size.height)
                        }
                    }
                }
            }
            .padding(.horizontal, sideMargin(isLandscape: isLandscape))
            // Folded shut the status bar is hidden, and the page starts at the
            // very top of the glass
            .padding(.top, duoPose == .open ? .duoCorner : cameraStrip != nil ? 20 : isLandscape ? 8 : 4)
            // Opened up, the buttons sit as far from the bottom corner of the
            // glass as the top ones do from theirs, past the safe area
            .padding(.bottom, duoPose == .open ? .duoCorner - geometry.safeAreaInsets.bottom : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(swipe)
            .opacity(contentShown ? 1 : 0)
            // Bending the glass or laying it flat slides the page between them
            .animation(spine == nil ? nil : .snappy, value: geometry.fold == nil)
        }
        // Folded shut and tall, the way out stands in the camera band
        .cameraStripPage {
            RailButton(symbol: "xmark", label: "Leave Cook Mode") { close() }
                .keyboardShortcut(.cancelAction)
                .tint(Color.primary)
        }
        .background(.background)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { drag.width = $0 }
        .onGeometryChange(for: Bool.self, of: { $0.size.width > $0.size.height }) { landscape in
            screenIsLandscape = landscape
            screenTurned(toLandscape: landscape)
        }
        #if os(macOS)
        .frame(minWidth: 780, minHeight: 480)
        #endif
        .sensoryFeedback(.impact(weight: .medium), trigger: stepIndex)
        .onAppear {
            store.cookingRecipeID = recipe.id
            plans.prepare(recipe)
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            OrientationLock.cookModeOpened()
            // If the screen doesn't turn (the phone went flat), show it anyway
            if !contentShown {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if !contentShown, !closingUpright { withAnimation(.easeOut(duration: 0.25)) { contentShown = true } }
                }
            }
            #endif
        }
        .onChange(of: store.pendingCookStep) { _, request in
            // A timer's Live Activity for this recipe was tapped
            guard let request, request.recipeID == recipe.id else { return }
            store.pendingCookStep = nil
            showStep(request.step)
        }
        .onDisappear {
            if store.cookingRecipeID == recipe.id { store.cookingRecipeID = nil }
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            releaseOrientation()
            #endif
            // Cooked it, and back on the recipe page with no timers left
            // going: a good moment to ask for a review
            if isCooked, timerStore.timers.isEmpty {
                ReviewPrompter.shared.requestReviewIfAppropriate()
            }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            // Opened by turning the phone, turning it back closes it. The
            // phone says so before the screen turns, so the cook can fade out
            // first and the screen turns with nothing on it.
            guard enteredByRotation, OrientationLock.phoneTurnsToCook,
                  UIDevice.current.orientation == .portrait, screenIsLandscape else { return }
            close()
        }
        .onChange(of: verticalSizeClass) { _, sizeClass in
            // Turned back upright without the phone saying so first
            if enteredByRotation, sizeClass == .regular, !closingUpright { close() }
        }
        #endif
    }

    // MARK: - Chrome

    private func topBar(titleWidth: CGFloat? = nil) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                // Folded shut and tall, it's in the camera band
                if !controlsRailed { closeButton }

                recipeTitle
            }
            .frame(maxWidth: titleWidth, alignment: .leading)

            Spacer(minLength: 0)

            timerStatus

            pageLabel
        }
        .clearOfCameraStrip(cameraStrip)
    }

    /// The left-hand page: it starts at the margin, and its trailing 24pt
    /// reach the crease.
    private func bookColumnWidth(spine: CGRect) -> CGFloat {
        max(spine.minX - sideMargin(isLandscape: true) - 24, 0)
    }

    private var recipeTitle: some View {
        Text(recipe.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var pageLabel: some View {
        Text(introPage == .overview ? "Overview" : introPage == .prep ? "Prep"
             : isFinished ? "All done" : "Step \(stepIndex + 1) of \(directions.count)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .fixedSize()
    }

    @ViewBuilder
    private var timerStatus: some View {
        // Timers from other steps keep running here; only Stop ends one
        // The Dynamic Island and lock screen show system timers; without
        // them, timers from other steps show here
        if !timerStore.systemShowsTimers {
            ForEach(timerStore.timers(for: recipe.id).filter { $0.step != stepIndex || isFinished }) { timer in
                CookTimerPill(timer: timer, tint: Self.timerTint)
            }
        }

        // Any timer running, from any step or recipe, shows as a small
        // blue status icon; tapping it lists them
        CookTimersButton(tint: Self.timerTint, recipeID: recipe.id) { step in
            showStep(step)
        }
    }

    private var bookBackButton: some View {
        Button { if !isSwiping { goBack() } } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.fill.tertiary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.leftArrow, modifiers: [])
        .accessibilityLabel("Previous Step")
    }

    private var bookNextButton: some View {
        Button { if !isSwiping { advance() } } label: {
            HStack(spacing: 6) {
                Text(nextLabel)
                Image(systemName: "chevron.right")
            }
            .font(.body.weight(.bold))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(accentColor, in: Capsule())
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.rightArrow, modifiers: [])
    }

    private var closeButton: some View {
        roundButton(symbol: "xmark") { close() }
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Leave Cook Mode")
    }

    private func roundButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                // Folded shut, glass like the rest of the camera band's buttons
                if cameraStrip != nil {
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .duoGlass()
                } else {
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.fill.tertiary, in: Circle())
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            // Before step 1: the overview and prep get two short segments
            if let page = introPage {
                Capsule()
                    .fill(page == .overview ? AnyShapeStyle(accentColor.opacity(0.35)) : AnyShapeStyle(accentColor))
                    .frame(width: 28, height: 4)
                Capsule()
                    .fill(page == .prep ? AnyShapeStyle(accentColor.opacity(0.35)) : AnyShapeStyle(.fill.tertiary))
                    .frame(width: 28, height: 4)
                    .opacity(hasPrepPage ? 1 : 0)
                Spacer().frame(width: 6)
            }
            ForEach(directions.indices, id: \.self) { index in
                Capsule()
                    .fill(index < stepIndex ? AnyShapeStyle(accentColor)
                          : index == stepIndex ? AnyShapeStyle(accentColor.opacity(0.35))
                          : AnyShapeStyle(.fill.tertiary))
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(min(stepIndex, directions.count)) of \(directions.count) steps done")
        .clearOfCameraStrip(cameraStrip)
    }

    // MARK: - Steps

    /// Opened up (`spine`), the ingredients are on the left and the step on
    /// the right. Held like a book they're a page each, with the crease for
    /// the rule between them.
    private func landscapeStep(scale: CGFloat, spine: CGRect?) -> some View {
        let columnWidth = spine.map(bookColumnWidth) ?? 228 * min(scale, 1.3)
        return VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    // A long list scrolls rather than running off the bottom; each
                    // step starts at the top of its own
                    ScrollView(.vertical) {
                        ingredientListContent
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // A whole page to itself, to read from the counter
                            .dynamicTypeSize(spine != nil ? DynamicTypeSize.xxxLarge... : DynamicTypeSize.xSmall...)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .id(stepIndex)
                    .transition(.opacity)
                    .fadesWithSwipe(drag, page: pageKey)

                    if spine != nil { shortTextToggle }
                }
                .frame(width: columnWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.trailing, 24)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(.separator).frame(width: 1)
                        .opacity(spine?.width ?? 0 > 0 ? 0 : 1)
                }

                VStack(spacing: 12) {
                    // Sliding step text is masked at the rule, not drawn over the
                    // ingredients (taller than the column so highlights aren't cut).
                    // Opened up, with the buttons under it, a long step gets
                    // smaller before it has to scroll.
                    slidingStepText(size: fontSize(landscape: true) * scale, scrolls: spine == nil)

                    if spine != nil {
                        // Next in the corner
                        HStack(spacing: 12) {
                            Spacer(minLength: 0)
                            nextHint
                            bookBackButton
                            bookNextButton
                        }
                    }
                }
                .padding(.leading, spine.map { $0.width + 24 } ?? 28)
            }
            .frame(maxHeight: .infinity)

            if spine == nil {
                HStack(spacing: 16) {
                    backButton(compact: false)
                    shortTextToggle
                    Spacer(minLength: 0)
                    nextHint
                    nextButton(fullWidth: false)
                }
            }
        }
    }

    /// A phone turned sideways has the system's margins to lean on. An iPhone
    /// Duo opened up has none, and the room for real ones.
    private func sideMargin(isLandscape: Bool) -> CGFloat {
        duoPose == .open ? 24 : isLandscape ? 8 : 20
    }

    private func portraitStep(scale: CGFloat, pageHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if !currentStep.items.isEmpty {
                // The step is what's read from the counter, and it already
                // highlights what goes in, so a long list gives way to it
                HeightLimit(maxHeight: pageHeight * 0.28) {
                    ingredientCard
                }
            }

            shortTextToggle

            // Opened up, there's no call for a long step to get smaller
            slidingStepText(size: fontSize(landscape: false) * scale, scrolls: duoPose == .open)

            HStack(spacing: 12) {
                backButton(compact: true)
                nextButton(fullWidth: true)
            }
            .clearOfCameraStrip(cameraStrip)
        }
        .padding(.top, 6)
    }

    /// Stood up like a laptop on the counter: the step on the upright half,
    /// at reading distance, and what goes in with the buttons on the half
    /// lying flat, under the hand. Nothing sits on the hinge.
    private func laptopStep(fold: CGRect, scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                topBar()
                progressBar
                shortTextToggle
                slidingStepText(size: fontSize(landscape: false) * scale, scrolls: true)
            }
            // The page starts 4pt down; the upper half ends at the fold
            .frame(height: max(fold.minY - 4 - 12, 0), alignment: .top)
            .padding(.bottom, 12)

            Color.clear
                .frame(height: fold.height)

            VStack(spacing: 16) {
                if !currentStep.items.isEmpty {
                    ingredientCard
                }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    backButton(compact: true)
                    nextButton(fullWidth: true)
                }
            }
            .padding(.top, 16)
            .frame(maxHeight: .infinity)
        }
    }

    private func fontSize(landscape: Bool) -> CGFloat {
        let length = currentText.count
        let size: CGFloat = length <= 120 ? 32 : length <= 200 ? 28 : length <= 260 ? 25 : 23
        return landscape ? size : size + 2
    }

    private func stepText(size: CGFloat) -> some View {
        let durations = CookPlanner.durations(in: currentText)
        let hasTimer = durations.contains { timerStore.timer(for: recipe.id, step: stepIndex, label: $0.label) != nil }

        return VStack(alignment: .leading, spacing: 12) {
            Group {
                if hasTimer {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        stepTextBody(size: size, durations: durations, now: context.date)
                    }
                } else {
                    stepTextBody(size: size, durations: durations, now: Date())
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                handleTimerLink(url, durations: durations)
            })

            if !hasStartedTimer, !durations.isEmpty {
                Label {
                    Text("Tap a cooking time to start a timer")
                } icon: {
                    Image(systemName: "timer").foregroundStyle(Self.timerTint)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The step's text, replaced with a slide when the step changes and
    /// moving with a swipe. The slide happens inside a clipped box, so in
    /// landscape the incoming text is cut off at the rule instead of passing
    /// over the ingredients. In landscape a long step scrolls at its full
    /// size. Stacked, it gets smaller first, but only so far: past what can
    /// be read from the counter, it scrolls too.
    private func slidingStepText(size: CGFloat, scrolls: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                if scrolls {
                    ScrollView(.vertical) { stepText(size: size) }
                        .scrollBounceBehavior(.basedOnSize)
                } else {
                    ViewThatFits(in: .vertical) {
                        ForEach(Array(stride(from: size, to: Self.smallestStepSize, by: -2)), id: \.self) { size in
                            stepText(size: size)
                        }
                        stepText(size: Self.smallestStepSize)

                        ScrollView(.vertical) { stepText(size: Self.smallestStepSize) }
                            .scrollBounceBehavior(.basedOnSize)
                            .scrollIndicatorsFlash(onAppear: true)
                    }
                }
            }
                .id(stepIndex)
                .followsSwipe(drag, page: pageKey)
                .transition(.asymmetric(
                    insertion: .move(edge: movingBack ? .leading : .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .alert("Stop this timer?", isPresented: Binding(
            get: { timerToStop != nil },
            set: { if !$0 { timerToStop = nil } }
        ), presenting: timerToStop) { timer in
            Button("Stop Timer", role: .destructive) { timerStore.stop(timer) }
            Button("Keep Running", role: .cancel) { }
        } message: { timer in
            Text("Step \(timer.step + 1) · \(timer.label)")
        }
    }

    /// The smallest a step gets before it scrolls instead.
    private static let smallestStepSize: CGFloat = 22

    /// Timers are the system's, so they use the system's blue rather than
    /// the recipe's category color.
    static let timerTint = Color.blue

    @ViewBuilder
    private func stepTextBody(size: CGFloat, durations: [CookDuration], now: Date) -> some View {
        let roundedPills: Bool = {
            if #available(iOS 18.0, macOS 15.0, visionOS 2.0, *) { return true }
            return false
        }()
        let text = composedText(currentText, step: currentStep, durations: durations, now: now, size: size, roundedPills: roundedPills)
        Group {
            if #available(iOS 18.0, macOS 15.0, visionOS 2.0, *) {
                text.textRenderer(TimerPillRenderer(fill: Self.timerTint))
            } else {
                text
            }
        }
        .font(.system(size: size, weight: .medium))
        .lineSpacing(size * 0.08)
        .accessibilityAddTraits(.isHeader)
    }

    /// Ingredients get a tinted background. Each cooking time is a link that
    /// starts a timer, marked with a timer icon; once running, a countdown pill
    /// follows it.
    private func composedText(_ text: String, step: CookStep, durations: [CookDuration], now: Date, size: CGFloat, roundedPills: Bool) -> Text {
        var styled = AttributedString(text)
        func attributedRange(_ range: Range<String.Index>) -> Range<AttributedString.Index> {
            let lower = styled.index(styled.startIndex, offsetByCharacters: text.distance(from: text.startIndex, to: range.lowerBound))
            let upper = styled.index(lower, offsetByCharacters: text.distance(from: range.lowerBound, to: range.upperBound))
            return lower..<upper
        }
        for range in CookPlanner.highlightRanges(in: text, terms: step.items.flatMap(\.highlightTerms)) {
            let r = attributedRange(range)
            styled[r].backgroundColor = accentColor.opacity(colorScheme == .dark ? 0.45 : 0.22)
            styled[r].inlinePresentationIntent = .stronglyEmphasized
        }

        var result = Text("")
        var cursor = styled.startIndex
        for (index, duration) in durations.enumerated() {
            let r = attributedRange(duration.range)
            result = Text("\(result)\(Text(AttributedString(styled[cursor..<r.lowerBound])))")

            var time = AttributedString(styled[r])
            let link = URL(string: "cookbo-timer://step/\(index)")
            time.link = link
            time.foregroundColor = Self.timerTint
            time.underlineStyle = Text.LineStyle(pattern: .dot, color: Self.timerTint)
            time.inlinePresentationIntent = .stronglyEmphasized
            result = Text("\(result)\(Text(time))")

            if let timer = timerStore.timer(for: recipe.id, step: stepIndex, label: duration.label) {
                let remaining = timer.isPaused ? "Paused \(timer.remainingText(at: now))" : timer.remainingText(at: now)
                // No-break spaces pad the capsule and keep icon, countdown and
                // cooking time together on one line
                var digits = AttributedString("\u{00A0}\(remaining)\u{00A0}\u{00A0}")
                digits.link = link
                digits.foregroundColor = .white
                if !roundedPills { digits.backgroundColor = Self.timerTint }
                var lead = AttributedString("\u{00A0}\u{00A0}")
                lead.link = link
                let pill = Text("\(Text(lead))\(Image(systemName: "timer"))\(Text(digits))")
                    .font(.system(size: size * 0.68, weight: .bold).monospacedDigit())
                    .foregroundColor(.white)
                    .baselineOffset(size * 0.1)
                result = Text("\(result)\u{00A0}\(pillMarked(pill, roundedPills: roundedPills))")
            } else {
                let icon = Text(Image(systemName: "timer"))
                    .font(.system(size: size * 0.8, weight: .semibold))
                    .foregroundColor(Self.timerTint)
                result = Text("\(result)\u{2009}\(icon)")
            }
            cursor = r.upperBound
        }
        return Text("\(result)\(Text(AttributedString(styled[cursor...])))")
    }

    private func pillMarked(_ text: Text, roundedPills: Bool) -> Text {
        if #available(iOS 18.0, macOS 15.0, visionOS 2.0, *), roundedPills {
            return text.customAttribute(TimerPillAttribute())
        }
        return text
    }

    /// A tap on a cooking time starts its timer, or offers to stop it.
    private func handleTimerLink(_ url: URL, durations: [CookDuration]) -> OpenURLAction.Result {
        guard url.scheme == "cookbo-timer",
              let index = Int(url.lastPathComponent),
              durations.indices.contains(index) else { return .systemAction }
        let duration = durations[index]
        let step = stepIndex
        // SwiftUI can call this in the middle of updating the view, which is
        // no time to change the timers it's showing; do it straight after
        DispatchQueue.main.async {
            if let timer = timerStore.timer(for: recipe.id, step: step, label: duration.label) {
                // A finished timer just clears; a running one asks first
                if timer.isDone(at: Date()) { timerStore.stop(timer) } else { timerToStop = timer }
            } else {
                timerStore.start(recipe: recipe, step: step, duration: duration)
                hasStartedTimer = true
            }
        }
        return .handled
    }

    // MARK: - Ingredients

    /// As tall as the list, or scrolling once that's more than it has room
    /// for. The rows run to the card's edge and fade out at its foot, to show
    /// there are more. A new step brings a new list rather than reshaping the
    /// old rows, and starts at the top of its own.
    private var ingredientCard: some View {
        ViewThatFits(in: .vertical) {
            ingredientListContent
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            ScrollView(.vertical) {
                ingredientListContent
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    // The last row comes clear of the fade
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicatorsFlash(onAppear: true)
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 24)
                }
            }
        }
        .id(stepIndex)
        .transition(.opacity)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .fadesWithSwipe(drag, page: pageKey)
    }

    private var ingredientListContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("For This Step")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            if currentStep.items.isEmpty {
                Text("Nothing new to add.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(currentStep.items.enumerated()), id: \.offset) { _, item in
                ingredientRow(item)
            }
        }
    }

    /// What goes in, to read at a glance; nothing to tick off mid-cook. Next
    /// checks the step's ingredients off in the recipe. Something made in an
    /// earlier step is dimmed: it's already there.
    private func ingredientRow(_ item: CookStepItem) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            (Text(item.amount.isEmpty ? "" : item.amount + " ").bold()
             + Text(item.amount.isEmpty ? item.name.prefix(1).uppercased() + item.name.dropFirst() : item.name))
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = rowDetail(item) {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(item.isPrepared ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    private func rowDetail(_ item: CookStepItem) -> String? {
        var parts: [String] = []
        if !item.note.isEmpty { parts.append(item.note.prefix(1).uppercased() + item.note.dropFirst()) }
        if let from = item.preparedInStep { parts.append("From step \(from + 1)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Moving between steps

    private var nextLabel: String {
        stepIndex < directions.count - 1 ? "Next Step" : "Finish"
    }

    private func nextButton(fullWidth: Bool) -> some View {
        Button { if !isSwiping { advance() } } label: {
            HStack(spacing: 6) {
                Text(nextLabel)
                Image(systemName: "chevron.right")
            }
            .font(.title3.weight(.bold))
            .foregroundColor(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 56)
            .frame(minWidth: fullWidth ? nil : 220)
            .padding(.horizontal, 24)
            .background(accentColor, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.rightArrow, modifiers: [])
    }

    @ViewBuilder
    private func backButton(compact: Bool) -> some View {
        Button { if !isSwiping { goBack() } } label: {
            if compact {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 56, height: 56)
                    .background(.fill.tertiary, in: Circle())
                    .contentShape(Circle())
            } else {
                Label("Back", systemImage: "chevron.left")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .background(.fill.tertiary, in: Capsule())
                    .contentShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.leftArrow, modifiers: [])
        .accessibilityLabel("Previous Step")
    }

    @ViewBuilder
    private var shortTextToggle: some View {
        if currentStep.shortText != nil {
            Button {
                withAnimation(.snappy) { prefersShortSteps.toggle() }
            } label: {
                Label(prefersShortSteps ? "Shortened · Show Full Step" : "Show Shorter Version", systemImage: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(.fill.tertiary, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// Until someone has used Next a few times, say what it does.
    @ViewBuilder
    private var nextHint: some View {
        if nextTaps < 3 {
            Text("Next checks off this step")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 200, alignment: .trailing)
        }
    }

    private func advance() {
        guard !isFinished else { return }
        recipe.setStepCompleted(stepIndex, true)
        store.saveRecipe(recipe)
        nextTaps += 1
        movingBack = false
        withAnimation(.snappy) {
            stepIndex += 1
        }
    }

    private func goBack() {
        // Back from step 1 returns to the screens before it
        guard stepIndex > 0 else {
            withAnimation(.snappy) { introPage = hasPrepPage ? .prep : .overview }
            return
        }
        let previous = stepIndex - 1
        // The step is open again
        recipe.setStepCompleted(previous, false)
        store.saveRecipe(recipe)
        movingBack = true
        withAnimation(.snappy) {
            stepIndex = previous
        }
    }

    /// Swipe left for Next and right for Back, like turning a page: the page
    /// follows the finger, and goes on off the screen once it's far enough
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                drag.moved()
                let distance = value.translation.width
                // Sideways or not is settled at the start, so scrolling a
                // long step never nudges the page
                if drag.isSideways == nil {
                    drag.isSideways = abs(distance) > abs(value.translation.height)
                    drag.page = pageKey
                }
                guard drag.isSideways == true else { return }
                // With no page that way, it only gives a little
                drag.offset = distance * (canSwipe(forward: distance < 0) ? 1 : 0.25)
            }
            .onEnded { value in
                let distance = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let sideways = drag.isSideways == true
                drag.isSideways = nil
                let flung = abs(predicted) > 160 && predicted * distance > 0
                let forward = distance < 0
                guard sideways, abs(distance) > 60 || flung, canSwipe(forward: forward) else {
                    withAnimation(.snappy) { drag.offset = 0 }
                    return
                }
                // Reset only once the old page has finished fading, or it
                // jumps back to the middle on its way out
                withAnimation(.snappy, completionCriteria: .removed) {
                    drag.offset = forward ? -drag.width : drag.width
                } completion: {
                    drag.page = nil
                    drag.offset = 0
                }
                if forward { swipeForward() } else { swipeBack() }
            }
    }

    /// Whether there's a page to swipe to. Marking as cooked stays a
    /// deliberate tap.
    private func canSwipe(forward: Bool) -> Bool {
        if forward { return introPage != nil || (!isCooked && !isFinished) }
        switch introPage {
        case .prep: return true
        case .overview: return false
        case nil: return !isCooked
        }
    }

    private func swipeForward() {
        if introPage != nil { introNext() } else { advance() }
    }

    private func swipeBack() {
        if introPage == .prep {
            withAnimation(.snappy) { introPage = .overview }
        } else {
            goBack()
        }
    }

    /// Straight to a timer's step, from its Live Activity or the timer list.
    private func showStep(_ step: Int) {
        let target = min(max(step, 0), max(directions.count - 1, 0))
        isCooked = false
        introPage = nil
        movingBack = target < stepIndex
        withAnimation(.snappy) {
            stepIndex = target
        }
    }

    private func introNext() {
        withAnimation(.snappy) {
            introPage = introPage == .overview && hasPrepPage ? .prep : nil
        }
    }

    // MARK: - Finishing

    private func finishView(isLandscape: Bool, spine: CGRect?) -> some View {
        let layout = isLandscape
            ? AnyLayout(HStackLayout(alignment: .center, spacing: spine.map { $0.width + 48 } ?? 32))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
        // Opened like a book, the picture is the left-hand page and the rest
        // the right, which is too narrow for the buttons side by side
        let leftPage = spine.map { max($0.minX - sideMargin(isLandscape: true) - 24, 0) }
        let buttonsInARow = isLandscape && spine == nil

        return layout {
            if let image = recipe.image {
                Color.clear
                    .frame(maxWidth: isLandscape ? 236 : .infinity)
                    .frame(width: isLandscape ? 236 : nil, height: 236)
                    .overlay { image.resizable().scaledToFill() }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frame(width: leftPage)
            } else if let leftPage {
                Color.clear
                    .frame(width: leftPage, height: 0)
            }

            finishText(buttonsInARow: buttonsInARow)
                .frame(maxWidth: spine != nil ? .infinity : nil, alignment: .leading)
                .clearOfCameraStrip(cameraStrip)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Stood up like a laptop: the picture on the upright half, and what to
    /// do about it on the half under the hand.
    private func laptopFinish(fold: CGRect) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                topBar()
                progressBar
                if let image = recipe.image {
                    Color.clear
                        .overlay { image.resizable().scaledToFill() }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            // The page starts 4pt down; the upper half ends at the fold
            .frame(height: max(fold.minY - 4 - 12, 0), alignment: .top)
            .padding(.bottom, 12)

            Color.clear
                .frame(height: fold.height)

            finishText(buttonsInARow: false)
                .padding(.top, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func finishText(buttonsInARow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Time to eat.")
                .font(.largeTitle.weight(.bold))
            Text("Mark it as cooked to add today to this recipe's history. The checkmarks reset for next time.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let buttons = buttonsInARow ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 10))
            buttons {
                Button(action: markCooked) {
                    Label("Mark as Cooked", systemImage: "checkmark.circle")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: buttonsInARow ? nil : .infinity, minHeight: 56)
                        .background(accentColor, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                Button { close() } label: {
                    Text("Not Now")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 22)
                        .frame(maxWidth: buttonsInARow ? nil : .infinity, minHeight: 52)
                        .background(.fill.tertiary, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)

            Button("Back to the Last Step", action: goBack)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.top, 4)
        }
    }

    private func cookedView(spine: CGRect?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(accentColor, in: Circle())
                .symbolEffect(.bounce, value: isCooked)
            Text("Marked as Cooked")
                .font(.title.weight(.bold))
            Text("Cooked \(recipe.datesCooked.count) time\(recipe.datesCooked.count == 1 ? "" : "s")")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Opened like a book, on the right-hand page rather than the crease
        .padding(.leading, spine.map { $0.maxX - sideMargin(isLandscape: true) } ?? 0)
    }

    private func markCooked() {
        recipe = store.markCooked(recipe)
        ReviewPrompter.shared.recordSignificantEvent(weight: 2)
        withAnimation(.spring(duration: 0.4)) { isCooked = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { close() }
    }

    // MARK: - Opening and closing

    /// Leaves cook mode. Sideways on an iPhone it fades out and turns the
    /// screen upright first, so the recipe page underneath is only ever seen
    /// upright; otherwise it slides away as usual.
    private func close() {
        #if os(iOS)
        if OrientationLock.phoneTurnsToCook, screenIsLandscape {
            guard !closingUpright else { return }
            closingUpright = true
            withAnimation(.easeIn(duration: 0.15)) { contentShown = false }
            releaseOrientation()
            // In case the screen never reports turning
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismissWithoutSliding() }
            return
        }
        #endif
        dismiss()
    }

    /// The screen finished turning.
    private func screenTurned(toLandscape landscape: Bool) {
        if landscape, !contentShown, !closingUpright {
            withAnimation(.easeOut(duration: 0.25)) { contentShown = true }
        } else if !landscape, closingUpright {
            dismissWithoutSliding()
        }
    }

    private func dismissWithoutSliding() {
        guard closingUpright else { return }
        closingUpright = false
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { dismiss() }
    }

    private func releaseOrientation() {
        #if os(iOS)
        guard !releasedOrientation else { return }
        releasedOrientation = true
        OrientationLock.cookModeClosed()
        #endif
    }
}

// MARK: - Countdown pill

/// Marks the countdown that follows a cooking time.
@available(iOS 18.0, macOS 15.0, visionOS 2.0, *)
struct TimerPillAttribute: TextAttribute {}

/// Draws a capsule behind each countdown, which text attributes alone can't
/// do (their backgrounds are square).
@available(iOS 18.0, macOS 15.0, visionOS 2.0, *)
struct TimerPillRenderer: TextRenderer {
    var fill: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            // A pill is several runs (icon, digits); one capsule covers them all
            var pill: CGRect?
            for run in line where run[TimerPillAttribute.self] != nil {
                let bounds = run.typographicBounds.rect
                pill = pill.map { $0.union(bounds) } ?? bounds
            }
            if let pill {
                let rect = pill.insetBy(dx: 0, dy: -2)
                context.fill(Capsule().path(in: rect), with: .color(fill))
            }
            for run in line {
                context.draw(run)
            }
        }
    }
}

/// Holds the screens before step 1 between redraws. Checking things off
/// changes the recipe but not what these are made from, so they're kept
/// until the steps, ingredients, prep time or plan change.
/// A swipe between pages as it happens. Only the page that moves reads
/// it, so a drag redraws that page rather than all of cook mode.
@Observable
final class PageDrag {
    /// How far the page has followed the finger
    var offset: CGFloat = 0
    /// The page being swiped. The page coming in isn't moved with it.
    var page: String?
    /// How far a page goes to leave the screen
    @ObservationIgnored var width: CGFloat = 400
    @ObservationIgnored var isSideways: Bool?
    @ObservationIgnored private var lastMoved = Date.distantPast

    func moved() { lastMoved = Date() }

    /// The tap that lifts with a swipe comes in right after its last move
    var justMoved: Bool { Date().timeIntervalSince(lastMoved) < 0.3 }
}

extension View {
    /// Moves with the finger while this page is being swiped, fading a little.
    func followsSwipe(_ drag: PageDrag, page: String) -> some View {
        modifier(SwipeFollower(drag: drag, page: page, moves: true))
    }

    /// Fades while this page is being swiped, staying in place.
    func fadesWithSwipe(_ drag: PageDrag, page: String) -> some View {
        modifier(SwipeFollower(drag: drag, page: page, moves: false))
    }
}

/// Offers its content no more than `maxHeight`. Unlike a frame, it stays the
/// content's own size when that's shorter.
private struct HeightLimit: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(limited(proposal))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: limited(proposal))
    }

    private func limited(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width, height: min(proposal.height ?? maxHeight, maxHeight))
    }
}

private struct SwipeFollower: ViewModifier {
    let drag: PageDrag
    let page: String
    let moves: Bool

    func body(content: Content) -> some View {
        let offset = drag.page == page ? drag.offset : 0
        let progress = min(abs(offset) / max(drag.width, 1), 1)
        content
            .offset(x: moves ? offset : 0)
            .opacity(1 - progress * (moves ? 0.5 : 0.8))
    }
}

private final class IntroCache {
    struct Content {
        let overview: CookOverview
        let prepTasks: [PrepTask]
        let measureTasks: [MeasureTask]
    }

    private var key: [String] = []
    private var plan: CookPlan?
    private var cached: Content?

    func content(for recipe: Recipe, plan: CookPlan) -> Content {
        let key = recipe.orderedDirections.map(\.text) + ["--"] + recipe.allIngredients.map(\.text)
            + ["\(recipe.prepDuration)"]
        if let cached, key == self.key, plan == self.plan { return cached }
        let content = Content(
            overview: CookIntroPlanner.overview(for: recipe, plan: plan),
            prepTasks: CookIntroPlanner.prepTasks(for: recipe, plan: plan),
            measureTasks: CookIntroPlanner.measureTasks(for: recipe, plan: plan)
        )
        self.key = key
        self.plan = plan
        cached = content
        return content
    }
}
