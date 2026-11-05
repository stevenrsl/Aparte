import Analyse
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

@MainActor
@Test func lesActionsSontRangeesSansInventerDeDate() throws {
    let racine = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "Point", type: .visio, dossier: nil)
    func action(_ texte: String, _ echeance: String?) -> ActionOuverte {
        ActionOuverte(reunion: reunion, element: ElementSource(texte: texte, sources: [1], citation: texte, echeance: echeance))
    }
    let actions = [action("A", nil), action("B", "vendredi"), action("C", "  "), action("D", "avant le 12")]
    let rangees = rangerActions(actions)
    #expect(rangees.avecEcheance.map(\.element.texte) == ["B", "D"])
    #expect(rangees.sansEcheance.map(\.element.texte) == ["A", "C"])
    #expect(rangees.avecEcheance.first?.element.echeance == "vendredi")

    #expect(phraseEtat(actions: [], derniere: nil, enCours: nil) == "Aucune action ouverte. Pas encore de réunion.")
    #expect(phraseEtat(actions: [action("B", "vendredi")], derniere: nil, enCours: "Point").hasPrefix("Réunion en cours : Point. 1 action ouverte."))
    #expect(phraseEtat(actions: actions, derniere: nil, enCours: nil).hasPrefix("4 actions ouvertes, dont 2 sans échéance."))
    #expect(phraseEtat(actions: [], derniere: reunion, enCours: nil).contains("Dernière réunion : Point, "))
}
