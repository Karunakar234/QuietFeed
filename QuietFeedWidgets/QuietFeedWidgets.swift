import SwiftUI
import WidgetKit

/// One moment in the Focus widget's timeline: a session running until `endDate`, or none.
struct FocusEntry: TimelineEntry {
    let date: Date
    let endDate: Date?
    let isEnabled: Bool
}

struct FocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusEntry {
        FocusEntry(date: .now, endDate: .now.addingTimeInterval(25 * 60), isEnabled: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    /// The countdown runs on its own (`Text(timerInterval:)`), so the timeline needs only the
    /// running entry and, at the end time, the idle one. The app reloads it on start and stop.
    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusEntry>) -> Void) {
        let now = Date.now
        let entry = currentEntry(now: now)
        var entries = [entry]
        if let end = entry.endDate {
            entries.append(FocusEntry(date: end, endDate: nil, isEnabled: entry.isEnabled))
        }
        completion(Timeline(entries: entries, policy: .never))
    }

    private func currentEntry(now: Date = .now) -> FocusEntry {
        let enabled = FocusShared.isEnabled
        return FocusEntry(date: now, endDate: enabled ? FocusShared.activeEndDate(now: now) : nil, isEnabled: enabled)
    }
}

struct FocusWidgetView: View {
    let entry: FocusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            if let end = entry.endDate {
                Label {
                    Text(timerInterval: entry.date...end, countsDown: true)
                } icon: {
                    Image(systemName: "leaf.fill")
                }
            } else {
                Label("No focus session", systemImage: "leaf")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if let end = entry.endDate {
                    VStack(spacing: 0) {
                        Image(systemName: "leaf.fill").font(.caption)
                        Text(timerInterval: entry.date...end, countsDown: true)
                            .font(.caption2.monospacedDigit())
                            .multilineTextAlignment(.center)
                    }
                    .padding(4)
                } else {
                    Image(systemName: "leaf")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(entry.endDate == nil ? "No focus session" : "Focus session running")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Focus", systemImage: entry.endDate == nil ? "leaf" : "leaf.fill")
                    .font(.headline)
                if let end = entry.endDate {
                    Text(timerInterval: entry.date...end, countsDown: true)
                        .font(.title3.monospacedDigit())
                } else {
                    Text(entry.isEnabled ? "No session running" : "Focus Mode is off")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            homeScreenView
        }
    }

    private var homeScreenView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Focus", systemImage: entry.endDate == nil ? "leaf" : "leaf.fill")
                .font(.headline)
                .foregroundStyle(FocusWidgetStyle.teal)
            Spacer(minLength: 0)
            if let end = entry.endDate {
                Text(timerInterval: entry.date...end, countsDown: true)
                    .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                Text("remaining")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                Text(entry.isEnabled ? "No session running" : "Focus Mode is off")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if entry.isEnabled {
                    Text("Start one in QuietFeed or with Siri.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// The app's neon look, on its fixed dark backdrop (white text stays readable on it in both
/// appearances: 19.6:1 on navy).
enum FocusWidgetStyle {
    static let teal = Color(red: 0.36, green: 0.95, blue: 0.85)
    static let background = LinearGradient(
        colors: [Color(red: 0.03, green: 0.04, blue: 0.12), Color(red: 0.06, green: 0.03, blue: 0.17)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FocusShared.widgetKind, provider: FocusProvider()) { entry in
            FocusWidgetView(entry: entry)
                .containerBackground(for: .widget) { FocusWidgetStyle.background }
        }
        .configurationDisplayName("Focus")
        .description("Time left in your QuietFeed focus session.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

#Preview(as: .systemSmall) {
    FocusWidget()
} timeline: {
    FocusEntry(date: .now, endDate: .now.addingTimeInterval(18 * 60), isEnabled: true)
    FocusEntry(date: .now, endDate: nil, isEnabled: true)
}
