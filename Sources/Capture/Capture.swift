import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

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

    public var errorDescription: String? {
        switch self {
        case .microRefuse:
            return "Aparté n'a pas accès au micro. Autorise-le dans Réglages Système, Confidentialité et sécurité, Micro."
        case .aucunMicro:
            return "Aucun micro n'est disponible sur ce Mac."
        case let .sonDuMac(etape, code):
            return "Le son du Mac n'a pas pu être capté (\(etape), code \(code))."
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
    private let engine = AVAudioEngine()
    private let entree: AudioDeviceID?
    private var running = false

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
        let input = engine.inputNode
        if var entree, let unite = input.audioUnit {
            AudioUnitSetProperty(unite, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &entree, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw ErreurCapture.aucunMicro }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.onBuffer?(buffer)
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    public func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}

/// Une source écrite dans son fichier et remise au transcripteur, hors du fil audio.
public final class PisteAudio: @unchecked Sendable {
    private let source: AudioSource
    private let fichierURL: URL
    private let formatCible: AVAudioFormat
    private let surConverti: @Sendable (AVAudioPCMBuffer) -> Void
    private let surNiveau: @Sendable (Float) -> Void
    private let file = DispatchQueue(label: "eu.stevenrsl.aparte.piste", qos: .userInitiated)
    private var fichier: AVAudioFile?
    private var convertisseur: StreamConverter?
    public private(set) var erreurEcriture: Error?

    public init(source: AudioSource, fichier: URL, formatCible: AVAudioFormat,
                surConverti: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
                surNiveau: @escaping @Sendable (Float) -> Void) {
        self.source = source
        self.fichierURL = fichier
        self.formatCible = formatCible
        self.surConverti = surConverti
        self.surNiveau = surNiveau
    }

    public func demarrer() throws {
        source.onBuffer = { [weak self] tampon in
            guard let self, let mono = AudioBuffers.mono(tampon) else { return }
            self.file.async { self.traiter(mono) }
        }
        try source.start()
    }

    private func traiter(_ mono: AVAudioPCMBuffer) {
        surNiveau(AudioBuffers.level(mono))
        do {
            if fichier == nil { fichier = try Recording.open(fichierURL, sampleRate: mono.format.sampleRate) }
            try fichier?.write(from: mono)
        } catch {
            erreurEcriture = error
        }
        if convertisseur == nil { convertisseur = StreamConverter(from: mono.format, to: formatCible) }
        if let converti = convertisseur?.convert(mono) { surConverti(converti) }
    }

    /// Arrête la source, puis ferme le fichier une fois tout écrit.
    public func arreter() {
        source.stop()
        source.onBuffer = nil
        file.sync { fichier = nil }
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

/// Termine un enregistrement : le `.aac` passe en `.m4a` sans réencodage, puis va à la corbeille.
public func terminerEnregistrement(_ aac: URL) throws {
    let m4a = aac.deletingPathExtension().appendingPathExtension("m4a")
    if let duree = Recording.seconds(of: aac), duree > 0 {
        try Recording.remux(aac, to: m4a)
    }
    try FileManager.default.trashItem(at: aac, resultingItemURL: nil)
}
