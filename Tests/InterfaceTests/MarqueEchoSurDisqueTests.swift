import Foundation
import Stockage
import Testing
import Transcription
@testable import Interface

// Sans ce test, `ajouter` pourrait afficher « écho probable » en direct sans l'écrire sur le
// disque (régression possible : la mention disparaîtrait si la relecture échoue ou n'a pas
// encore tourné, et l'analyse lirait la ligne comme dite avec certitude).
@MainActor
@Test func laMarqueEchoEstEcriteSurLeDisqueEtSurvitATerminer() async throws {
    let racine = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "R", type: .visio, dossier: nil)
    let session = SessionReunion(reunion: reunion)

    session.ajouter(Segment(debut: 3, fin: 5, piste: .micro, texte: "On décide de ne pas garder la version longue pour le festival."))
    session.ajouter(Segment(debut: 0, fin: 2, piste: .systeme, texte: "On décide de garder la version longue pour le festival."))

    let enMemoire = try #require(session.segments.first { $0.piste == .micro })
    #expect(enMemoire.echoProbable == true)

    let surLeDisque = try #require(reunion.segments().first { $0.piste == .micro })
    #expect(surLeDisque.echoProbable == true)

    let finie = try await session.terminer()
    let apresTerminer = try #require(finie.segments().first { $0.piste == .micro })
    #expect(apresTerminer.echoProbable == true)
}
