import DesignSystem
import SwiftUI

/// Ce qui recouvre l'app pendant une session : l'écran de nuit, puis « Bonjour » après l'arrêt.
public struct NightFlowView: View {
    private let model: NightViewModel
    private let onFinished: () -> Void

    public init(model: NightViewModel, onFinished: @escaping () -> Void) {
        self.model = model
        self.onFinished = onFinished
    }

    public var body: some View {
        if let morning = model.morning {
            MorningView(model: morning) {
                model.finishMorning()
                onFinished()
            }
            .transition(.opacity)
        } else {
            NightScreen(model: model)
                .transition(.opacity)
        }
    }
}
