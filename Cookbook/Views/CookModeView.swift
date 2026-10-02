import SwiftUI
import UserNotifications

/// One step at a time, in big type, with the ingredients that step needs.
/// Next is the only control you need: it checks off the step and the
/// ingredients that first go in there, on the same checkmarks the recipe
/// page shows. After the last step, Mark as Cooked.
///
/// On iPhone it opens when you turn the phone sideways on a recipe page and
/// closes when you turn it back; Start Cooking opens it anywhere.
struct CookModeView: View {
    @EnvironmentObject private var store: RecipeStore
    @ObservedObject private var plans = CookPlanProvider.shared
    @Binding var recipe: Recipe
    let accentColor: Color
    let enteredByRotation: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @AppStorage("cookModeShowsShortSteps") private var prefersShortSteps = true
    @AppStorage("cookModeNextTaps") private var nextTaps = 0

    @State private var stepIndex: Int
    /// Rows checked by hand on this step that aren't a first use (a second
    /// pinch of salt), so they don't touch the recipe's checkmarks.
    @State private var checkedRows: Set<Int> = []
    @State private var timers: [CookTimer] = []
    @State private var isCooked = false
    @State private var finishedTimerCount = 0

    init(recipe: Binding<Recipe>, accentColor: Color, enteredByRotation: Bool) {
        _recipe = recipe
        self.accentColor = accentColor
        self.enteredByRotation = enteredByRotation
        _stepIndex = State(initialValue: recipe.wrappedValue.firstIncompleteStepIndex)
    }

    private var directions: [Direction] { recipe.orderedDirections }
    private var plan: CookPlan { plans.plan(for: recipe) }
    private var isFinished: Bool { stepIndex >= directions.count }

    private var currentStep: CookStep {
        plan.steps.indices.contains(stepIndex) ? plan.steps[stepIndex] : CookStep(shortText: nil, items: [])
    }

    private var currentText: String {
        guard directions.indices.contains(stepIndex) else { return "" }
        if prefersShortSteps, let short = currentStep.shortText { return short }
        return directions[stepIndex].text.sanitizedForDisplay
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let scale = min(max((isLandscape ? geometry.size.height / 390 : geometry.size.width / 390), 1), 1.6)

            VStack(spacing: 12) {
                topBar
                progressBar
                if isCooked {
                    cookedView
                } else if isFinished {
                    finishView(isLandscape: isLandscape)
                } else if isLandscape {
                    landscapeStep(scale: scale)
                } else {
                    portraitStep(scale: scale)
                }
            }
            .padding(.horizontal, isLandscape ? 8 : 20)
            .padding(.top, isLandscape ? 8 : 4)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.background)
        #if os(macOS)
        .frame(minWidth: 780, minHeight: 480)
        #endif
        .sensoryFeedback(.impact(weight: .medium), trigger: stepIndex)
        .sensoryFeedback(.warning, trigger: finishedTimerCount)
        .onAppear {
            plans.prepare(recipe)
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
        }
        .onDisappear {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
            for timer in timers { CookTimerAlerts.cancel(timer) }
        }
        #if os(iOS)
        .onChange(of: verticalSizeClass) { _, sizeClass in
            if enteredByRotation, sizeClass == .regular { dismiss() }
        }
        #endif
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.fill.tertiary, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Leave Cook Mode")

            Text(recipe.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            ForEach(timers.filter { $0.step != stepIndex || isFinished }) { timer in
                runningTimerPill(timer)
            }

            Text(isFinished ? "All done" : "Step \(stepIndex + 1) of \(directions.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
        }
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
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
    }

    // MARK: - Steps

