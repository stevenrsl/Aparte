@preconcurrency import AVFoundation
import Analyse
import AppKit
import Capture
import Foundation
import Observation
import Stockage
import Transcription
import Voix

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
    /// Les réunions en cours de relecture, avec leur avancée.
    public private(set) var relectures: [String: Double] = [:]
    /// Les réunions en cours d'analyse, avec leur avancée.
    public private(set) var analyses: [String: Double] = [:]
    /// Une analyse lancée sans clic qui n'a pas abouti, avec sa raison lisible. Elle s'efface au
    /// prochain essai, clic compris.
    public private(set) var echecsAnalyseAuto: [String: String] = [:]
    /// Une clé Mistral est dans le trousseau. Elle-même n'est lue qu'au moment d'envoyer.
    public private(set) var cleMistralPresente = Trousseau.mistral.presente()
    @ObservationIgnored private var compteRendus: [String: CompteRendu] = [:]
    @ObservationIgnored private var comptesRendusLus: [String: (signature: String, compteRendu: CompteRendu)] = [:]
    @ObservationIgnored private var faites: [String: Set<UUID>] = [:]
    @ObservationIgnored private var echecsSignales: Set<String> = []
    @ObservationIgnored private static let cleRacine = "racine"

    public init() {
        // Pour essayer l'app dans un dossier de test, sans toucher au choix de Steven.
        if let chemin = ProcessInfo.processInfo.environment["APARTE_RACINE"] ?? UserDefaults.standard.string(forKey: Self.cleRacine) {
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
        var echecs: [String] = []
        for reunion in reunions {
            // Un enregistrement coupé par un plantage se termine ici.
            if session?.reunion.id != reunion.id {
                for aac in [reunion.microEnCours, reunion.systemeEnCours]
                where FileManager.default.fileExists(atPath: aac.path) {
                    do {
                        try terminerEnregistrement(aac)
                    } catch where echecsSignales.insert(aac.path).inserted {
                        echecs.append("« \(reunion.meta.titre) » : \(error.localizedDescription)")
                    } catch {}
                }
            }
            // Revalider coûte une dizaine de millisecondes pour 2 h de réunion : tant que ni l'analyse
            // ni la transcription n'ont bougé, le résultat précédent vaut toujours.
            let signature = reunion.signatureAnalyse()
            if let signature, let lu = comptesRendusLus[reunion.id], lu.signature == signature {
                compteRendus[reunion.id] = lu.compteRendu
            } else if let compteRendu = compteRendu(de: reunion) {
                compteRendus[reunion.id] = compteRendu
                if let signature { comptesRendusLus[reunion.id] = (signature, compteRendu) }
            }
        }
        if !echecs.isEmpty { erreur = ([erreur].compactMap { $0 } + echecs).joined(separator: "\n") }
    }

    func compteRendu(de reunion: Reunion) -> CompteRendu? {
        guard let data = reunion.analyseJSON() else { return nil }
        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .iso8601
        return (try? decodeur.decode(CompteRendu.self, from: data))?.revalide(dans: reunion.segments())
    }

    func resumeEnregistre(de reunion: Reunion) -> CompteRendu? { compteRendus[reunion.id] }

    /// Le JSON et l'empreinte d'origine ne changent jamais ici : seul le Markdown lisible, et le cache
    /// affiché, sortent de la version revalidée face à la transcription actuelle. Une analyse qui finit
    /// après une relecture (son empreinte, prise avant, ne correspond plus) s'enregistre donc déjà périmée,
    /// sans attendre un prochain `recharger()`.
    func enregistrer(_ compteRendu: CompteRendu, pour reunion: Reunion) throws {
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.prettyPrinted, .sortedKeys]
        encodeur.dateEncodingStrategy = .iso8601
        let revalidee = compteRendu.revalide(dans: reunion.segments())
        try reunion.enregistrer(analyseJSON: encodeur.encode(compteRendu), markdown: revalidee.markdown(incidents: reunion.meta.incidentsAudio ?? []))
        var meta = reunion
        if !meta.meta.fournisseurs.contains(compteRendu.fournisseur) {
            meta.meta.fournisseurs.append(compteRendu.fournisseur)
            try? meta.enregistrerMeta()
        }
        compteRendus[reunion.id] = revalidee
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
            try await nouvelle.demarrer(entree: entree, vocabulaire: vocabulaire(pour: reunion))
            recharger()
        } catch {
            session = nil
            ecran = .nouvelle
            erreur = error.localizedDescription
        }
    }

    /// La réunion en cours d'enregistrement ou de relecture ne se range pas : ses fichiers sont utilisés.
    func estEnCours(_ reunion: Reunion) -> Bool { session?.reunion.id == reunion.id || relectures[reunion.id] != nil || analyses[reunion.id] != nil }

    /// Les noms que le transcripteur doit reconnaître : le titre, le dossier, et tous les noms déjà
    /// donnés à des voix. Plus on nomme de voix, mieux les noms s'écrivent.
    func vocabulaire(pour reunion: Reunion) -> [String] {
        let noms = reunions.flatMap { Array(($0.meta.nomsDesVoix ?? [:]).values) + $0.meta.participants }
        var vus = Set<String>()
        return ([reunion.meta.titre, reunion.dossier].compactMap { $0 } + noms).filter { !$0.isEmpty && vus.insert($0).inserted }
    }

    /// Relit l'enregistrement : les voix séparées, l'écho marqué, les noms corrigés. Si les voix
    /// échouent, les mots restent : ils valent plus que de savoir qui les a dits.
    public func relire(_ reunion: Reunion) {
        guard relectures[reunion.id] == nil, session?.reunion.id != reunion.id else { return }
        relectures[reunion.id] = 0
        let vocabulaire = vocabulaire(pour: reunion)
        Task {
            do {
                let resultat = try await Relecture.relire(reunion, vocabulaire: vocabulaire) { [weak self] avancee in
                    Task { @MainActor in if self?.relectures[reunion.id] != nil { self?.relectures[reunion.id] = avancee } }
                }
                var relue = reunion
                relue.meta.relue = true
                try relue.remplacer(segments: resultat.segments)
                try relue.enregistrerMeta()
                if let raison = resultat.voixEchouees {
                    erreur = "Les voix n'ont pas pu être séparées (\(raison)). La transcription est là, sans elles."
                }
            } catch {
                erreur = "L'enregistrement de « \(reunion.meta.titre) » n'a pas pu être relu : \(error.localizedDescription) La transcription du direct reste là."
            }
            relectures[reunion.id] = nil
            actualiser(reunion)
            if let relue = reunions.first(where: { $0.id == reunion.id }) {
                // Le compte rendu est prêt sans clic, mais seulement sur ce Mac : rien ne part jamais tout seul.
                if compteRendu(de: relue) == nil {
                    analyser(relue, avec: AnalysteLocal(), signaler: false)
                } else {
                    marquerSiPerimee(relue)
                }
            }
        }
    }

    /// Si la relecture a changé la transcription, l'analyse déjà là ne la montre plus : son fichier
    /// lisible le dit aussi, sans toucher à son contenu ni à son empreinte. Pas de ré-analyse automatique
    /// sur une réunion déjà analysée : elle partirait sur un fournisseur que Steven n'a pas forcément
    /// choisi cette fois.
    private func marquerSiPerimee(_ reunion: Reunion) {
        guard let donnees = reunion.analyseJSON() else { return }
        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .iso8601
        guard let brute = try? decodeur.decode(CompteRendu.self, from: donnees) else { return }
        let segments = reunion.segments()
        guard brute.etat(selon: segments) == .perimee else { return }
        let revalidee = brute.revalide(dans: segments)
        let markdown = revalidee.markdown(incidents: reunion.meta.incidentsAudio ?? [])
        do {
            try reunion.enregistrer(analyseJSON: donnees, markdown: markdown)
        } catch {
            // `enregistrer` écrit le Markdown avant le JSON : si lui seul a échoué, le compte rendu
            // affiché dit déjà « périmée », et ce message ne doit pas prétendre le contraire.
            let lisible = reunion.url.appendingPathComponent("analyse.md")
            if (try? String(contentsOf: lisible, encoding: .utf8)) == markdown {
                erreur = "Le compte rendu de « \(reunion.meta.titre) » est marqué périmé, mais n'a pas pu l'être dans son fichier interne : \(error.localizedDescription)"
            } else {
                erreur = "Le compte rendu de « \(reunion.meta.titre) » n'a pas pu être marqué périmé : \(error.localizedDescription)"
            }
        }
    }

    /// Analyse une réunion. `signaler` : une analyse lancée sans clic n'interrompt pas pour dire
    /// qu'Apple Intelligence n'est pas disponible, le bouton reste là.
    public func analyser(_ reunion: Reunion, avec analyste: any Analyste, signaler: Bool = true) {
        guard analyses[reunion.id] == nil, relectures[reunion.id] == nil else { return }
        // Le modèle lit les noms donnés aux voix. Les temps et les mots ne changent pas.
        var segments = reunion.segments()
        guard !segments.isEmpty else { return }
        // Prise avant le remplacement des voix par leurs noms : une relecture qui finit pendant cette
        // analyse encore en cours changera cette empreinte, et l'analyse apparaîtra périmée dès sa fin.
        let empreinte = CompteRendu.empreinte(de: segments)
        for i in segments.indices { segments[i].voix = segments[i].voix.map { reunion.nom(de: $0) } }
        analyses[reunion.id] = 0
        echecsAnalyseAuto[reunion.id] = nil
        let notes = reunion.notes()
        let type = reunion.meta.type
        Task {
            do {
                var resultat = try await analyste.analyser(segments: segments, notes: notes, type: type) { [weak self] avancee in
                    Task { @MainActor in if self?.analyses[reunion.id] != nil { self?.analyses[reunion.id] = avancee } }
                }
                resultat.empreinte = empreinte
                try enregistrer(resultat, pour: reunion)
            } catch {
                // Lancée sans clic, une erreur n'interrompt pas (le bouton reste là) : mais elle ne doit
                // pas non plus rester muette, sans quoi l'écran dit « pas encore d'analyse » pour toujours.
                if signaler { erreur = error.localizedDescription } else { echecsAnalyseAuto[reunion.id] = error.localizedDescription }
            }
            analyses[reunion.id] = nil
            actualiser(reunion)
        }
    }

    /// Envoie cette réunion à Mistral. Seul un clic de Steven, confirmé, arrive ici (règle 2).
    public func analyserAvecMistral(_ reunion: Reunion) {
        guard let cle = Trousseau.mistral.lire() else { return }
        analyser(reunion, avec: AnalysteMistral(cle: cle))
    }

    public func enregistrerCleMistral(_ cle: String?) {
        if !Trousseau.mistral.ecrire(cle) { erreur = "La clé n'a pas pu être rangée dans le trousseau." }
        cleMistralPresente = Trousseau.mistral.presente()
    }

    /// Copie la clé que Cairn a rangée, sur le clic de Steven. macOS peut demander son autorisation, et
    /// la clé de Cairn reste en place. Vrai si une clé a été reprise.
    @discardableResult
    public func reprendreCleDeCairn(depuis source: Trousseau = .mistralDeCairn, vers cible: Trousseau = .mistral) -> Bool {
        guard let cle = source.lire() else { return false }
        guard cible.ecrire(cle) else {
            erreur = "La clé n'a pas pu être rangée dans le trousseau."
            return false
        }
        cleMistralPresente = Trousseau.mistral.presente()
        return true
    }

    /// Le nombre de réunions déjà envoyées à un service hors du Mac.
    public var reunionsEnvoyees: Int {
        reunions.filter { $0.meta.fournisseurs.contains { !$0.hasPrefix("Local") } }.count
    }

    /// Une réunion qui a touché plusieurs dossiers : chacun reçoit un extrait avec ses sujets, leurs
    /// phrases, leurs notes et leurs éléments. L'original ne change pas. Rien ne s'écrit sans ce clic.
    public func repartir(_ reunion: Reunion, _ choix: [UUID: String]) {
        guard let bibliotheque, let compteRendu = compteRendu(de: reunion), !estEnCours(reunion) else { return }
        let sujets = compteRendu.sujets ?? []
        let dossiersChoisis = Set(choix.values)
        do {
            for dossier in dossiersChoisis.sorted() {
                let choisis = sujets.filter { choix[$0.id] == dossier }
                guard !choisis.isEmpty else { continue }
                func garder(_ temps: Double) -> Bool { choisis.contains { $0.contient(temps) } }
                var extrait = try bibliotheque.creerReunion(titre: "\(reunion.meta.titre) · extrait", type: reunion.meta.type,
                                                            dossier: bibliotheque.creerDossier(dossier), date: reunion.meta.date)
                extrait.meta.origine = reunion.meta.titre
                extrait.meta.duree = choisis.reduce(0) { $0 + ($1.fin - $1.debut) }
                extrait.meta.decalages = reunion.meta.decalages
                extrait.meta.nomsDesVoix = reunion.meta.nomsDesVoix
                try extrait.enregistrerMeta()
                // Même chevauchement que le contrôle des sujets périmés (`CompteRendu.revalide`) : un seul
                // long segment qui englobe tout un sujet doit aussi être gardé, pas seulement celui qui
                // commence ou finit dedans. Les notes, elles, restent un point : `garder` au-dessus.
                let segmentsExtrait = reunion.segments().filter { segment in choisis.contains { $0.chevauche(segment) } }
                try extrait.enregistrer(segments: segmentsExtrait)
                try extrait.enregistrer(notes: reunion.notes().filter { garder($0.temps) })
                // L'extrait d'une analyse qui n'était déjà plus à jour, ou sans aucune transcription à lui,
                // ne peut pas se déclarer à jour lui-même.
                let empreinteExtrait = (compteRendu.fraicheur == .aJour && !segmentsExtrait.isEmpty)
                    ? CompteRendu.empreinte(de: segmentsExtrait) : nil
                try enregistrer(compteRendu.extrait(choisis, empreinte: empreinteExtrait), pour: extrait)
            }
            recharger()
        } catch {
            erreur = "La répartition de « \(reunion.meta.titre) » n'a pas pu se terminer : \(error.localizedDescription) L'original n'a pas changé."
            recharger()
        }
    }

    /// Donne un nom à une voix, partout dans la réunion. La transcription n'est pas réécrite.
    public func nommer(_ voix: String, _ nom: String, dans reunion: Reunion) {
        var nommee = reunions.first { $0.id == reunion.id } ?? reunion
        nommee.meta.nomsDesVoix = (nommee.meta.nomsDesVoix ?? [:]).merging([voix: nom.trimmingCharacters(in: .whitespacesAndNewlines)]) { _, nouveau in nouveau }
        do {
            try nommee.enregistrerMeta()
            actualiser(reunion)
        } catch {
            erreur = "Le nom n'a pas pu être enregistré : \(error.localizedDescription)"
        }
    }

    private func actualiser(_ reunion: Reunion) {
        recharger()
        if case let .compteRendu(affichee) = ecran, affichee.id == reunion.id,
           let relue = reunions.first(where: { $0.id == reunion.id }) {
            ecran = .compteRendu(relue)
        }
    }

    public func renommer(_ reunion: Reunion, en titre: String) {
        ranger(reunion) { try $0.renommer(reunion, en: titre) }
    }

    public func deplacer(_ reunion: Reunion, vers dossier: String?) {
        ranger(reunion) { try $0.deplacer(reunion, vers: dossier) }
    }

    /// Crée un dossier et y range la réunion.
    public func deplacer(_ reunion: Reunion, versNouveauDossier nom: String) {
        let propre = nom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return }
        ranger(reunion) { try $0.deplacer(reunion, vers: $0.creerDossier(propre)) }
    }

    private func ranger(_ reunion: Reunion, _ action: (Bibliotheque) throws -> Reunion) {
        guard let bibliotheque, !estEnCours(reunion) else { return }
        do {
            let rangee = try action(bibliotheque)
            faites[reunion.id] = nil
            recharger()
            if case let .compteRendu(affichee) = ecran, affichee.id == reunion.id {
                ecran = .compteRendu(reunions.first { $0.id == rangee.id } ?? rangee)
            }
        } catch {
            erreur = "« \(reunion.meta.titre) » n'a pas pu être rangée : \(error.localizedDescription)"
        }
    }

    public func mettreALaCorbeille(_ reunion: Reunion) {
        guard let bibliotheque, !estEnCours(reunion) else { return }
        do {
            try bibliotheque.mettreALaCorbeille(reunion)
            faites[reunion.id] = nil
            if case let .compteRendu(affichee) = ecran, affichee.id == reunion.id { ecran = .accueil }
            recharger()
        } catch {
            erreur = "« \(reunion.meta.titre) » n'a pas pu aller à la Corbeille : \(error.localizedDescription)"
        }
    }

    public func terminer() async {
        guard let session else { return }
        do {
            let reunion = try await session.terminer()
            self.session = nil
            recharger()
            let terminee = reunions.first { $0.id == reunion.id } ?? reunion
            ecran = .compteRendu(terminee)
            relire(terminee)
        } catch {
            // La session reste ouverte : rien de ce qui est en mémoire n'est abandonné.
            erreur = "Ta réunion n'a pas pu être écrite sur le disque : \(error.localizedDescription) Vérifie le dossier, puis clique de nouveau sur Terminer."
        }
    }
}

