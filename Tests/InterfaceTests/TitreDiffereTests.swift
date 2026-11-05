import Foundation
import Stockage
import Testing
@testable import Interface

@Test @MainActor func titreAttendLaFinDeLaCapture() async throws {
    let racine = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: racine) }
    let bibliotheque = Bibliotheque(racine: racine)
    let reunion = try bibliotheque.creerReunion(titre: "Avant", type: .presentiel, dossier: nil)
    let session = SessionReunion(reunion: reunion)
    session.titre = "Après"
    #expect(throws: (any Error).self) { try session.appliquerTitre(dans: bibliotheque) }
    #expect(FileManager.default.fileExists(atPath: reunion.url.path))
    #expect(session.reunion.meta.titre == "Avant")
    _ = try await session.terminer()
    let renommee = try session.appliquerTitre(dans: bibliotheque)
    #expect(renommee.meta.titre == "Après")
    #expect(renommee.url != reunion.url)
    #expect(!FileManager.default.fileExists(atPath: reunion.url.path))
    #expect(try bibliotheque.reunions().first?.meta.titre == "Après")
}

@Test @MainActor func echecRenommageDiffereConserveTitreEtSession() async throws {
    let racine = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: racine) }
    let bibliotheque = Bibliotheque(racine: racine)
    let reunion = try bibliotheque.creerReunion(titre: "Avant", type: .presentiel, dossier: nil)
    let session = SessionReunion(reunion: reunion)
    session.titre = "Après"
    _ = try await session.terminer()
    try FileManager.default.removeItem(at: reunion.url)
    #expect(throws: (any Error).self) { try session.appliquerTitre(dans: bibliotheque) }
    #expect(session.titre == "Après")
    #expect(session.reunion.url == reunion.url)
}
