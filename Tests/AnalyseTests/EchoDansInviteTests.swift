import Foundation
import Testing
@testable import Analyse

// La mention « écho probable » doit arriver jusqu'au texte donné au modèle (local ou Mistral,
// qui partagent `invite`) : sans ce test, une régression dans `qui` passerait inaperçue.
@Test func uneLigneMarqueePorteLaMentionEtUneLigneNonMarqueeNeLaPortePas() {
    let lignes = [
        AnalysteLocal.Ligne(phrase: "On garde la version longue.", debut: 0, piste: .micro, voix: nil, echoProbable: true),
        AnalysteLocal.Ligne(phrase: "Marie envoie la musique.", debut: 5, piste: .micro, voix: nil, echoProbable: false),
    ]
    let texte = AnalysteLocal.invite(lignes, notes: [], type: .visio)
    #expect(texte.contains("moi, écho probable : On garde la version longue."))
    #expect(texte.contains("moi : Marie envoie la musique."))
}

@Test func uneLigneMarqueeAvecUneVoixGardeLaVoixEtLaMention() {
    let lignes = [AnalysteLocal.Ligne(phrase: "C'est décidé.", debut: 0, piste: .micro, voix: "Voix 1", echoProbable: true)]
    let texte = AnalysteLocal.invite(lignes, notes: [], type: .visio)
    #expect(texte.contains("Voix 1, écho probable : C'est décidé."))
}
