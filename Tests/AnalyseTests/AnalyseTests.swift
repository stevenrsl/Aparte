import Analyse
import Foundation
import Testing
import Transcription

private let segments = [
    Segment(debut: 10, fin: 14, piste: .micro, texte: "On valide la version longue."),
    Segment(debut: 20, fin: 25, piste: .systeme, texte: "Marie envoie la musique avant vendredi."),
]

@Test func unElementSansHorodatageEstEcarte() {
    #expect(ValidationSources.valider(ElementSource(texte: "Décision", sources: []), dans: segments) == nil)
}

@Test func unHorodatageQuiNExistePasEstEcarte() {
    #expect(ValidationSources.valider(ElementSource(texte: "Décision", sources: [500]), dans: segments) == nil)
}

@Test func uneCitationIntrouvableEstEcartee() {
    let element = ElementSource(texte: "Décision", sources: [11], citation: "On annule tout le projet.")
    #expect(ValidationSources.valider(element, dans: segments) == nil)
}

@Test func uneCitationExacteEstGardeeMalgreLaCasseEtLaPonctuation() throws {
    let element = ElementSource(texte: "Version longue", sources: [11], citation: "on valide la VERSION longue")
    #expect(try #require(ValidationSources.valider(element, dans: segments)).citation != nil)
}

@Test func unResponsableOuUneEcheanceNonDitsSontRetires() throws {
    let element = ElementSource(texte: "Envoyer la musique", sources: [21], responsable: "Paul", echeance: "lundi")
    let valide = try #require(ValidationSources.valider(element, dans: segments))
    #expect(valide.responsable == nil)
    #expect(valide.echeance == nil)
}

@Test func unResponsableEtUneEcheanceDitsSontGardes() throws {
    let element = ElementSource(texte: "Envoyer la musique", sources: [21], responsable: "Marie", echeance: "vendredi")
    let valide = try #require(ValidationSources.valider(element, dans: segments))
    #expect(valide.responsable == "Marie")
    #expect(valide.echeance == "vendredi")
}
