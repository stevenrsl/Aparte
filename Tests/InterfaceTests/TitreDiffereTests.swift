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

@Test @MainActor func titreBlancGardeLeTitreExistant() async throws {
    let racine = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: racine) }
    let bibliotheque = Bibliotheque(racine: racine)
    let reunion = try bibliotheque.creerReunion(titre: "Avant", type: .presentiel, dossier: nil)
    let session = SessionReunion(reunion: reunion)
    session.titre = " \n "
    _ = try await session.terminer()
    let resultat = try session.appliquerTitre(dans: bibliotheque)
    #expect(resultat.url == reunion.url)
    #expect(resultat.meta.titre == "Avant")
    #expect(session.captureArretee)
}

@Test @MainActor func renommagePeutEtreRetenteApresEchec() async throws {
    let racine = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: racine) }
    let bibliotheque = Bibliotheque(racine: racine)
    let reunion = try bibliotheque.creerReunion(titre: "Avant", type: .presentiel, dossier: nil)
    let session = SessionReunion(reunion: reunion)
    session.titre = "Après"
    _ = try await session.terminer()
    let temporaire = racine.appendingPathComponent("temporaire")
    try FileManager.default.moveItem(at: reunion.url, to: temporaire)
    #expect(throws: (any Error).self) { try session.appliquerTitre(dans: bibliotheque) }
    #expect(session.captureArretee)
    try FileManager.default.moveItem(at: temporaire, to: reunion.url)
    _ = try await session.terminer()
    let resultat = try session.appliquerTitre(dans: bibliotheque)
    #expect(resultat.meta.titre == "Après")
}

@Test @MainActor func finalisationConcurrenteAttendLaTranscription() async throws {
    let racine = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: racine) }
    let bibliotheque = Bibliotheque(racine: racine)
    let reunion = try bibliotheque.creerReunion(titre: "Avant", type: .presentiel, dossier: nil)
    let session = SessionReunion(reunion: reunion)
    session.titre = "Après"
    var suspension: CheckedContinuation<Void, Never>?
    session.terminerTranscriptionSimulee = { await withCheckedContinuation { suspension = $0 } }
    let premiere = Task { try await session.terminer() }
    while suspension == nil { await Task.yield() }
    #expect(session.finalisationEnCours)
    await #expect(throws: (any Error).self) { _ = try await session.terminer() }
    #expect(throws: (any Error).self) { try session.appliquerTitre(dans: bibliotheque) }
    #expect(FileManager.default.fileExists(atPath: reunion.url.path))
    suspension?.resume()
    _ = try await premiere.value
    #expect(!session.finalisationEnCours)
    _ = try await session.terminer()
    #expect(try session.appliquerTitre(dans: bibliotheque).meta.titre == "Après")
}

@Test func demandesSuccessivesVersLaMemeLigneSontDistinctes() {
    let id = UUID()
    #expect(CibleDefilement(id: id) != CibleDefilement(id: id))
}
