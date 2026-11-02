import Interface
import SwiftUI

AparteApp.main()

struct AparteApp: App {
    @State private var modele = ModeleApp()

    var body: some Scene {
        WindowGroup("Aparté") {
            FenetreAparte(modele: modele)
                .frame(minWidth: 1180, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nouvelle réunion") { modele.ecran = .nouvelle }
                    .keyboardShortcut("n")
                    .disabled(modele.session != nil)
            }
        }
    }
}
