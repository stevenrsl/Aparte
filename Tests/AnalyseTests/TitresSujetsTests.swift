import Foundation
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
    #expect(!dit("Plan A", "On retient le plan A."))
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
    for mot in ["à", "au", "aux", "de", "des", "du", "en", "et", "la", "le", "les", "À", "La", "De"] {
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
        if mot.count > 1 && mot != mot.uppercased() { #expect(dit("budget \(mot)", "budget \(mot)")) }
    }
}

@Test func contreExemplesHomographesEtElisions() {
    for (titre, phrase) in [
        ("Plan A", "On retient le plan B, il a raison."), ("Option A", "On va à Lyon, option C."),
        ("Plan D", "Plan B, d'accord."), ("Taille L", "Taille M pour l'équipe."),
        ("Bureau à LA", "Le bureau de la ville ferme."), ("Accord UN", "Un accord confirmé"),
        ("Marché DE", "Marché de Noël confirmé"), ("Version EN", "Version en cours"),
        ("plan a", "On retient le plan B, il a raison."), ("Taille l", "Taille M pour l’équipe."),
        ("Phase un", "phase deux"),
        ("Phase Un", "phase deux"), ("Option Une", "option deux"),
        ("Plan 'D'", "plan B"), ("Taille ’L’", "taille M"), ("Taille L'", "taille M"),
        ("Plan d' budget", "Plan budget"), ("À", "à")
    ] { #expect(!dit(titre, phrase)) }
}

@Test func separateursEtSignesInventesSontRefuses() {
    for titre in ["Livraison 10/12", "Point à 10:30", "Retard 1-5 mois", "Budget 2 - 3"] {
        #expect(!dit(titre, "Livraison Point Retard mois Budget 10 12 30 1 5 2 3"))
    }
    for separateur in ["'", "’", "-", "_", "\u{200b}", "\u{2060}", "\u{00ad}", "\u{202f}", "\u{00a0}", "\u{2009}", "\t", ":", ",", "."] {
        #expect(!dit("budget 2\(separateur)000", "budget 2 000"))
    }
    #expect(!dit("Q3 2026", "Q3 2026"))
    for (titre, phrase) in [
        ("Livraison 10/12", "Livraison de 10 caisses et 12 palettes."),
        ("Point à 10:30", "Point sur 10 dossiers et 30 clients."),
        ("Retard 1-5 mois", "Retard de 1 mois pour 5 personnes."),
        ("Budget 2 - 3", "Budget 2 personnes 3 jours"),
        ("Salle 20 °", "Salle 20 personnes."), ("Budget ≠ validé", "Budget validé."),
        ("Budget -20", "Budget 20 personnes."), ("Budget +20", "Budget 20 personnes."),
        ("Budget ×2", "Budget 2 personnes."), ("Effectif > 20", "Effectif 20 personnes."),
        ("#2", "Budget 2 personnes.")
    ] { #expect(!dit(titre, phrase), "Titre refusé : \(titre)") }
    for signe in ["€", "$", "£", "%", "¥", "₿", "₹", "‰", "％", "﹪", "٪", "＄", "°", "≠", "+", "×", ">", "#", "?", "!", "/"] {
        #expect(!dit("Budget \(signe)20", "Budget 20"))
    }
    for nombre in ["-20", "- 20"] { #expect(!dit("Budget \(nombre)", "Budget 20")) }
}

@Test func formesUnicodeEtPonctuationPermise() {
    for titre in ["Budget dû", "Budget dé", "Plan là"] {
        #expect(!dit(titre.decomposedStringWithCanonicalMapping, "Budget Plan validé"))
    }
    for (titre, phrase) in [("3D", "3D"), ("Q3", "Q3"), ("Saint-Denis", "Saint Denis"),
                            ("L'ÉQUIPE", "équipe"), ("Budget : tournée", "Budget tournée"),
                            ("« Budget »", "Budget"), ("\"Budget\"", "Budget"),
                            ("L'équipe", "équipe"), ("Budget été", "Budget été"), ("À revoir", "revoir")] {
        #expect(dit(titre, phrase))
        #expect(dit(titre.decomposedStringWithCanonicalMapping, phrase))
    }
    #expect(!dit("3D", "3 D"))
    #expect(!dit("Q3", "Q 3"))
}

@Test func elisionsCourantesSontAccepteesSansExempterLesLettresSeules() {
    for apostrophe in ["'", "’"] {
        for (debut, suite) in [("C", "est validé"), ("J", "ai confirmé"), ("M", "organiser"),
                               ("N", "oublie pas"), ("S", "organiser"), ("T", "organiser"), ("Qu", "on confirme")] {
            let titre = debut + apostrophe + suite
            #expect(dit(titre, titre))
            #expect(dit(titre.lowercased(), suite))
            #expect(!dit(debut + apostrophe + " " + suite, suite))
            #expect(!dit(debut + apostrophe + "5", "5"))
            #expect(!dit(titre, "budget"))
        }
    }
    for lettre in ["C", "J", "M", "N", "S", "T", "c", "j", "m", "n", "s", "t"] {
        #expect(!dit("Plan " + lettre, "Plan " + lettre))
    }
    #expect(!dit("Taille S", "Taille S"))
}

@Test func tiretsLongsSeparentSeulementDesMots() {
    for tiret in ["—", "–"] {
        for titre in ["Budget \(tiret) tournée", "Budget\(tiret)tournée"] {
            #expect(dit(titre, "Budget tournée"))
            #expect(titreValide(titre, dans: "Budget tournée confirmé.") == titre)
        }
        for titre in ["10 \(tiret) 12", "Budget \(tiret)5", "Budget \(tiret) 5", "5\(tiret)Budget",
                      "5 \(tiret) Budget", "\(tiret) Budget", "Budget \(tiret)"] {
            #expect(!dit(titre, "Budget 5 10 12"))
        }
    }
}
