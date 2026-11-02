import Foundation
import Stockage
import Testing
import Transcription
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

@MainActor
@Test func uneAutreEcritureNeMasquePasDesNotesEnAttente() throws {
    let racine = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "R", type: .presentiel, dossier: nil)
    let session = SessionReunion(reunion: reunion)

    // Seules les notes ne peuvent plus s'écrire : un dossier non vide occupe leur place.
    let notes = reunion.url.appendingPathComponent("notes.md")
    try? FileManager.default.removeItem(at: notes)
    try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: notes.appendingPathComponent("bloque"))
    let ligne = try #require(session.lignes.first)
    session.changer(ligne.id, texte: "Une note précieuse")
    #expect(session.alerte != nil)

    session.ajouter(Segment(debut: 1, fin: 2, piste: .micro, texte: "Un mot"))
    #expect(reunion.segments().count == 1)
    #expect(session.alerte != nil)

    // La place se libère : la sauvegarde suivante écrit aussi les notes, et l'alerte part.
    try FileManager.default.removeItem(at: notes)
    session.ajouter(Segment(debut: 3, fin: 4, piste: .micro, texte: "Encore"))
    #expect(session.alerte == nil)
    #expect(reunion.notes().first?.texte == "Une note précieuse")
}
