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

// « En bref » ne lisait pas la mention avant cette passe : sans ce test, la liste envoyée au
// modèle pourrait de nouveau présenter une ligne douteuse comme une ligne normale.
@Test func laListeEnBrefMarqueSeulementLesRetenusEcho() {
    let retenus: [(texte: String, debut: Double)] = [
        (texte: "On garde la version longue.", debut: 0),
        (texte: "Marie envoie la musique.", debut: 5),
    ]
    let liste = AnalysteLocal.retenusEnBref(retenus, marques: [0])
    #expect(liste.contains("1. On garde la version longue. (écho probable)"))
    #expect(liste.contains("2. Marie envoie la musique."))
    #expect(!liste.contains("Marie envoie la musique. (écho probable)"))
}

// La seconde lecture (`confirmer`) juge une ligne avec son contexte : sans la mention, elle peut
// confirmer une ligne douteuse comme si elle était certaine.
@Test func leContexteDeLaSecondeLecturePorteLaMentionSiMarquee() {
    let marquee = AnalysteLocal.Ligne(phrase: "On garde la version longue.", debut: 0, piste: .micro, voix: nil, echoProbable: true)
    let normale = AnalysteLocal.Ligne(phrase: "Marie envoie la musique.", debut: 5, piste: .micro, voix: nil, echoProbable: false)
    #expect(AnalysteLocal.contexte(marquee) == "On garde la version longue. (écho probable)")
    #expect(AnalysteLocal.contexte(normale) == "Marie envoie la musique.")
}
