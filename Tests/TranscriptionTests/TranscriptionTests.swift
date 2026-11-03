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

@Test func unAncienJsonSansEchoProbableSeDecode() throws {
    let ancien = """
    {"id":"00000000-0000-0000-0000-000000000000","debut":1.5,"fin":3,"piste":"systeme","texte":"Bonjour"}
    """
    let segment = try JSONDecoder().decode(Segment.self, from: Data(ancien.utf8))
    #expect(segment.texte == "Bonjour")
    #expect(segment.echoProbable == nil)
}

private func seg(_ debut: Double, _ piste: Piste, _ texte: String, fin: Double? = nil, voix: String? = nil) -> Segment {
    Segment(debut: debut, fin: fin ?? debut + 4, piste: piste, texte: texte, voix: voix)
}

@Test func lEchoDuHautParleurEstMarqueSansQuAucunMotSoitRetire() {
    let segments = [
        seg(10, .systeme, "On décide de garder la version longue pour le festival."),
        seg(12, .micro, "On décide de garder la version longue pour le festival."),
        seg(30, .micro, "Je ne suis pas du tout d'accord avec cette idée."),
    ]
    let marques = Nettoyage.marquerEcho(segments)
    #expect(marques.map(\.texte) == [
        "On décide de garder la version longue pour le festival.",
        "On décide de garder la version longue pour le festival.",
        "Je ne suis pas du tout d'accord avec cette idée.",
    ])
    #expect(marques.map(\.echoProbable) == [nil, true, nil])
}

/// Le contre-exemple de Codex (issue #16) : l'ancien retrait d'écho pouvait effacer une vraie
/// réponse, y compris une négation. Les mots du micro doivent tous survivre, et la ligne reste
/// marquée comme preuve à prendre avec doute plutôt que retirée.
@Test func leContreExempleDeCodexGardeLaNegationEtMarqueLaLigne() throws {
    let segments = [
        seg(0, .systeme, "On décide de garder la version longue pour le festival.", fin: 2),
        seg(3, .micro, "On décide de ne pas garder la version longue pour le festival.", fin: 5),
        seg(60, .micro, "On passe au point suivant.", fin: 63),
    ]
    let marques = Nettoyage.marquerEcho(segments)
    let reponse = try #require(marques.first { $0.debut == 3 })
    #expect(reponse.texte == "On décide de ne pas garder la version longue pour le festival.")
    #expect(reponse.echoProbable == true)
    let autreMoment = try #require(marques.first { $0.debut == 60 })
    #expect(autreMoment.texte == "On passe au point suivant.")
    #expect(autreMoment.echoProbable == nil)
}

@Test func uneReponseCourteEtUneRepetitionVolontaireSurvivent() {
    let segments = [
        seg(0, .systeme, "On valide le budget.", fin: 2),
        seg(3, .micro, "Non.", fin: 3.5),
        seg(20, .systeme, "On valide le budget.", fin: 22),
        seg(23, .micro, "On valide le budget, je suis d'accord.", fin: 26),
    ]
    let marques = Nettoyage.marquerEcho(segments)
    #expect(marques.first { $0.debut == 3 }?.texte == "Non.")
    let repetition = marques.first { $0.debut == 23 }
    #expect(repetition?.texte == "On valide le budget, je suis d'accord.")
    #expect(repetition?.echoProbable == true)
}

@Test func unSegmentSansMotCommunNEstPasMarque() {
    let segments = [seg(0, .systeme, "On parle du budget.", fin: 2), seg(3, .micro, "Le café est prêt.", fin: 5)]
    #expect(Nettoyage.marquerEcho(segments).map(\.echoProbable) == [nil, nil])
}

@Test func deuxPersonnesQuiDisentDesChosesLointainesNeSontPasMarquees() {
    let segments = [seg(10, .systeme, "On garde la version longue."), seg(200, .micro, "On garde la version longue.")]
    let marques = Nettoyage.marquerEcho(segments)
    #expect(marques.count == 2)
    #expect(marques.map(\.echoProbable) == [nil, nil])
}

@Test func laFusionNeMelangePasUneLigneMarqueeEtUneLigneNonMarquee() {
    var echo = seg(0, .micro, "On décide de ne pas garder la version.", fin: 2)
    echo.echoProbable = true
    let suite = seg(2.5, .micro, "Et on passe au point suivant.", fin: 5)
    #expect(Nettoyage.fusionner([echo, suite]).count == 2)
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
