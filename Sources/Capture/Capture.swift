import AVFoundation
import AudioToolbox
import CaptureObjC
import CoreAudio
import Foundation
import os

public protocol AudioSource: AnyObject {
    /// Appelé sur un fil audio, avec un tampon valable seulement pendant l'appel.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)? { get set }
    func start() throws
    func stop()
}

public enum ErreurCapture: LocalizedError {
    case microRefuse
    case aucunMicro
    case sonDuMac(String, OSStatus)
    case enregistrementIllisible(String)
    case enregistrementEnDouble(String, String)
    case microEnTransition
    case entreeIndisponible
    case fichierDisparu(String)

    public var errorDescription: String? {
        switch self {
        case .microRefuse:
            return "Aparté n'a pas accès au micro. Autorise-le dans Réglages Système, Confidentialité et sécurité, Micro."
        case .aucunMicro:
            return "Aucun micro n'est disponible sur ce Mac."
        case let .sonDuMac(etape, code):
            return "Le son du Mac n'a pas pu être capté (\(etape), code \(code))."
        case let .enregistrementIllisible(fichier):
            return "L'enregistrement \(fichier) n'a pas pu être terminé. Le fichier reste dans son dossier."
        case .microEnTransition:
            return "Le micro change de réglage. Réessaie dans quelques secondes."
        case .entreeIndisponible:
            return "Le micro choisi n'est plus disponible. Choisis-en un autre."
        case let .fichierDisparu(fichier):
            return "Le fichier \(fichier) a disparu pendant l'enregistrement."
        case let .enregistrementEnDouble(enCours, termine):
            return "\(enCours) et \(termine) existent tous les deux, avec des durées différentes. Aparté garde les deux dans le dossier de la réunion."
        }
    }
}

/// Une entrée audio du Mac.
public struct EntreeAudio: Identifiable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let nom: String

    /// Les périphériques qui ont au moins un canal d'entrée.
    public static func liste() -> [EntreeAudio] {
        var adresse = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var taille: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &adresse, 0, nil, &taille) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(taille) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &adresse, 0, nil, &taille, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var canaux = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                    mScope: kAudioDevicePropertyScopeInput,
                                                    mElement: kAudioObjectPropertyElementMain)
            var tailleCanaux: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &canaux, 0, nil, &tailleCanaux) == noErr, tailleCanaux > 0 else { return nil }
            let liste = UnsafeMutableRawPointer.allocate(byteCount: Int(tailleCanaux), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { liste.deallocate() }
            guard AudioObjectGetPropertyData(id, &canaux, 0, nil, &tailleCanaux, liste) == noErr else { return nil }
            let tampons = UnsafeMutableAudioBufferListPointer(liste.assumingMemoryBound(to: AudioBufferList.self))
            guard tampons.reduce(0, { $0 + Int($1.mNumberChannels) }) > 0 else { return nil }

            var nomAdresse = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                        mScope: kAudioObjectPropertyScopeGlobal,
                                                        mElement: kAudioObjectPropertyElementMain)
            var nom: Unmanaged<CFString>?
            var tailleNom = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nomAdresse, 0, nil, &tailleNom, &nom) == noErr,
                  let valeur = nom?.takeRetainedValue() else { return nil }
            return EntreeAudio(id: id, nom: valeur as String)
        }
    }
}

/// Le micro, par AVAudioEngine, sur l'entrée choisie ou celle par défaut.
public final class MicrophoneSource: AudioSource {
    public var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var engine = AVAudioEngine()
    private let entree: AudioDeviceID?
    private var running = false
    private var observateur: NSObjectProtocol?
    private let verrou = NSLock()
    /// Pour les tests : un format que le micro refuse, comme pendant le changement de profil d'un casque.
    var formatImpose: AVAudioFormat?
    private(set) var relances = 0

    public init(entree: AudioDeviceID? = nil) {
        self.entree = entree
    }

