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

private func seg(_ debut: Double, _ piste: Piste, _ texte: String, fin: Double? = nil, voix: String? = nil) -> Segment {
    Segment(debut: debut, fin: fin ?? debut + 4, piste: piste, texte: texte, voix: voix)
}

@Test func lEchoDuHautParleurQuitteLaPisteDuMicro() {
    let segments = [
        seg(10, .systeme, "On décide de garder la version longue pour le festival."),
        seg(12, .micro, "On décide de garder la version longue pour le festival."),
        seg(30, .micro, "Je ne suis pas du tout d'accord avec cette idée."),
    ]
    #expect(Nettoyage.sansEcho(segments).map(\.texte) == [
        "On décide de garder la version longue pour le festival.",
        "Je ne suis pas du tout d'accord avec cette idée.",
    ])
}

@Test func cQueJeDisEntreDeuxEchosResteDansLaPisteDuMicro() throws {
    let segments = [
        seg(10, .systeme, "On décide de garder la version longue."),
        seg(12, .micro, "On décide de garder moi je préfère vraiment la courte franchement la version longue."),
    ]
    let micro = try #require(Nettoyage.sansEcho(segments).first { $0.piste == .micro })
    #expect(micro.texte.contains("préfère vraiment la courte"))
    #expect(!micro.texte.contains("décide"))
}

@Test func deuxPersonnesQuiDisentDesChosesLointainesNeSontPasDeLEcho() {
    let segments = [seg(10, .systeme, "On garde la version longue."), seg(200, .micro, "On garde la version longue.")]
    #expect(Nettoyage.sansEcho(segments).count == 2)
}

@Test func lesPhrasesDUneMemePersonneSeReunissent() {
    let fusion = Nettoyage.fusionner([
        seg(0, .systeme, "Bonjour.", fin: 2, voix: "Voix 1"),
        seg(3, .systeme, "Ça va ?", fin: 4, voix: "Voix 1"),
        seg(5, .systeme, "Très bien.", fin: 6, voix: "Voix 2"),
        seg(20, .systeme, "Parfait.", fin: 21, voix: "Voix 2"),
    ])
    #expect(fusion.map(\.texte) == ["Bonjour. Ça va ?", "Très bien.", "Parfait."])
}

@Test func unNomProcheEstCorrigeAvecPrudence() {
    #expect(Nettoyage.corrigerNoms("On parle de Lumena demain.", noms: ["Lumina"]) == "On parle de Lumina demain.")
    #expect(Nettoyage.corrigerNoms("Le projet lumena avance.", noms: ["Lumina"]) == "Le projet lumena avance.")
    #expect(Nettoyage.corrigerNoms("On passe à Montreal.", noms: ["Belleville"]) == "On passe à Montreal.")
    #expect(Nettoyage.corrigerNoms("Paul arrive.", noms: ["Pauline"]) == "Paul arrive.")
}

private func mots(_ textes: [String], depuis debut: Double) -> [Mot] {
    textes.enumerated().map { Mot(texte: $0.element + " ", debut: debut + Double($0.offset), fin: debut + Double($0.offset) + 0.8) }
}

@Test func unePhraseSeCoupeLaOuLaVoixChange() {
    let phrase = mots(["Tu", "viens", "demain.", "Oui", "bien", "sûr"], depuis: 0)
    let tours = [TourDeVoix(voix: "Voix 1", debut: 0, fin: 2.9), TourDeVoix(voix: "Voix 2", debut: 2.9, fin: 6)]
    let segments = Attribution.attribuer([phrase], a: tours, piste: .systeme)
    #expect(segments.map(\.texte) == ["Tu viens demain.", "Oui bien sûr"])
    #expect(segments.map(\.voix) == ["Voix 1", "Voix 2"])
}

@Test func uneSeuleVoixNeDistinguePersonne() {
    let tours = [TourDeVoix(voix: "Voix 1", debut: 0, fin: 6)]
    #expect(Attribution.attribuer([mots(["Bonjour", "à", "tous"], depuis: 0)], a: tours, piste: .micro).first?.voix == nil)
}

@Test func uneVoixTropBreveDisparaitEtLesAutresSeNumerotent() {
    let nommes = Attribution.nommes([
        TourDeVoix(voix: "b", debut: 0, fin: 5), TourDeVoix(voix: "toux", debut: 5, fin: 6), TourDeVoix(voix: "a", debut: 6, fin: 12),
    ])
    #expect(nommes.map(\.voix) == ["Voix 1", "Voix 2"])
}
