import CryptoKit
import Foundation
import FoundationModels
import NaturalLanguage
import Stockage
import Transcription

/// Un élément du compte rendu et ce qui permet de le vérifier.
public struct ElementSource: Codable, Sendable, Identifiable, Hashable {
    public var id = UUID()
    public var texte: String
    public var sources: [Double]
    public var citation: String?
    public var responsable: String?
    public var echeance: String?

    public init(texte: String, sources: [Double], citation: String? = nil, responsable: String? = nil, echeance: String? = nil) {
        self.texte = texte
        self.sources = sources
        self.citation = citation
        self.responsable = responsable
        self.echeance = echeance
    }

    /// La citation à montrer sous le texte : rien si le texte est déjà la citation.
    public var citationAffichee: String? {
        guard let citation, ValidationSources.normaliser(citation) != ValidationSources.normaliser(texte) else { return nil }
        return citation
    }
}

/// Un sujet abordé : un moment de la réunion, son titre et ce qui y a été dit.
public struct Sujet: Codable, Sendable, Identifiable, Hashable {
    public var id = UUID()
    public var titre: String
    public var debut: Double
    public var fin: Double
    /// Ce qui a été dit sur ce sujet, chaque point avec sa source. Absent des analyses plus anciennes.
    public var points: [ElementSource]?

    public init(titre: String, debut: Double, fin: Double, points: [ElementSource]? = nil) {
        self.titre = titre
        self.debut = debut
        self.fin = fin
        self.points = points
    }

    public func contient(_ temps: Double) -> Bool { temps >= debut && temps <= fin }

    /// Vrai si une partie de ce segment tombe dans le sujet, même un seul long segment qui l'englobe
    /// entièrement. Utilisé pour les extraits (`Modele.repartir`) et le contrôle d'un sujet périmé
    /// (`revalide`) : les deux doivent voir le même chevauchement, sans découper les segments.
    public func chevauche(_ segment: Segment) -> Bool { segment.fin >= debut && segment.debut <= fin }
}

/// Une phrase rédigée par le modèle pour « En bref », et les moments qu'elle résume.
public struct PhraseSourcee: Codable, Sendable, Hashable {
    public var texte: String
    public var sources: [Double]

    public init(texte: String, sources: [Double]) {
        self.texte = texte
        self.sources = sources
    }
}

/// À jour : l'empreinte correspond à la transcription actuelle. Périmée : elle a changé depuis
/// l'analyse. À vérifier : l'analyse a été écrite avant ce contrôle, elle n'a pas d'empreinte.
public enum Fraicheur: String, Codable, Sendable, Hashable {
    case aJour
    case perimee
    case aVerifier
}

/// La sortie commune, quel que soit le fournisseur.
public struct CompteRendu: Codable, Sendable, Hashable {
    public var fournisseur: String
    public var date: Date
    public var decisions: [ElementSource]
    public var actions: [ElementSource]
    public var questions: [ElementSource]
    /// Absent des analyses écrites avant les sujets.
    public var sujets: [Sujet]?
    /// Deux ou trois phrases rédigées, chacune avec ses sources. Absent : le résumé construit prend la place.
    public var enBref: [PhraseSourcee]?
    /// Les trois à cinq points à retenir, avec leur source. Absent des analyses plus anciennes.
    public var pointsCles: [ElementSource]?
    public var passagesNonAnalyses: Int
    public var elementsEcartes: Int
    /// L'empreinte de la transcription lue par l'analyse. Absente avant ce contrôle : l'analyse reste « à vérifier ».
    public var empreinte: String?
    /// Calculée à chaque lecture face à la transcription actuelle (`revalide`) : jamais lue ni écrite sur disque.
    public var fraicheur: Fraicheur = .aJour

    private enum CodingKeys: String, CodingKey {
        case fournisseur, date, decisions, actions, questions, sujets, enBref, pointsCles, passagesNonAnalyses, elementsEcartes, empreinte
    }

    public init(fournisseur: String, date: Date = Date(), decisions: [ElementSource], actions: [ElementSource],
                questions: [ElementSource], sujets: [Sujet]? = nil, enBref: [PhraseSourcee]? = nil, pointsCles: [ElementSource]? = nil, empreinte: String? = nil,
                passagesNonAnalyses: Int = 0, elementsEcartes: Int = 0) {
        self.fournisseur = fournisseur
        self.date = date
        self.decisions = decisions
        self.actions = actions
        self.questions = questions
        self.passagesNonAnalyses = passagesNonAnalyses
        self.sujets = sujets
        self.enBref = enBref
        self.pointsCles = pointsCles
        self.elementsEcartes = elementsEcartes
        self.empreinte = empreinte
    }

