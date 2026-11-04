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
    #expect(titreValide("TV à 999", dans: "La TV coûte 999 euros.") == "TV à 999")
}

@Test func titreSeulementGrammaticalEstRefuse() {
    #expect(titreValide("de la à", dans: "On parle de la tournée à venir.") == "On parle de la tournée à")
}

@Test func symboleSeulEtTitreVideSontRefuses() {
    #expect(ValidationSources.normaliser("Été à 999 €") == "ete a 999")
    #expect(titreValide("€", dans: "Budget refusé.") == "Budget refusé.")
    #expect(titreValide("", dans: "Budget refusé.") == "Budget refusé.")
}

private func dit(_ titre: String, _ phrase: String = "budget") -> Bool {
    DecoupageSujets.titreDit(titre, lu: Set(ValidationSources.normaliser(phrase).split(separator: " ")))
}

@Test func homographesInventesSontRefuses() {
    for titre in ["Plan A", "plan a"] { #expect(!dit(titre, "On retient le plan B.")) }
    for titre in ["Taille L", "Taille l"] { #expect(!dit(titre, "taille M")) }
    for (titre, phrase) in [("Bureau à LA", "Le bureau ferme."), ("Accord UN", "Accord confirmé"),
                            ("Marché DE", "Marché confirmé"), ("Version EN", "Version confirmée")] {
        #expect(!dit(titre, phrase))
    }
    #expect(dit("Plan A", "On retient le plan A."))
}

@Test func unitesEtNombresAmbigusSontRefuses() {
    for (titre, phrase) in [("Budget à 999 €", "Budget de 999 personnes."),
                            ("Budget 20 %", "Budget pour 20 personnes."),
                            ("Budget 2 000", "Budget pour 2 personnes et 1 000 euros."),
                            ("Retard 1,5 mois", "Retard de 1 mois pour 5 personnes.")] {
        #expect(!dit(titre, phrase))
        #expect(titreValide(titre, dans: phrase) == phrase.split(separator: " ").prefix(6).joined(separator: " "))
    }
    for symbole in ["€", "$", "£", "%"] { #expect(!dit("budget 999 \(symbole)", "budget 999 euros")) }
    for nombre in ["2 000", "2\u{00a0}000", "2\u{202f}000", "1,5", "1.5"] {
        #expect(!dit("budget \(nombre)", "budget 2 000 1 5"))
    }
    #expect(!dit("TV à 999 €", "La TV coûte 999 euros."))
}

@Test func exemptionsGrammaticalesExplicites() {
    // Liste indépendante de celle de production : un retrait doit casser ce test.
    for mot in ["à", "au", "aux", "de", "des", "du", "en", "et", "la", "le", "les", "un", "une", "À", "La", "De"] {
        #expect(dit("\(mot) budget"), "Exception attendue : \(mot)")
    }
    for apostrophe in ["'", "’"] {
        #expect(dit("Plan d\(apostrophe)action", "Plan action"))
        #expect(dit("L\(apostrophe)équipe", "équipe"))
        #expect(dit("l\(apostrophe)équipe", "équipe"))
    }
    #expect(dit("À revoir le budget", "revoir budget"))
    #expect(dit("La TV", "TV"))
}

@Test func motsNonExemptesRestentControles() {
    for mot in ["pas", "ne", "ou", "sur", "pour", "a", "l", "d", "LA", "UN", "DE", "EN", "L"] {
        #expect(!dit("budget \(mot)"), "Mot à contrôler : \(mot)")
        #expect(dit("budget \(mot)", "budget \(mot)"))
    }
}