/// La réunion en cours d'enregistrement.
@MainActor
@Observable
public final class SessionReunion {
    public private(set) var reunion: Reunion
    public private(set) var segments: [Segment] = []
    /// Ce qui s'affiche : l'écho marqué, les phrases réunies. `segments` garde les phrases séparées.
    public private(set) var segmentsLisibles: [Segment] = []
    public private(set) var provisoires: [Piste: String] = [:]
    public var lignes: [LigneDeNote] = [LigneDeNote(temps: 0, texte: "")]
    public private(set) var niveauxMoi: [Float] = Array(repeating: 0, count: 24)
    public private(set) var niveauxEux: [Float] = Array(repeating: 0, count: 24)
    public private(set) var debut: Date?
    public private(set) var etat = "Préparation de la transcription…"
    private var alerteSysteme: String?
    private var alertesAudio: [String: String] = [:]
    private var alerteSauvegarde: String?
    private enum Ecriture { case meta, transcription, notes }
    @ObservationIgnored private var enAttente: Set<Ecriture> = []
    @ObservationIgnored private var arretee = false
    @ObservationIgnored private var activite: NSObjectProtocol?
    @ObservationIgnored private var duree = 0.0
    @ObservationIgnored private var pistes: [PisteAudio] = []
    @ObservationIgnored private var transcripteurs: [TranscripteurDirect] = []