    /// Le flux ignore les bornes des segments : un découpage différent au même contenu rend la même empreinte.
    /// Seuls un mot, une voix, une piste ou une marque d'écho différents la changent. Le nom donné à une
    /// voix n'y entre pas. La piste entre, car une même phrase sans voix renseignée ne dit pas la même
    /// chose selon qu'elle vient du micro ou du son du Mac (voir `invite`, `qui`).
    ///
    /// Un flux par piste, dans un ordre stable (micro, puis système) : le flux d'une piste ne dépend
    /// ainsi plus de la façon dont les segments des deux pistes s'entrecroisent dans le temps. Limite
    /// gardée : un même contenu dont seul l'ordre entre les deux pistes change n'est pas détecté.
    public static func empreinte(de segments: [Segment]) -> String {
        var flux = ""
        for piste in [Piste.micro, Piste.systeme] {
            var sousFlux = ""
            var derniereVoix: String?
            var dernierEcho = false
            var premier = true
            for segment in segments where segment.piste == piste {
                // Un segment sans aucun mot (« … » seul) ne doit rien changer, y compris ses marqueurs :
                // sinon un espace supplémentaire suffirait à rendre une analyse périmée à tort.
                let texte = ValidationSources.normaliser(segment.texte)
                guard !texte.isEmpty else { continue }
                if premier || segment.voix != derniereVoix {
                    sousFlux += "§\(segment.voix ?? "")§"
                    derniereVoix = segment.voix
                }
                let echo = segment.echoProbable == true
                if premier || echo != dernierEcho {
                    sousFlux += echo ? "¤echo¤" : "¤¤"
                    dernierEcho = echo
                }
                sousFlux += texte + " "
                premier = false
            }
            guard !sousFlux.isEmpty else { continue }
            flux += "#\(piste.rawValue)#" + sousFlux
        }
        let empreinte = SHA256.hash(data: Data(flux.utf8))
        return empreinte.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// L'état de cette analyse face à la transcription actuelle, sans filtrer ses éléments.
    public func etat(selon segments: [Segment]) -> Fraicheur {
        guard let empreinte else { return .aVerifier }
        return empreinte == Self.empreinte(de: segments) ? .aJour : .perimee
    }

    /// Le résumé ne dit que ce qui a été validé, chaque élément avec son horodatage. Il n'est jamais
    /// écrit par un modèle : calculé ici, il ne peut pas échapper à la règle 1.
    public var resume: String {
        func phrase(_ singulier: String, _ pluriel: String, _ elements: [ElementSource], maximum: Int) -> String? {
            guard !elements.isEmpty else { return nil }
            let cites = elements.prefix(maximum).map { element -> String in
                let texte = element.texte.trimmingCharacters(in: CharacterSet(charactersIn: " .;"))
                return "\(texte) (\(element.sources.map { horodatage($0) }.joined(separator: ", ")))"
            }
            let reste = elements.count - cites.count
            let suite = reste > 0 ? ", et \(reste) de plus" : ""
            return "\(elements.count > 1 ? pluriel : singulier) : \(cites.joined(separator: " ; "))\(suite)."
        }
        let phrases = [
            phrase("Décision", "Décisions", decisions, maximum: 3),
            phrase("Action", "Actions", actions, maximum: 2),
            phrase("Question ouverte", "Questions ouvertes", questions, maximum: 1),
        ].compactMap { $0 }
        guard phrases.isEmpty else { return phrases.joined(separator: " ") }
        // Ne dit que ce qui a été obtenu : le modèle peut avoir manqué un élément, ou un passage échoué.
        switch passagesNonAnalyses {
        case 0: return "Aucun élément vérifié obtenu."
        case 1: return "Aucun élément vérifié obtenu. 1 passage non analysé."
        default: return "Aucun élément vérifié obtenu. \(passagesNonAnalyses) passages non analysés."
        }
    }

    /// Ce qui revient à ces sujets, pour un extrait : le reste de la réunion n'y figure pas. L'extrait
    /// ne reçoit une empreinte que si l'original était à jour : sinon, il reste « à vérifier ».
    public func extrait(_ choisis: [Sujet], empreinte: String? = nil) -> CompteRendu {
        func garder(_ elements: [ElementSource]) -> [ElementSource] {
            elements.filter { element in element.sources.contains { temps in choisis.contains { $0.contient(temps) } } }
        }
        return CompteRendu(fournisseur: fournisseur, date: date, decisions: garder(decisions), actions: garder(actions),
                           questions: garder(questions), sujets: choisis, empreinte: empreinte)
    }

    /// Une analyse relue depuis le disque repasse la validation : une reformulation qui ne tient plus laisse
    /// place à la transcription, et ce qui n'est plus prouvé est écarté. Son état face à la transcription
    /// actuelle décide ensuite du sort d'« En bref » et des sujets (règle 1 : rien n'est affiché sans preuve).
    public func revalide(dans segments: [Segment], noms: [String] = []) -> CompteRendu {
        var copie = self
        func garder(_ elements: [ElementSource]) -> [ElementSource] {
            let gardes = elements.compactMap { ValidationSources.valider($0, dans: segments, noms: noms) }
            copie.elementsEcartes += elements.count - gardes.count
            return gardes
        }
        copie.decisions = garder(decisions)
        copie.actions = garder(actions)
        copie.questions = garder(questions)
        let pointsClesValides = pointsCles.map { $0.compactMap { ValidationSources.valider($0, dans: segments, noms: noms) } }

        // Un sujet n'est retiré que si son début ne tombe plus sur un segment. Une fin au-delà de la
        // transcription (et de la tolérance) est ramenée à sa fin : une relecture qui finit plus tôt, ou
        // une fin dans un silence entre deux segments, ne doit pas faire perdre un bon sujet.
        // Son titre, lui, doit encore être fait de mots dits dans ce moment (comme DecoupageSujets.valider
        // à l'analyse) : sinon il revient aux six premiers mots dits du passage, bornes et id conservés.
        func sujetsValides() -> [Sujet]? {
            let finTranscription = segments.map(\.fin).max() ?? 0
            return sujets?.compactMap { original -> Sujet? in
                // Un début après la fin de la transcription n'est jamais un bon sujet, même si la
                // tolérance de segmentsSources le ferait passer : sinon il resterait affiché, ramené
                // à une durée nulle, après la dernière parole.
                guard original.debut <= finTranscription else { return nil }
                let sources = ValidationSources.segmentsSources(de: original.debut, dans: segments)
                guard !sources.isEmpty else { return nil }
                var sujet = original
                if sujet.fin > finTranscription + ValidationSources.marge { sujet.fin = max(sujet.debut, finTranscription) }
                // Un long segment peut englober tout le sujet : on garde ce qui le chevauche, pas seulement ce qui y commence ou finit.
                let chevauchants = segments.filter { sujet.chevauche($0) }
                let texteCouverts = (chevauchants.isEmpty ? sources : chevauchants).map(\.texte).joined(separator: " ")
                let lu = Set(ValidationSources.normaliser(texteCouverts).split(separator: " "))
                guard !DecoupageSujets.titreDit(sujet.titre, lu: lu) else { return sujet }
                // Aucun mot dit à montrer : garder le titre refusé ferait afficher un mot inventé.
                guard let premiere = ValidationSources.phrases(de: texteCouverts).first else { return nil }
                var repli = sujet
                repli.titre = premiere.split(separator: " ").prefix(6).joined(separator: " ")
                return repli
            }
        }
        func enBrefControle() -> [PhraseSourcee]? {
            // Une seule instance pour toutes les phrases : son instanciation coûte plus que son usage,
            // et un ancien compte rendu sans empreinte repasse par ici à chaque recharger().
            let etiquettes = NLTagger(tagSchemes: [.nameType])
            return enBref?.filter { phrase in
                guard !phrase.sources.isEmpty else { return false }
                let dits = phrase.sources.flatMap { ValidationSources.segmentsSources(de: $0, dans: segments) }
                guard !dits.isEmpty else { return false }
                let lu = Set(ValidationSources.normaliser(dits.map(\.texte).joined(separator: " ")).split(separator: " ").map(String.init))
                return EnBref.motsNonDits(phrase.texte, lu: lu, etiquettes: etiquettes).isEmpty
            }
        }

        copie.fraicheur = etat(selon: segments)
        switch copie.fraicheur {
        case .aJour:
            copie.enBref = enBref?.filter { phrase in
                !phrase.sources.isEmpty && phrase.sources.allSatisfy { !ValidationSources.segmentsSources(de: $0, dans: segments).isEmpty }
            }
            copie.sujets = sujets
            copie.pointsCles = pointsClesValides
        case .perimee:
            // Une reformulation plus vieille que la transcription ne peut plus être garantie : le résumé construit prend sa place.
            copie.enBref = nil
            copie.pointsCles = pointsClesValides
            copie.sujets = sujetsValides()
        case .aVerifier:
            copie.enBref = enBrefControle()
            copie.pointsCles = pointsClesValides
            copie.sujets = sujetsValides()
        }
        return copie
    }

    /// Le compte rendu avec les noms donnés aux voix depuis l'analyse. Rien n'est écrit sur le disque : un
    /// nom changé plus tard se lit partout, sans refaire l'analyse.
    public func avecNoms(_ noms: [String: String]) -> CompteRendu {
        let donnes = noms.filter { !$0.value.isEmpty }
        guard !donnes.isEmpty else { return self }
        func nomme(_ texte: String) -> String {
            donnes.keys.sorted { $0.count > $1.count }.reduce(texte) { sortie, voix in
                sortie.replacingOccurrences(of: "\\b\(voix)\\b", with: donnes[voix] ?? voix, options: .regularExpression)
            }
        }
        func nomme(_ element: ElementSource) -> ElementSource {
            var copie = element
            copie.texte = nomme(element.texte)
            copie.responsable = element.responsable.map(nomme)
            return copie
        }
        var copie = self
        copie.decisions = decisions.map(nomme)
        copie.actions = actions.map(nomme)
        copie.questions = questions.map(nomme)
        copie.pointsCles = pointsCles?.map(nomme)
        copie.enBref = enBref?.map { PhraseSourcee(texte: nomme($0.texte), sources: $0.sources) }
        copie.sujets = sujets?.map { sujet in
            var nomme_ = sujet
            nomme_.titre = nomme(sujet.titre)
            nomme_.points = sujet.points?.map(nomme)
            return nomme_
        }
        return copie
    }

    /// Ce qu'on lit d'abord : « En bref » s'il existe, sinon le résumé construit.
    public var apercu: String {
        let phrases = (enBref ?? []).map(\.texte)
        return phrases.isEmpty ? resume : phrases.joined(separator: " ")
    }

    /// Résumé, décisions et actions, sans la transcription : prêt à coller.
    public func texteACopier(incidents: [IncidentAudio] = []) -> String {
        var parties = [apercu]
        if let avertissement = Self.perimee(fraicheur) { parties.append(avertissement) }
        if let audio = Self.audioIncomplet(incidents) { parties.append(audio) }
        func ligne(_ element: ElementSource) -> String {
            let details = [element.responsable, element.echeance].compactMap { $0 }
            return "- \(element.texte)" + (details.isEmpty ? "" : " (\(details.joined(separator: ", ")))")
        }
        if let pointsCles, !pointsCles.isEmpty { parties.append("Points clés\n" + pointsCles.map(ligne).joined(separator: "\n")) }
        if !decisions.isEmpty { parties.append("Décisions\n" + decisions.map(ligne).joined(separator: "\n")) }
        if !actions.isEmpty { parties.append("Actions\n" + actions.map(ligne).joined(separator: "\n")) }
        if !questions.isEmpty { parties.append("Questions ouvertes\n" + questions.map(ligne).joined(separator: "\n")) }
        return parties.joined(separator: "\n\n")
    }

    /// Il manque un moment de la réunion : ce qui en est tiré ne peut pas le cacher.
    private static func audioIncomplet(_ incidents: [IncidentAudio]) -> String? {
        incidents.isEmpty ? nil : "Audio incomplet : " + incidents.map(\.description).joined(separator: ", ") + "."
    }

    /// La transcription a changé depuis cette analyse : la copie et le Markdown le disent aussi.
    private static func perimee(_ fraicheur: Fraicheur) -> String? {
        fraicheur == .perimee ? "La transcription a changé depuis cette analyse : ce compte rendu n'est plus à jour." : nil
    }

    public func markdown(incidents: [IncidentAudio] = []) -> String {
        func bloc(_ titre: String, _ elements: [ElementSource]) -> String {
            guard !elements.isEmpty else { return "" }
            return "\n## \(titre)\n\n" + elements.map(ligne).joined(separator: "\n") + "\n"
        }
        func ligne(_ element: ElementSource) -> String {
            let details = [element.responsable, element.echeance].compactMap { $0 }
            var texte = "- \(element.texte)" + (details.isEmpty ? "" : " — \(details.joined(separator: ", "))")
                + " (\(element.sources.map { horodatage($0) }.joined(separator: ", ")))"
            if let citation = element.citationAffichee { texte += "\n  > « \(citation) »" }
            return texte
        }
        func sujet(_ sujet: Sujet) -> String {
            "### \(sujet.titre) (\(horodatage(sujet.debut)))\n\n" + (sujet.points ?? []).map { "- \($0.texte) (\($0.sources.map { horodatage($0) }.joined(separator: ", ")))" }.joined(separator: "\n")
        }
        return "# Compte rendu\n\nProduit par : \(fournisseur)\n\n\(apercu)\n"
            + (Self.perimee(fraicheur).map { "\n\($0)\n" } ?? "")
            + (Self.audioIncomplet(incidents).map { "\n\($0)\n" } ?? "")
            + bloc("Points clés", pointsCles ?? [])
            + bloc("Décisions", decisions) + bloc("Actions", actions) + bloc("Questions ouvertes", questions)
            + ((sujets ?? []).isEmpty ? "" : "\n## Sujets\n\n" + (sujets ?? []).map(sujet).joined(separator: "\n\n") + "\n")
    }
}

/// Règle 1 : un élément sans source vérifiable est écarté.
public enum ValidationSources {
    /// Tolérance autour d'une phrase, le modèle arrondissant ses horodatages.
    static let marge = 2.0

