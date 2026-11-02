import Analyse
import Foundation
import Stockage
import Testing
import Transcription

private let segments = [
    Segment(debut: 10, fin: 14, piste: .micro, texte: "On valide la version longue."),
    Segment(debut: 20, fin: 25, piste: .systeme, texte: "Marie envoie la musique avant vendredi."),
]

private let citationMarie = "Marie envoie la musique avant vendredi."

@Test func unElementSansHorodatageEstEcarte() {
    #expect(ValidationSources.valider(ElementSource(texte: "Décision", sources: [], citation: "On valide la version longue."), dans: segments) == nil)
}

@Test func unHorodatageQuiNExistePasEstEcarte() {
    #expect(ValidationSources.valider(ElementSource(texte: "Décision", sources: [500], citation: "On valide la version longue."), dans: segments) == nil)
}

@Test func uneCitationIntrouvableEstEcartee() {
    let element = ElementSource(texte: "Décision", sources: [11], citation: "On annule tout le projet.")
    #expect(ValidationSources.valider(element, dans: segments) == nil)
}

@Test func uneCitationVideEstEcartee() {
    #expect(ValidationSources.valider(ElementSource(texte: "Décision", sources: [11]), dans: segments) == nil)
    #expect(ValidationSources.valider(ElementSource(texte: "Décision", sources: [11], citation: " ... "), dans: segments) == nil)
}

@Test func uneCitationAilleursQuAuMomentCiteEstEcartee() {
    let element = ElementSource(texte: "Envoyer la musique", sources: [11], citation: citationMarie)
    #expect(ValidationSources.valider(element, dans: segments) == nil)
}

@Test func uneCitationDoitTomberSurDesMotsEntiers() {
    let element = ElementSource(texte: "Décision", sources: [11], citation: "alide la version")
    #expect(ValidationSources.valider(element, dans: segments) == nil)
}

@Test func uneCitationExacteEstGardeeMalgreLaCasseEtLaPonctuation() throws {
    let element = ElementSource(texte: "Version longue", sources: [11], citation: "on valide la VERSION longue")
    #expect(try #require(ValidationSources.valider(element, dans: segments)).citation != nil)
}

@Test func uneReformulationFausseNEstJamaisRendue() throws {
    let element = ElementSource(texte: "On ne valide pas la version longue.", sources: [11], citation: "On valide la version longue.")
    #expect(try #require(ValidationSources.valider(element, dans: segments)).texte == "On valide la version longue.")
}

@Test func uneCitationTronqueeRendLaPhraseEntiere() throws {
    let negation = [Segment(debut: 10, fin: 14, piste: .micro, texte: "On ne valide pas la version longue. Autre sujet.")]
    let element = ElementSource(texte: "Validé", sources: [11], citation: "valide pas la version longue")
    let valide = try #require(ValidationSources.valider(element, dans: negation))
    #expect(valide.texte == "On ne valide pas la version longue.")
    #expect(valide.citation == valide.texte)
}

@Test func uneSourceSansLaCitationEstRetiree() throws {
    let element = ElementSource(texte: "Décision", sources: [11, 21], citation: "On valide la version longue.")
    #expect(try #require(ValidationSources.valider(element, dans: segments)).sources == [11])
}

@Test func unResponsableDitAilleursQueDansLaPhraseEstRetire() throws {
    let voisins = [Segment(debut: 10, fin: 12, piste: .micro, texte: "Paul est en retard."),
                   Segment(debut: 12, fin: 14, piste: .micro, texte: "On envoie la musique lundi.")]
    let element = ElementSource(texte: "Envoyer", sources: [13], citation: "On envoie la musique lundi.", responsable: "Paul", echeance: "lundi")
    let valide = try #require(ValidationSources.valider(element, dans: voisins))
    #expect(valide.responsable == nil)
    #expect(valide.echeance == "lundi")
}

@Test func uneAnalyseEnregistreeRepasseLaValidation() {
    let ancienne = CompteRendu(fournisseur: "Test", decisions: [
        ElementSource(texte: "On ne valide pas.", sources: [11], citation: "On valide la version longue."),
        ElementSource(texte: "Sans preuve", sources: [11], citation: "On annule tout."),
    ], actions: [], questions: [])
    let relue = ancienne.revalide(dans: segments)
    #expect(relue.decisions.map(\.texte) == ["On valide la version longue."])
    #expect(relue.decisions.first?.id == ancienne.decisions.first?.id)
    #expect(relue.elementsEcartes == 1)
}

