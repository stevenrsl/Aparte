import Foundation
import Testing
import Transcription
@testable import Analyse

// Règle 1 : un responsable n'apparaît que s'il a été dit, ou s'il est la voix qui le dit.
private let segments = [
    Segment(debut: 0, fin: 4, piste: .systeme, texte: "Je m'occupe d'envoyer le contrat.", voix: "Voix 1"),
    Segment(debut: 5, fin: 9, piste: .systeme, texte: "Très bien, merci.", voix: "Voix 2"),
]
private let noms = ["Voix 1": "Clémence", "Voix 2": "Marc"]

private func action(_ responsable: String) -> ElementSource {
    ElementSource(texte: "Envoyer le contrat", sources: [0], citation: "Je m'occupe d'envoyer le contrat.", responsable: responsable)
}

@Test func leNomDeLaVoixQuiParleEstUnResponsable() {
    #expect(ValidationSources.valider(action("Clémence"), dans: segments, noms: noms)?.responsable == "Clémence")
}

@Test func unAutreParticipantNommeNEstPasResponsable() {
    // Marc parle juste après, et sa voix a un nom : il n'a pourtant rien pris en charge.
    let valide = ValidationSources.valider(action("Marc"), dans: segments, noms: noms)
    #expect(valide != nil)
    #expect(valide?.responsable == nil)
}

@Test func unNomQuiNeParlePasNePassePasALaRelecture() {
    let rendu = CompteRendu(fournisseur: "Local", decisions: [], actions: [action("Marc")], questions: [])
        .revalide(dans: segments, noms: ["Voix 1": "Clémence", "Voix 3": "Marc"])
    #expect(rendu.actions.first?.responsable == nil)
}

@Test func uneReformulationNeNommePasUnParticipantAbsent() {
    let element = ElementSource(texte: "Sophie envoie le contrat", sources: [0], citation: "Je m'occupe d'envoyer le contrat.")
    let valide = ValidationSources.valider(element, dans: segments, noms: ["Voix 1": "Clémence", "Voix 9": "Sophie"])
    #expect(valide?.texte == "Je m'occupe d'envoyer le contrat.")
}
