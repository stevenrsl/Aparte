import Interface
import SwiftUI

AparteApp.main()

struct AparteApp: App {
    @State private var modele = ModeleApp()
    @NSApplicationDelegateAdaptor(DelegueAparte.self) private var delegue

    var body: some Scene {
        // Une seule fenêtre : la fermer revient à quitter, jamais à enregistrer sans indicateur visible.
        Window("Aparté", id: "principale") {
            FenetreAparte(modele: modele)
                .frame(minWidth: 1180, minHeight: 720)
                .onAppear { delegue.modele = modele }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nouvelle réunion") { modele.preparerReunion() }
                    .keyboardShortcut("n")
                    .disabled(modele.session != nil)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Réglages…") { modele.ecran = .reglages }.keyboardShortcut(",")
            }
            CommandMenu("Présentation") {
                Button("Accueil") { modele.ecran = .accueil }
                Button("Toutes les réunions") { modele.ecran = .toutes }
                Divider()
                Button("Retour") { modele.revenir() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled({ if case .compteRendu = modele.ecran { return false }; if case .nouvelle = modele.ecran { return false }; return true }())
            }
            CommandGroup(after: .newItem) {
                Button("Terminer la réunion") { Task { await modele.terminer() } }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .disabled(modele.session?.debut == nil)
            }
        }
    }
}
