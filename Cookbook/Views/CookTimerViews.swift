import SwiftUI

/// A running timer, compact: for cook mode's top bar, the recipe page and the
/// recipe list. Stopping it takes a confirmation, so a stray tap can't end
/// it; a finished timer clears with one tap.
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

/// The current step's timer in cook mode, large enough to read across the
/// kitchen.
struct CookTimerBar: View {
    let timer: CookTimer
    let tint: Color

    @State private var confirmingStop = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let done = timer.isDone(at: context.date)
            Button {
                if done { CookTimerStore.shared.stop(timer) } else { confirmingStop = true }
            } label: {
                HStack {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(timer.remainingText(at: context.date))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text(done ? "\(timer.label) · Tap to clear" : "of \(timer.label)")
                            .font(.footnote)
                            .foregroundStyle(done ? Color.white.opacity(0.85) : Color.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: done ? "xmark" : "stop.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(done ? tint : .white)
                        .frame(width: 32, height: 32)
                        .background(done ? Color.white : tint, in: Circle())
                }
                .foregroundStyle(done ? Color.white : Color.primary)
                .padding(.leading, 18)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(done ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.18)), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Timer done. Clear" : "Timer, \(timer.remainingText(at: context.date)) left. Stop")
        }
        .stopTimerConfirmation(timer, isPresented: $confirmingStop)
    }
}

/// Every running timer, from any recipe, for the recipe list.
struct RunningTimersRow: View {
    @ObservedObject private var timerStore = CookTimerStore.shared
    @EnvironmentObject private var store: RecipeStore

    var body: some View {
        if !timerStore.timers.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(timerStore.timers) { timer in
                        CookTimerPill(timer: timer, tint: tint(for: timer), showsRecipe: true)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func tint(for timer: CookTimer) -> Color {
        if let recipe = store.recipes.first(where: { $0.id == timer.recipeID }),
           let category = store.category(for: recipe) {
            return category.color
        }
        return .accentColor
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
