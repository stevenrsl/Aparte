import Foundation
import Stockage
import Transcription

/// Les consignes et la lecture des réponses du modèle local, repris de Cairn : un texte court sous des
/// titres fixes. Demandé en liste structurée, le petit modèle remplit jusqu'à la limite qu'on lui donne ;
/// sous des titres, il s'arrête de lui-même et reste fidèle.
///
/// Différence avec Cairn (règle 1) : chaque puce commence par le numéro de la ligne où c'est dit. Une
/// puce sans numéro est écartée, et la phrase de cette ligne devient la citation affichée dessous.
enum Gabarit {
    /// Les plafonds d'un compte rendu : assez pour tout dire, trop peu pour tout recopier.
    static let maxDecisions = 8
    static let maxActions = 10
    static let maxQuestions = 6
    static let maxSujets = 8
    static let maxPointsParSujet = 5
    static let maxPointsCles = 5

    static let secretaire = """
    Tu rédiges des comptes rendus de réunion en français, courts, sobres et exacts, avec des phrases simples.
    Tu t'appuies uniquement sur ce qu'on te donne. Tu n'inventes ni noms, ni dates, ni chiffres, ni tâches, \
    et tu ne complètes pas une date partielle : « le 20 » reste « le 20 ».
    La transcription vient d'une reconnaissance vocale automatique : corrige en silence les mots mal compris \
    quand le sens est évident.
    Une décision est un choix arrêté pendant la réunion. Une action est une tâche que quelqu'un s'engage \
    clairement à faire. Ne mets jamais la même chose dans les deux, et laisse vide plutôt que deviner.
    Ce qui a été promis n'est pas encore fait : écris-le au futur, jamais au passé composé.
    Chaque ligne de la transcription a un numéro. Commence chaque puce par le numéro, entre crochets, de la ligne \
    où c'est dit. Ne répète jamais une phrase.
    """

    static let passage = """
    Résume ce passage avec tes propres mots. Ne recopie pas les répliques. Garde seulement ce qui compte.
    Réponds exactement dans ce format, sans rien ajouter :
    SUJET : (titre court)
    - [numéro] (ce qui a été dit, deux à quatre puces par sujet)
    DÉCISIONS
    - [numéro] (un choix arrêté par ligne, ou « aucune »)
    ACTIONS
    - [numéro] (Prénom : tâche à l'infinitif, avec l'échéance si elle a été dite ; ou « aucune »)
    QUESTIONS
    - [numéro] (une question restée sans réponse par ligne, ou « aucune »)

    Exemple de réponse, pour un tout autre passage :
    SUJET : Les deux devis
    - [3] L'atelier Morel est plus cher mais livre avant l'été
    - [7] Le second devis n'inclut pas la pose
    DÉCISIONS
    - [12] Retenir le devis de l'atelier Morel
    ACTIONS
    - [15] Marc : envoyer l'acompte, avant jeudi
    QUESTIONS
    - aucune
    """

    static let synthese = """
    Écris l'essentiel de cette réunion à partir des points numérotés.
    Réponds exactement dans ce format, sans rien ajouter :
    EN BREF
    (deux ou trois phrases, pas plus)
    POINTS CLÉS
    - [numéro] (trois à cinq points courts, un par ligne)

    Exemple de réponse, pour une tout autre réunion :
    EN BREF
    Léa et Marc ont comparé les deux devis pour la cuisine et retiennent celui de l'atelier Morel. Le plan de travail reste à choisir.
    POINTS CLÉS
    - [2] L'atelier Morel est plus cher mais livre avant l'été
    - [5] Le plan de travail n'est pas choisi
    """

