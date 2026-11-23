import DesignSystem
import SleepDomain
import SwiftUI

/// « Nuit en cours » (maquette E31) : écran très sombre ou rouge, heure, réveil prévu,
/// état de l'écoute, reprise, et arrêt par appui long.
struct NightScreen: View {
    let model: NightViewModel

    var body: some View {
        let palette = model.lighting == .red ? NightScreenPalette.red : NightScreenPalette.dark
        TimelineView(.everyMinute) { context in
            content(at: context.date, palette: palette)
        }
        .background(palette.background.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .alert("Impossible de continuer", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private func content(at moment: Date, palette: NightScreenPalette) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Label {
                    Text(model.nightHeader)
                } icon: {
                    Image(systemName: model.status.mode == .off ? "mic.slash" : "mic")
                }
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(palette.dim)
                Text(model.listeningLine(at: moment))
                    .font(.subheadline)
                    .foregroundStyle(palette.text)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 16)

            VStack(spacing: 6) {
                Text(model.clock(at: moment))
                    .font(NocturneFont.clock(size: 88, weight: .light))
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundStyle(palette.clock)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(model.day(at: moment))
                    .font(.subheadline)
                    .foregroundStyle(palette.dim)
                if let alarm = model.alarmLine(at: moment) {
                    alarmBox(alarm, palette: palette)
                        .padding(.top, 22)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 16)

            if let message = model.cutMessage {
                cutBanner(message, palette: palette)
                    .padding(.bottom, 20)
            }

            HoldToStopButton(title: model.stopTitle, palette: palette) {
                Task { await model.stop() }
            }
            .disabled(model.isStopping)

            Text(model.lockHint)
                .font(.footnote)
                .foregroundStyle(palette.dim)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(palette.text)
    }

    private func alarmBox(_ text: String, palette: NightScreenPalette) -> some View {
        VStack(spacing: 4) {
            Label {
                Text(text)
            } icon: {
                Image(systemName: "alarm")
            }
            .font(.body.weight(.medium))
            .foregroundStyle(palette.text)
            if let detail = model.alarmDetailLine {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(palette.dim)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(palette.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.line, lineWidth: 1))
    }

    private func cutBanner(_ message: String, palette: NightScreenPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await model.resume() }
            } label: {
                Text("Reprendre l’écoute")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.text, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil && model.morning == nil },
            set: { if !$0 { model.alertMessage = nil } }
        )
    }
}

/// Bouton d'arrêt : il faut le maintenir 1,5 s, pour ne pas arrêter la nuit par erreur.
/// Avec VoiceOver, l'action « Arrêter » agit directement.
struct HoldToStopButton: View {
    private let title: String
    private let palette: NightScreenPalette
    private let action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var completions = 0
    private let holdDuration = 1.5

    init(title: String, palette: NightScreenPalette, action: @escaping () -> Void) {
        self.title = title
        self.palette = palette
        self.action = action
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(palette.line, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(palette.text, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(palette.text)
                    .frame(width: 13, height: 13)
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 40) {
                completions += 1
                action()
            } onPressingChanged: { isPressing in
                if isPressing {
                    withAnimation(.linear(duration: holdDuration)) { progress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                }
            }
            Text("Maintenir pour arrêter")
                .font(.footnote)
                .foregroundStyle(palette.dim)
        }
        .sensoryFeedback(.success, trigger: completions)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("Maintiens le bouton appuyé pour arrêter.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            completions += 1
            action()
        }
    }
}
