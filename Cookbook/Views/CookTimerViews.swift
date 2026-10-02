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
