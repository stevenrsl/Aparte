import Foundation
import Transcription

public enum TypeReunion: String, Codable, Sendable {
    case visio
    case presentiel
}

public struct MetaReunion: Codable, Sendable, Hashable {
    public var titre: String
    public var date: Date
    public var duree: Double
    public var type: TypeReunion
    public var participants: [String]
    public var fournisseurs: [String]
    /// Le temps, depuis le début de la réunion, où chaque piste a commencé à écrire son son.
    /// Absent des réunions enregistrées avant que ce décalage soit mesuré.
    public var decalages: [String: Double]?
    /// Les moments où l'audio s'est coupé. Absent des réunions sans incident.
    public var incidentsAudio: [IncidentAudio]?
    /// Le nom que Steven a donné à chaque voix : « Voix 1 » : « Claire ». Rien ne le devine.
    public var nomsDesVoix: [String: String]?
    /// La relecture de l'enregistrement a écrit la transcription.
    public var relue: Bool?
    /// Pour un extrait : le titre de la réunion dont il vient. L'original n'est pas modifié.
    public var origine: String?

    public init(titre: String, date: Date, type: TypeReunion) {
        self.titre = titre
        self.date = date
        self.duree = 0
        self.type = type
        self.participants = []
        self.fournisseurs = []
    }
}

/// Un moment où une piste n'a plus enregistré, compté depuis le début de la réunion.
public struct IncidentAudio: Codable, Sendable, Hashable {
    public var piste: String
    public var debut: Double
    /// Absent quand le son n'est jamais revenu.
    public var fin: Double?

    public init(piste: String, debut: Double, fin: Double? = nil) {
        self.piste = piste
        self.debut = debut
        self.fin = fin
    }

    /// « micro coupé de 12:03 à 12:40 »
    public var description: String {
        if let fin { return "\(piste) coupé de \(horodatage(debut)) à \(horodatage(fin))" }
        return "\(piste) coupé à \(horodatage(debut))"
    }
}

/// Une ligne de notes et le moment où elle a été commencée.
public struct LigneDeNote: Identifiable, Sendable, Hashable {
    public let id: UUID
    public var temps: Double
    public var texte: String

    public init(id: UUID = UUID(), temps: Double, texte: String) {
        self.id = id
        self.temps = temps
        self.texte = texte
    }
}

/// Où lire une piste pour un moment de la réunion : sa position, et l'attente si elle n'avait pas encore commencé.
public func positionDeLecture(temps: Double, decalage: Double) -> (position: Double, attente: Double) {
    let position = temps - decalage
    return position >= 0 ? (position, 0) : (0, -position)
}

public func horodatage(_ secondes: Double) -> String {
    let total = max(0, Int(secondes))
    let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}

public func secondes(depuis horodatage: String) -> Double? {
    let parties = horodatage.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Int($0) }
    guard (2...3).contains(parties.count), !parties.contains(where: { $0 == nil }) else { return nil }
    return Double(parties.compactMap { $0 }.reduce(0) { $0 * 60 + $1 })
}

/// Le format de `notes.md` : « `04:12` le texte », une ligne par note.
public enum FormatNotes {
    public static func ecrire(_ lignes: [LigneDeNote]) -> String {
        lignes.filter { !$0.texte.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "`\(horodatage($0.temps))` \($0.texte)" }
            .joined(separator: "\n") + "\n"
    }

    public static func lire(_ texte: String) -> [LigneDeNote] {
        texte.split(separator: "\n", omittingEmptySubsequences: true).map { ligne in
            let brut = String(ligne)
            if brut.hasPrefix("`"), let fin = brut.dropFirst().firstIndex(of: "`"),
               let temps = secondes(depuis: String(brut[brut.index(after: brut.startIndex)..<fin])) {
                return LigneDeNote(temps: temps, texte: String(brut[brut.index(after: fin)...]).trimmingCharacters(in: .whitespaces))
            }
            return LigneDeNote(temps: 0, texte: brut)
        }
    }
}

/// Une réunion, c'est un dossier lisible sans l'app.
public struct Reunion: Identifiable, Sendable, Hashable {
    public var url: URL
    public var meta: MetaReunion
    public var dossier: String?

    public var id: String { url.path }
    public var micro: URL { url.appendingPathComponent("micro.m4a") }
    public var systeme: URL { url.appendingPathComponent("systeme.m4a") }
    public var microEnCours: URL { url.appendingPathComponent("micro.aac") }
    public var systemeEnCours: URL { url.appendingPathComponent("systeme.aac") }
    private var metaURL: URL { url.appendingPathComponent("meta.json") }
    private var transcriptionURL: URL { url.appendingPathComponent("transcription.json") }
    private var notesURL: URL { url.appendingPathComponent("notes.md") }

