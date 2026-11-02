@preconcurrency import AVFoundation
import Analyse
import AppKit
import Capture
import Foundation
import Observation
import Stockage
import Transcription

public enum Ecran: Hashable {
    case accueil
    case nouvelle
    case enReunion
    case compteRendu(Reunion)
    case dossier(String)
    case reglages
}

/// Une action d'un compte rendu, avec la réunion où elle a été dite.
public struct ActionOuverte: Identifiable {
    public let reunion: Reunion
    public let element: ElementSource
    public var id: UUID { element.id }
}

@MainActor
@Observable
public final class ModeleApp {
    public var ecran: Ecran = .accueil
    public var racine: URL?
    public var reunions: [Reunion] = []
    public var dossiers: [String] = []
    public var session: SessionReunion?
    public var erreur: String?
    @ObservationIgnored private var compteRendus: [String: CompteRendu] = [:]
    @ObservationIgnored private var faites: [String: Set<UUID>] = [:]
    @ObservationIgnored private static let cleRacine = "racine"

    public init() {
        if let chemin = UserDefaults.standard.string(forKey: Self.cleRacine) {
            racine = URL(fileURLWithPath: chemin)
        }
        recharger()
    }

    var bibliotheque: Bibliotheque? { racine.map { Bibliotheque(racine: $0) } }

    public func choisirEmplacement() {
        let panneau = NSOpenPanel()
        panneau.canChooseDirectories = true
        panneau.canChooseFiles = false
        panneau.canCreateDirectories = true
        panneau.prompt = "Choisir ce dossier"
        panneau.message = "Choisis où ranger tes réunions. Tu peux prendre un dossier dans iCloud Drive."
        guard panneau.runModal() == .OK, let url = panneau.url else { return }
        racine = url
        UserDefaults.standard.set(url.path, forKey: Self.cleRacine)
        recharger()
    }

    public func recharger() {
        guard let bibliotheque else { return }
        reunions = bibliotheque.reunions()
        dossiers = bibliotheque.dossiers()
        compteRendus = [:]
        for reunion in reunions {
            // Un enregistrement coupé par un plantage se termine ici.
            if session?.reunion.id != reunion.id {
                for aac in [reunion.microEnCours, reunion.systemeEnCours]
                where FileManager.default.fileExists(atPath: aac.path) {
                    try? terminerEnregistrement(aac)
                }
            }
            if let compteRendu = compteRendu(de: reunion) { compteRendus[reunion.id] = compteRendu }
        }
    }

    func compteRendu(de reunion: Reunion) -> CompteRendu? {
        guard let data = reunion.analyseJSON() else { return nil }
        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .iso8601
        return try? decodeur.decode(CompteRendu.self, from: data)
    }

    func resumeEnregistre(de reunion: Reunion) -> CompteRendu? { compteRendus[reunion.id] }

    func enregistrer(_ compteRendu: CompteRendu, pour reunion: Reunion) throws {
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.prettyPrinted, .sortedKeys]
        encodeur.dateEncodingStrategy = .iso8601
        try reunion.enregistrer(analyseJSON: encodeur.encode(compteRendu), markdown: compteRendu.markdown)
        var meta = reunion
        if !meta.meta.fournisseurs.contains(compteRendu.fournisseur) {
            meta.meta.fournisseurs.append(compteRendu.fournisseur)
            try? meta.enregistrerMeta()
        }
        compteRendus[reunion.id] = compteRendu
    }

    // MARK: Les actions à cocher

    private func urlFaites(_ reunion: Reunion) -> URL { reunion.url.appendingPathComponent("actions-faites.json") }

    private func actionsFaites(_ reunion: Reunion) -> Set<UUID> {
        if let connues = faites[reunion.id] { return connues }
        let lues = (try? Data(contentsOf: urlFaites(reunion))).flatMap { try? JSONDecoder().decode(Set<UUID>.self, from: $0) } ?? []
        faites[reunion.id] = lues
        return lues
    }

    func actionsOuvertes(dossier: String? = nil) -> [ActionOuverte] {
        reunions.filter { dossier == nil || $0.dossier == dossier }.flatMap { reunion -> [ActionOuverte] in
            let cochees = actionsFaites(reunion)
            return (compteRendus[reunion.id]?.actions ?? [])
                .filter { !cochees.contains($0.id) }
                .map { ActionOuverte(reunion: reunion, element: $0) }
        }
    }

    func cocher(_ action: ActionOuverte) {
        var cochees = actionsFaites(action.reunion)
        cochees.insert(action.element.id)
        faites[action.reunion.id] = cochees
        try? JSONEncoder().encode(cochees).write(to: urlFaites(action.reunion), options: .atomic)
        reunions = reunions
    }

    // MARK: L'enregistrement

    public func demarrer(titre: String, type: TypeReunion, dossier: String?, entree: EntreeAudio?) async {
        guard let bibliotheque, session == nil else { return }
        do {
            guard await MicrophoneSource.requestAccess() else { throw ErreurCapture.microRefuse }
            let reunion = try bibliotheque.creerReunion(titre: titre, type: type, dossier: dossier)
            let nouvelle = SessionReunion(reunion: reunion)
            session = nouvelle
            ecran = .enReunion
            try await nouvelle.demarrer(entree: entree)
            recharger()
        } catch {
            session = nil
            ecran = .nouvelle
            erreur = error.localizedDescription
        }
    }

    public func terminer() async {
        guard let session else { return }
        let reunion = await session.terminer()
        self.session = nil
        recharger()
        ecran = .compteRendu(reunions.first { $0.id == reunion.id } ?? reunion)
    }
}