    /// Qui parle, pour le modèle : un nom vaut mieux qu'un pronom, et il ne doit pas en inventer.
    static func contexte(lignes: [AnalysteLocal.Ligne], type: TypeReunion, moi: String) -> String {
        var parties: [String] = []
        let voix = Array(Set(lignes.compactMap(\.voix))).sorted()
        if !voix.isEmpty {
            let liste = voix.map { "« \($0) »" }.joined(separator: ", ")
            parties.append("Les répliques \(liste) viennent de personnes différentes : garde ces libellés, n'invente pas de nom.")
        } else if type == .presentiel {
            parties.append("La réunion a été enregistrée avec un seul micro : on ne sait pas qui parle. N'écris jamais qui a dit quoi.")
        }
        if type == .visio { parties.append("« moi » est \(moi), la personne qui utilise l'application. « eux », ce sont les autres.") }
        return parties.joined(separator: " ")
    }

    // MARK: Lire une réponse

    struct Puce: Equatable {
        var ligne: Int
        var texte: String
    }

    struct SujetLu: Equatable {
        var titre: String
        var points: [Puce]
    }

    struct PassageLu: Equatable {
        var sujets: [SujetLu] = []
        var decisions: [Puce] = []
        var actions: [Puce] = []
        var questions: [Puce] = []
    }

    struct SyntheseLue: Equatable {
        var enBref: [String] = []
        var points: [Puce] = []
    }