    public func decalage(_ piste: Piste) -> Double {
        meta.decalages?[piste.rawValue] ?? 0
    }

    public func enregistrerMeta() throws {
        try Bibliotheque.encodeur.encode(meta).write(to: metaURL, options: .atomic)
    }

    public func enregistrer(segments: [Segment]) throws {
        try Bibliotheque.encodeur.encode(segments).write(to: transcriptionURL, options: .atomic)
    }

    /// Remplace la transcription par celle de la relecture. Celle du direct reste à côté, jamais écrasée.
    public func remplacer(segments: [Segment]) throws {
        let direct = url.appendingPathComponent("transcription-direct.json")
        if !FileManager.default.fileExists(atPath: direct.path), FileManager.default.fileExists(atPath: transcriptionURL.path) {
            try FileManager.default.copyItem(at: transcriptionURL, to: direct)
        }
        try enregistrer(segments: segments)
    }

    /// Le nom d'une voix : celui donné par Steven, sinon « Voix 1 ».
    public func nom(de voix: String) -> String {
        meta.nomsDesVoix?[voix].flatMap { $0.isEmpty ? nil : $0 } ?? voix
    }

    public func segments() -> [Segment] {
        guard let data = try? Data(contentsOf: transcriptionURL) else { return [] }
        return (try? JSONDecoder().decode([Segment].self, from: data)) ?? []
    }

    public func enregistrer(notes: [LigneDeNote]) throws {
        try FormatNotes.ecrire(notes).write(to: notesURL, atomically: true, encoding: .utf8)
    }

    public func notes() -> [LigneDeNote] {
        guard let texte = try? String(contentsOf: notesURL, encoding: .utf8) else { return [] }
        return FormatNotes.lire(texte)
    }

    /// Écrit la dernière analyse. La précédente part dans `analyses/`.
    public func enregistrer(analyseJSON: Data, markdown: String) throws {
        let actuelle = url.appendingPathComponent("analyse.json")
        let lisible = url.appendingPathComponent("analyse.md")
        let gestionnaire = FileManager.default
        if gestionnaire.fileExists(atPath: actuelle.path) {
            let archives = url.appendingPathComponent("analyses")
            try gestionnaire.createDirectory(at: archives, withIntermediateDirectories: true)
            let base = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            // Plusieurs analyses dans la même seconde ne doivent pas se marcher dessus : on cherche un
            // nom libre pour la paire .json/.md, avec un suffixe -2, -3…
            var nom = base
            var suffixe = 2
            while gestionnaire.fileExists(atPath: archives.appendingPathComponent("\(nom).json").path) {
                nom = "\(base)-\(suffixe)"
                suffixe += 1
            }
            try gestionnaire.moveItem(at: actuelle, to: archives.appendingPathComponent("\(nom).json"))
            if gestionnaire.fileExists(atPath: lisible.path) {
                try gestionnaire.moveItem(at: lisible, to: archives.appendingPathComponent("\(nom).md"))
            }
        }
        try analyseJSON.write(to: actuelle, options: .atomic)
        try markdown.write(to: lisible, atomically: true, encoding: .utf8)
    }

    public func analyseJSON() -> Data? {
        try? Data(contentsOf: url.appendingPathComponent("analyse.json"))
    }

    /// Change dès que l'analyse ou la transcription est réécrite. Absente sans analyse ou sans transcription.
    public func signatureAnalyse() -> String? {
        let signatures = [url.appendingPathComponent("analyse.json"), transcriptionURL].map { fichier -> String? in
            guard let attributs = try? FileManager.default.attributesOfItem(atPath: fichier.path),
                  let date = attributs[.modificationDate] as? Date, let taille = attributs[.size] as? Int else { return nil }
            return "\(date.timeIntervalSinceReferenceDate)-\(taille)"
        }
        let presentes = signatures.compactMap { $0 }
        return presentes.count == signatures.count ? presentes.joined(separator: "|") : nil
    }
}

/// Le dossier choisi par Steven, avec ses réunions, rangées ou non dans des dossiers.
public struct Bibliotheque: Sendable {
    public let racine: URL

    static let encodeur: JSONEncoder = {
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encodeur.dateEncodingStrategy = .iso8601
        return encodeur
    }()

