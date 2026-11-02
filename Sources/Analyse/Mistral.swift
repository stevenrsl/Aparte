import Foundation
import Security
import Stockage
import Transcription

/// La clé d'un service, dans le trousseau de session : jamais dans un fichier, ni dans le dossier des
/// réunions, qui peut être synchronisé.
public struct Trousseau: Sendable {
    public static let mistral = Trousseau(service: "eu.stevenrsl.aparte", compte: "mistral-api-key")

    let service: String
    let compte: String

    private var requete: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: compte]
    }

    public func lire() -> String? {
        var cherche = requete
        cherche[kSecReturnData as String] = true
        cherche[kSecMatchLimit as String] = kSecMatchLimitOne
        var trouve: CFTypeRef?
        guard SecItemCopyMatching(cherche as CFDictionary, &trouve) == errSecSuccess, let donnees = trouve as? Data,
              let cle = String(data: donnees, encoding: .utf8), !cle.isEmpty else { return nil }
        return cle
    }

    /// nil ou une clé vide retire ce qui y était.
    @discardableResult
    public func ecrire(_ cle: String?) -> Bool {
        SecItemDelete(requete as CFDictionary)
        guard let cle = cle?.trimmingCharacters(in: .whitespacesAndNewlines), !cle.isEmpty else { return true }
        var ajout = requete
        ajout[kSecValueData as String] = Data(cle.utf8)
        return SecItemAdd(ajout as CFDictionary, nil) == errSecSuccess
    }
}

public enum ErreurMistral: LocalizedError {
    case cleRefusee
    case tropDeDemandes
    case aucunModele([String])
    case reponse(String)

    public var errorDescription: String? {
        switch self {
        case .cleRefusee: return "Mistral a refusé ta clé d'API. Vérifie-la dans les réglages."
        case .tropDeDemandes: return "Trop de demandes pour cette clé en ce moment. Réessaie dans une minute."
        case let .aucunModele(fermes): return "Aucun des modèles essayés n'est ouvert sur cette clé (\(fermes.joined(separator: ", ")))."
        case let .reponse(message): return "Mistral n'a pas pu analyser cette réunion : \(message)."
        }
    }
}

