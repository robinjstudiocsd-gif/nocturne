import DesignSystem
import SleepDomain
import SwiftUI

/// Journal des nuits. Au lot 0 : la liste ; l'ajout, la modification et la fiche de nuit arrivent au lot 1.
public struct JournalView: View {
    @State private var model: JournalViewModel

    public init(model: JournalViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Group {
            if let message = model.errorMessage {
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Lecture impossible", message: message)
            } else if model.sessions.isEmpty && !model.isLoading {
                EmptyStateView(
                    systemImage: "calendar",
                    title: "Journal vide",
                    message: "Chaque nuit enregistrée s'ajoutera ici, avec ses horaires, ses sons et ton ressenti."
                )
            } else {
                List(model.sessions) { session in
                    Text(model.title(for: session))
                        .listRowBackground(NocturneColor.card)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NocturneColor.night)
        .navigationTitle("Journal")
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}
