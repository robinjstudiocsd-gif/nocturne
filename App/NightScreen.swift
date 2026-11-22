import SwiftUI

/// Écran de nuit de la phase 0 : très sombre ou en lumière rouge, arrêt par appui long.
struct NightScreen: View {
    @ObservedObject var lab: LabModel
    @ObservedObject var recorder: NightRecorder
    @ObservedObject var alarm: AlarmController
    @State private var redLight = false

    var body: some View {
        let main = redLight ? Theme.red : Theme.nightClock
        let dim = redLight ? Theme.red : Theme.nightDim
        ZStack {
            (redLight ? Color.black : Theme.nightScreen)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Text(alarm.isRinging ? "Réveil" : "Nuit en cours · mode continu")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(dim)
                if let start = recorder.startDate {
                    Text("Écoute depuis \(Format.time(start)) · \(recorder.segmentCount) tranches")
                        .font(.subheadline)
                        .foregroundStyle(main)
                }
                Spacer()
                TimelineView(.everyMinute) { context in
                    Text(Format.time(context.date))
                        .font(.system(size: 84, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(alarm.isRinging ? Theme.amber : main)
                }
                if let next = alarm.nextAlarm {
                    Label("Réveil \(Format.time(next))", systemImage: "alarm")
                        .foregroundStyle(main)
                }
                LevelBar(levelDb: recorder.levelDb, color: dim)
                    .frame(width: 160, height: 4)
                Spacer()
                if recorder.needsResume {
                    Button("Reprendre l’écoute") {
                        recorder.resume(automatic: false)
                    }
                    .buttonStyle(.bordered)
                    .tint(main)
                }
                if alarm.isRinging {
                    Button {
                        lab.stopNight(reason: "réveil")
                    } label: {
                        Text("Je suis réveillé")
                            .font(.headline)
                            .foregroundStyle(Theme.night)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.amber)
                } else {
                    HoldToStopButton(color: main, dim: dim) {
                        lab.stopNight(reason: "arrêt manuel")
                    }
                }
                Button(redLight ? "Lumière normale" : "Lumière rouge") {
                    redLight.toggle()
                }
                .font(.footnote)
                .foregroundStyle(dim)
                .frame(minHeight: 44)
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }
}

struct LevelBar: View {
    let levelDb: Float
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let fraction = CGFloat(max(0, min(1, (levelDb + 70) / 60)))
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.25))
                Capsule().fill(color).frame(width: geometry.size.width * fraction)
            }
        }
        .accessibilityLabel("Niveau sonore")
    }
}

struct HoldToStopButton: View {
    let color: Color
    let dim: Color
    let action: () -> Void
    @State private var pressing = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(dim.opacity(0.5), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: pressing ? 1 : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: pressing ? 1.5 : 0.2), value: pressing)
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: 22, height: 22)
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: 1.5, perform: action, onPressingChanged: { pressing = $0 })
            Text("Maintenir pour arrêter")
                .font(.footnote)
                .foregroundStyle(dim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Arrêter la nuit")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