/// L'API de Mistral : toute la réunion tient en une demande, une réponse en JSON. Le modèle choisit des
/// numéros de lignes, comme en local : rien de ce qu'il écrit n'est affiché, hors titres de sujets contrôlés.
///
/// Les modèles ouverts dépendent de l'offre : Cairn a vu une clé valide répondre 429 avec une limite de
/// zéro sur les plus grands. D'où l'essai du meilleur au plus petit, et le dernier qui a répondu d'abord.
public struct AnalysteMistral: Analyste {
    public typealias Envoi = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse?)

    struct Modele {
        let id: String
        let nom: String
    }

    static let modeles = [
        Modele(id: "mistral-medium-latest", nom: "Medium"),
        Modele(id: "mistral-small-latest", nom: "Small"),
        Modele(id: "ministral-14b-latest", nom: "Ministral 14B"),
        Modele(id: "ministral-8b-latest", nom: "Ministral 8B"),
    ]
    private static let cleRetenue = "modeleMistral"

    public let nom = "Mistral"
    let cle: String
    let envoi: Envoi
    let attente: @Sendable (Double) async throws -> Void

    public init(cle: String) {
        self.init(cle: cle, envoi: { requete in
            let (donnees, reponse) = try await URLSession.shared.data(for: requete)
            return (donnees, reponse as? HTTPURLResponse)
        }, attente: { try await Task.sleep(for: .seconds($0)) })
    }

    init(cle: String, envoi: @escaping Envoi, attente: @escaping @Sendable (Double) async throws -> Void = { _ in }) {
        self.cle = cle
        self.envoi = envoi
        self.attente = attente
    }

    private static var ordre: [Modele] {
        let retenu = UserDefaults.standard.string(forKey: cleRetenue)
        return modeles.filter { $0.id == retenu } + modeles.filter { $0.id != retenu }
    }

    static let consigne = """
    Tu relis la transcription d'une réunion, ligne par ligne, chaque ligne a un numéro. Tu ne réécris rien : \
    tu choisis des numéros de lignes. Réponds uniquement avec un objet JSON de cette forme :
    {"decisions": [numéros], "actions": [{"ligne": numéro, "responsable": "", "echeance": ""}], "questions": [numéros], \
    "sujets": [{"titre": "", "premiere": numéro, "derniere": numéro}]}
    decisions : les lignes où un choix est arrêté : décidé, retenu, validé, refusé, maintenu ou abandonné. Pas les avis ni les constats.
    actions : les lignes qui disent qu'une tâche précise est à faire. Responsable et échéance : seulement si la ligne les dit, sinon vides.
    questions : les vraies questions sur le travail auxquelles les lignes suivantes ne répondent pas.
    sujets : un à huit sujets, dans l'ordre, chacun sur des lignes qui se suivent. Le titre fait de deux à cinq mots repris tels quels de ces lignes.
    Ne manque aucune ligne qui correspond et n'en retiens aucune qui ne correspond pas. Les listes peuvent être vides. \
    La transcription vient d'une reconnaissance vocale : une ligne peut contenir des erreurs, ne la corrige pas.
    """

    private struct Reponse: Decodable {
        struct Action: Decodable {
            var ligne: Int
            var responsable: String?
            var echeance: String?
        }
        struct SujetPropose: Decodable {
            var titre: String
            var premiere: Int
            var derniere: Int
        }
        var decisions: [Int]?
        var actions: [Action]?
        var questions: [Int]?
        var sujets: [SujetPropose]?
    }

    public func analyser(segments: [Segment], notes: [LigneDeNote], type: TypeReunion,
                         progression: @escaping @Sendable (Double) -> Void) async throws -> CompteRendu {
        guard !segments.isEmpty else { throw ErreurAnalyse.rienAAnalyser }
        let ordonnes = segments.sorted { $0.debut < $1.debut }
        let lignes = AnalysteApple.lignes(de: ordonnes)
        progression(0.1)
        let (reponse, modele): (Reponse, Modele) = try await demander(texte: AnalysteApple.invite(lignes, notes: notes, type: type))
        progression(0.9)

        var ecartes = 0
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
        let decisions = garder((reponse.decisions ?? []).map { AnalysteApple.element($0, dans: lignes) })
        let actions = garder((reponse.actions ?? []).map {
            AnalysteApple.element($0.ligne, dans: lignes, responsable: $0.responsable, echeance: $0.echeance)
        })
        let questions = garder((reponse.questions ?? []).map { AnalysteApple.element($0, dans: lignes) })
        let sujets = DecoupageSujets.valider(
            (reponse.sujets ?? []).map { .init(titre: $0.titre, premiere: $0.premiere, derniere: $0.derniere) },
            phrases: lignes.map(\.phrase), debuts: lignes.map(\.debut), fin: ordonnes.last?.fin ?? 0)
        progression(1)
        return CompteRendu(fournisseur: "Mistral · \(modele.nom)", decisions: decisions, actions: actions, questions: questions,
                           sujets: sujets, elementsEcartes: ecartes)
    }

    /// Pour les réglages : un seul mot part, aucune réunion.
    public func tester() async -> String {
        var fermes: [String] = []
        for modele in Self.modeles {
            do {
                let (statut, limite, _) = try await envoyer(modele: modele, messages: [["role": "user", "content": "ok"]], json: false, maximum: 1)
                switch statut {
                case 200:
                    UserDefaults.standard.set(modele.id, forKey: Self.cleRetenue)
                    return "La clé marche, avec le modèle \(modele.nom)."
                case 401: return "Mistral a refusé cette clé."
                case 429 where limite == "0", 400, 403, 404: fermes.append(modele.nom)
                default: return "Mistral a répondu \(statut)."
                }
            } catch {
                return "Mistral n'a pas pu être joint : \(error.localizedDescription)"
            }
        }
        return ErreurMistral.aucunModele(fermes).errorDescription ?? ""
    }

    private func demander<T: Decodable>(texte: String) async throws -> (T, Modele) {
        let messages = [["role": "system", "content": Self.consigne], ["role": "user", "content": texte]]
        var fermes: [String] = []
        for modele in Self.ordre {
            var statut = 0
            var limite: String?
            var donnees = Data()
            // Une limite au-dessus de zéro épuisée, c'est « ralentis ». À zéro, ce modèle n'est pas ouvert.
            for essai in 0..<4 {
                (statut, limite, donnees) = try await envoyer(modele: modele, messages: messages, json: true, maximum: nil)
                guard statut == 429, limite != "0", essai < 3 else { break }
                try await attente(pow(2, Double(essai + 1)))
            }
            switch statut {
            case 200:
                UserDefaults.standard.set(modele.id, forKey: Self.cleRetenue)
                return (try Self.decoder(donnees), modele)
            case 401: throw ErreurMistral.cleRefusee
            case 429 where limite == "0", 403, 404: fermes.append(modele.nom)
            case 429: throw ErreurMistral.tropDeDemandes
            default:
                // Le message de Mistral peut citer la demande : seul le code est affiché.
                throw ErreurMistral.reponse("réponse \(statut)")
            }
        }
        throw ErreurMistral.aucunModele(fermes)
    }

    private func envoyer(modele: Modele, messages: [[String: String]], json: Bool, maximum: Int?) async throws -> (Int, String?, Data) {
        var requete = URLRequest(url: URL(string: "https://api.mistral.ai/v1/chat/completions")!)
        requete.httpMethod = "POST"
        requete.timeoutInterval = 180
        requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requete.setValue("Bearer \(cle)", forHTTPHeaderField: "Authorization")
        var corps: [String: Any] = ["model": modele.id, "temperature": 0, "messages": messages]
        if json { corps["response_format"] = ["type": "json_object"] }
        if let maximum { corps["max_tokens"] = maximum }
        requete.httpBody = try JSONSerialization.data(withJSONObject: corps)
        let (donnees, reponse) = try await envoi(requete)
        return (reponse?.statusCode ?? 0, reponse?.value(forHTTPHeaderField: "x-ratelimit-limit-req-minute"), donnees)
    }

    private struct Completion: Decodable {
        struct Choix: Decodable {
            struct Message: Decodable { var content: String }
            var message: Message
        }
        var choices: [Choix]
    }

    private static func decoder<T: Decodable>(_ donnees: Data) throws -> T {
        guard var contenu = (try? JSONDecoder().decode(Completion.self, from: donnees))?.choices.first?.message.content else {
            throw ErreurMistral.reponse("réponse vide")
        }
        // Certaines réponses arrivent quand même entre ```json.
        contenu = contenu.trimmingCharacters(in: .whitespacesAndNewlines)
        if contenu.hasPrefix("```") {
            contenu = contenu.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if let fin = contenu.range(of: "```", options: .backwards) { contenu = String(contenu[..<fin.lowerBound]) }
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contenu.utf8))
        } catch {
            throw ErreurMistral.reponse("la réponse n'a pas la forme attendue")
        }
    }
}