    private func landscapeStep(scale: CGFloat) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    ingredientList
                    Spacer(minLength: 0)
                    timerControl
                }
                .frame(width: 228 * min(scale, 1.3), alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.trailing, 24)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(.separator).frame(width: 1)
                }

                stepText(size: fontSize(landscape: true) * scale)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 16) {
                backButton(compact: false)
                shortTextToggle
                Spacer(minLength: 0)
                nextHint
                nextButton(fullWidth: false)
            }
        }
    }

    private func portraitStep(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if !currentStep.items.isEmpty {
                ingredientList
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            shortTextToggle

            stepText(size: fontSize(landscape: false) * scale)

            timerControl

            HStack(spacing: 12) {
                backButton(compact: true)
                nextButton(fullWidth: true)
            }
        }
        .padding(.top, 6)
    }

    private func fontSize(landscape: Bool) -> CGFloat {
        let length = currentText.count
        let size: CGFloat = length <= 120 ? 32 : length <= 200 ? 28 : length <= 260 ? 25 : 23
        return landscape ? size : size + 2
    }

    private func stepText(size: CGFloat) -> some View {
        Text(styledText(currentText, step: currentStep))
            .font(.system(size: size, weight: .medium))
            .lineSpacing(size * 0.08)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(stepIndex)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .opacity
            ))
            .accessibilityAddTraits(.isHeader)
    }

    /// Ingredients get a tinted background, cooking times a dotted underline.
    private func styledText(_ text: String, step: CookStep) -> AttributedString {
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
        for duration in CookPlanner.durations(in: text) {
            let r = attributedRange(duration.range)
            styled[r].underlineStyle = Text.LineStyle(pattern: .dot, color: accentColor)
            styled[r].inlinePresentationIntent = .stronglyEmphasized
        }
        return styled
    }

    // MARK: - Ingredients

    private var ingredientList: some View {
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

            ForEach(Array(currentStep.items.enumerated()), id: \.offset) { row, item in
                Button { toggle(row: row, item: item) } label: {
                    ingredientRow(item, checked: isChecked(row: row, item: item))
                }
                .buttonStyle(.plain)
                .disabled(item.isPrepared)
            }
        }
    }

    private func ingredientRow(_ item: CookStepItem, checked: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(checked ? Color.green : Color.secondary)

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
        }
        .opacity(item.isPrepared ? 0.55 : 1)
        .contentShape(Rectangle())
    }

    private func rowDetail(_ item: CookStepItem) -> String? {
        var parts: [String] = []
        if !item.note.isEmpty { parts.append(item.note.prefix(1).uppercased() + item.note.dropFirst()) }
        if let from = item.preparedInStep { parts.append("From step \(from + 1)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func isFirstUse(_ item: CookStepItem) -> Bool {
        guard let index = item.ingredientIndex, !item.isPrepared else { return false }
        return plan.firstUseStep(ofIngredient: index) == stepIndex
    }

    private func isChecked(row: Int, item: CookStepItem) -> Bool {
        if item.isPrepared { return true }
        if isFirstUse(item), let index = item.ingredientIndex { return recipe.isIngredientChecked(index) }
        return checkedRows.contains(row)
    }

    private func toggle(row: Int, item: CookStepItem) {
        if isFirstUse(item), let index = item.ingredientIndex {
            recipe.setIngredientChecked(index, !recipe.isIngredientChecked(index))
            store.saveRecipe(recipe)
        } else if checkedRows.contains(row) {
            checkedRows.remove(row)
        } else {
            checkedRows.insert(row)
        }
    }

    // MARK: - Moving between steps

    private var nextLabel: String {
        stepIndex < directions.count - 1 ? "Next Step" : "Finish"
    }

    private func nextButton(fullWidth: Bool) -> some View {
        Button(action: advance) {
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
        Button(action: goBack) {
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
        .disabled(stepIndex == 0)
        .opacity(stepIndex == 0 ? 0.35 : 1)
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
            let count = plan.ingredientsFirstUsed(inStep: stepIndex).count
            Text(count > 0 ? "Next checks off this step and its \(count == 1 ? "ingredient" : "\(count) ingredients")" : "Next checks off this step")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 200, alignment: .trailing)
        }
    }

    private func advance() {
        guard !isFinished else { return }
        recipe.setStepCompleted(stepIndex, true)
        for index in plan.ingredientsFirstUsed(inStep: stepIndex) {
            recipe.setIngredientChecked(index, true)
        }
        store.saveRecipe(recipe)
        nextTaps += 1
        withAnimation(.snappy) {
            stepIndex += 1
            checkedRows = []
        }
    }

    private func goBack() {
        guard stepIndex > 0 else { return }
        let previous = stepIndex - 1
        recipe.setStepCompleted(previous, false)
        for index in plan.ingredientsFirstUsed(inStep: previous) {
            recipe.setIngredientChecked(index, false)
        }
        store.saveRecipe(recipe)
        withAnimation(.snappy) {
            stepIndex = previous
            checkedRows = []
        }
    }

    // MARK: - Timers

    private var currentDuration: CookDuration? {
        guard directions.indices.contains(stepIndex) else { return nil }
        return CookPlanner.durations(in: directions[stepIndex].text.sanitizedForDisplay).first
    }

    @ViewBuilder
    private var timerControl: some View {
        if let duration = currentDuration {
            if let timer = timers.first(where: { $0.step == stepIndex }) {
                Button { stopTimer(timer) } label: {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(timer.remainingText(at: context.date))
                                    .font(.title2.weight(.bold))
                                    .monospacedDigit()
                                Text("of \(timer.label)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: timer.isDone(at: context.date) ? "checkmark" : "pause.fill")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(accentColor, in: Circle())
                        }
                        .onChange(of: timer.isDone(at: context.date)) { _, done in
                            if done { finishedTimerCount += 1 }
                        }
                    }
                    .padding(.leading, 18)
                    .padding(.trailing, 8)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(accentColor.opacity(0.18), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop timer")
            } else {
                Button { startTimer(duration) } label: {
                    Label {
                        Text("Timer · \(duration.label)")
                    } icon: {
                        Image(systemName: "timer").foregroundStyle(accentColor)
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.fill.tertiary, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func runningTimerPill(_ timer: CookTimer) -> some View {
        Button { stopTimer(timer) } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Label(timer.remainingText(at: context.date), systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(accentColor.opacity(0.18), in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Step \(timer.step + 1) timer. Stop timer")
    }

    private func startTimer(_ duration: CookDuration) {
        let timer = CookTimer(
            step: stepIndex,
            label: duration.label,
            end: Date().addingTimeInterval(TimeInterval(duration.seconds))
        )
        timers.append(timer)
        CookTimerAlerts.schedule(timer, recipeTitle: recipe.title)
    }

    private func stopTimer(_ timer: CookTimer) {
        timers.removeAll { $0.id == timer.id }
        CookTimerAlerts.cancel(timer)
    }

    // MARK: - Finishing

    private func finishView(isLandscape: Bool) -> some View {
        let layout = isLandscape
            ? AnyLayout(HStackLayout(alignment: .center, spacing: 32))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))

        return layout {
            if let image = recipe.image {
                Color.clear
                    .frame(maxWidth: isLandscape ? 236 : .infinity)
                    .frame(width: isLandscape ? 236 : nil, height: 236)
                    .overlay { image.resizable().scaledToFill() }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("All \(directions.count) steps done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Time to eat.")
                    .font(.largeTitle.weight(.bold))
                Text("Mark it as cooked to add today to this recipe's history. The checkmarks reset for next time.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                let buttons = isLandscape ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 10))
                buttons {
                    Button(action: markCooked) {
                        Label("Mark as Cooked", systemImage: "checkmark.circle")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .frame(maxWidth: isLandscape ? nil : .infinity, minHeight: 56)
                            .background(accentColor, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)

                    Button { dismiss() } label: {
                        Text("Not Now")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 22)
                            .frame(maxWidth: isLandscape ? nil : .infinity, minHeight: 52)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cookedView: some View {
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
    }

    private func markCooked() {
        recipe = store.markCooked(recipe)
        for timer in timers { CookTimerAlerts.cancel(timer) }
        timers = []
        withAnimation(.spring(duration: 0.4)) { isCooked = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { dismiss() }
    }
}

// MARK: - Timers

struct CookTimer: Identifiable, Equatable {
    let id = UUID()
    let step: Int
    let label: String
    let end: Date

    func isDone(at date: Date) -> Bool { date >= end }

    func remainingText(at date: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(date).rounded(.up)))
        if seconds == 0 { return "Done" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// A notification for when a timer ends while the app is in the background.
/// Permission is asked the first time someone starts a timer.
enum CookTimerAlerts {
    static func schedule(_ timer: CookTimer, recipeTitle: String) {
        let interval = timer.end.timeIntervalSinceNow
        guard interval > 1 else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Timer done"
            content.body = "\(recipeTitle) · Step \(timer.step + 1) · \(timer.label)"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: timer.id.uuidString,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            )
            try? await center.add(request)
        }
    }

    static func cancel(_ timer: CookTimer) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString])
    }
}