    public static var accesAccorde: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    public func start() throws {
        try verrou.withLock {
            do {
                try lancer(sur: entree)
            } catch ErreurCapture.microEnTransition {
                // Le casque change de profil : on réessaie. `PisteAudio` signale le blanc s'il dure.
                relancerPlusTard()
            }
            running = true
        }
    }

    public func stop() {
        verrou.withLock {
            guard running else { return }
            running = false
            arreterMoteur()
        }
    }

    private func lancer(sur entree: AudioDeviceID?) throws {
        let input = engine.inputNode
        if var entree, let unite = input.audioUnit {
            let statut = AudioUnitSetProperty(unite, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                              &entree, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard statut == noErr else { throw ErreurCapture.entreeIndisponible }
        }
        let format = formatImpose ?? input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw ErreurCapture.aucunMicro }
        // Pendant qu'un casque Bluetooth change de profil, ce format n'est plus celui du matériel et
        // AVAudioEngine lance une exception Objective-C, que Swift ne sait pas attraper.
        var erreurDemarrage: Error?
        let exception = attraperException {
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                self?.onBuffer?(buffer)
            }
            self.engine.prepare()
            do {
                try self.engine.start()
            } catch {
                erreurDemarrage = error
            }
        }
        if exception != nil || erreurDemarrage != nil {
            _ = attraperException { input.removeTap(onBus: 0) }
        }
        if let exception {
            Logger(subsystem: "eu.stevenrsl.aparte", category: "capture").error("Micro : \(exception, privacy: .public)")
            throw ErreurCapture.microEnTransition
        }
        if let erreurDemarrage { throw erreurDemarrage }
        observateur = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.relancer()
        }
    }

    private func arreterMoteur() {
        if let observateur { NotificationCenter.default.removeObserver(observateur) }
        observateur = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// L'entrée a changé (micro débranché, casque connecté) : le moteur s'est arrêté. On repart sur
    /// l'entrée choisie si elle est encore là, sinon sur celle du système, et on réessaie tant qu'il n'y
    /// a rien. `PisteAudio` signale le blanc et le comble.
    private func relancer() {
        let finie = verrou.withLock { () -> Bool in
            guard running else { return true }
            guard !engine.isRunning else { return true }
            relances += 1
            arreterMoteur()
            return Self.repartir(sur: entree) { essai in
                engine = AVAudioEngine()
                try lancer(sur: essai)
            }
        }
        if !finie { relancerPlusTard() }
    }

    /// Un micro en transition est encore là : on le réessaiera, sans basculer sur celui du système.
    static func repartir(sur entree: AudioDeviceID?, lancer: (AudioDeviceID?) throws -> Void) -> Bool {
        for essai in [entree, nil] {
            do {
                try lancer(essai)
                return true
            } catch ErreurCapture.microEnTransition {
                return false
            } catch {}
        }
        return false
    }

    private func relancerPlusTard() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in self?.relancer() }
    }
}

/// Une source écrite dans son fichier et remise au transcripteur, hors du fil audio.
public final class PisteAudio: @unchecked Sendable {
    private let source: AudioSource
    private let fichierURL: URL
    private let formatCible: AVAudioFormat
    private let surConverti: @Sendable (AVAudioPCMBuffer) -> Void
    private let surNiveau: @Sendable (Float) -> Void
    private let surPremierSon: @Sendable (Date) -> Void
    private let surErreur: @Sendable (Error) -> Void
    private let surCoupure: @Sendable (Bool, Date) -> Void
    private let delaiCoupure: TimeInterval
    private var premierSonVu = false
    private var dernierTampon: Date?
    private var dernierSigne = Date()
    private var coupee = false
    private var surveillance: DispatchSourceTimer?
    private var convertisseurFichier: StreamConverter?
    private var erreurSignalee = false
    private let file = DispatchQueue(label: "eu.stevenrsl.aparte.piste", qos: .userInitiated)
    private var fichier: AVAudioFile?
    private var convertisseur: StreamConverter?

