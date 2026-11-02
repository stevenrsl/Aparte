import Foundation
import Testing
import Transcription

/// Lit le fichier désigné par APARTE_AUDIO_REFERENCE, hors du repo, et se saute s'il est absent.
/// N'affiche que des nombres : le contenu d'une vraie réunion ne doit pas sortir du test.
@Test(.enabled(if: ProcessInfo.processInfo.environment["APARTE_AUDIO_REFERENCE"] != nil))
func transcritLeFichierDeReference() async throws {
    let chemin = try #require(ProcessInfo.processInfo.environment["APARTE_AUDIO_REFERENCE"])
    let segments = try await TranscripteurFichier.transcrire(url: URL(fileURLWithPath: chemin), piste: .micro)
    #expect(!segments.isEmpty)
    #expect(zip(segments, segments.dropFirst()).allSatisfy { $0.debut <= $1.debut })
    #expect(segments.allSatisfy { $0.debut <= $0.fin })
    print("segments: \(segments.count), fin: \(Int(segments.last?.fin ?? 0)) s, mots: \(segments.reduce(0) { $0 + $1.texte.split(separator: " ").count })")
}

@Test func unSegmentSeRelitDepuisLeDisque() throws {
    let segment = Segment(debut: 1.5, fin: 3, piste: .systeme, texte: "Bonjour")
    let relu = try JSONDecoder().decode(Segment.self, from: JSONEncoder().encode(segment))
    #expect(relu == segment)
}
