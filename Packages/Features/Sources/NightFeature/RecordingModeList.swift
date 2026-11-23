import DesignSystem
import SleepDomain
import SwiftUI

/// Choix du mode d'écoute ; le choix reste celui des nuits suivantes.
struct RecordingModeList: View {
    @Binding var selection: RecordingMode
    let retentionNights: Int

    var body: some View {
        List {
            Section {
                ForEach(RecordingMode.allCases, id: \.self) { mode in
                    Button {
                        selection = mode
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NightText.modeTitle(mode))
                                    .font(.body)
                                    .foregroundStyle(NocturneColor.textPrimary)
                                Text(NightText.modeDescription(mode, retention: retentionNights))
                                    .font(.footnote)
                                    .foregroundStyle(NocturneColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            if selection == mode {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(NocturneColor.lavender)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == mode ? .isSelected : [])
                }
            } footer: {
                Text("Le mode choisi reste celui des nuits suivantes. Micro ouvert, le niveau sonore est noté chaque seconde, quel que soit le mode.")
                    .foregroundStyle(NocturneColor.textSecondary)
            }
            .listRowBackground(NocturneColor.card)
        }
        .scrollContentBackground(.hidden)
        .background(NocturneColor.night)
        .navigationTitle("Mode d’écoute")
        .navigationBarTitleDisplayMode(.inline)
    }
}
