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
}

/// Un sujet abordé : un moment de la réunion et un titre fait de ses propres mots.
public struct Sujet: Codable, Sendable, Identifiable, Hashable {
    public var id = UUID()
    public var titre: String
    public var debut: Double
    public var fin: Double

    public init(titre: String, debut: Double, fin: Double) {
        self.titre = titre
        self.debut = debut
        self.fin = fin
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
    public var passagesNonAnalyses: Int
    public var elementsEcartes: Int
    /// L'empreinte de la transcription lue par l'analyse. Absente avant ce contrôle : l'analyse reste « à vérifier ».
    public var empreinte: String?
    /// Calculée à chaque lecture face à la transcription actuelle (`revalide`) : jamais lue ni écrite sur disque.
    public var fraicheur: Fraicheur = .aJour

    private enum CodingKeys: String, CodingKey {
        case fournisseur, date, decisions, actions, questions, sujets, enBref, passagesNonAnalyses, elementsEcartes, empreinte
    }

    public init(fournisseur: String, date: Date = Date(), decisions: [ElementSource], actions: [ElementSource],
                questions: [ElementSource], sujets: [Sujet]? = nil, enBref: [PhraseSourcee]? = nil, empreinte: String? = nil,
                passagesNonAnalyses: Int = 0, elementsEcartes: Int = 0) {
        self.fournisseur = fournisseur
        self.date = date
        self.decisions = decisions
        self.actions = actions
        self.questions = questions
        self.passagesNonAnalyses = passagesNonAnalyses
        self.sujets = sujets
        self.enBref = enBref
        self.elementsEcartes = elementsEcartes
        self.empreinte = empreinte
    }

    /// Le flux ignore les bornes des segments : un découpage différent au même contenu rend la même empreinte.
    /// Seuls un mot, une voix, une piste ou une marque d'écho différents la changent. Le nom donné à une
    /// voix n'y entre pas. La piste entre, car une même phrase sans voix renseignée ne dit pas la même
    /// chose selon qu'elle vient du micro ou du son du Mac (voir `invite`, `qui`).
    public static func empreinte(de segments: [Segment]) -> String {
        var flux = ""
        var dernierePiste: Piste?
        var derniereVoix: String?
        var dernierEcho = false
        var premier = true
        for segment in segments {
            // Un segment sans aucun mot (« … » seul) ne doit rien changer, y compris ses marqueurs :
            // sinon un espace supplémentaire suffirait à rendre une analyse périmée à tort.
            let texte = ValidationSources.normaliser(segment.texte)
            guard !texte.isEmpty else { continue }
            if premier || segment.piste != dernierePiste {
                flux += "#\(segment.piste.rawValue)#"
                dernierePiste = segment.piste
            }
            if premier || segment.voix != derniereVoix {
                flux += "§\(segment.voix ?? "")§"
                derniereVoix = segment.voix
            }
            let echo = segment.echoProbable == true
            if premier || echo != dernierEcho {
                flux += echo ? "¤echo¤" : "¤¤"
                dernierEcho = echo
            }
            flux += texte + " "
            premier = false
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

    /// Une analyse relue depuis le disque repasse la validation : une ancienne reformulation laisse
    /// place à la transcription, et ce qui n'est plus prouvé est écarté. Son état face à la transcription
    /// actuelle décide ensuite du sort d'« En bref » et des sujets (règle 1 : rien n'est affiché sans preuve).
    public func revalide(dans segments: [Segment]) -> CompteRendu {
        var copie = self
        func garder(_ elements: [ElementSource]) -> [ElementSource] {
            let gardes = elements.compactMap { ValidationSources.valider($0, dans: segments) }
            copie.elementsEcartes += elements.count - gardes.count
            return gardes
        }
        copie.decisions = garder(decisions)
        copie.actions = garder(actions)
        copie.questions = garder(questions)

        // Un sujet n'est retiré que si ses bornes ne tombent plus sur un segment. Son titre, lui, doit
        // encore être fait de mots dits dans ce moment (comme DecoupageSujets.valider à l'analyse) :
        // sinon il revient aux six premiers mots dits du passage, bornes et id conservés.
        func sujetsValides() -> [Sujet]? {
            sujets?.compactMap { sujet -> Sujet? in
                let sources = ValidationSources.segmentsSources(de: sujet.debut, dans: segments)
                guard !sources.isEmpty else { return nil }
                // Un long segment peut englober tout le sujet : on garde ce qui le chevauche, pas seulement ce qui y commence ou finit.
                let chevauchants = segments.filter { $0.fin >= sujet.debut && $0.debut <= sujet.fin }
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
        case .perimee:
            // Une reformulation plus vieille que la transcription ne peut plus être garantie : le résumé construit prend sa place.
            copie.enBref = nil
            copie.sujets = sujetsValides()
        case .aVerifier:
            copie.enBref = enBrefControle()
            copie.sujets = sujetsValides()
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
        if !decisions.isEmpty { parties.append("Décisions\n" + decisions.map { "- \($0.texte)" }.joined(separator: "\n")) }
        if !actions.isEmpty { parties.append("Actions\n" + actions.map { "- \($0.texte)" }.joined(separator: "\n")) }
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
            let lignes = elements.map { element in
                "- \(element.texte) (\(element.sources.map { horodatage($0) }.joined(separator: ", ")))"
            }
            return "\n## \(titre)\n\n" + lignes.joined(separator: "\n") + "\n"
        }
        return "# Compte rendu\n\nProduit par : \(fournisseur)\n\n\(apercu)\n"
            + (Self.perimee(fraicheur).map { "\n\($0)\n" } ?? "")
            + (Self.audioIncomplet(incidents).map { "\n\($0)\n" } ?? "")
            + ((sujets ?? []).isEmpty ? "" : "\n## Sujets\n\n" + (sujets ?? []).map { "- \($0.titre) (\(horodatage($0.debut)))" }.joined(separator: "\n") + "\n")
            + bloc("Décisions", decisions) + bloc("Actions", actions) + bloc("Questions ouvertes", questions)
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

    /// L'élément si ses sources le prouvent, sinon nil. Son texte est toujours la transcription : aucune
    /// reformulation n'est gardée, puisqu'aucun contrôle ne peut prouver qu'elle dit vrai. Seules les sources
    /// où la citation se trouve restent, et un responsable ou une échéance doit être dans la phrase rendue.
    public static func valider(_ element: ElementSource, dans segments: [Segment]) -> ElementSource? {
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
        let lu = normaliser(phrases)

        func dit(_ valeur: String?) -> String? {
            guard let valeur = valeur?.trimmingCharacters(in: .whitespacesAndNewlines), !valeur.isEmpty else { return nil }
            let mots = normaliser(valeur)
            return !mots.isEmpty && " \(lu) ".contains(" \(mots) ") ? valeur : nil
        }
        var valide = element
        valide.texte = phrases
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

    public static func valider(_ proposes: [Propose], phrases: [String], debuts: [Double]) -> [PhraseSourcee] {
        guard phrases.count == debuts.count else { return [] }
        return proposes.compactMap { propose -> PhraseSourcee? in
            let texte = propose.texte.trimmingCharacters(in: .whitespacesAndNewlines)
            let lignes = propose.lignes.filter { phrases.indices.contains($0 - 1) }
            guard !texte.isEmpty, !lignes.isEmpty, lignes.count == propose.lignes.count else { return nil }
            let lu = Set(lignes.flatMap { ValidationSources.normaliser(phrases[$0 - 1]).split(separator: " ").map(String.init) })
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

    /// Exceptions sur le mot brut : « a » n'est pas « à », ni « LA » le déterminant « la ».
    private static let motsGrammaticaux: Set<String> = [
        "à", "au", "aux", "de", "des", "du", "en", "et", "la", "le", "les", "un", "une"
    ]

    /// Les unités et nombres ambigus reviennent aux mots dits plutôt que d'être interprétés.
    static func titreDit(_ titre: String, lu: Set<Substring>) -> Bool {
        guard titre.rangeOfCharacter(from: CharacterSet(charactersIn: "€$£%")) == nil,
              titre.range(of: #"\d[\s,.]+\d"#, options: .regularExpression) == nil else { return false }
        let expression = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#)
        let texte = titre as NSString
        var porteur = false
        for correspondance in expression.matches(in: titre, range: NSRange(location: 0, length: texte.length)) {
            let brut = texte.substring(with: correspondance.range)
            let minuscule = brut.lowercased()
            let suite = correspondance.range.location + correspondance.range.length
            let apostrophe = suite < texte.length && ["'", "’"].contains(texte.substring(with: NSRange(location: suite, length: 1)))
            let capitales = brut == brut.uppercased()
            let elision = ["l", "d"].contains(minuscule) && apostrophe
            let grammatical = (brut == "À") || elision || (!capitales && motsGrammaticaux.contains(minuscule))
            if !grammatical {
                porteur = true
                let mots = ValidationSources.normaliser(brut).split(separator: " ")
                guard !mots.isEmpty, mots.allSatisfy({ lu.contains($0) }) else { return false }
            }
        }
        return porteur
    }

    public static func valider(_ proposes: [Propose], phrases: [String], debuts: [Double], fin: Double) -> [Sujet] {
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
            let dit = titreDit(titre, lu: lu)
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

@Generable
struct LignesChoisies {
    @Guide(description: "Les numéros des lignes retenues. Vide s'il n'y en a aucune.")
    var lignes: [Int]
}

@Generable
struct Confirmation {
    @Guide(description: "Vrai seulement si la ligne marquée correspond clairement, d'après son contexte.")
    var correspond: Bool
}

@Generable
struct PhraseGeneree {
    @Guide(description: "Une phrase simple, qui ne dit que ce que disent ses lignes.")
    var texte: String
    @Guide(description: "Les numéros des lignes que cette phrase résume.")
    var lignes: [Int]
}

@Generable
struct EnBrefGenere {
    @Guide(description: "Deux ou trois phrases, pas plus.")
    var phrases: [PhraseGeneree]
}

@Generable
struct SujetChoisi {
    @Guide(description: "Le sujet en deux à cinq mots, repris tels quels de ces lignes.")
    var titre: String
    @Guide(description: "Le numéro de la première ligne du sujet.")
    var premiere: Int
    @Guide(description: "Le numéro de la dernière ligne du sujet.")
    var derniere: Int
}

@Generable
struct SujetsChoisis {
    @Guide(description: "Les sujets, dans l'ordre de la réunion.")
    var sujets: [SujetChoisi]
}

@Generable
struct ActionChoisie {
    @Guide(description: "Le numéro de la ligne.")
    var ligne: Int
    @Guide(description: "La personne qui doit le faire, seulement si la ligne la nomme. Sinon vide.")
    var responsable: String
    @Guide(description: "L'échéance, seulement si la ligne la dit. Sinon vide.")
    var echeance: String
}

@Generable
struct ActionsChoisies {
    @Guide(description: "Les lignes retenues. Vide s'il n'y en a aucune.")
    var actions: [ActionChoisie]
}

/// Foundation Models sur l'appareil. La fenêtre de 4 096 tokens étant partagée entre
/// l'entrée et la sortie, la transcription est découpée en passages d'environ cinq minutes.
public struct AnalysteLocal: Analyste {
    public let nom = "Local · Apple Intelligence"
    static let dureePassage = 300.0
    static let motsMinimum = 4

    public init() {}

    /// Résumer les mots de quelqu'un, c'est les transformer, d'où ces garde-fous : ceux par défaut
    /// refusent parfois un passage pour un mot sorti de son contexte.
    private func session(_ consigne: String) -> LanguageModelSession {
        LanguageModelSession(model: SystemLanguageModel(guardrails: .permissiveContentTransformations), instructions: consigne)
    }

    /// Partagée par les quatre consignes qui lisent une transcription marquée (ici et dans
    /// `AnalysteMistral.consigne`), pour n'écrire qu'une fois ce que signifie la mention.
    static let consigneEcho = """
     Une ligne « écho probable » est peut-être ce que le micro a capté du haut-parleur plutôt qu'une vraie réponse : \
    elle peut servir de preuve, mais ne conclus pas que c'est « moi » qui l'a dite, et ne la compte pas comme \
    une deuxième occurrence de ce qu'elle répète.
    """
    /// Le modèle ne recopie ni n'écrit rien : il choisit des numéros de lignes, une catégorie à la fois.
    /// Le texte rendu est donc toujours celui de la transcription.
    private static let consigneCommune = """
    Tu relis la transcription d'une réunion, ligne par ligne. Chaque ligne a un numéro. \
    Renvoie seulement les numéros demandés. Sois attentif : ne manque aucune ligne qui correspond, \
    et n'en retiens aucune qui ne correspond pas.
    """ + consigneEcho
    static let consigneDecisions = consigneCommune + """
     Retiens les lignes où un choix est arrêté : ce qui est décidé, retenu, validé, refusé, maintenu ou abandonné. \
    Pas les avis, les préférences, les constats, les questions ni les tâches à faire.
    """
    static let consigneActions = consigneCommune + """
     Retiens les lignes qui disent qu'une tâche précise est à faire : quelqu'un fait, envoie, appelle, réserve, écrit ou demande quelque chose. \
    Pas les choix arrêtés, les constats, les questions ni les simples accords.
    """
    static let consigneEnBref = """
    Tu résumes une réunion en français, en deux ou trois phrases simples, pour quelqu'un qui veut savoir \
    en dix secondes ce qui s'est dit. Tu ne t'appuies que sur les lignes numérotées qu'on te donne, et tu indiques \
    celles que chaque phrase résume. Tu n'inventes ni nom, ni date, ni chiffre. Ce qui a été promis n'est pas encore fait.
    """ + consigneEcho
    static let consigneSujets = """
    Tu relis la transcription d'une réunion, ligne par ligne. Chaque ligne a un numéro. \
    Découpe-la en sujets abordés, un à six, dans l'ordre. Un sujet réunit des lignes qui se suivent. \
    Ne compte pas les politesses comme un sujet. Son titre reprend des mots de ces lignes, tels quels.
    """ + consigneEcho
    static let consigneQuestions = consigneCommune + """
     Retiens les lignes qui posent une vraie question sur le travail, à laquelle les lignes suivantes ne répondent pas. \
    Pas les questions de politesse, ni celles qui reçoivent une réponse.
    """

    static func decouper(_ segments: [Segment], duree: Double = dureePassage) -> [[Segment]] {
        var passages: [[Segment]] = []
        var courant: [Segment] = []
        for segment in segments.sorted(by: { $0.debut < $1.debut }) {
            if let premier = courant.first, segment.debut - premier.debut >= duree {
                passages.append(courant)
                courant = []
            }
            courant.append(segment)
        }
        if !courant.isEmpty { passages.append(courant) }
        return passages
    }

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

    static func element(_ numero: Int, dans lignes: [Ligne], responsable: String? = nil, echeance: String? = nil) -> ElementSource? {
        guard lignes.indices.contains(numero - 1) else { return nil }
        let ligne = lignes[numero - 1]
        return ElementSource(texte: ligne.phrase, sources: [ligne.debut], citation: ligne.phrase, responsable: responsable, echeance: echeance)
    }

    private func analyserPassage(_ passage: [Segment], notes: [LigneDeNote], type: TypeReunion) async throws -> PassageChoisi {
        let lignes = Self.lignes(de: passage)
        let texte = Self.invite(lignes, notes: notes, type: type)
        // Sans tirage au hasard : la même réunion donne le même compte rendu.
        let options = GenerationOptions(sampling: .greedy)
        do {
            let decisions = try await session(Self.consigneDecisions)
                .respond(to: texte, generating: LignesChoisies.self, options: options).content.lignes
            let actions = try await session(Self.consigneActions)
                .respond(to: texte, generating: ActionsChoisies.self, options: options).content.actions
            let questions = try await session(Self.consigneQuestions)
                .respond(to: texte, generating: LignesChoisies.self, options: options).content.lignes
            // « Très bien » ou « ok ça marche » ne disent rien à eux seuls, même si le modèle les retient.
            func parlante(_ numero: Int) -> Bool {
                !lignes.indices.contains(numero - 1)
                    || ValidationSources.normaliser(lignes[numero - 1].phrase).split(separator: " ").count >= Self.motsMinimum
            }
            var choisi = PassageChoisi(decisions: [], actions: [], questions: [])
            for numero in decisions where parlante(numero) {
                if await confirmer(numero, dans: lignes, consigne: Self.consigneDecisions, options: options) {
                    choisi.decisions.append(Self.element(numero, dans: lignes))
                }
            }
            for action in actions where parlante(action.ligne) {
                if await confirmer(action.ligne, dans: lignes, consigne: Self.consigneActions, options: options) {
                    choisi.actions.append(Self.element(action.ligne, dans: lignes, responsable: action.responsable, echeance: action.echeance))
                }
            }
            for numero in questions where parlante(numero) {
                if await confirmer(numero, dans: lignes, consigne: Self.consigneQuestions, options: options) {
                    choisi.questions.append(Self.element(numero, dans: lignes))
                }
            }
            // Sans sujets, le compte rendu reste utile : un refus ici ne fait pas tomber le passage.
            if let sujets = try? await session(Self.consigneSujets).respond(to: texte, generating: SujetsChoisis.self, options: options).content.sujets {
                let proposes = sujets.map { DecoupageSujets.Propose(titre: $0.titre, premiere: $0.premiere, derniere: $0.derniere) }
                choisi.sujets = DecoupageSujets.valider(proposes, phrases: lignes.map(\.phrase), debuts: lignes.map(\.debut),
                                                        fin: passage.last?.fin ?? 0)
            }
            return choisi
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize where passage.count > 1 {
            // Un passage trop dense pour la fenêtre : on le coupe en deux.
            let milieu = passage.count / 2
            let a = try await analyserPassage(Array(passage[..<milieu]), notes: notes, type: type)
            let b = try await analyserPassage(Array(passage[milieu...]), notes: notes, type: type)
            return PassageChoisi(decisions: a.decisions + b.decisions, actions: a.actions + b.actions, questions: a.questions + b.questions,
                                 sujets: a.sujets + b.sujets)
        }
    }

    /// La phrase d'une ligne, avec sa mention d'écho probable si elle est marquée : la seconde lecture
    /// doit la voir, comme la première passe la voit dans `invite`.
    static func contexte(_ ligne: Ligne) -> String {
        ligne.echoProbable ? "\(ligne.phrase) (écho probable)" : ligne.phrase
    }

    /// Seconde lecture de chaque ligne retenue, avec ses voisines : la première passe en retient trop.
    /// Si le modèle refuse de répondre, la ligne reste : le passage entier ne doit pas tomber pour autant.
    private func confirmer(_ numero: Int, dans lignes: [Ligne], consigne: String, options: GenerationOptions) async -> Bool {
        guard lignes.indices.contains(numero - 1) else { return true }
        let voisines = max(0, numero - 3)...min(lignes.count - 1, numero + 1)
        let contexte = voisines.map { ($0 == numero - 1 ? ">>> " : "") + Self.contexte(lignes[$0]) }.joined(separator: "\n")
        let reponse = try? await session(consigne + " La ligne à juger est marquée >>>.")
            .respond(to: contexte, generating: Confirmation.self, options: options)
        return reponse?.content.correspond ?? true
    }

    /// Ce qu'un passage a retenu. nil : un numéro de ligne qui n'existe pas.
    private struct PassageChoisi {
        var decisions: [ElementSource?]
        var actions: [ElementSource?]
        var questions: [ElementSource?]
        var sujets: [Sujet] = []
    }

    /// Les lignes numérotées envoyées au modèle pour « En bref », chacune marquée « (écho probable) »
    /// si son moment source vient d'une ligne marquée : la validation qui suit (`EnBref.valider`)
    /// reçoit elle le texte brut, sans la mention, pour ne pas la prendre pour un mot dit.
    static func retenusEnBref(_ retenus: [(texte: String, debut: Double)], marques: Set<Double>) -> String {
        retenus.enumerated().map { offset, retenu in
            let texte = marques.contains(retenu.debut) ? "\(retenu.texte) (écho probable)" : retenu.texte
            return "\(offset + 1). \(texte)"
        }.joined(separator: "\n")
    }

    public func analyser(segments: [Segment], notes: [LigneDeNote], type: TypeReunion,
                         progression: @escaping @Sendable (Double) -> Void) async throws -> CompteRendu {
        guard !segments.isEmpty else { throw ErreurAnalyse.rienAAnalyser }
        switch SystemLanguageModel.default.availability {
        case .available: break
        case let .unavailable(raison): throw ErreurAnalyse.indisponible(String(describing: raison))
        }

        let passages = Self.decouper(segments)
        var decisions: [ElementSource] = []
        var actions: [ElementSource] = []
        var questions: [ElementSource] = []
        var echecs = 0
        var ecartes = 0

        // Une ligne n'apparaît qu'une fois : une décision prime sur une action, une action sur une question.
        var sujets: [Sujet] = []
        var vues = Set<String>()
        func garder(_ choisis: [ElementSource?]) -> [ElementSource] {
            choisis.compactMap { choisi in
                guard let choisi, let valide = ValidationSources.valider(choisi, dans: segments) else {
                    ecartes += 1
                    return nil
                }
                return vues.insert("\(valide.sources) \(valide.texte)").inserted ? valide : nil
            }
        }

        for (rang, passage) in passages.enumerated() {
            do {
                let choisi = try await analyserPassage(passage, notes: notes, type: type)
                decisions += garder(choisi.decisions)
                actions += garder(choisi.actions)
                questions += garder(choisi.questions)
                sujets += choisi.sujets
            } catch {
                // Un passage refusé par le modèle ne bloque pas les autres, et il est compté.
                echecs += 1
            }
            progression(Double(rang + 1) / Double(passages.count + 1))
        }
        guard echecs < passages.count else { throw ErreurAnalyse.aucunPassage }

        // « En bref » se rédige à partir de ce qui a été retenu : une longue réunion tient ainsi dans la fenêtre.
        let retenus: [(texte: String, debut: Double)] = (decisions + actions + questions)
            .compactMap { element in element.sources.first.map { (texte: element.texte, debut: $0) } }
            + sujets.map { (texte: $0.titre, debut: $0.debut) }
        var enBref: [PhraseSourcee]?
        if !retenus.isEmpty {
            let marques = Set(segments.filter { $0.echoProbable ?? false }.map(\.debut))
            let liste = Self.retenusEnBref(retenus, marques: marques)
            if let genere = try? await session(Self.consigneEnBref).respond(to: liste, generating: EnBrefGenere.self, options: GenerationOptions(sampling: .greedy)).content {
                let valides = EnBref.valider(genere.phrases.map { .init(texte: $0.texte, lignes: $0.lignes) },
                                             phrases: retenus.map(\.0), debuts: retenus.map(\.1))
                enBref = valides.isEmpty ? nil : valides
            }
        }

        progression(1)
        return CompteRendu(fournisseur: nom, decisions: decisions, actions: actions, questions: questions, sujets: sujets, enBref: enBref,
                           passagesNonAnalyses: echecs, elementsEcartes: ecartes)
    }
}
