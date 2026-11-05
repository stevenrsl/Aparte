import Foundation
import Testing
import Transcription
@testable import Analyse

private let reponse = """
SUJET : Les interviews
- [1] Quatre personnes sont prévues
- Un point sans numéro
- [2] Deux ont déjà dit oui
**DÉCISIONS**
- [3] Filmer le jeudi
ACTIONS
- [4] Clémence : envoyer le NDA
- [99] Marc : ligne inconnue
QUESTIONS
- aucune
"""

private let segments = [
    Segment(debut: 0, fin: 4, piste: .systeme, texte: "J'ai demandé à quatre personnes.", voix: "Voix 1"),
    Segment(debut: 5, fin: 9, piste: .systeme, texte: "Deux m'ont dit oui.", voix: "Voix 1"),
    Segment(debut: 10, fin: 14, piste: .systeme, texte: "Bon on filme jeudi alors.", voix: "Voix 2"),
    Segment(debut: 15, fin: 19, piste: .systeme, texte: "Clémence, tu m'envoies le NDA ?", voix: "Voix 2"),
]

@Test func uneReponseSeLitSousSesTitres() {
    let lu = Gabarit.lirePassage(reponse)
    #expect(lu.sujets.map(\.titre) == ["Les interviews"])
    #expect(lu.sujets.first?.points.count == 2)
    #expect(lu.decisions == [Gabarit.Puce(ligne: 3, texte: "Filmer le jeudi")])
    #expect(lu.actions.count == 2)
    #expect(lu.questions.isEmpty)
}

@Test func unePuceSansNumeroEstEcartee() {
    #expect(Gabarit.puce("- Un point sans numéro") == nil)
    #expect(Gabarit.puce("- [3] aucune") == nil)
    #expect(Gabarit.puce("- [3] Marc : aucune") == nil)
    #expect(Gabarit.puce("- 3. Garder la longue")?.ligne == 3)
    #expect(Gabarit.puce("* [3, 4] garder la longue") == Gabarit.Puce(ligne: 3, texte: "Garder la longue"))
}

@Test func chaqueElementPorteSaCitationEtSonMoment() {
    let lignes = AnalysteLocal.lignes(de: segments)
    let choisi = AnalysteLocal.choisir(Gabarit.lirePassage(reponse), dans: lignes, segments: segments)
    #expect(choisi.decisions.first?.texte == "Filmer le jeudi")
    #expect(choisi.decisions.first?.citation == "Bon on filme jeudi alors.")
    #expect(choisi.decisions.first?.sources == [10])
    #expect(choisi.actions.first?.texte == "Envoyer le NDA")
    #expect(choisi.actions.first?.responsable == "Clémence")
    #expect(choisi.ecartes == 1)
    #expect(choisi.sujets.first?.points?.count == 2)
}

@Test func uneReformulationSansPreuveRevientALaCitation() throws {
    func valide(_ texte: String, citation: String, sources: [Double]) throws -> ElementSource {
        try #require(ValidationSources.valider(ElementSource(texte: texte, sources: sources, citation: citation), dans: segments))
    }
    // Un nom, un chiffre ou un moment jamais dit.
    #expect(try valide("Filmer vendredi", citation: "Bon on filme jeudi alors.", sources: [10]).texte == "Bon on filme jeudi alors.")
    #expect(try valide("Budget de 999 euros", citation: "Bon on filme jeudi alors.", sources: [10]).texte == "Bon on filme jeudi alors.")
    #expect(try valide("Filmer avec Paul", citation: "Bon on filme jeudi alors.", sources: [10]).texte == "Bon on filme jeudi alors.")
    // Ce qui est dit juste autour compte.
    #expect(try valide("Filmer jeudi avec Clémence", citation: "Bon on filme jeudi alors.", sources: [10]).texte == "Filmer jeudi avec Clémence")
    // Un élément dont la citation n'existe pas n'apparaît pas.
    #expect(ValidationSources.valider(ElementSource(texte: "Filmer", sources: [10], citation: "Jamais dit ici."), dans: segments) == nil)
}