    static func normaliser(_ texte: String) -> String {
        texte.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func segmentsSources(de temps: Double, dans segments: [Segment]) -> [Segment] {
        segments.filter { temps >= $0.debut - marge && temps <= $0.fin + marge }
    }

    static func phrases(de texte: String) -> [String] {
        let decoupe = NLTokenizer(unit: .sentence)
        decoupe.string = texte
        decoupe.setLanguage(.french)
        return decoupe.tokens(for: texte.startIndex..<texte.endIndex).map {
            texte[$0].trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    /// Les phrases entières de ces segments qui contiennent la citation, telles que transcrites. Une
    /// citation tronquée ne peut pas perdre un « ne… pas » : on rend toujours la phrase complète.
    private static func phrasesEntieres(contenant cherche: String, dans segments: [Segment]) -> String? {
        let phrases = segments.flatMap { phrases(de: $0.texte) }
        guard !phrases.isEmpty else { return nil }
        for longueur in 1...phrases.count {
            for debut in 0...(phrases.count - longueur) {
                let bloc = phrases[debut..<(debut + longueur)].joined(separator: " ")
                if " \(normaliser(bloc)) ".contains(" \(cherche) ") { return bloc }
            }
        }
        return nil
    }

    /// Le contrôle le moins coûteux d'un contresens : une reformulation ne change pas le sens d'une négation.
    private static func negative(_ texte: String) -> Bool {
        let mots = Set(normaliser(texte).split(separator: " ").map(String.init))
        return !mots.isDisjoint(with: ["ne", "n", "pas", "jamais", "aucun", "aucune"])
    }

    /// Autour d'une source, ce qui compte comme dit pour un responsable, une échéance ou une reformulation.
    static let voisinage = 30.0

    /// L'élément si ses sources le prouvent, sinon nil. La citation est toujours la transcription, et elle
    /// reste affichée sous la reformulation : aucun contrôle ne peut prouver qu'une reformulation dit vrai,
    /// mais on peut toujours la comparer à sa preuve. Une reformulation avec un nom, un chiffre ou un moment
    /// absent de ce passage laisse place à la citation. Seules les sources où la citation se trouve restent,
    /// et un responsable ou une échéance doit être dans la phrase citée, ou être la voix qui la dit.
    public static func valider(_ element: ElementSource, dans segments: [Segment], noms: [String] = []) -> ElementSource? {
        guard !element.sources.isEmpty else { return nil }
        let passages = element.sources.map { segmentsSources(de: $0, dans: segments) }
        guard !passages.contains(where: \.isEmpty) else { return nil }

        let cherche = normaliser(element.citation ?? "")
        guard !cherche.isEmpty else { return nil }
        let prouvants = zip(element.sources, passages).filter { _, passage in
            " \(normaliser(passage.map(\.texte).joined(separator: " "))) ".contains(" \(cherche) ")
        }
        var vus = Set<UUID>()
        let cites = prouvants.flatMap(\.1).filter { vus.insert($0.id).inserted }.sorted { $0.debut < $1.debut }
        guard let phrases = phrasesEntieres(contenant: cherche, dans: cites) else { return nil }
        let temps = prouvants.map(\.0)
        let autour = segments.filter { segment in
            temps.contains { $0 >= segment.debut - voisinage && $0 <= segment.fin + voisinage }
        }
        let voix = Set(autour.compactMap(\.voix)).union(noms)
        let lu = normaliser(([phrases] + autour.map(\.texte) + Array(voix)).joined(separator: " "))
        // Un voisin nommé n'est pas pour autant responsable : il faut sa voix, ou son nom dans la phrase.
        let porte = normaliser(([phrases] + cites.compactMap(\.voix) + noms).joined(separator: " "))

        func dit(_ valeur: String?) -> String? {
            guard let valeur = valeur?.trimmingCharacters(in: .whitespacesAndNewlines), !valeur.isEmpty else { return nil }
            let mots = normaliser(valeur)
            return !mots.isEmpty && " \(porte) ".contains(" \(mots) ") ? valeur : nil
        }
        var valide = element
        let propose = element.texte.trimmingCharacters(in: .whitespacesAndNewlines)
        let tient = !propose.isEmpty && EnBref.motsNonDits(propose, lu: Set(lu.split(separator: " ").map(String.init))).isEmpty
            && negative(phrases) == negative(propose)
        valide.texte = tient ? propose : phrases
        valide.citation = phrases
        valide.sources = prouvants.map(\.0)
        valide.responsable = dit(element.responsable)
        valide.echeance = dit(element.echeance)
        return valide
    }
}

/// « En bref » est écrit par le modèle, à la demande de Steven : une reformulation peut donc se tromper, et
/// l'écran dit qui l'a rédigée. Chaque phrase doit au moins citer des lignes qui existent, et ne nommer
/// ni personne, ni chiffre, ni moment absent de ces lignes. Une phrase qui échoue n'est pas affichée.
public enum EnBref {
    public struct Propose: Sendable {
        public var texte: String
        public var lignes: [Int]

        public init(texte: String, lignes: [Int]) {
            self.texte = texte
            self.lignes = lignes
        }
    }

    static let maximum = 3

    private static let motsDeTemps: Set<String> = [
        "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche",
        "janvier", "fevrier", "mars", "avril", "mai", "juin", "juillet", "aout", "septembre", "octobre", "novembre", "decembre",
        "demain", "hier", "matin", "soir", "midi", "semaine", "mois", "annee",
    ]

    /// Les noms, chiffres et mots de temps du texte qui ne sont pas dans ce qui a été dit. `etiquettes`
    /// peut être réutilisé sur plusieurs phrases : son instanciation coûte plus que son usage, et
    /// `revalide` le fait pour chaque phrase d'« En bref » à chaque recharger().
    static func motsNonDits(_ texte: String, lu: Set<String>, etiquettes: NLTagger = NLTagger(tagSchemes: [.nameType])) -> [String] {
        var suspects = ValidationSources.normaliser(texte).split(separator: " ").map(String.init).filter { mot in
            motsDeTemps.contains(mot) || mot.contains(where: \.isNumber)
        }
        etiquettes.string = texte
        etiquettes.setLanguage(.french, range: texte.startIndex..<texte.endIndex)
        etiquettes.enumerateTags(in: texte.startIndex..<texte.endIndex, unit: .word, scheme: .nameType,
                                 options: [.omitWhitespace, .omitPunctuation, .joinNames]) { etiquette, plage in
            if let etiquette, [.personalName, .placeName, .organizationName].contains(etiquette) {
                suspects += ValidationSources.normaliser(String(texte[plage])).split(separator: " ").map(String.init)
            }
            return true
        }
        // Une majuscule au milieu d'une phrase annonce un nom propre.
        let bruts = texte.split(whereSeparator: \.isWhitespace)
        for (precedent, mot) in zip(bruts, bruts.dropFirst()) where mot.first?.isUppercase == true {
            if let dernier = precedent.last, ".!?:".contains(dernier) { continue }
            suspects += ValidationSources.normaliser(String(mot)).split(separator: " ").map(String.init)
        }
        return suspects.filter { !lu.contains($0) }
    }

    /// `lu` : tout ce qui compte comme dit, pour une synthèse qui dépasse les lignes qu'elle cite.
    public static func valider(_ proposes: [Propose], phrases: [String], debuts: [Double], lu dits: String? = nil) -> [PhraseSourcee] {
        guard phrases.count == debuts.count else { return [] }
        return proposes.compactMap { propose -> PhraseSourcee? in
            let texte = propose.texte.trimmingCharacters(in: .whitespacesAndNewlines)
            let lignes = propose.lignes.filter { phrases.indices.contains($0 - 1) }
            guard !texte.isEmpty, !lignes.isEmpty, lignes.count == propose.lignes.count else { return nil }
            let lu = Set(ValidationSources.normaliser(dits ?? lignes.map { phrases[$0 - 1] }.joined(separator: " ")).split(separator: " ").map(String.init))
            guard motsNonDits(texte, lu: lu).isEmpty else { return nil }
            return PhraseSourcee(texte: texte, sources: lignes.map { debuts[$0 - 1] })
        }.prefix(maximum).map { $0 }
    }
}

/// Le découpage en sujets proposé par le modèle. Ses bornes doivent exister, et son titre ne doit
/// contenir que des mots dits dans ce moment : sinon, le titre devient le début de sa première phrase.
public enum DecoupageSujets {
    public struct Propose: Sendable {
        public var titre: String
        public var premiere: Int
        public var derniere: Int

        public init(titre: String, premiere: Int, derniere: Int) {
            self.titre = titre
            self.premiere = premiere
            self.derniere = derniere
        }
    }

    private static let motsGrammaticaux: Set<String> = [
        "à", "au", "aux", "de", "des", "du", "en", "et", "la", "le", "les"
    ]
    private static let caracteresInterdits = try! NSRegularExpression(pattern: #"[^\p{L}\p{N}\p{M}\s'’\-—–,.:()«»"]"#)
    private static let nombresAmbigus = try! NSRegularExpression(pattern: #"\d[^\p{L}\p{N}]+\d|-\s*\d"#)
    private static let motsTitre = try! NSRegularExpression(pattern: #"[\p{L}\p{N}\p{M}]+"#)
    private static let lettreInitiale = try! NSRegularExpression(pattern: #"^\p{L}"#)

    /// Un titre douteux revient aux mots dits ; l'ordre et la négation ne sont pas contrôlés.
    static func titreDit(_ titre: String, lu: Set<Substring>) -> Bool {
        let titre = titre.precomposedStringWithCanonicalMapping
        let texte = titre as NSString
        let entier = NSRange(location: 0, length: texte.length)
        guard caracteresInterdits.firstMatch(in: titre, range: entier) == nil,
              nombresAmbigus.firstMatch(in: titre, range: entier) == nil else { return false }
        // Les tirets longs séparent des mots, jamais des nombres ou un bord de titre.
        for index in titre.indices where titre[index] == "—" || titre[index] == "–" {
            let avant = titre[..<index].trimmingCharacters(in: .whitespacesAndNewlines)
            let apres = titre[titre.index(after: index)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard avant.last?.isLetter == true, apres.first?.isLetter == true else { return false }
        }
        var porteur = false
        for correspondance in motsTitre.matches(in: titre, range: entier) {
            let brut = texte.substring(with: correspondance.range)
            let minuscule = brut.lowercased()
            let suite = correspondance.range.location + correspondance.range.length
            let apostrophe = suite < texte.length && ["'", "’"].contains(texte.substring(with: NSRange(location: suite, length: 1)))
            let apres = suite + 1
            let lettreApres = apres < texte.length && lettreInitiale.firstMatch(
                in: texte.substring(from: apres), range: NSRange(location: 0, length: texte.length - apres)) != nil
            let elision = ["l", "d", "c", "j", "m", "n", "s", "t", "qu"].contains(minuscule) && apostrophe && lettreApres
            let capitales = brut == brut.uppercased()
            guard !(brut.count == 1 && brut.first!.isLetter && !["à", "À"].contains(brut) && !elision),
                  !(capitales && (motsGrammaticaux.contains(minuscule) || ["un", "une"].contains(minuscule)) && brut != "À") else { return false }
            let grammatical = (brut == "À") || elision || (!capitales && motsGrammaticaux.contains(minuscule))
            if !grammatical {
                porteur = true
                let mots = ValidationSources.normaliser(brut).split(separator: " ")
                guard !mots.isEmpty, mots.allSatisfy({ lu.contains($0) }) else { return false }
            }
        }
        return porteur
    }

    /// Un titre rédigé par le modèle (« Interviews et atelier ») : court, et sans nom, chiffre ni moment
    /// absent de ce qui a été dit.
    static func titreRedige(_ titre: String, lu: Set<String>) -> Bool {
        let mots = titre.split(whereSeparator: \.isWhitespace)
        return !mots.isEmpty && mots.count <= 8 && EnBref.motsNonDits(titre, lu: lu).isEmpty
    }

    public static func valider(_ proposes: [Propose], phrases: [String], debuts: [Double], fin: Double, redige: Bool = false) -> [Sujet] {
        guard phrases.count == debuts.count, !phrases.isEmpty else { return [] }
        var sujets: [Sujet] = []
        var suivante = 1
        for propose in proposes.sorted(by: { $0.premiere < $1.premiere }) {
            let premiere = max(propose.premiere, suivante)
            let derniere = min(propose.derniere, phrases.count)
            guard premiere >= 1, premiere <= derniere else { continue }
            let dites = phrases[(premiere - 1)..<derniere]
            let lu = Set(ValidationSources.normaliser(dites.joined(separator: " ")).split(separator: " "))
            let titre = propose.titre.trimmingCharacters(in: .whitespacesAndNewlines)
            let dit = redige ? titreRedige(titre, lu: Set(lu.map(String.init))) : titreDit(titre, lu: lu)
            let debutPhrase = dites.first.map { $0.split(separator: " ").prefix(6).joined(separator: " ") } ?? ""
            sujets.append(Sujet(titre: dit ? titre : debutPhrase, debut: debuts[premiere - 1],
                                fin: derniere < debuts.count ? debuts[derniere] : fin))
            suivante = derniere + 1
        }
        return sujets
    }
}

public protocol Analyste: Sendable {
    var nom: String { get }
    func analyser(segments: [Segment], notes: [LigneDeNote], type: TypeReunion,
                  progression: @escaping @Sendable (Double) -> Void) async throws -> CompteRendu
}

public enum ErreurAnalyse: LocalizedError {
    case indisponible(String)
    case rienAAnalyser
    case aucunPassage

    public var errorDescription: String? {
        switch self {
        case let .indisponible(raison): return "L'analyse locale n'est pas disponible : \(raison)"
        case .rienAAnalyser: return "Il n'y a pas de transcription à analyser."
        case .aucunPassage: return "Aucun passage n'a pu être analysé. Rien n'a été inventé : réessaie plus tard."
        }
    }
}

/// Foundation Models sur l'appareil, à la façon de Cairn : chaque passage donne ses sujets, ses décisions et
/// ses actions, fusionnés ici, puis l'essentiel s'écrit à partir des sujets. La fenêtre de 4 096 tokens étant
/// partagée entre l'entrée et la sortie, la transcription est découpée en passages selon sa longueur réelle.
public struct AnalysteLocal: Analyste {
    public let nom = "Local · Apple Intelligence"
    /// Tokens de transcription par passage : il reste la place de la consigne et d'une réponse.
    static let budgetPassage = 2_200
    static let reponsePassage = 500
    static let reponseSynthese = 400

    public init() {}

    /// Résumer les mots de quelqu'un, c'est les transformer, d'où ces garde-fous : ceux par défaut
    /// refusent parfois un passage pour un mot sorti de son contexte.
    private let modele = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    /// Partagée par les consignes qui lisent une transcription marquée (ici et dans
    /// `AnalysteMistral.consigne`), pour n'écrire qu'une fois ce que signifie la mention.
    static let consigneEcho = """
     Une ligne « écho probable » est peut-être ce que le micro a capté du haut-parleur plutôt qu'une vraie réponse : \
    elle peut servir de preuve, mais ne conclus pas que c'est « moi » qui l'a dite, et ne la compte pas comme \
    une deuxième occurrence de ce qu'elle répète.
    """

    /// Une phrase de la transcription, numérotée pour le modèle.
    struct Ligne {
        var phrase: String
        var debut: Double
        var piste: Piste
        var voix: String?
        /// Vrai si la ligne est sans doute l'écho du haut-parleur plutôt qu'une vraie réponse.
        var echoProbable: Bool = false
    }

    static func lignes(de passage: [Segment]) -> [Ligne] {
        passage.flatMap { segment in
            ValidationSources.phrases(de: segment.texte).map {
                Ligne(phrase: $0, debut: segment.debut, piste: segment.piste, voix: segment.voix, echoProbable: segment.echoProbable ?? false)
            }
        }
    }

    static func invite(_ lignes: [Ligne], notes: [LigneDeNote], type: TypeReunion) -> String {
        // Une ligne marquée reste une preuve citable, mais elle n'est pas forcément dite par moi avec
        // certitude : c'est peut-être l'écho du haut-parleur.
        // Une ligne marquée vient forcément du micro pendant une visio (`marquerEcho` a besoin
        // de la piste système, qui n'existe que là) : `qui` n'est donc jamais vide ici.
        func qui(_ ligne: Ligne) -> String {
            var qui = ligne.voix ?? (type == .visio ? (ligne.piste == .micro ? "moi" : "eux") : "")
            if ligne.echoProbable { qui += ", écho probable" }
            return qui.isEmpty ? "" : "\(qui) : "
        }
        let debut = (lignes.first?.debut ?? 0) - 15
        let fin = (lignes.last?.debut ?? 0) + 15
        let ancres = notes.filter { $0.temps >= debut && $0.temps <= fin && !$0.texte.isEmpty }
        var texte = ""
        if !ancres.isEmpty {
            texte += "Regarde en priorité autour de ce que j'ai noté :\n"
            texte += ancres.map { "- \($0.texte)" }.joined(separator: "\n") + "\n\n"
        }
        texte += "Transcription :\n"
        texte += lignes.enumerated().map { "\($0.offset + 1). \(qui($0.element))\($0.element.phrase)" }.joined(separator: "\n")
        return texte
    }

    /// Une puce rédigée et la phrase de sa ligne, sa preuve. Le numéro doit exister.
    static func element(_ puce: Gabarit.Puce, dans lignes: [Ligne], responsable: String? = nil) -> ElementSource? {
        guard lignes.indices.contains(puce.ligne - 1) else { return nil }
        let ligne = lignes[puce.ligne - 1]
        return ElementSource(texte: puce.texte, sources: [ligne.debut], citation: ligne.phrase, responsable: responsable)
    }

    /// Les lignes rangées en passages d'au plus `budget` tokens estimés, coupés entre deux lignes.
    static func passages(_ lignes: [Ligne], budget: Int = budgetPassage) -> [[Ligne]] {
        var sortie: [[Ligne]] = []
        var courant: [Ligne] = []
        var estime = 0
        for ligne in lignes {
            let cout = max(1, ligne.phrase.count / 3)
            if !courant.isEmpty, estime + cout > budget {
                sortie.append(courant)
                courant = []
                estime = 0
            }
            courant.append(ligne)
            estime += cout
        }
        if !courant.isEmpty { sortie.append(courant) }
        return sortie
    }

    /// Un passage lu par le modèle, gardé seulement s'il tient sur ses preuves.
    struct PassageChoisi {
        var decisions: [ElementSource] = []
        var actions: [ElementSource] = []
        var questions: [ElementSource] = []
        var sujets: [Sujet] = []
        var ecartes = 0
    }

    static func choisir(_ lu: Gabarit.PassageLu, dans lignes: [Ligne], segments: [Segment], noms: [String] = []) -> PassageChoisi {
        var choisi = PassageChoisi()
        func garder(_ puce: Gabarit.Puce, responsable: String? = nil) -> ElementSource? {
            guard let brut = element(puce, dans: lignes, responsable: responsable),
                  let valide = ValidationSources.valider(brut, dans: segments, noms: noms) else {
                choisi.ecartes += 1
                return nil
            }
            return valide
        }
        choisi.decisions = lu.decisions.compactMap { garder($0) }
        choisi.actions = lu.actions.compactMap { puce in
            let (tache, responsable) = Gabarit.action(puce.texte)
            return garder(Gabarit.Puce(ligne: puce.ligne, texte: tache), responsable: responsable)
        }
        choisi.questions = lu.questions.compactMap { garder($0) }
        let dits = Set(ValidationSources.normaliser((lignes.map(\.phrase) + lignes.compactMap(\.voix) + noms).joined(separator: " ")).split(separator: " ").map(String.init))
        choisi.sujets = lu.sujets.compactMap { sujet in
            let points = sujet.points.compactMap { garder($0) }
            let temps = points.flatMap(\.sources)
            guard let debut = temps.min(), let fin = temps.max() else { return nil }
            let titre = DecoupageSujets.titreRedige(sujet.titre, lu: dits) ? sujet.titre : (points.first?.texte ?? sujet.titre)
            return Sujet(titre: titre, debut: debut, fin: fin, points: points)
        }
        return choisi
    }

    private func repondre(_ question: String, consigne: String, maximum: Int) async throws -> String {
        let session = LanguageModelSession(model: modele, instructions: consigne)
        // Sans tirage au hasard : la même réunion donne le même compte rendu.
        return try await session.respond(to: question, options: GenerationOptions(sampling: .greedy, maximumResponseTokens: maximum)).content
    }

    private func lirePassage(_ lignes: [Ligne], notes: [LigneDeNote], type: TypeReunion, contexte: String) async throws -> [(Gabarit.PassageLu, [Ligne])] {
        let question = "\(contexte)\n\nVoici un passage de la transcription d'une réunion.\n\n\(Self.invite(lignes, notes: notes, type: type))\n\n\(Gabarit.passage)"
        do {
            if lignes.count > 1, try await modele.tokenCount(for: question) > 3_400 { throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "passage trop long")) }
            let reponse = try await repondre(question, consigne: Gabarit.secretaire + Self.consigneEcho, maximum: Self.reponsePassage)
            return [(Gabarit.lirePassage(reponse), lignes)]
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize where lignes.count > 1 {
            // Un passage trop dense pour la fenêtre : on le coupe en deux.
            let milieu = lignes.count / 2
            let a = try await lirePassage(Array(lignes[..<milieu]), notes: notes, type: type, contexte: contexte)
            let b = try await lirePassage(Array(lignes[milieu...]), notes: notes, type: type, contexte: contexte)
            return a + b
        }
    }

    /// Les prénoms déjà donnés aux voix comptent comme dits : ils sont dans l'invite.
    public func analyser(segments: [Segment], notes: [LigneDeNote], type: TypeReunion,
                         progression: @escaping @Sendable (Double) -> Void) async throws -> CompteRendu {
        guard !segments.isEmpty else { throw ErreurAnalyse.rienAAnalyser }
        switch SystemLanguageModel.default.availability {
        case .available: break
        case let .unavailable(raison): throw ErreurAnalyse.indisponible(String(describing: raison))
        }

        let ordonnes = segments.sorted { $0.debut < $1.debut }
        let toutes = Self.lignes(de: ordonnes)
        let contexte = Gabarit.contexte(lignes: toutes, type: type, moi: NSFullUserName().split(separator: " ").first.map(String.init) ?? "moi")
        let passages = Self.passages(toutes)
        var decisions: [ElementSource] = []
        var actions: [ElementSource] = []
        var questions: [ElementSource] = []
        var sujets: [Sujet] = []
        var echecs = 0
        var ecartes = 0

        for (rang, passage) in passages.enumerated() {
            do {
                for (lu, lignes) in try await lirePassage(passage, notes: notes, type: type, contexte: contexte) {
                    let choisi = Self.choisir(lu, dans: lignes, segments: ordonnes)
                    decisions += choisi.decisions
                    actions += choisi.actions
                    questions += choisi.questions
                    sujets += choisi.sujets
                    ecartes += choisi.ecartes
                }
            } catch {
                // Un passage refusé par le modèle ne bloque pas les autres, et il est compté.
                echecs += 1
            }
            progression(Double(rang + 1) / Double(passages.count + 1))
        }
        guard echecs < passages.count else { throw ErreurAnalyse.aucunPassage }

        let finales = Self.assembler(decisions: decisions, actions: actions, questions: questions, sujets: sujets, fin: ordonnes.last?.fin ?? 0)

        // L'essentiel s'écrit à partir des sujets : le modèle ne reçoit plus la transcription.
        let points = finales.sujets.flatMap { $0.points ?? [] }
        var enBref: [PhraseSourcee]?
        var pointsCles: [ElementSource]?
        if !points.isEmpty {
            let liste = points.enumerated().map { "\($0.offset + 1). \($0.element.texte)" }.joined(separator: "\n")
            let question = "\(contexte)\n\nLes points de la réunion :\n\(liste)\n\n\(Gabarit.synthese)"
            if let reponse = try? await repondre(question, consigne: Gabarit.secretaire, maximum: Self.reponseSynthese) {
                let lu = Gabarit.lireSynthese(reponse)
                enBref = Self.enBref(lu.enBref, points: points, segments: ordonnes)
                pointsCles = Self.pointsCles(lu.points, points: points)
            }
        }

        progression(1)
        return CompteRendu(fournisseur: nom, decisions: finales.decisions, actions: finales.actions, questions: finales.questions,
                           sujets: finales.sujets, enBref: enBref, pointsCles: pointsCles,
                           passagesNonAnalyses: echecs, elementsEcartes: ecartes)
    }

    /// Fusionné ici plutôt que rendu au modèle : devant une page de notes à réécrire, il mêle qui fait quoi
    /// et se répète. Une action prime sur une décision, une décision sur une question.
    static func assembler(decisions: [ElementSource], actions: [ElementSource], questions: [ElementSource], sujets: [Sujet], fin: Double)
        -> (decisions: [ElementSource], actions: [ElementSource], questions: [ElementSource], sujets: [Sujet]) {
        let actionsGardees = Array(Gabarit.distincts(actions).prefix(Gabarit.maxActions))
        let decisionsGardees = Array(Gabarit.distincts(decisions, autres: actionsGardees).prefix(Gabarit.maxDecisions))
        let questionsGardees = Array(Gabarit.distincts(questions, autres: actionsGardees + decisionsGardees).prefix(Gabarit.maxQuestions))
        var fusionnes = Array(Gabarit.fusionner(sujets).prefix(Gabarit.maxSujets)).sorted { $0.debut < $1.debut }
        for rang in fusionnes.indices {
            fusionnes[rang].points = fusionnes[rang].points.map { Array($0.prefix(Gabarit.maxPointsParSujet)) }
            let suivant = rang + 1 < fusionnes.count ? fusionnes[rang + 1].debut : fin
            fusionnes[rang].fin = max(fusionnes[rang].fin, suivant)
        }
        return (decisionsGardees, actionsGardees, questionsGardees, fusionnes)
    }

    /// Les sources d'une phrase de synthèse : le point dont elle reprend le plus de mots.
    static func enBref(_ phrases: [String], points: [ElementSource], segments: [Segment]) -> [PhraseSourcee]? {
        let lu = Set(ValidationSources.normaliser(segments.map(\.texte).joined(separator: " ")).split(separator: " ").map(String.init))
            .union(ValidationSources.normaliser(segments.compactMap(\.voix).joined(separator: " ")).split(separator: " ").map(String.init))
        let gardees = phrases.compactMap { phrase -> PhraseSourcee? in
            guard EnBref.motsNonDits(phrase, lu: lu).isEmpty else { return nil }
            let mots = Gabarit.mots(phrase)
            let proche = points.max { Gabarit.recouvrement(mots, Gabarit.mots($0.texte)) < Gabarit.recouvrement(mots, Gabarit.mots($1.texte)) }
            return proche.map { PhraseSourcee(texte: phrase, sources: $0.sources) }
        }
        return gardees.isEmpty ? nil : gardees
    }

    /// Un point clé reprend la source et la citation du point dont il porte le numéro.
    static func pointsCles(_ puces: [Gabarit.Puce], points: [ElementSource]) -> [ElementSource]? {
        let gardes = puces.compactMap { puce -> ElementSource? in
            guard points.indices.contains(puce.ligne - 1) else { return nil }
            var point = points[puce.ligne - 1]
            point.id = UUID()
            point.texte = puce.texte
            return point
        }
        let distincts = Array(Gabarit.distincts(gardes).prefix(Gabarit.maxPointsCles))
        return distincts.isEmpty ? nil : distincts
    }
}
