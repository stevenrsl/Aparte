import Analyse
import Foundation
import Stockage
import Testing
import Transcription

// Fausses réunions, inventées pour la mesure. Lancement : APARTE_MESURE=3 swift test --filter mesureOublis
private struct Fausse {
    var titre: String
    var type: TypeReunion = .presentiel
    var pas: Double
    var phrases: [String]
    var decisions: [String]
    var actions: [String]
    var questions: [String]
}

private let fausses = [
    Fausse(titre: "Festival", pas: 12, phrases: [
        "Bonjour à tous, merci d'être là.", "On a une petite heure pour faire le point sur le festival.",
        "Le montage avance bien, on en est à la deuxième version.", "La version courte fait vingt-six minutes.",
        "La version longue fait trente-huit minutes.", "Franchement je préfère la longue, elle respire plus.",
        "Moi aussi, la courte coupe trop le passage à l'usine.", "On décide de garder la version longue pour le festival.",
        "Très bien, et pour la musique, où est-ce qu'on en est ?", "Le compositeur a livré deux morceaux la semaine dernière.",
        "Il en manque encore un pour le générique.", "Marie envoie la musique à Paul avant vendredi.",
        "D'accord, je m'en occupe demain.", "Pour les sous-titres, on verra ça plus tard.",
        "Est-ce qu'on sait qui prend les photos de plateau ?", "Non, personne ne s'est proposé pour l'instant.",
        "Bon, on y reviendra.", "Il faudrait aussi réserver la salle de projection.",
        "Paul réserve la salle de projection pour le douze.", "Parfait, merci à tous, bonne journée.",
    ], decisions: ["On décide de garder la version longue pour le festival."],
       actions: ["Marie envoie la musique à Paul avant vendredi.", "Paul réserve la salle de projection pour le douze."],
       questions: ["Est-ce qu'on sait qui prend les photos de plateau ?"]),
    Fausse(titre: "Budget", type: .visio, pas: 15, phrases: [
        "Tu m'entends bien ?", "Oui c'est bon, je t'entends.", "Alors, le budget de la tournée.",
        "On avait prévu douze mille euros.", "Là on est plutôt à quinze mille avec les transports.",
        "Ça fait beaucoup quand même.", "On ne valide pas le budget de la tournée pour l'instant.",
        "Oui attendons d'avoir le devis du transporteur.", "Sophie demande le devis au transporteur cette semaine.",
        "Je le relance dès ce soir.", "Et la date de Lyon, elle est maintenue ?",
        "Je ne sais pas, le théâtre n'a pas répondu.", "On maintient la date de Lyon.",
        "D'accord, je préviens l'équipe.", "Il reste la question des hôtels.",
        "Qui s'occupe de réserver les hôtels à Lyon ?", "On en reparle mardi.", "Allez, à mardi alors.",
    ], decisions: ["On ne valide pas le budget de la tournée pour l'instant.", "On maintient la date de Lyon."],
       actions: ["Sophie demande le devis au transporteur cette semaine."],
       questions: ["Qui s'occupe de réserver les hôtels à Lyon ?"]),
    Fausse(titre: "Client", type: .visio, pas: 14, phrases: [
        "Merci d'avoir pris le temps.", "On voulait vous montrer la maquette du site.",
        "La page d'accueil a été simplifiée.", "C'est beaucoup plus clair qu'avant.",
        "Par contre le bleu me semble trop foncé.", "On peut l'éclaircir sans problème.",
        "Julien propose une nouvelle couleur d'ici lundi.", "Et pour le formulaire de contact ?",
        "On enlève le champ téléphone, personne ne le remplit.", "Oui c'est une bonne idée, on retire le champ téléphone du formulaire.",
        "Quand est-ce que le site peut être en ligne ?", "Ça dépend de vos textes, on ne les a pas encore reçus.",
        "Claire envoie les textes définitifs à Julien avant la fin du mois.", "Très bien.",
        "Faut-il traduire le site en anglais ?", "Il faut que j'en parle à ma direction.", "D'accord, merci à vous.",
    ], decisions: ["on retire le champ téléphone du formulaire."],
       actions: ["Julien propose une nouvelle couleur d'ici lundi.", "Claire envoie les textes définitifs à Julien avant la fin du mois."],
       questions: ["Quand est-ce que le site peut être en ligne ?", "Faut-il traduire le site en anglais ?"]),
    Fausse(titre: "Tournage", pas: 25, phrases: [
        "bon alors on commence", "le tournage est prévu sur trois jours", "euh le premier jour c'est à la ferme",
        "il faut prévenir le propriétaire", "Antoine appelle le propriétaire de la ferme demain matin", "ok ça marche",
        "pour la lumière on a besoin de quoi", "deux projecteurs ça devrait suffire", "on loue deux projecteurs chez le loueur habituel",
        "ça coûte combien à peu près", "environ trois cents euros", "c'est validé on prend ça",
        "et pour la cantine", "le traiteur de la dernière fois était très bien", "Léa réserve le traiteur pour les trois jours",
        "est-ce qu'on a l'autorisation de tourner sur la route", "je ne crois pas non", "il faudrait demander à la mairie",
        "Antoine écrit à la mairie cette semaine", "bon on fait une pause et on reprend", "oui cinq minutes",
        "alors la suite", "le deuxième jour on tourne à l'usine", "le directeur est d'accord",
        "on commence à huit heures le deuxième jour", "très bien", "et si il pleut le premier jour on fait quoi",
        "on verra bien", "voilà je crois qu'on a fait le tour", "merci tout le monde",
    ], decisions: ["on loue deux projecteurs chez le loueur habituel", "on commence à huit heures le deuxième jour"],
       actions: ["Antoine appelle le propriétaire de la ferme demain matin", "Léa réserve le traiteur pour les trois jours", "Antoine écrit à la mairie cette semaine"],
       questions: ["est-ce qu'on a l'autorisation de tourner sur la route", "et si il pleut le premier jour on fait quoi"]),
    Fausse(titre: "Sans objet", pas: 15, phrases: [
        "Salut, ça va ?", "Oui très bien et toi ?", "Tranquille, je rentre de vacances.", "Ah super, c'était où ?",
        "En Bretagne, il a fait beau toute la semaine.", "La chance, ici il a plu.", "Les enfants ont adoré la plage.",
        "On y était aussi l'année dernière.", "C'est vraiment joli par là-bas.", "Oui. Bon, à plus tard alors.",
    ], decisions: [], actions: [], questions: []),
]

