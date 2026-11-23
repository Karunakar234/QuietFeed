#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// The Focus session on the Lock Screen and in the Dynamic Island, counting down to its end.
/// Once the end time passes the activity is stale and reads "Focus complete".
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            lockScreen(context)
                .padding()
                .activityBackgroundTint(Color(red: 0.03, green: 0.04, blue: 0.12))
                .activitySystemActionForegroundColor(FocusWidgetStyle.teal)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Focus", systemImage: "leaf.fill")
                        .foregroundStyle(FocusWidgetStyle.teal)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context)
                        .font(.title3.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.isStale ? "Focus complete" : "Platforms stay paused inside QuietFeed until it ends.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "leaf.fill").foregroundStyle(FocusWidgetStyle.teal)
            } compactTrailing: {
                countdown(context)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "leaf.fill").foregroundStyle(FocusWidgetStyle.teal)
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: context.isStale ? "checkmark.circle.fill" : "leaf.fill")
                .font(.title2)
                .foregroundStyle(FocusWidgetStyle.teal)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.isStale ? "Focus complete" : "Focus session")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("QuietFeed")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
            if !context.isStale {
                countdown(context)
                    .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    @ViewBuilder
    private func countdown(_ context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        if context.isStale {
            Image(systemName: "checkmark")
        } else {
            Text(timerInterval: Date.now...max(Date.now, context.state.endDate), countsDown: true)
        }
    }
}

#Preview("Lock Screen", as: .content, using: FocusActivityAttributes()) {
    FocusLiveActivity()
} contentStates: {
    FocusActivityAttributes.ContentState(endDate: .now.addingTimeInterval(20 * 60))
}
#endif
