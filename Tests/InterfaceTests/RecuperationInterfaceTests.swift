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

@MainActor
@Test func uneCoupureResteDansLaReunion() throws {
    let racine = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "R", type: .presentiel, dossier: nil)
    let session = SessionReunion(reunion: reunion)

    session.noterCoupure("micro", coupee: true, a: Date())
    #expect(session.alerte?.contains("plus de son") == true)
    session.noterCoupure("micro", coupee: false, a: Date())
    #expect(session.alerte?.contains("revenu") == true)
    session.signalerAudio("son du Mac")

    let relue = try #require(Bibliotheque(racine: racine).reunions().first)
    let incidents = try #require(relue.meta.incidentsAudio)
    #expect(incidents.count == 2)
    #expect(incidents[0].piste == "micro" && incidents[0].fin != nil)
    #expect(incidents[1].piste == "son du Mac" && incidents[1].fin == nil)
}

@MainActor
@Test func gererUneReunionSuitLEcranAffiche() throws {
    let racine = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let bibliotheque = Bibliotheque(racine: racine)
    let reunion = try bibliotheque.creerReunion(titre: "Fictive", type: .presentiel, dossier: nil)
    setenv("APARTE_RACINE", racine.path, 1)
    defer { unsetenv("APARTE_RACINE") }
    let modele = ModeleApp()

    modele.ecran = .compteRendu(reunion)
    modele.renommer(reunion, en: "Fictive renommée")
    guard case let .compteRendu(renommee) = modele.ecran else { Issue.record("écran perdu"); return }
    #expect(renommee.meta.titre == "Fictive renommée")

    modele.deplacer(renommee, versNouveauDossier: "Clients")
    guard case let .compteRendu(rangee) = modele.ecran else { Issue.record("écran perdu"); return }
    #expect(rangee.dossier == "Clients")
    #expect(modele.dossiers == ["Clients"])

    modele.mettreALaCorbeille(rangee)
    #expect(modele.ecran == .accueil)
    #expect(modele.reunions.isEmpty)
    #expect(modele.erreur == nil)
}

@MainActor
@Test func uneReunionEnCoursNeSeRangePas() throws {
    let racine = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "En cours", type: .presentiel, dossier: nil)
    setenv("APARTE_RACINE", racine.path, 1)
    defer { unsetenv("APARTE_RACINE") }
    let modele = ModeleApp()
    modele.session = SessionReunion(reunion: reunion)
    modele.renommer(reunion, en: "Autre")
    modele.mettreALaCorbeille(reunion)
    #expect(FileManager.default.fileExists(atPath: reunion.url.path))
    #expect(modele.reunions.first?.meta.titre == "En cours")
}