    private static let titres = ["DÉCISIONS", "ACTIONS", "QUESTIONS", "EN BREF", "POINTS CLÉS"]
    private static let rien: Set<String> = ["aucune", "aucun", "aucune action", "aucune décision", "aucune question", "néant", "rien"]
    private static let francais = Locale(identifier: "fr_FR")
    private static let numero = try! NSRegularExpression(pattern: #"^\[?\s*(\d+)(?:\s*[,\-–]\s*\d+)*\s*\]?\s*[.:)\-–]?\s*"#)

    /// Le titre que porte cette ligne, sans ses décorations de Markdown.
    private static func titre(_ ligne: String) -> String? {
        let nu = ligne.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*#: ")).uppercased(with: francais)
        return titres.first { $0 == nu }
    }

    /// Une puce et son numéro. Sans numéro, ou vide : rien (règle 1).
    static func puce(_ brute: String) -> Puce? {
        var ligne = brute.trimmingCharacters(in: .whitespaces)
        guard ligne.hasPrefix("-") || ligne.hasPrefix("•") || ligne.hasPrefix("*") else { return nil }
        ligne = String(ligne.drop { "-•*".contains($0) }).trimmingCharacters(in: .whitespaces)
        let entier = NSRange(ligne.startIndex..., in: ligne)
        guard let trouve = numero.firstMatch(in: ligne, range: entier), trouve.range.length > 0,
              let plage = Range(trouve.range(at: 1), in: ligne), let rang = Int(ligne[plage]),
              let fin = Range(trouve.range, in: ligne) else { return nil }
        let texte = String(ligne[fin.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        let nu = texte.trimmingCharacters(in: CharacterSet(charactersIn: ".()« »")).lowercased()
        let apresNom = texte.range(of: ": ").map { String(texte[$0.upperBound...]).lowercased() } ?? nu
        guard !texte.isEmpty, !texte.hasPrefix("("), !rien.contains(nu), !rien.contains(apresNom) else { return nil }
        return Puce(ligne: rang, texte: phrase(texte))
    }

    static func phrase(_ texte: String) -> String {
        guard let premiere = texte.first else { return texte }
        return premiere.uppercased() + texte.dropFirst()
    }

    static func lirePassage(_ reponse: String) -> PassageLu {
        var lu = PassageLu()
        var section: String?
        for brute in reponse.components(separatedBy: "\n") {
            let ligne = brute.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*#")).trimmingCharacters(in: .whitespaces)
            if ligne.uppercased(with: francais).hasPrefix("SUJET"), let deuxPoints = ligne.firstIndex(of: ":") {
                let nom = String(ligne[ligne.index(after: deuxPoints)...]).trimmingCharacters(in: CharacterSet(charactersIn: " .()*"))
                section = "SUJET"
                if !nom.isEmpty { lu.sujets.append(SujetLu(titre: phrase(nom), points: [])) }
            } else if let titre = titre(ligne) {
                section = titre
            } else if let puce = puce(brute) {
                switch section {
                case "SUJET": if !lu.sujets.isEmpty { lu.sujets[lu.sujets.count - 1].points.append(puce) }
                case "DÉCISIONS": lu.decisions.append(puce)
                case "ACTIONS": lu.actions.append(puce)
                case "QUESTIONS": lu.questions.append(puce)
                default: break
                }
            }
        }
        lu.sujets = lu.sujets.filter { !$0.points.isEmpty }
        return lu
    }

    static func lireSynthese(_ reponse: String) -> SyntheseLue {
        var lu = SyntheseLue()
        var section: String?
        var bref: [String] = []
        for brute in reponse.components(separatedBy: "\n") {
            if let titre = titre(brute) {
                section = titre
            } else if section == "EN BREF" {
                let ligne = brute.trimmingCharacters(in: .whitespaces)
                if !ligne.isEmpty, !ligne.hasPrefix("(") { bref.append(ligne) }
            } else if section == "POINTS CLÉS", let puce = puce(brute) {
                lu.points.append(puce)
            }
        }
        lu.enBref = phrases(bref.joined(separator: " "))
        return lu
    }

    /// Au plus trois phrases, sans les renvois que le modèle y laisse ni les répétitions.
    static func phrases(_ texte: String) -> [String] {
        let sansRenvoi = texte.replacingOccurrences(of: #"\s*\[[\d,\s\-–]+\]"#, with: "", options: .regularExpression)
        let decoupees = ValidationSources.phrases(de: sansRenvoi)
        return Array(distincts(decoupees, seuil: 0.8).prefix(EnBref.maximum))
    }

    // MARK: Fusionner

    static func mots(_ texte: String) -> Set<String> {
        Set(ValidationSources.normaliser(texte).split(separator: " ").map(String.init).filter { $0.count > 2 })
    }

    static func recouvrement(_ a: Set<String>, _ b: Set<String>) -> Double {
        let petit = min(a.count, b.count)
        return petit > 0 ? Double(a.intersection(b).count) / Double(petit) : 0
    }

    /// Sans ce qui redit une ligne précédente, ou ce qui est déjà dans `autres`.
    static func distincts(_ textes: [String], autres: [String] = [], seuil: Double = 0.6) -> [String] {
        var vus = autres.map(mots)
        return textes.filter { texte in
            let ceux = mots(texte)
            if vus.contains(where: { recouvrement($0, ceux) >= seuil }) { return false }
            vus.append(ceux)
            return true
        }
    }

    static func distincts(_ elements: [ElementSource], autres: [ElementSource] = []) -> [ElementSource] {
        let gardes = Set(distincts(elements.map(\.texte), autres: autres.map(\.texte)))
        var vus = Set<String>()
        return elements.filter { gardes.contains($0.texte) && vus.insert($0.texte).inserted }
    }

    /// « Marc : envoyer l'acompte » devient une tâche et son responsable.
    static func action(_ texte: String) -> (tache: String, responsable: String?) {
        guard let deuxPoints = texte.range(of: " : ") ?? texte.range(of: ": ") else { return (texte, nil) }
        let qui = String(texte[..<deuxPoints.lowerBound]).trimmingCharacters(in: .whitespaces)
        let quoi = String(texte[deuxPoints.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !qui.isEmpty, !quoi.isEmpty, qui.split(separator: " ").count <= 3 else { return (texte, nil) }
        return (phrase(quoi), qui)
    }

    /// Un sujet repris plus loin dans la réunion redevient un seul sujet.
    static func fusionner(_ sujets: [Sujet]) -> [Sujet] {
        var sortie: [Sujet] = []
        for sujet in sujets {
            if let rang = sortie.firstIndex(where: { recouvrement(mots($0.titre), mots(sujet.titre)) >= 0.6 }) {
                sortie[rang].debut = min(sortie[rang].debut, sujet.debut)
                sortie[rang].fin = max(sortie[rang].fin, sujet.fin)
                sortie[rang].points = Array(distincts((sortie[rang].points ?? []) + (sujet.points ?? [])).prefix(maxPointsParSujet + 1))
            } else {
                sortie.append(sujet)
            }
        }
        return sortie
    }
}