@Test(.enabled(if: ProcessInfo.processInfo.environment["APARTE_MESURE"] != nil))
func mesureOublis() async throws {
    // APARTE_MESURE_PCC envoie ces fausses réunions chez Apple. Jamais une vraie.
    let analyste = ProcessInfo.processInfo.environment["APARTE_MESURE_PCC"] != nil ? AnalysteApple.pcc : .local
    let essais = Int(ProcessInfo.processInfo.environment["APARTE_MESURE"] ?? "") ?? 1
    func trouve(_ attendu: String, _ elements: [ElementSource]) -> Bool {
        let cherche = attendu.lowercased().filter { $0.isLetter || $0.isNumber }
        return elements.contains { $0.texte.lowercased().filter { $0.isLetter || $0.isNumber }.contains(cherche) }
    }
    var attendus = 0, trouves = 0, malRanges = 0, enTrop = 0, ecartes = 0
    for fausse in fausses {
        let segments = fausse.phrases.enumerated().map { rang, phrase in
            Segment(debut: Double(rang) * fausse.pas, fin: Double(rang) * fausse.pas + fausse.pas - 2,
                    piste: fausse.type == .visio && rang % 2 == 1 ? .systeme : .micro, texte: phrase)
        }
        for essai in 1...essais {
            let c = try await analyste.analyser(segments: segments, notes: [], type: fausse.type, progression: { _ in })
            let tous = c.decisions + c.actions + c.questions
            var manques: [String] = []
            let groupes = [(fausse.decisions, c.decisions), (fausse.actions, c.actions), (fausse.questions, c.questions)]
            for (liste, sortis) in groupes {
                for attendu in liste {
                    attendus += 1
                    if trouve(attendu, sortis) { trouves += 1 }
                    else if trouve(attendu, tous) { malRanges += 1; manques.append("mal rangé : \(attendu)") }
                    else { manques.append("manqué : \(attendu)") }
                }
            }
            let tousAttendus = fausse.decisions + fausse.actions + fausse.questions
            let inattendus = tous.filter { element in !tousAttendus.contains { trouve($0, [element]) } }
            enTrop += inattendus.count
            ecartes += c.elementsEcartes
            print("MESURE \(fausse.titre) sujets : \((c.sujets ?? []).map(\.titre).joined(separator: " | "))")
            print("MESURE \(fausse.titre) #\(essai) écartés \(c.elementsEcartes) non analysés \(c.passagesNonAnalyses)")
            for m in manques { print("MESURE   \(m)") }
            for e in inattendus { print("MESURE   en trop : \(e.texte)") }
        }
    }
    print("MESURE TOTAL attendus \(attendus) trouvés \(trouves) mal rangés \(malRanges) en trop \(enTrop) écartés \(ecartes)")
}