@Test func unResponsableOuUneEcheanceNonDitsSontRetires() throws {
    let element = ElementSource(texte: "Envoyer la musique", sources: [21], citation: citationMarie, responsable: "Paul", echeance: "lundi")
    let valide = try #require(ValidationSources.valider(element, dans: segments))
    #expect(valide.responsable == nil)
    #expect(valide.echeance == nil)
}

@Test func unResponsableEtUneEcheanceDitsSontGardes() throws {
    let element = ElementSource(texte: "Envoyer la musique", sources: [21], citation: citationMarie, responsable: "Marie", echeance: "vendredi")
    let valide = try #require(ValidationSources.valider(element, dans: segments))
    #expect(valide.responsable == "Marie")
    #expect(valide.echeance == "vendredi")
}

@Test func leResumeNeDitQueLesElementsValidesAvecLeursSources() {
    let compteRendu = CompteRendu(fournisseur: "Test",
                                  decisions: [ElementSource(texte: "Garder la version longue.", sources: [250])],
                                  actions: [ElementSource(texte: "Envoyer la musique", sources: [1410, 1500])],
                                  questions: [])
    #expect(compteRendu.resume == "Décision : Garder la version longue (04:10). Action : Envoyer la musique (23:30, 25:00).")
}

@Test func leResumeDitCeQuIlNeMontrePas() {
    let decisions = (1...5).map { ElementSource(texte: "D\($0)", sources: [Double($0)]) }
    let compteRendu = CompteRendu(fournisseur: "Test", decisions: decisions, actions: [], questions: [])
    #expect(compteRendu.resume == "Décisions : D1 (00:01) ; D2 (00:02) ; D3 (00:03), et 2 de plus.")
}

@Test func unResumeSansElementValideNInventeRien() {
    let compteRendu = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [])
    #expect(compteRendu.resume == "Aucun élément vérifié obtenu.")
    let partiel = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [], passagesNonAnalyses: 2)
    #expect(partiel.resume == "Aucun élément vérifié obtenu. 2 passages non analysés.")
}

@Test func uneAncienneAnalyseSeRelitSansSonResumeLibre() throws {
    let ancienne = #"{"fournisseur":"Test","date":"2026-11-02T14:00:00Z","resume":"Un résumé libre, non vérifié.","decisions":[],"actions":[],"questions":[],"passagesNonAnalyses":0,"elementsEcartes":0}"#
    let decodeur = JSONDecoder()
    decodeur.dateDecodingStrategy = .iso8601
    let relue = try decodeur.decode(CompteRendu.self, from: Data(ancienne.utf8))
    #expect(!relue.resume.contains("libre"))
}

/// Analyse le fichier de APARTE_AUDIO_REFERENCE. N'affiche que des nombres, jamais le contenu de la réunion.
@Test(.enabled(if: ProcessInfo.processInfo.environment["APARTE_AUDIO_REFERENCE"] != nil))
func analyseLeFichierDeReference() async throws {
    let chemin = try #require(ProcessInfo.processInfo.environment["APARTE_AUDIO_REFERENCE"])
    let segments = try await TranscripteurFichier.transcrire(url: URL(fileURLWithPath: chemin), piste: .micro)
    let compteRendu = try await AnalysteLocal().analyser(segments: segments, notes: [], type: .presentiel, progression: { _ in })
    let elements = compteRendu.decisions + compteRendu.actions + compteRendu.questions
    #expect(elements.allSatisfy { ValidationSources.valider($0, dans: segments) != nil })
    print("resume: \(compteRendu.resume.count) car., decisions: \(compteRendu.decisions.count), actions: \(compteRendu.actions.count), questions: \(compteRendu.questions.count), ecartes: \(compteRendu.elementsEcartes), passages non analyses: \(compteRendu.passagesNonAnalyses)")
}

@Test func unBlancAudioSeDitDansCeQuiSeCopie() {
    let compteRendu = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [])
    let incidents = [IncidentAudio(piste: "micro", debut: 40, fin: 52)]
    #expect(compteRendu.texteACopier(incidents: incidents).contains("Audio incomplet : micro coupé de 00:40 à 00:52."))
    #expect(compteRendu.markdown(incidents: incidents).contains("Audio incomplet"))
    #expect(!compteRendu.texteACopier().contains("Audio incomplet"))
}
