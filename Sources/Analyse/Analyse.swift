import Foundation
import FoundationModels
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
    public var resume: String
    public var decisions: [ElementSource]
    public var actions: [ElementSource]
    public var questions: [ElementSource]
    public var passagesNonAnalyses: Int
    public var elementsEcartes: Int

    public init(fournisseur: String, date: Date = Date(), resume: String, decisions: [ElementSource], actions: [ElementSource],
                questions: [ElementSource], passagesNonAnalyses: Int = 0, elementsEcartes: Int = 0) {
        self.fournisseur = fournisseur
        self.date = date
        self.resume = resume
        self.decisions = decisions
        self.actions = actions
        self.questions = questions
        self.passagesNonAnalyses = passagesNonAnalyses
        self.elementsEcartes = elementsEcartes
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

    /// L'élément si ses sources tiennent, sinon nil. Un responsable ou une échéance
    /// qui n'ont pas été dits dans les passages sources sont retirés.
    public static func valider(_ element: ElementSource, dans segments: [Segment]) -> ElementSource? {
        let texte = element.texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty, !element.sources.isEmpty else { return nil }
        let passages = element.sources.map { segmentsSources(de: $0, dans: segments) }
        guard !passages.contains(where: \.isEmpty) else { return nil }

        let toutLeTexte = normaliser(segments.map(\.texte).joined(separator: " "))
        var valide = element
        valide.texte = texte
        if let citation = element.citation?.trimmingCharacters(in: .whitespacesAndNewlines), !citation.isEmpty {
            guard toutLeTexte.contains(normaliser(citation)) else { return nil }
            valide.citation = citation
        } else {
            valide.citation = nil
        }

        let lu = normaliser(passages.flatMap { $0 }.map(\.texte).joined(separator: " "))
        func dit(_ valeur: String?) -> String? {
            guard let valeur = valeur?.trimmingCharacters(in: .whitespacesAndNewlines), !valeur.isEmpty else { return nil }
            let cherche = normaliser(valeur)
            return !cherche.isEmpty && lu.contains(cherche) ? valeur : nil
        }
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
    @Guide(description: "La décision, l'action ou la question, en une phrase courte en français.")
    var texte: String
    @Guide(description: "Les horodatages exacts entre crochets de la transcription qui prouvent cet élément, au format mm:ss.")
    var horodatages: [String]
    @Guide(description: "La phrase exacte de la transcription, recopiée mot pour mot.")
    var citation: String
    @Guide(description: "La personne responsable, seulement si elle est nommée dans la transcription. Sinon vide.")
    var responsable: String
    @Guide(description: "L'échéance, seulement si elle est dite dans la transcription. Sinon vide.")
    var echeance: String
}

@Generable
struct PassageGenere {
    @Guide(description: "Ce qui s'est dit dans ce passage, en deux phrases au plus en français.")
    var resume: String
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
        ElementSource(texte: genere.texte, sources: genere.horodatages.compactMap { secondes(depuis: $0) },
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
        var resumes: [String] = []
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
                    if !genere.resume.isEmpty { resumes.append(genere.resume) }
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

        var resume = resumes.joined(separator: " ")
        if resumes.count > 1 {
            let session = LanguageModelSession(instructions: "Tu résumes une réunion en français, en trois phrases au plus, sans rien ajouter à ce qui t'est donné.")
            if let reponse = try? await session.respond(to: resumes.joined(separator: "\n")) {
                resume = reponse.content
            }
        }
        progression(1)
        return CompteRendu(fournisseur: nom, resume: resume, decisions: decisions, actions: actions, questions: questions,
                           passagesNonAnalyses: echecs, elementsEcartes: ecartes)
    }
}
