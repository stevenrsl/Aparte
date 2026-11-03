import Testing
@testable import Analyse

private func titreValide(_ titre: String, dans phrase: String) -> String? {
    DecoupageSujets.valider([.init(titre: titre, premiere: 1, derniere: 1)],
                          phrases: [phrase], debuts: [0], fin: 10).first?.titre
}

@Test func titresCourtsInventesRetombentSurLaPhrase() {
    let phrase = "Nous refusons ce budget pour le moment."
    for titre in ["TV à 999 €", "TV", "999", "Bob"] {
        #expect(titreValide(titre, dans: phrase) == "Nous refusons ce budget pour le")
    }
}

@Test func titreAvecMotsGrammaticauxCourtsEstAccepte() {
    #expect(titreValide("Budget de la tournée", dans: "Budget tournée confirmé.") == "Budget de la tournée")
}

@Test func sigleEtNombreDitsSontAcceptes() {
    #expect(titreValide("TV à 999 €", dans: "La TV coûte 999 euros.") == "TV à 999 €")
}

@Test func titreSeulementGrammaticalEstRefuse() {
    #expect(titreValide("de la à", dans: "On parle de la tournée à venir.") == "On parle de la tournée à")
}

@Test func symboleSeulEtTitreVideSontRefuses() {
    #expect(ValidationSources.normaliser("Été à 999 €") == "ete a 999")
    #expect(titreValide("€", dans: "Budget refusé.") == "Budget refusé.")
    #expect(titreValide("", dans: "Budget refusé.") == "Budget refusé.")
}
