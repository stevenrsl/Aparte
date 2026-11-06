import Foundation
import Security
import Stockage
import Transcription

/// La clé d'un service, dans le trousseau de session : jamais dans un fichier, ni dans le dossier des
/// réunions, qui peut être synchronisé.
public struct Trousseau: Sendable {
    public static let mistral = Trousseau(service: "eu.stevenrsl.aparte", compte: "mistral-api-key")
    /// La clé déjà rangée par Cairn. Lue seulement quand Steven le demande, et jamais modifiée.
    public static let mistralDeCairn = Trousseau(service: "eu.stevenrsl.cairn", compte: "mistral-api-key")

    public let service: String
    public let compte: String

    public init(service: String, compte: String) {
        self.service = service
        self.compte = compte
    }

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

    /// Vrai si une clé est rangée, sans la lire : aucune fenêtre d'autorisation au démarrage.
    public func presente() -> Bool {
        var cherche = requete
        cherche[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(cherche as CFDictionary, nil) == errSecSuccess
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

/// L'API de Mistral : toute la réunion tient en une demande, une réponse en JSON. Comme en local, chaque
/// élément est rédigé par le modèle, avec le numéro de la ligne dont la phrase devient sa citation.
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
    /// Les numéros de ligne de Mistral sont fiables à quelques lignes près.
    static let rayon = 8

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

    static let consigne = Gabarit.secretaire + """

    Réponds uniquement avec un objet JSON de cette forme :
    {"en_bref": [{"texte": "", "lignes": [numéros]}], "points_cles": [{"ligne": numéro, "texte": ""}], \
    "decisions": [{"ligne": numéro, "texte": ""}], \
    "actions": [{"ligne": numéro, "texte": "", "responsable": "", "echeance": ""}], \
    "questions": [{"ligne": numéro, "texte": ""}], \
    "sujets": [{"titre": "", "premiere": numéro, "derniere": numéro, "points": [{"ligne": numéro, "texte": ""}]}]}
    Chaque texte est court et rédigé avec tes mots, et « ligne » est le numéro de la ligne qui le prouve.
    en_bref : deux ou trois phrases courtes, pour savoir en dix secondes ce qui s'est dit, chacune avec les lignes qu'elle résume.
    points_cles : trois à cinq points, ce qu'il faut retenir.
    decisions : seulement un choix clairement arrêté pendant la réunion, au plus cinq. Une piste, un souhait ou \
    un point « à confirmer » n'est pas une décision. Souvent il n'y en a aucune : laisse la liste vide.
    actions : seulement un engagement clair de quelqu'un, au plus huit, la tâche à l'infinitif ; \
    responsable et échéance seulement s'ils ont été dits, sinon vides.
    questions : seulement une question posée pendant la réunion et restée sans réponse, au plus quatre. Souvent aucune.
    Si des notes sont données, ce sont les miennes : elles disent ce qui compte pour moi. Couvre-les en priorité, \
    mais seulement avec ce que dit la transcription.
    sujets : un à huit sujets, dans l'ordre, chacun sur des lignes qui se suivent, avec un titre court et deux à quatre points.
    Les listes peuvent être vides. N'écris ni nom, ni date, ni chiffre qui ne soit dans la transcription.
    """ + AnalysteLocal.consigneEcho

    private struct Reponse: Decodable {
        struct Element: Decodable {
            var ligne: Int
            var texte: String?
            var responsable: String?
            var echeance: String?
        }
        struct PhrasePropose: Decodable {
            var texte: String
            var lignes: [Int]?
        }
        struct SujetPropose: Decodable {
            var titre: String
            var premiere: Int
            var derniere: Int
            var points: [Element]?
        }
        var decisions: [Element]?
        var actions: [Element]?
        var questions: [Element]?
        var points_cles: [Element]?
        var sujets: [SujetPropose]?
        var en_bref: [PhrasePropose]?
    }

    public func analyser(segments: [Segment], notes: [LigneDeNote], type: TypeReunion,
                         progression: @escaping @Sendable (Double) -> Void) async throws -> CompteRendu {
        guard !segments.isEmpty else { throw ErreurAnalyse.rienAAnalyser }
        let ordonnes = segments.sorted { $0.debut < $1.debut }
        let lignes = AnalysteLocal.lignes(de: ordonnes)
        progression(0.1)
        let (reponse, modele): (Reponse, Modele) = try await demander(texte: AnalysteLocal.invite(lignes, notes: notes, type: type))
        progression(0.9)

        var ecartes = 0
        let connus = ValidationSources.connus(segments: ordonnes, notes: notes)
        func garder(_ propose: Reponse.Element) -> ElementSource? {
            let puce = Gabarit.Puce(ligne: propose.ligne, texte: propose.texte ?? "")
            guard var brut = AnalysteLocal.element(puce, dans: lignes, rayon: Self.rayon) else {
                ecartes += 1
                return nil
            }
            brut.responsable = propose.responsable
            brut.echeance = propose.echeance
            guard let valide = ValidationSources.valider(brut, dans: segments, connus: connus, citationSiRefus: false) else {
                ecartes += 1
                return nil
            }
            return valide
        }
        // Un sujet tient par ses points prouvés : ses bornes sont celles de leurs sources, pas les numéros
        // proposés, qui se chevauchent souvent d'un sujet à l'autre. Sans point prouvé, il n'a rien à montrer.
        // Son titre est rédigé : il ne doit nommer ni personne, ni chiffre, ni moment jamais dit.
        let connusTitres = Set(ValidationSources.normaliser(connus).split(separator: " ").map(String.init))
        let sujets = (reponse.sujets ?? []).compactMap { propose -> Sujet? in
            let points = Array((propose.points ?? []).compactMap(garder).prefix(Gabarit.maxPointsParSujet))
            let temps = points.flatMap(\.sources)
            guard let debut = temps.min(), let fin = temps.max() else { return nil }
            let titre = DecoupageSujets.titreRedige(propose.titre, lu: connusTitres) ? propose.titre : points[0].texte
            return Sujet(titre: titre, debut: debut, fin: fin, points: points)
        }
        let finales = AnalysteLocal.assembler(decisions: (reponse.decisions ?? []).compactMap(garder),
                                              actions: (reponse.actions ?? []).compactMap(garder),
                                              questions: (reponse.questions ?? []).compactMap(garder),
                                              sujets: sujets, fin: ordonnes.last?.fin ?? 0)
        let pointsCles = Array(Gabarit.distincts((reponse.points_cles ?? []).compactMap(garder)).prefix(Gabarit.maxPointsCles))
        let lu = connus
        let enBref = EnBref.valider((reponse.en_bref ?? []).map { .init(texte: $0.texte, lignes: $0.lignes ?? []) },
                                    phrases: lignes.map(\.phrase), debuts: lignes.map(\.debut), lu: lu)
        progression(1)
        return CompteRendu(fournisseur: "Mistral · \(modele.nom)", decisions: finales.decisions, actions: finales.actions,
                           questions: finales.questions, sujets: finales.sujets, enBref: enBref.isEmpty ? nil : enBref,
                           pointsCles: pointsCles.isEmpty ? nil : pointsCles, elementsEcartes: ecartes)
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
