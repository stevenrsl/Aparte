import Foundation
import Stockage
import Testing
@testable import Interface

@MainActor
@Test func chaqueEchecDeRecuperationEstSignale() throws {
    let racine = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let bibliotheque = Bibliotheque(racine: racine)
    for titre in ["Fictive A", "Fictive B"] {
        let reunion = try bibliotheque.creerReunion(titre: titre, type: .presentiel, dossier: nil)
        try Data().write(to: reunion.microEnCours)
    }

    setenv("APARTE_RACINE", racine.path, 1)
    defer { unsetenv("APARTE_RACINE") }
    let modele = ModeleApp()
    #expect(modele.erreur?.contains("Fictive A") == true)
    #expect(modele.erreur?.contains("Fictive B") == true)
    modele.erreur = nil
    modele.recharger()
    #expect(modele.erreur == nil)
}
