import SwiftUI

/// A timer from another step, in cook mode's top bar, for devices where the
/// system doesn't show timers itself. Stopping it takes a confirmation, so a
/// stray tap can't end it; a finished timer clears with one tap.
struct CookTimerPill: View {
    let timer: CookTimer
    let tint: Color
    /// Name the recipe, for places that show timers from every recipe.
    var showsRecipe = false

    @State private var confirmingStop = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let done = timer.isDone(at: context.date)
            Button {
                if done { CookTimerStore.shared.stop(timer) } else { confirmingStop = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: done ? "bell.fill" : "timer")
                        .foregroundStyle(done ? Color.white : tint)
                    Text(timer.remainingText(at: context.date))
                        .monospacedDigit()
                    Text(showsRecipe ? "Step \(timer.step + 1) ·" : "Step \(timer.step + 1)")
                        .foregroundStyle(done ? .white : .secondary)
                    if showsRecipe {
                        Text(timer.recipeTitle)
                            .lineLimit(1)
                            .frame(maxWidth: 150, alignment: .leading)
                            .foregroundStyle(done ? .white : .secondary)
                    }
                    if done {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(done ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(done ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.18)), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done
                ? "Step \(timer.step + 1) timer done. Clear"
                : "Step \(timer.step + 1) timer, \(timer.remainingText(at: context.date)) left")
        }
        .stopTimerConfirmation(timer, isPresented: $confirmingStop)
    }
}

private extension View {
    func stopTimerConfirmation(_ timer: CookTimer, isPresented: Binding<Bool>) -> some View {
        confirmationDialog("Stop this timer?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Stop Timer", role: .destructive) { CookTimerStore.shared.stop(timer) }
            Button("Keep Running", role: .cancel) { }
        } message: {
            Text("\(timer.recipeTitle) · Step \(timer.step + 1) · \(timer.label)")
        }
    }
}

/// Cook mode's timer status: a small blue timer while any are running, like
/// the system's dot for a microphone in use. It rings as a bell once one is
/// done; tapping it lists them all.
struct CookTimersButton: View {
    let tint: Color
    /// The recipe being cooked: its timers can jump to their step.
    let recipeID: UUID
    let onShowStep: (Int) -> Void

    @ObservedObject private var store = CookTimerStore.shared
    @State private var showingList = false

    var body: some View {
        if !store.timers.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let count = store.timers.count
                let anyDone = store.timers.contains { $0.isDone(at: context.date) }
                Button { showingList = true } label: {
                    HStack(spacing: 3) {
                        Image(systemName: anyDone ? "bell.fill" : "timer")
                            .font(.footnote.weight(.bold))
                        if count > 1 {
                            Text("\(count)")
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(anyDone ? Color.white : tint)
                    .padding(.horizontal, count > 1 ? 8 : 0)
                    .frame(minWidth: 28, minHeight: 28)
                    .background(anyDone ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.18)), in: Capsule())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(anyDone ? "Timer done" : count == 1 ? "1 timer running" : "\(count) timers running")
                .accessibilityHint("Shows your timers")
            }
            .popover(isPresented: $showingList, arrowEdge: .top) {
                CookTimerList(tint: tint, recipeID: recipeID) { step in
                    showingList = false
                    onShowStep(step)
                } onEmpty: {
                    showingList = false
                }
                .presentationCompactAdaptation(.popover)
            }
        }
    }
}

/// Every running timer, soonest first, each with its countdown and a way to
/// stop it.
private struct CookTimerList: View {
    let tint: Color
    let recipeID: UUID
    let onShowStep: (Int) -> Void
    let onEmpty: () -> Void

    @ObservedObject private var store = CookTimerStore.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let timers = store.timers.sorted { left, right in
                // Done first, then whatever finishes next
                let leftDone = left.isDone(at: context.date), rightDone = right.isDone(at: context.date)
                if leftDone != rightDone { return leftDone }
                return (left.pausedRemaining.map { context.date.addingTimeInterval($0) } ?? left.end)
                    < (right.pausedRemaining.map { context.date.addingTimeInterval($0) } ?? right.end)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(timers.count == 1 ? "Timer" : "Timers")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                ForEach(Array(timers.enumerated()), id: \.element.id) { offset, timer in
                    if offset > 0 { Divider() }
                    row(timer, now: context.date)
                }
            }
            .padding(16)
            .frame(minWidth: 280)
        }
        .onChange(of: store.timers.isEmpty) { _, empty in
            if empty { onEmpty() }
        }
    }

    private func row(_ timer: CookTimer, now: Date) -> some View {
        let done = timer.isDone(at: now)
        let here = timer.recipeID == recipeID
        let detail = here ? "Step \(timer.step + 1) · \(timer.label)" : "\(timer.recipeTitle) · Step \(timer.step + 1)"
        return HStack(spacing: 12) {
            Button {
                if here { onShowStep(timer.step) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: done ? "bell.fill" : timer.isPaused ? "pause.fill" : "timer")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timer.remainingText(at: now))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text(timer.isPaused ? "Paused · \(detail)" : detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!here)
            .accessibilityLabel("\(detail), \(done ? "done" : "\(timer.remainingText(at: now)) left")")
            .accessibilityHint(here ? "Goes to step \(timer.step + 1)" : "")

            // Stopping is a deliberate tap on its own button; nothing else
            // ends a timer
            Button(done ? "Clear" : "Stop") { store.stop(timer) }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(done ? tint : .red)
                .accessibilityLabel(done ? "Clear step \(timer.step + 1) timer" : "Stop step \(timer.step + 1) timer")
        }
        .padding(.vertical, 10)
    }
}
