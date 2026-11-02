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

    public init(titre: String, date: Date, type: TypeReunion) {
        self.titre = titre
        self.date = date
        self.duree = 0
        self.type = type
        self.participants = []
        self.fournisseurs = []
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
            let nom = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
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
        let parent = dossier.map { racine.appendingPathComponent($0) } ?? racine
        let format = DateFormatter()
        format.locale = Locale(identifier: "fr_FR")
        format.dateFormat = "yyyy-MM-dd"
        let titrePropre = titre.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "\(format.string(from: date)) \(Self.nomDeFichier(titrePropre.isEmpty ? "Réunion" : titrePropre))"
        var url = parent.appendingPathComponent(base)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = parent.appendingPathComponent("\(base) \(n)")
            n += 1
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let reunion = Reunion(url: url, meta: MetaReunion(titre: titrePropre.isEmpty ? "Réunion" : titrePropre, date: date, type: type), dossier: dossier)
        try reunion.enregistrerMeta()
        return reunion
    }

    static func nomDeFichier(_ nom: String) -> String {
        let interdits = CharacterSet(charactersIn: "/:\\\n\r\t")
        let propre = nom.components(separatedBy: interdits).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        return propre.isEmpty ? "Sans titre" : String(propre.prefix(80))
    }
}