    public init(source: AudioSource, fichier: URL, formatCible: AVAudioFormat,
                surConverti: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
                surNiveau: @escaping @Sendable (Float) -> Void,
                surPremierSon: @escaping @Sendable (Date) -> Void,
                surErreur: @escaping @Sendable (Error) -> Void,
                surCoupure: @escaping @Sendable (Bool, Date) -> Void = { _, _ in },
                delaiCoupure: TimeInterval = 5) {
        self.source = source
        self.fichierURL = fichier
        self.formatCible = formatCible
        self.surConverti = surConverti
        self.surNiveau = surNiveau
        self.surPremierSon = surPremierSon
        self.surErreur = surErreur
        self.surCoupure = surCoupure
        self.delaiCoupure = delaiCoupure
    }

    public func demarrer() throws {
        source.onBuffer = { [weak self] tampon in
            guard let self, let mono = AudioBuffers.mono(tampon) else { return }
            // Le temps de cette piste part d'ici : son fichier et sa transcription commencent à ce tampon.
            if !self.premierSonVu {
                self.premierSonVu = true
                self.surPremierSon(Date())
            }
            let arrivee = Date()
            self.file.async { self.traiter(mono, arrivee: arrivee) }
        }
        try source.start()
        surveiller()
    }

    /// Plus aucun tampon pendant le délai : le son est coupé, et il faut le dire, car rien d'autre ne
    /// le signale. Rien ne dépend de la cause (débranchement, veille, panne du système).
    private func surveiller() {
        let minuteur = DispatchSource.makeTimerSource(queue: file)
        minuteur.schedule(deadline: .now() + delaiCoupure / 5, repeating: delaiCoupure / 5)
        minuteur.setEventHandler { [weak self] in
            guard let self, !self.coupee, Date().timeIntervalSince(self.dernierSigne) > self.delaiCoupure else { return }
            self.coupee = true
            self.surCoupure(true, self.dernierSigne)
        }
        minuteur.resume()
        file.sync { dernierSigne = Date(); surveillance = minuteur }
    }

    private func traiter(_ mono: AVAudioPCMBuffer, arrivee: Date) {
        surNiveau(AudioBuffers.level(mono))
        // Un blanc se comble par du silence : le fichier et la transcription restent à l'heure de la réunion.
        if let dernierTampon {
            let duree = Double(mono.frameLength) / mono.format.sampleRate
            let blanc = arrivee.timeIntervalSince(dernierTampon) - duree
            if blanc > 1 { combler(blanc, format: mono.format) }
        }
        dernierTampon = arrivee
        dernierSigne = arrivee
        if coupee {
            coupee = false
            surCoupure(false, arrivee)
        }
        ecrireEtTranscrire(mono)
    }

    private func combler(_ secondes: Double, format: AVAudioFormat) {
        var reste = Int(secondes * format.sampleRate)
        while reste > 0 {
            let frames = min(reste, Int(format.sampleRate))
            guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
                  let canal = silence.floatChannelData?[0] else { return }
            silence.frameLength = AVAudioFrameCount(frames)
            canal.initialize(repeating: 0, count: frames)
            ecrireEtTranscrire(silence)
            reste -= frames
        }
    }