    init(reunion: Reunion) {
        self.reunion = reunion
    }

    public var alerte: String? {
        let alertes = alertesAudio.keys.sorted().compactMap { alertesAudio[$0] } + [alerteSauvegarde, alerteSysteme].compactMap { $0 }
        return alertes.isEmpty ? nil : alertes.joined(separator: " ")
    }

    public var temps: Double { debut.map { Date().timeIntervalSince($0) } ?? 0 }

    func demarrer(entree: EntreeAudio?, vocabulaire: [String] = []) async throws {
        let locale = try await Parole.preparer()

        let surFinal: @MainActor (Segment) -> Void = { [weak self] segment in self?.ajouter(segment) }
        let surProvisoire: @MainActor (Piste, String) -> Void = { [weak self] piste, texte in self?.provisoires[piste] = texte }

        // Tout se prépare d'abord, pour que les pistes démarrent au plus près l'une de l'autre.
        let micro = try await TranscripteurDirect.demarrer(locale: locale, piste: .micro, vocabulaire: vocabulaire, surFinal: surFinal, surProvisoire: surProvisoire)
        transcripteurs.append(micro)
        var transcripteurSysteme: TranscripteurDirect?
        if reunion.meta.type == .visio {
            do {
                let systeme = try await TranscripteurDirect.demarrer(locale: locale, piste: .systeme, vocabulaire: vocabulaire, surFinal: surFinal, surProvisoire: surProvisoire)
                transcripteurs.append(systeme)
                transcripteurSysteme = systeme
            } catch {
                alerteSysteme = "\(error.localizedDescription) Le micro continue d'enregistrer."
            }
        }

        let origine = Date()
        debut = origine
        etat = ""

        let pisteMicro = PisteAudio(source: MicrophoneSource(entree: entree?.id), fichier: reunion.microEnCours,
                                    formatCible: micro.formatAttendu,
                                    surConverti: { micro.alimenter($0) },
                                    surNiveau: { [weak self] niveau in Task { @MainActor in self?.pousser(niveau, moi: true) } },
                                    surPremierSon: { [weak self] date in Task { @MainActor in self?.noter(.micro, date.timeIntervalSince(origine)) } },
                                    surErreur: { [weak self] _ in Task { @MainActor in self?.signalerAudio("micro") } },
                                    surCoupure: { [weak self] coupee, date in Task { @MainActor in self?.noterCoupure("micro", coupee: coupee, a: date) } })
        try pisteMicro.demarrer()
        pistes.append(pisteMicro)
        // Le Mac ne s'endort pas seul pendant une réunion. Fermer le capot reste possible : l'alerte le dira.
        activite = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "Réunion en cours d'enregistrement")

