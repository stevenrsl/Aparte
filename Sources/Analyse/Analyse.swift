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

/// La sortie commune, quel que soit le fournisseur.
public struct CompteRendu: Codable, Sendable, Hashable {
    public var fournisseur: String
    public var date: Date
    public var decisions: [ElementSource]
    public var actions: [ElementSource]
    public var questions: [ElementSource]
    public var passagesNonAnalyses: Int
    public var elementsEcartes: Int

    public init(fournisseur: String, date: Date = Date(), decisions: [ElementSource], actions: [ElementSource],
                questions: [ElementSource], passagesNonAnalyses: Int = 0, elementsEcartes: Int = 0) {
        self.fournisseur = fournisseur
        self.date = date
        self.decisions = decisions
        self.actions = actions
        self.questions = questions
        self.passagesNonAnalyses = passagesNonAnalyses
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
    public var texteACopier: String {
        var parties = [resume]
        if !decisions.isEmpty { parties.append("Décisions\n" + decisions.map { "- \($0.texte)" }.joined(separator: "\n")) }
        if !actions.isEmpty { parties.append("Actions\n" + actions.map { "- \($0.texte)" }.joined(separator: "\n")) }
        return parties.joined(separator: "\n\n")
    }

    public var markdown: String {
        func bloc(_ titre: String, _ elements: [ElementSource]) -> String {
            guard !elements.isEmpty else { return "" }
            let lignes = elements.map { element in
                "- \(element.texte) (\(element.sources.map { horodatage($0) }.joined(separator: ", ")))"
            }
            return "\n## \(titre)\n\n" + lignes.joined(separator: "\n") + "\n"
        }
        return "# Compte rendu\n\nProduit par : \(fournisseur)\n\n\(resume)\n"
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

    /// Les phrases entières de ces segments qui contiennent la citation, telles que transcrites. Une
    /// citation tronquée ne peut pas perdre un « ne… pas » : on rend toujours la phrase complète.
    private static func phrasesEntieres(contenant cherche: String, dans segments: [Segment]) -> String? {
        let phrases = segments.flatMap { segment -> [String] in
            let decoupe = NLTokenizer(unit: .sentence)
            decoupe.string = segment.texte
            decoupe.setLanguage(.french)
            return decoupe.tokens(for: segment.texte.startIndex..<segment.texte.endIndex).map {
                segment.texte[$0].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
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
struct ElementGenere {
    @Guide(description: "Les horodatages exacts entre crochets de la transcription qui prouvent cet élément, au format mm:ss.")
    var horodatages: [String]
    @Guide(description: "La phrase entière de la transcription qui dit la décision, l'action ou la question, recopiée mot pour mot.")
    var citation: String
    @Guide(description: "La personne responsable, seulement si elle est nommée dans la transcription. Sinon vide.")
    var responsable: String
    @Guide(description: "L'échéance, seulement si elle est dite dans la transcription. Sinon vide.")
    var echeance: String
}

@Generable
struct PassageGenere {
    @Guide(description: "Les décisions prises. Vide s'il n'y en a pas.")
    var decisions: [ElementGenere]
    @Guide(description: "Les actions à faire. Vide s'il n'y en a pas.")
    var actions: [ElementGenere]
    @Guide(description: "Les questions restées sans réponse. Vide s'il n'y en a pas.")
    var questions: [ElementGenere]
}

/// Foundation Models sur l'appareil. La fenêtre de 4 096 tokens étant partagée entre
/// l'entrée et la sortie, la transcription est découpée en passages d'environ cinq minutes.
public struct AnalysteLocal: Analyste {
    public let nom = "Local · Apple Intelligence"
    static let dureePassage = 300.0
    static let consignes = """
    Tu relis la transcription d'une réunion. N'invente rien : chaque élément doit venir d'une phrase \
    de la transcription, avec son horodatage exact. S'il n'y a rien, renvoie des listes vides. Réponds en français.
    """

    public init() {}

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

    private func invite(_ passage: [Segment], notes: [LigneDeNote], type: TypeReunion) -> String {
        func qui(_ piste: Piste) -> String {
            guard type == .visio else { return "" }
            return piste == .micro ? "moi : " : "eux : "
        }
        let debut = (passage.first?.debut ?? 0) - 15
        let fin = (passage.last?.fin ?? 0) + 15
        let ancres = notes.filter { $0.temps >= debut && $0.temps <= fin }
        var texte = ""
        if !ancres.isEmpty {
            texte += "Regarde en priorité autour de ce que j'ai noté :\n"
            texte += ancres.map { "[\(horodatage($0.temps))] \($0.texte)" }.joined(separator: "\n") + "\n\n"
        }
        texte += "Transcription :\n"
        texte += passage.map { "[\(horodatage($0.debut))] \(qui($0.piste))\($0.texte)" }.joined(separator: "\n")
        return texte
    }

    private func elementSource(_ genere: ElementGenere) -> ElementSource {
        ElementSource(texte: genere.citation, sources: genere.horodatages.compactMap { secondes(depuis: $0) },
                      citation: genere.citation, responsable: genere.responsable, echeance: genere.echeance)
    }

    private func analyserPassage(_ passage: [Segment], notes: [LigneDeNote], type: TypeReunion) async throws -> [PassageGenere] {
        do {
            let session = LanguageModelSession(instructions: Self.consignes)
            let reponse = try await session.respond(to: invite(passage, notes: notes, type: type), generating: PassageGenere.self)
            return [reponse.content]
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize where passage.count > 1 {
            // Un passage trop dense pour la fenêtre : on le coupe en deux.
            let milieu = passage.count / 2
            let a = try await analyserPassage(Array(passage[..<milieu]), notes: notes, type: type)
            let b = try await analyserPassage(Array(passage[milieu...]), notes: notes, type: type)
            return a + b
        }
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

        func garder(_ generes: [ElementGenere]) -> [ElementSource] {
            generes.compactMap { genere in
                let valide = ValidationSources.valider(elementSource(genere), dans: segments)
                if valide == nil { ecartes += 1 }
                return valide
            }
        }

        for (rang, passage) in passages.enumerated() {
            do {
                for genere in try await analyserPassage(passage, notes: notes, type: type) {
                    decisions += garder(genere.decisions)
                    actions += garder(genere.actions)
                    questions += garder(genere.questions)
                }
            } catch {
                // Un passage refusé par le modèle ne bloque pas les autres, et il est compté.
                echecs += 1
            }
            progression(Double(rang + 1) / Double(passages.count + 1))
        }
        guard echecs < passages.count else { throw ErreurAnalyse.aucunPassage }

        progression(1)
        return CompteRendu(fournisseur: nom, decisions: decisions, actions: actions, questions: questions,
                           passagesNonAnalyses: echecs, elementsEcartes: ecartes)
    }
}