    private static let decodeur: JSONDecoder = {
        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .iso8601
        return decodeur
    }()

    public init(racine: URL) {
        self.racine = racine
    }

    private func sousDossiers(de url: URL) -> [URL] {
        let contenu = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                                    options: [.skipsHiddenFiles])) ?? []
        return contenu.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private func lireReunion(_ url: URL, dossier: String?) -> Reunion? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("meta.json")),
              let meta = try? Self.decodeur.decode(MetaReunion.self, from: data) else { return nil }
        return Reunion(url: url, meta: meta, dossier: dossier)
    }

    /// Toutes les réunions, les plus récentes d'abord.
    public func reunions() -> [Reunion] {
        var trouvees: [Reunion] = []
        for url in sousDossiers(de: racine) {
            if let reunion = lireReunion(url, dossier: nil) {
                trouvees.append(reunion)
            } else {
                trouvees += sousDossiers(de: url).compactMap { lireReunion($0, dossier: url.lastPathComponent) }
            }
        }
        return trouvees.sorted { $0.meta.date > $1.meta.date }
    }

    /// Les dossiers : ceux du disque qui ne sont pas eux-mêmes des réunions.
    public func dossiers() -> [String] {
        sousDossiers(de: racine)
            .filter { lireReunion($0, dossier: nil) == nil }
            .map(\.lastPathComponent)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func creerDossier(_ nom: String) throws -> String {
        let propre = Self.nomDeFichier(nom)
        try FileManager.default.createDirectory(at: racine.appendingPathComponent(propre), withIntermediateDirectories: true)
        return propre
    }

    public func creerReunion(titre: String, type: TypeReunion, dossier: String?, date: Date = Date()) throws -> Reunion {
        let titrePropre = titre.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = emplacementLibre(dans: dossier, base: Self.nomDeDossier(titre: titrePropre.isEmpty ? "Réunion" : titrePropre, date: date))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let reunion = Reunion(url: url, meta: MetaReunion(titre: titrePropre.isEmpty ? "Réunion" : titrePropre, date: date, type: type), dossier: dossier)
        try reunion.enregistrerMeta()
        return reunion
    }

    private static func nomDeDossier(titre: String, date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "fr_FR")
        format.dateFormat = "yyyy-MM-dd"
        return "\(format.string(from: date)) \(nomDeFichier(titre))"
    }

    private func emplacementLibre(dans dossier: String?, base: String) -> URL {
        let parent = dossier.map { racine.appendingPathComponent($0) } ?? racine
        var url = parent.appendingPathComponent(base)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = parent.appendingPathComponent("\(base) \(n)")
            n += 1
        }
        return url
    }

    /// Change le titre et le nom du dossier. Tout le contenu suit, notes comprises, sans y toucher.
    public func renommer(_ reunion: Reunion, en titre: String) throws -> Reunion {
        let propre = titre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty, propre != reunion.meta.titre else { return reunion }
        let cible = emplacementLibre(dans: reunion.dossier, base: Self.nomDeDossier(titre: propre, date: reunion.meta.date))
        try FileManager.default.moveItem(at: reunion.url, to: cible)
        var renommee = reunion
        renommee.url = cible
        renommee.meta.titre = propre
        do {
            try renommee.enregistrerMeta()
        } catch {
            // Le titre et le dossier ne doivent pas se contredire : tout revient en place.
            try? FileManager.default.moveItem(at: cible, to: reunion.url)
            throw error
        }
        return renommee
    }

    /// Range la réunion dans un dossier, ou à la racine avec nil.
    public func deplacer(_ reunion: Reunion, vers dossier: String?) throws -> Reunion {
        guard dossier != reunion.dossier else { return reunion }
        let cible = emplacementLibre(dans: dossier, base: reunion.url.lastPathComponent)
        try FileManager.default.createDirectory(at: cible.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: reunion.url, to: cible)
        var deplacee = reunion
        deplacee.url = cible
        deplacee.dossier = dossier
        return deplacee
    }

    /// Le dossier entier part à la Corbeille, d'où il reste récupérable.
    public func mettreALaCorbeille(_ reunion: Reunion) throws {
        try FileManager.default.trashItem(at: reunion.url, resultingItemURL: nil)
    }

    static func nomDeFichier(_ nom: String) -> String {
        let interdits = CharacterSet(charactersIn: "/:\\\n\r\t")
        let propre = nom.components(separatedBy: interdits).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        return propre.isEmpty ? "Sans titre" : String(propre.prefix(80))
    }
}