        guard let transcripteurSysteme else { return }
        do {
            let pisteSysteme = PisteAudio(source: SystemAudioSource(), fichier: reunion.systemeEnCours,
                                          formatCible: transcripteurSysteme.formatAttendu,
                                          surConverti: { transcripteurSysteme.alimenter($0) },
                                          surNiveau: { [weak self] niveau in Task { @MainActor in self?.pousser(niveau, moi: false) } },
                                          surPremierSon: { [weak self] date in Task { @MainActor in self?.noter(.systeme, date.timeIntervalSince(origine)) } },
                                          surErreur: { [weak self] _ in Task { @MainActor in self?.signalerAudio("son du Mac") } },
                                          surCoupure: { [weak self] coupee, date in Task { @MainActor in self?.noterCoupure("son du Mac", coupee: coupee, a: date) } })
            try pisteSysteme.demarrer()
            pistes.append(pisteSysteme)
        } catch {
            // Le micro continue : mieux vaut une piste qu'aucune, et Steven le voit.
            alerteSysteme = "\(error.localizedDescription) Le micro continue d'enregistrer."
        }
    }

    func signalerAudio(_ piste: String) {
        alertesAudio[piste] = "Attention : l'audio (\(piste)) n'est plus enregistré. Vérifie l'espace disque et le dossier des réunions."
        ajouterIncident(IncidentAudio(piste: piste, debut: temps))
    }

    /// Le son d'une piste s'arrête ou revient. L'incident reste dans la réunion, pour que le compte
    /// rendu dise qu'il manque un moment.
    func noterCoupure(_ piste: String, coupee: Bool, a date: Date) {
        let moment = debut.map { date.timeIntervalSince($0) } ?? 0
        if coupee {
            alertesAudio[piste] = "Attention : plus de son (\(piste)) depuis \(horodatage(moment)). Vérifie ton entrée audio."
            ajouterIncident(IncidentAudio(piste: piste, debut: moment))
        } else {
            alertesAudio[piste] = "Le son (\(piste)) est revenu à \(horodatage(moment)). Il reste un blanc dans l'enregistrement."
            if let rang = reunion.meta.incidentsAudio?.lastIndex(where: { $0.piste == piste && $0.fin == nil }) {
                reunion.meta.incidentsAudio?[rang].fin = moment
            }
            sauvegarder(.meta)
        }
    }

    private func ajouterIncident(_ incident: IncidentAudio) {
        reunion.meta.incidentsAudio = (reunion.meta.incidentsAudio ?? []) + [incident]
        sauvegarder(.meta)
    }

    /// Une écriture ratée reste en attente et se réessaie à chaque sauvegarde. L'alerte ne part que
    /// lorsque plus rien n'attend : le succès d'une autre écriture ne suffit pas.
    private func sauvegarder(_ ecriture: Ecriture) {
        enAttente.insert(ecriture)
        for attente in enAttente {
            do {
                switch attente {
                case .meta: try reunion.enregistrerMeta()
                case .transcription: try reunion.enregistrer(segments: segments)
                case .notes: try reunion.enregistrer(notes: lignes)
                }
                enAttente.remove(attente)
            } catch {}
        }
        alerteSauvegarde = enAttente.isEmpty ? nil : "Attention : tes notes et la transcription ne s'écrivent plus sur le disque. Elles restent ici : ne quitte pas Aparté."
    }

    /// Le décalage d'une piste part sur le disque dès qu'il est connu, pour survivre à un plantage.
    private func noter(_ piste: Piste, _ decalage: Double) {
        reunion.meta.decalages = (reunion.meta.decalages ?? [:]).merging([piste.rawValue: decalage]) { _, nouveau in nouveau }
        sauvegarder(.meta)
    }

    func ajouter(_ recu: Segment) {
        // Le transcripteur compte depuis le premier son de sa piste : on revient à l'horloge de la réunion.
        var segment = recu
        segment.debut += reunion.decalage(recu.piste)
        segment.fin += reunion.decalage(recu.piste)
        let rang = segments.firstIndex { $0.debut > segment.debut } ?? segments.endIndex
        segments.insert(segment, at: rang)
        let marques = Nettoyage.marquerEcho(segments)
        segments = marques
        segmentsLisibles = Nettoyage.fusionner(marques)
        sauvegarder(.transcription)
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
        sauvegarder(.notes)
    }

    public func ligneSuivante() -> UUID {
        if let derniere = lignes.last, derniere.texte.isEmpty { return derniere.id }
        let nouvelle = LigneDeNote(temps: temps, texte: "")
        lignes.append(nouvelle)
        return nouvelle.id
    }

    /// Arrête l'audio une seule fois, puis écrit tout. Si l'écriture échoue, l'erreur remonte et
    /// tout reste en mémoire : un nouvel appel réessaie sans rien réenregistrer.
    func terminer() async throws -> Reunion {
        if !arretee {
            arretee = true
            etat = "Derniers mots en cours de transcription…"
            duree = temps
            for piste in pistes { piste.arreter() }
            if let activite { ProcessInfo.processInfo.endActivity(activite) }
            activite = nil
            for transcripteur in transcripteurs { await transcripteur.terminer() }
            etat = ""
        }
        reunion.meta.duree = duree
        try reunion.enregistrerMeta()
        try reunion.enregistrer(segments: segments)
        try reunion.enregistrer(notes: lignes)
        return reunion
    }
}