    private func ecrireEtTranscrire(_ mono: AVAudioPCMBuffer) {
        do {
            if fichier == nil { fichier = try Recording.open(fichierURL, sampleRate: Recording.fileSampleRate(for: mono.format.sampleRate)) }
            // Un fichier supprimé mais ouvert accepte encore les écritures : seul son chemin le dit.
            guard FileManager.default.fileExists(atPath: fichierURL.path) else {
                throw ErreurCapture.fichierDisparu(fichierURL.lastPathComponent)
            }
            if let tampon = pourFichier(mono) { try fichier?.write(from: tampon) }
        } catch {
            if !erreurSignalee {
                erreurSignalee = true
                Logger(subsystem: "eu.stevenrsl.aparte", category: "capture")
                    .error("Écriture de \(self.fichierURL.lastPathComponent, privacy: .public) : \(String(describing: error), privacy: .public)")
                surErreur(error)
            }
        }
        // Une nouvelle entrée peut avoir une autre fréquence : le convertisseur suit.
        if convertisseur?.source != mono.format { convertisseur = StreamConverter(from: mono.format, to: formatCible) }
        if let converti = convertisseur?.convert(mono) { surConverti(converti) }
    }

    /// `nil` quand le convertisseur garde encore ce tampon : l'écrire tel quel le mettrait à la mauvaise fréquence.
    private func pourFichier(_ mono: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let cible = fichier?.processingFormat, cible != mono.format else { return mono }
        if convertisseurFichier?.source != mono.format { convertisseurFichier = StreamConverter(from: mono.format, to: cible) }
        return convertisseurFichier?.convert(mono)
    }

    /// Arrête la source, puis ferme le fichier une fois tout écrit.
    public func arreter() {
        source.stop()
        source.onBuffer = nil
        file.sync {
            surveillance?.cancel()
            surveillance = nil
            fichier = nil
        }
    }
}

/// Le niveau du micro, sans rien écrire : pour le test d'avant la réunion.
public final class TestMicro: @unchecked Sendable {
    private let source: MicrophoneSource

    public init(entree: AudioDeviceID?, surNiveau: @escaping @Sendable (Float) -> Void) {
        source = MicrophoneSource(entree: entree)
        source.onBuffer = { tampon in
            if let mono = AudioBuffers.mono(tampon) { surNiveau(AudioBuffers.level(mono)) }
        }
    }

    public func demarrer() throws { try source.start() }
    public func arreter() { source.stop() }
}

/// Termine un enregistrement : le `.aac` passe en `.m4a` sans réencodage. Il ne part à la corbeille
/// qu'une fois le `.m4a` relu. S'il est illisible, il reste à sa place et l'erreur remonte.
/// Un `.m4a` déjà là n'est jamais remplacé : de même durée, c'est la conversion d'un essai coupé avant
/// la corbeille, et le `.aac` peut y partir. Sinon, les deux fichiers restent et l'erreur remonte.
public func terminerEnregistrement(_ aac: URL) throws {
    guard let duree = Recording.seconds(of: aac), duree > 0 else {
        throw ErreurCapture.enregistrementIllisible(aac.lastPathComponent)
    }
    let m4a = aac.deletingPathExtension().appendingPathExtension("m4a")
    if FileManager.default.fileExists(atPath: m4a.path) {
        guard let existant = Recording.seconds(of: m4a), abs(existant - duree) < 0.5 else {
            throw ErreurCapture.enregistrementEnDouble(aac.lastPathComponent, m4a.lastPathComponent)
        }
        mettreAACALaCorbeille(aac)
        return
    }
    try Recording.remux(aac, to: m4a)
    guard let relu = Recording.seconds(of: m4a), relu > 0 else {
        throw ErreurCapture.enregistrementIllisible(aac.lastPathComponent)
    }
    mettreAACALaCorbeille(aac)
}

/// Le son est déjà sauf dans le `.m4a` relu : un refus de la corbeille ne doit pas empêcher la relecture de
/// la réunion. Le `.aac` reste à sa place, et un prochain lancement réessaiera.
private func mettreAACALaCorbeille(_ aac: URL) {
    do {
        try FileManager.default.trashItem(at: aac, resultingItemURL: nil)
    } catch {
        Logger(subsystem: "eu.stevenrsl.aparte", category: "capture")
            .error("\(aac.lastPathComponent, privacy: .public) reste à sa place : \(String(describing: error), privacy: .public)")
    }
}