/// La réunion en cours d'enregistrement.
@MainActor
@Observable
public final class SessionReunion {
    public private(set) var reunion: Reunion
    public private(set) var segments: [Segment] = []
    public private(set) var provisoires: [Piste: String] = [:]
    public var lignes: [LigneDeNote] = [LigneDeNote(temps: 0, texte: "")]
    public private(set) var niveauxMoi: [Float] = Array(repeating: 0, count: 24)
    public private(set) var niveauxEux: [Float] = Array(repeating: 0, count: 24)
    public private(set) var debut: Date?
    public private(set) var etat = "Préparation de la transcription…"
    public private(set) var alerte: String?
    @ObservationIgnored private var pistes: [PisteAudio] = []
    @ObservationIgnored private var transcripteurs: [TranscripteurDirect] = []

    init(reunion: Reunion) {
        self.reunion = reunion
    }

    public var temps: Double { debut.map { Date().timeIntervalSince($0) } ?? 0 }

    func demarrer(entree: EntreeAudio?) async throws {
        let locale = try await Parole.preparer()

        let surFinal: @MainActor (Segment) -> Void = { [weak self] segment in self?.ajouter(segment) }
        let surProvisoire: @MainActor (Piste, String) -> Void = { [weak self] piste, texte in self?.provisoires[piste] = texte }

        let micro = try await TranscripteurDirect.demarrer(locale: locale, piste: .micro, surFinal: surFinal, surProvisoire: surProvisoire)
        transcripteurs.append(micro)
        let pisteMicro = PisteAudio(source: MicrophoneSource(entree: entree?.id), fichier: reunion.microEnCours,
                                    formatCible: micro.formatAttendu,
                                    surConverti: { micro.alimenter($0) },
                                    surNiveau: { [weak self] niveau in Task { @MainActor in self?.pousser(niveau, moi: true) } })
        try pisteMicro.demarrer()
        pistes.append(pisteMicro)
        debut = Date()
        etat = ""

        guard reunion.meta.type == .visio else { return }
        do {
            let systeme = try await TranscripteurDirect.demarrer(locale: locale, piste: .systeme, surFinal: surFinal, surProvisoire: surProvisoire)
            transcripteurs.append(systeme)
            let pisteSysteme = PisteAudio(source: SystemAudioSource(), fichier: reunion.systemeEnCours,
                                          formatCible: systeme.formatAttendu,
                                          surConverti: { systeme.alimenter($0) },
                                          surNiveau: { [weak self] niveau in Task { @MainActor in self?.pousser(niveau, moi: false) } })
            try pisteSysteme.demarrer()
            pistes.append(pisteSysteme)
        } catch {
            // Le micro continue : mieux vaut une piste qu'aucune, et Steven le voit.
            alerte = "\(error.localizedDescription) Le micro continue d'enregistrer."
        }
    }

    private func ajouter(_ segment: Segment) {
        let rang = segments.firstIndex { $0.debut > segment.debut } ?? segments.endIndex
        segments.insert(segment, at: rang)
        try? reunion.enregistrer(segments: segments)
    }

    private func pousser(_ niveau: Float, moi: Bool) {
        if moi {
            niveauxMoi.removeFirst()
            niveauxMoi.append(niveau)
        } else {
            niveauxEux.removeFirst()
            niveauxEux.append(niveau)
        }
    }

    /// Une ligne reçoit l'horodatage du moment où elle est commencée.
    public func changer(_ id: UUID, texte: String) {
        guard let rang = lignes.firstIndex(where: { $0.id == id }) else { return }
        if lignes[rang].texte.isEmpty, !texte.isEmpty { lignes[rang].temps = temps }
        lignes[rang].texte = texte
        try? reunion.enregistrer(notes: lignes)
    }

    public func ligneSuivante() -> UUID {
        if let derniere = lignes.last, derniere.texte.isEmpty { return derniere.id }
        let nouvelle = LigneDeNote(temps: temps, texte: "")
        lignes.append(nouvelle)
        return nouvelle.id
    }

    func terminer() async -> Reunion {
        etat = "Derniers mots en cours de transcription…"
        let duree = temps
        for piste in pistes { piste.arreter() }
        for transcripteur in transcripteurs { await transcripteur.terminer() }
        for aac in [reunion.microEnCours, reunion.systemeEnCours] where FileManager.default.fileExists(atPath: aac.path) {
            try? terminerEnregistrement(aac)
        }
        reunion.meta.duree = duree
        try? reunion.enregistrerMeta()
        try? reunion.enregistrer(segments: segments)
        try? reunion.enregistrer(notes: lignes)
        return reunion
    }
}

/// Relit les deux pistes d'une réunion, ensemble, à un moment donné.
@MainActor
@Observable
final class Lecteur {
    private var lecteurs: [AVAudioPlayer] = []
    private(set) var enLecture = false

    func charger(_ reunion: Reunion) {
        arreter()
        lecteurs = [reunion.micro, reunion.systeme].compactMap { try? AVAudioPlayer(contentsOf: $0) }
        lecteurs.forEach { $0.prepareToPlay() }
    }

    var disponible: Bool { !lecteurs.isEmpty }

    func lire(a temps: Double) {
        guard let horloge = lecteurs.first?.deviceCurrentTime else { return }
        for lecteur in lecteurs {
            lecteur.stop()
            lecteur.currentTime = max(0, temps)
            lecteur.play(atTime: horloge + 0.05)
        }
        enLecture = true
    }

    func arreter() {
        lecteurs.forEach { $0.stop() }
        enLecture = false
    }
}