/// Relit les deux pistes d'une réunion, ensemble, à un moment donné.
@MainActor
@Observable
final class Lecteur {
    private var lecteurs: [(lecteur: AVAudioPlayer, decalage: Double)] = []
    private(set) var enLecture = false

    func charger(_ reunion: Reunion) {
        arreter()
        lecteurs = [(reunion.micro, Piste.micro), (reunion.systeme, Piste.systeme)].compactMap { url, piste in
            (try? AVAudioPlayer(contentsOf: url)).map { ($0, reunion.decalage(piste)) }
        }
        lecteurs.forEach { $0.lecteur.prepareToPlay() }
    }

    var disponible: Bool { !lecteurs.isEmpty }

    func lire(a temps: Double) {
        guard let horloge = lecteurs.first?.lecteur.deviceCurrentTime else { return }
        for (lecteur, decalage) in lecteurs {
            let (position, attente) = positionDeLecture(temps: max(0, temps), decalage: decalage)
            lecteur.stop()
            lecteur.currentTime = position
            lecteur.play(atTime: horloge + 0.05 + attente)
        }
        enLecture = true
    }

    func arreter() {
        lecteurs.forEach { $0.lecteur.stop() }
        enLecture = false
    }
}

/// La seconde lecture d'une réunion, à partir de ses enregistrements. En visio, le micro, c'est une
/// seule personne : seul le son du Mac est lu pour ses voix. En présentiel, c'est le micro.
enum Relecture {
    struct Resultat {
        var segments: [Segment]
        var voixEchouees: String?
    }

