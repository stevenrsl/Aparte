import Analyse
import Foundation
import Stockage
import Testing
@testable import Interface

@Test func choixDesSourcesParMoment() {
    let decision = ElementSource(texte: "Décision", sources: [10])
    let action = ElementSource(texte: "Action", sources: [20])
    let question = ElementSource(texte: "Question", sources: [30])
    let note = LigneDeNote(temps: 40, texte: "Note")
    let sujet = Sujet(titre: "Sujet", debut: 50, fin: 60)
    let compte = CompteRendu(fournisseur: "Test", decisions: [decision], actions: [action], questions: [question], sujets: [sujet])
    for (moment, cible) in [(10.0, decision.id), (20, action.id), (30, question.id), (40, note.id), (55, sujet.id), (58, sujet.id)] {
        let resultat = sourcePourMoment(moment, compteRendu: compte, notes: [note])
        #expect(resultat.cible == cible)
        #expect(resultat.element.sources.contains(moment) || resultat.element.sources == [50, 60])
    }
    #expect(sourcePourMoment(80, compteRendu: compte, notes: [note]).cible == nil)
}

@Test @MainActor func actionsReversiblesEtErreurEcriture() throws {
    let racine = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "Test", type: .presentiel, dossier: nil)
    let modele = ModeleApp(verifierCle: false, racineInitiale: racine)
    let action = ActionOuverte(reunion: reunion, element: ElementSource(texte: "Faire", sources: [1]))
    modele.definirAction(action, faite: true)
    #expect(modele.actionEstFaite(action))
    modele.definirAction(action, faite: false)
    #expect(!modele.actionEstFaite(action))
    try FileManager.default.removeItem(at: reunion.url)
    modele.definirAction(action, faite: true)
    #expect(!modele.actionEstFaite(action))
    #expect(modele.erreur?.contains("L’état de l’action") == true)
}
