import Foundation
import FoundationModels
import NaturalLanguage
import Security
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
    public var passagesNonAnalyses: Int
    public var elementsEcartes: Int

    public init(fournisseur: String, date: Date = Date(), decisions: [ElementSource], actions: [ElementSource],
                questions: [ElementSource], sujets: [Sujet]? = nil, passagesNonAnalyses: Int = 0, elementsEcartes: Int = 0) {
        self.fournisseur = fournisseur
        self.date = date
        self.decisions = decisions
        self.actions = actions
        self.questions = questions
        self.passagesNonAnalyses = passagesNonAnalyses
        self.sujets = sujets
        self.elementsEcartes = elementsEcartes
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

    /// Ce qui revient à ces sujets, pour un extrait : le reste de la réunion n'y figure pas.
    public func extrait(_ choisis: [Sujet]) -> CompteRendu {
        func garder(_ elements: [ElementSource]) -> [ElementSource] {
            elements.filter { element in element.sources.contains { temps in choisis.contains { $0.contient(temps) } } }
        }
        return CompteRendu(fournisseur: fournisseur, date: date, decisions: garder(decisions), actions: garder(actions),
                           questions: garder(questions), sujets: choisis)
    }

    /// Une analyse relue depuis le disque repasse la validation : une ancienne reformulation laisse
    /// place à la transcription, et ce qui n'est plus prouvé est écarté.
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
        return copie
    }

    /// Résumé, décisions et actions, sans la transcription : prêt à coller.
    public func texteACopier(incidents: [IncidentAudio] = []) -> String {
        var parties = [resume]
        if let audio = Self.audioIncomplet(incidents) { parties.append(audio) }
        if !decisions.isEmpty { parties.append("Décisions\n" + decisions.map { "- \($0.texte)" }.joined(separator: "\n")) }
        if !actions.isEmpty { parties.append("Actions\n" + actions.map { "- \($0.texte)" }.joined(separator: "\n")) }
        return parties.joined(separator: "\n\n")
    }

    /// Il manque un moment de la réunion : ce qui en est tiré ne peut pas le cacher.
    private static func audioIncomplet(_ incidents: [IncidentAudio]) -> String? {
        incidents.isEmpty ? nil : "Audio incomplet : " + incidents.map(\.description).joined(separator: ", ") + "."
    }

    public func markdown(incidents: [IncidentAudio] = []) -> String {
        func bloc(_ titre: String, _ elements: [ElementSource]) -> String {
            guard !elements.isEmpty else { return "" }
            let lignes = elements.map { element in
                "- \(element.texte) (\(element.sources.map { horodatage($0) }.joined(separator: ", ")))"
            }
            return "\n## \(titre)\n\n" + lignes.joined(separator: "\n") + "\n"
        }
        return "# Compte rendu\n\nProduit par : \(fournisseur)\n\n\(resume)\n"
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

    /// Les mots trop courts (« de », « la ») ne prouvent rien : ils ne sont pas contrôlés.
    private static let longueurControlee = 4

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
            let mots = ValidationSources.normaliser(titre).split(separator: " ")
            let dit = !mots.isEmpty && mots.allSatisfy { $0.count < longueurControlee || lu.contains($0) }
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
    case pcc(PrivateCloudComputeLanguageModel.Error)

    public var errorDescription: String? {
        switch self {
        case let .indisponible(raison): return "Cette analyse n'est pas disponible : \(raison)"
        case .rienAAnalyser: return "Il n'y a pas de transcription à analyser."
        case let .pcc(erreur):
            switch erreur {
            case .quotaLimitReached: return "La limite du jour de Private Cloud Compute est atteinte. Analyse sur ce Mac, ou réessaie demain."
            case .networkFailure: return "Private Cloud Compute n'a pas pu être joint. Vérifie ta connexion."
            default: return "Private Cloud Compute n'a pas pu analyser cette réunion."
            }
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
///
/// PCC est le même lecteur avec une fenêtre bien plus grande : une réunion d'une heure tient d'un coup.
public struct AnalysteApple: Analyste {
    public let nom: String
    let dureePassage: Double
    let session: @Sendable (String) -> LanguageModelSession
    let indisponible: @Sendable () -> String?

    /// Sur ce Mac. Rien ne part. Résumer les mots de quelqu'un, c'est les transformer, d'où ces garde-fous :
    /// ceux par défaut refusent parfois un passage pour un mot sorti de son contexte.
    public static let local = AnalysteApple(
        nom: "Local · Apple Intelligence", dureePassage: 300,
        session: { LanguageModelSession(model: SystemLanguageModel(guardrails: .permissiveContentTransformations), instructions: $0) },
        indisponible: {
            if case let .unavailable(raison) = SystemLanguageModel.default.availability { return String(describing: raison) }
            return nil
        })

    /// Dans Private Cloud Compute : la transcription et les notes partent chez Apple. Seul Steven peut le
    /// lancer, pour une réunion précise.
    public static let pcc = AnalysteApple(
        nom: "PCC · Apple", dureePassage: 3600,
        session: { LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: $0) },
        indisponible: {
            guard pccAutorise else { return "Apple doit d'abord autoriser Aparté à utiliser Private Cloud Compute." }
            if case let .unavailable(raison) = PrivateCloudComputeLanguageModel().availability { return String(describing: raison) }
            return nil
        })

    /// PCC demande une autorisation qu'Apple accorde sur demande. Sans elle, le premier appel fait planter
    /// l'app, même si le modèle se dit disponible : on regarde donc avant de le toucher.
    public static var pccAutorise: Bool {
        guard let tache = SecTaskCreateFromSelf(nil) else { return false }
        let droit = SecTaskCopyValueForEntitlement(tache, "com.apple.developer.private-cloud-compute" as CFString, nil)
        return (droit as? Bool) == true
    }

    static let motsMinimum = 4
    /// Le modèle ne recopie ni n'écrit rien : il choisit des numéros de lignes, une catégorie à la fois.
    /// Le texte rendu est donc toujours celui de la transcription.
    private static let consigneCommune = """
    Tu relis la transcription d'une réunion, ligne par ligne. Chaque ligne a un numéro. \
    Renvoie seulement les numéros demandés. Sois attentif : ne manque aucune ligne qui correspond, \
    et n'en retiens aucune qui ne correspond pas.
    """
    static let consigneDecisions = consigneCommune + """
     Retiens les lignes où un choix est arrêté : ce qui est décidé, retenu, validé, refusé, maintenu ou abandonné. \
    Pas les avis, les préférences, les constats, les questions ni les tâches à faire.
    """
    static let consigneActions = consigneCommune + """
     Retiens les lignes qui disent qu'une tâche précise est à faire : quelqu'un fait, envoie, appelle, réserve, écrit ou demande quelque chose. \
    Pas les choix arrêtés, les constats, les questions ni les simples accords.
    """
    static let consigneSujets = """
    Tu relis la transcription d'une réunion, ligne par ligne. Chaque ligne a un numéro. \
    Découpe-la en sujets abordés, un à six, dans l'ordre. Un sujet réunit des lignes qui se suivent. \
    Ne compte pas les politesses comme un sujet. Son titre reprend des mots de ces lignes, tels quels.
    """
    static let consigneQuestions = consigneCommune + """
     Retiens les lignes qui posent une vraie question sur le travail, à laquelle les lignes suivantes ne répondent pas. \
    Pas les questions de politesse, ni celles qui reçoivent une réponse.
    """

    static func decouper(_ segments: [Segment], duree: Double) -> [[Segment]] {
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
    }

    static func lignes(de passage: [Segment]) -> [Ligne] {
        passage.flatMap { segment in
            ValidationSources.phrases(de: segment.texte).map { Ligne(phrase: $0, debut: segment.debut, piste: segment.piste, voix: segment.voix) }
        }
    }

    static func invite(_ lignes: [Ligne], notes: [LigneDeNote], type: TypeReunion) -> String {
        func qui(_ ligne: Ligne) -> String {
            if let voix = ligne.voix { return "\(voix) : " }
            guard type == .visio else { return "" }
            return ligne.piste == .micro ? "moi : " : "eux : "
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

    /// Seconde lecture de chaque ligne retenue, avec ses voisines : la première passe en retient trop.
    /// Si le modèle refuse de répondre, la ligne reste : le passage entier ne doit pas tomber pour autant.
    private func confirmer(_ numero: Int, dans lignes: [Ligne], consigne: String, options: GenerationOptions) async -> Bool {
        guard lignes.indices.contains(numero - 1) else { return true }
        let voisines = max(0, numero - 3)...min(lignes.count - 1, numero + 1)
        let contexte = voisines.map { ($0 == numero - 1 ? ">>> " : "") + lignes[$0].phrase }.joined(separator: "\n")
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

    public func analyser(segments: [Segment], notes: [LigneDeNote], type: TypeReunion,
                         progression: @escaping @Sendable (Double) -> Void) async throws -> CompteRendu {
        guard !segments.isEmpty else { throw ErreurAnalyse.rienAAnalyser }
        if let raison = indisponible() { throw ErreurAnalyse.indisponible(raison) }

        let passages = Self.decouper(segments, duree: dureePassage)
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
            } catch let erreur as PrivateCloudComputeLanguageModel.Error {
                // La limite du jour ou le réseau : les passages suivants échoueraient de même.
                throw ErreurAnalyse.pcc(erreur)
            } catch {
                // Un passage refusé par le modèle ne bloque pas les autres, et il est compté.
                echecs += 1
            }
            progression(Double(rang + 1) / Double(passages.count + 1))
        }
        guard echecs < passages.count else { throw ErreurAnalyse.aucunPassage }

        progression(1)
        return CompteRendu(fournisseur: nom, decisions: decisions, actions: actions, questions: questions, sujets: sujets,
                           passagesNonAnalyses: echecs, elementsEcartes: ecartes)
    }
}