    /// Marque l'écho puis réunit les phrases proches : la relecture doit garder la marque après
    /// la fusion, comme le direct (`SessionReunion.ajouter`).
    static func nettoyer(_ segments: [Segment]) -> [Segment] {
        Nettoyage.fusionner(Nettoyage.marquerEcho(segments))
    }

    static func relire(_ reunion: Reunion, vocabulaire: [String], progression: @escaping @Sendable (Double) -> Void) async throws -> Resultat {
        let visio = reunion.meta.type == .visio
        let pistes = [(reunion.micro, Piste.micro), (reunion.systeme, Piste.systeme)]
            .filter { FileManager.default.fileExists(atPath: $0.0.path) }
        guard !pistes.isEmpty else { throw ErreurRelecture.sansEnregistrement }

        var segments: [Segment] = []
        var voixEchouees: String?
        for (rang, (url, piste)) in pistes.enumerated() {
            let base = Double(rang) / Double(pistes.count)
            let avancer: @Sendable (Double) -> Void = { progression(base + $0 * 0.8 / Double(pistes.count)) }
            var lus: [Segment]
            if visio && piste == .micro {
                lus = try await TranscripteurFichier.transcrire(url: url, piste: piste, vocabulaire: vocabulaire, progression: avancer)
            } else {
                let phrases = try await TranscripteurFichier.phrases(url: url, vocabulaire: vocabulaire, progression: avancer)
                var tours: [TourDeVoix] = []
                do {
                    tours = try await Voix.trouver(dans: url)
                } catch {
                    voixEchouees = error.localizedDescription
                }
                lus = Attribution.attribuer(phrases, a: tours, piste: piste)
                for i in lus.indices { lus[i].texte = Nettoyage.corrigerNoms(lus[i].texte, noms: vocabulaire) }
            }
            // Le fichier compte depuis le premier son de sa piste : on revient à l'horloge de la réunion.
            let decalage = reunion.decalage(piste)
            for i in lus.indices {
                lus[i].debut += decalage
                lus[i].fin += decalage
            }
            segments += lus
        }
        progression(1)
        return Resultat(segments: Self.nettoyer(segments), voixEchouees: voixEchouees)
    }
}

enum ErreurRelecture: LocalizedError {
    case sansEnregistrement

    var errorDescription: String? { "Aucun enregistrement n'a été trouvé pour cette réunion." }
}