@Test func uneNegationNeSePerdPasDansLaReformulation() throws {
    let dit = [Segment(debut: 0, fin: 4, piste: .micro, texte: "On ne garde pas la version longue.")]
    let perdue = try #require(ValidationSources.valider(ElementSource(texte: "Garder la version longue", sources: [0], citation: "On ne garde pas la version longue."), dans: dit))
    #expect(perdue.texte == "On ne garde pas la version longue.")
    #expect(perdue.citationAffichee == nil)
}

@Test func lesPlafondsEtLesRedites() {
    func element(_ texte: String, _ temps: Double = 0) -> ElementSource { ElementSource(texte: texte, sources: [temps], citation: texte) }
    let decisions = (1...20).map { element("alpha\($0) beta\($0) gamma\($0)") }
    let fini = AnalysteLocal.assembler(decisions: decisions + [element("Envoyer le devis final au client")],
                                       actions: [element("Envoyer le devis final au client")], questions: [], sujets: [], fin: 10)
    #expect(fini.decisions.count == Gabarit.maxDecisions)
    #expect(!fini.decisions.contains { $0.texte.contains("devis") })
    #expect(fini.actions.count == 1)
}

@Test func unSujetReprisPlusLoinNeFaitQuUn() {
    let point = { (t: String) in ElementSource(texte: t, sources: [0], citation: t) }
    let fusion = Gabarit.fusionner([
        Sujet(titre: "Les interviews", debut: 10, fin: 20, points: [point("Quatre personnes prévues")]),
        Sujet(titre: "Planning", debut: 30, fin: 40, points: [point("Jeudi après-midi")]),
        Sujet(titre: "Interviews", debut: 50, fin: 60, points: [point("Signer le NDA")]),
    ])
    #expect(fusion.map(\.titre) == ["Les interviews", "Planning"])
    #expect(fusion.first?.fin == 60)
    #expect(fusion.first?.points?.count == 2)
}

@Test func unNomDonneSeLitPartoutSansToucherLaCitation() throws {
    let citation = "Voix 2 envoie le NDA."
    let rendu = CompteRendu(fournisseur: "Local", decisions: [], actions: [ElementSource(texte: "Voix 2 : envoyer le NDA", sources: [0], citation: citation, responsable: "Voix 2")],
                            questions: [], enBref: [PhraseSourcee(texte: "Voix 2 et Voix 12 parlent.", sources: [0])])
        .avecNoms(["Voix 2": "Clémence", "Voix 1": ""])
    #expect(rendu.actions.first?.responsable == "Clémence")
    #expect(rendu.actions.first?.texte == "Clémence : envoyer le NDA")
    #expect(rendu.actions.first?.citation == citation)
    #expect(rendu.enBref?.first?.texte == "Clémence et Voix 12 parlent.")
}

@Test func uneAnalyseRecenteSeRelitEtGardeSesReformulations() throws {
    let rendu = CompteRendu(fournisseur: "Local", decisions: [ElementSource(texte: "Filmer jeudi", sources: [10], citation: "Bon on filme jeudi alors.")],
                            actions: [], questions: [], pointsCles: [ElementSource(texte: "Tournage jeudi", sources: [10], citation: "Bon on filme jeudi alors.")],
                            empreinte: CompteRendu.empreinte(de: segments))
    let relu = rendu.revalide(dans: segments)
    #expect(relu.decisions.first?.texte == "Filmer jeudi")
    #expect(relu.pointsCles?.first?.texte == "Tournage jeudi")
    #expect(relu.markdown().contains("> « Bon on filme jeudi alors. »"))
    #expect(relu.markdown().contains("## Points clés"))
}

@Test func lesPassagesSeCoupentEntreDeuxLignes() {
    let lignes = (0..<30).map { AnalysteLocal.Ligne(phrase: String(repeating: "mot ", count: 75), debut: Double($0), piste: .micro) }
    let passages = AnalysteLocal.passages(lignes, budget: 1000)
    #expect(passages.count == 3)
    #expect(passages.flatMap { $0 }.count == 30)
}
