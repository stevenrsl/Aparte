import Foundation
import Stockage
import Testing
@testable import Interface

@MainActor
@Test func uneReunionNonEcriteResteEnMemoireEtSeReessaie() async throws {
    let racine = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "R", type: .presentiel, dossier: nil)
    let session = SessionReunion(reunion: reunion)

    // Le dossier disparaît : un volume débranché, par exemple.
    let cache = racine.appendingPathExtension("cache")
    try FileManager.default.moveItem(at: racine, to: cache)
    defer { try? FileManager.default.removeItem(at: cache) }
    let ligne = try #require(session.lignes.first)
    session.changer(ligne.id, texte: "Une note précieuse")
    #expect(session.alerte != nil)
    await #expect(throws: (any Error).self) { _ = try await session.terminer() }
    #expect(session.lignes.first?.texte == "Une note précieuse")

    // Il revient : le nouvel essai écrit tout et l'alerte disparaît à la prochaine écriture réussie.
    try FileManager.default.moveItem(at: cache, to: racine)
    let finie = try await session.terminer()
    #expect(finie.notes().first?.texte == "Une note précieuse")
}
