import Foundation
import Testing
import Transcription
@testable import Interface

// `Relecture.relire` n'est testé qu'avec un fichier audio de référence, sauté ici : ce test couvre
// séparément la fonction qu'elle appelle, pour que le marquage de la relecture ne reste pas sans
// test (une ligne marquée doit le rester après la fusion des phrases proches).
@Test func laFusionDeLaRelectureGardeLaLigneMarquee() {
    let segments = [
        Segment(debut: 0, fin: 2, piste: .systeme, texte: "On décide de garder la version longue pour le festival."),
        Segment(debut: 3, fin: 5, piste: .micro, texte: "On décide de ne pas garder la version longue pour le festival."),
    ]
    let nettoyes = Relecture.nettoyer(segments)
    let micro = nettoyes.first { $0.piste == .micro }
    #expect(micro?.echoProbable == true)
}
