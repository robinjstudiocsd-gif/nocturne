import ActivityKit
import SleepDomain
import SwiftUI
import WidgetKit

extension NightActivityAttributes: @retroactive ActivityAttributes {}

/// Live Activity affichée sur l'écran verrouillé pendant la nuit.
struct NightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NightActivityAttributes.self) { context in
            LockScreenNightView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(WidgetPalette.night)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "moon.fill")
                        .foregroundStyle(WidgetPalette.lavender)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let alarm = context.state.alarmDate {
                        Text(alarm, style: .time)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(LockScreenNightView.statusText(context.state))
                }
            } compactLeading: {
                Image(systemName: "moon.fill")
                    .foregroundStyle(WidgetPalette.lavender)
            } compactTrailing: {
                if let alarm = context.state.alarmDate {
                    Text(alarm, style: .time)
                } else {
                    Image(systemName: context.state.isListening ? "waveform" : "moon.zzz")
                }
            } minimal: {
                Image(systemName: "moon.fill")
                    .foregroundStyle(WidgetPalette.lavender)
            }
        }
    }
}

struct LockScreenNightView: View {
    let attributes: NightActivityAttributes
    let state: NightActivityAttributes.ContentState

    static func statusText(_ state: NightActivityAttributes.ContentState) -> String {
        if state.isRinging { return "Réveil en cours" }
        return state.isListening ? "Écoute en cours" : "Nuit en cours, sans écoute"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.isRinging ? "alarm.fill" : "moon.fill")
                .font(.title2)
                .foregroundStyle(state.isRinging ? WidgetPalette.amber : WidgetPalette.lavender)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.kind == .nap ? "Sieste en cours" : "Nuit en cours")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(LockScreenNightView.statusText(state)) depuis \(attributes.startDate.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(WidgetPalette.secondary)
            }
            Spacer(minLength: 8)
            if let alarm = state.alarmDate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Réveil")
                        .font(.caption)
                        .foregroundStyle(WidgetPalette.secondary)
                    Text(alarm, style: .time)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(16)
    }
}
