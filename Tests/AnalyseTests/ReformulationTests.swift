import Foundation
import Stockage
import Testing
import Transcription
@testable import Analyse

private let phrases = [
    "Bonjour à tous.",
    "Alors,",
    "Et comment vous voulez avancer, on fait un groupe WhatsApp ou une boucle de mail ?",
    "Dans ce cas un groupe WhatsApp, c'est peut-être plus simple.",
    "Bon, on passe à la lumière.",
]

@Test func uneReformulationSeProuveAvecLesPhrasesVoisines() {
    // Trop de mots ajoutés pour une seule phrase, mais la fenêtre autour du numéro la prouve.
    let ligne = Gabarit.ligneQuiProuve("Création d’un groupe WhatsApp pour échanger sur l’organisation",
                                       numero: 4, dans: phrases, rayon: 8)
    #expect(ligne == 4 || ligne == 3)
}

@Test func laCitationNestPasUnFragmentVoisin() {
    let ligne = Gabarit.ligneQuiProuve("Avancer avec un groupe WhatsApp ou une boucle de mail", numero: 2, dans: phrases, rayon: 8)
    #expect(ligne == 3)
}

@Test func uneReformulationSansRapportNeSeProuvePas() {
    #expect(Gabarit.ligneQuiProuve("Signer le contrat de location du studio", numero: 4, dans: phrases, rayon: 8) == nil)
}

@Test func uneLigneTropLoinDuNumeroNeComptePas() {
    let longues = phrases + Array(repeating: "On parle d'autre chose ici.", count: 20) + ["Un salon Signal pour avancer, très bien."]
    #expect(Gabarit.ligneQuiProuve("Salon Signal pour avancer", numero: 25, dans: longues, rayon: 8) == 26)
    #expect(Gabarit.ligneQuiProuve("Salon Signal pour avancer", numero: 1, dans: longues, rayon: 2) == nil)
}

private let segments = [
    Segment(debut: 0, fin: 4, piste: .systeme, texte: "On demandera des images brutes à leur vidéaste.", voix: "Clémence"),
    Segment(debut: 200, fin: 204, piste: .systeme, texte: "Du 4K sans habillage, les images brutes.", voix: "Clémence"),
]

@Test func unChiffreDitAilleursDansLaReunionNestPasInvente() {
    let element = ElementSource(texte: "Demander des images brutes en 4K au vidéaste", sources: [0], citation: "On demandera des images brutes à leur vidéaste.")
    #expect(ValidationSources.valider(element, dans: segments, citationSiRefus: false) == nil)
    let connus = ValidationSources.connus(segments: segments)
    #expect(ValidationSources.valider(element, dans: segments, connus: connus, citationSiRefus: false)?.texte
        == "Demander des images brutes en 4K au vidéaste")
}

@Test func unChiffreJamaisDitEcarteLElementAuLieuDeMontrerLOral() {
    let element = ElementSource(texte: "Demander des images brutes en 8K au vidéaste", sources: [0], citation: "On demandera des images brutes à leur vidéaste.")
    let connus = ValidationSources.connus(segments: segments)
    #expect(ValidationSources.valider(element, dans: segments, connus: connus, citationSiRefus: false) == nil)
    // L'ancien comportement reste possible : la citation à la place.
    #expect(ValidationSources.valider(element, dans: segments)?.texte == "On demandera des images brutes à leur vidéaste.")
}

@Test func unNomNoteParStevenNestPasInvente() {
    let connus = ValidationSources.connus(segments: segments, notes: [LigneDeNote(temps: 0, texte: "Interview de Fanny jeudi")])
    let lu = Set(ValidationSources.normaliser(connus).split(separator: " ").map(String.init))
    #expect(EnBref.motsNonDits("Préparer les questions pour Fanny", lu: lu).isEmpty)
    #expect(!EnBref.motsNonDits("Préparer les questions pour Sophie", lu: lu).isEmpty)
}
