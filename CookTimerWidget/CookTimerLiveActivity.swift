import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct CookTimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        CookTimerLiveActivity()
    }
}

/// A cook mode timer's countdown on the lock screen and in the Dynamic
/// Island. AlarmKit runs the timer and rings it; this only draws it.
struct CookTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<CookTimerMetadata>.self) { context in
            LockScreenTimerView(context: context)
                .widgetURL(context.attributes.metadata?.url)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Step \(context.attributes.metadata?.stepNumber ?? 0)", systemImage: "timer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(state: context.state)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.metadata?.recipeTitle ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        TimerButtons(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                CountdownText(state: context.state)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(.orange)
            }
            .widgetURL(context.attributes.metadata?.url)
            .keylineTint(.orange)
        }
    }
}

private struct LockScreenTimerView: View {
    let context: ActivityViewContext<AlarmAttributes<CookTimerMetadata>>

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cookbo · Step \(context.attributes.metadata?.stepNumber ?? 0)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(context.attributes.metadata?.recipeTitle ?? "")
                    .font(.headline)
                    .lineLimit(1)
                CountdownText(state: context.state)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 8)
            TimerButtons(state: context.state)
        }
        .padding(16)
    }
}

/// Counts down while running; shows what's left while paused.
private struct CountdownText: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(timerInterval: countdown.startDate...countdown.fireDate, countsDown: true)
                .monospacedDigit()
        case .paused(let paused):
            Text(Duration.seconds(max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration))
                .formatted(.time(pattern: .minuteSecond)))
                .monospacedDigit()
        default:
            Text("Done")
        }
    }
}

private struct TimerButtons: View {
    let state: AlarmPresentationState

    var body: some View {
        HStack(spacing: 10) {
            switch state.mode {
            case .countdown:
                Button(intent: PauseCookTimerIntent(id: state.alarmID)) {
                    Image(systemName: "pause.fill")
                }
                .tint(.orange)
                .accessibilityLabel("Pause timer")
            case .paused:
                Button(intent: ResumeCookTimerIntent(id: state.alarmID)) {
                    Image(systemName: "play.fill")
                }
                .tint(.orange)
                .accessibilityLabel("Resume timer")
            default:
                EmptyView()
            }
            Button(intent: StopCookTimerIntent(id: state.alarmID)) {
                Image(systemName: "xmark")
            }
            .tint(.gray)
            .accessibilityLabel("Stop timer")
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .controlSize(.large)
    }
}
