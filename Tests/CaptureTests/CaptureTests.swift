import AVFoundation
@testable import Capture
import Foundation
import Testing

@Test func unEnregistrementCoupeSeTermineEnM4A() throws {
    let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dossier) }
    let aac = dossier.appendingPathComponent("micro.aac")
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
    let tampon = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
    tampon.frameLength = 48_000
    tampon.floatChannelData?[0].initialize(repeating: 0, count: 48_000)
    do {
        let fichier = try Recording.open(aac, sampleRate: 48_000)
        try fichier.write(from: tampon)
    }
    try terminerEnregistrement(aac)
    let duree = try #require(Recording.seconds(of: dossier.appendingPathComponent("micro.m4a")))
    #expect(duree > 0.8)
    #expect(!FileManager.default.fileExists(atPath: aac.path))
}

@Test func unEnregistrementIllisibleResteASaPlace() throws {
    let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dossier) }
    let aac = dossier.appendingPathComponent("micro.aac")
    try Data("pas de l'audio".utf8).write(to: aac)
    #expect(throws: ErreurCapture.self) { try terminerEnregistrement(aac) }
    #expect(FileManager.default.fileExists(atPath: aac.path))
    #expect(!FileManager.default.fileExists(atPath: dossier.appendingPathComponent("micro.m4a").path))
}

private final class SourceDeTest: AudioSource {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    func start() throws {}
    func stop() {}
}

private final class Erreurs: @unchecked Sendable {
    private let verrou = NSLock()
    private var compte = 0
    func ajouter() { verrou.withLock { compte += 1 } }
    var total: Int { verrou.withLock { compte } }
}

@Test func uneErreurDEcritureEstSignaleeUneSeuleFois() throws {
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
    let tampon = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
    tampon.frameLength = 4_800
    tampon.floatChannelData?[0].initialize(repeating: 0, count: 4_800)
    let source = SourceDeTest()
    let erreurs = Erreurs()
    let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dossier) }
    let impossible = dossier.appendingPathComponent("absent/micro.aac")
    let piste = PisteAudio(source: source, fichier: impossible, formatCible: format,
                           surConverti: { _ in }, surNiveau: { _ in }, surPremierSon: { _ in },
                           surErreur: { _ in erreurs.ajouter() })
    try piste.demarrer()
    source.onBuffer?(tampon)
    source.onBuffer?(tampon)
    piste.arreter()
    #expect(erreurs.total == 1)
}

// MARK: - La fréquence réelle du son du Mac

@Suite struct FrequenceMesureeTests {
    private func mesurer(annoncee: Double, reelle: Double, secondes: Double, depart: Double = 100,
                         _ mesure: inout FrequenceMesuree) -> Double? {
        let images = 512
        var temps = depart
        var derniere: Double?
        while temps < depart + secondes {
            derniere = mesure.observer(images: images, a: temps)
            temps += Double(images) / reelle
        }
        return derniere
    }

    @Test func unFluxA16kHzAnnonceA48kHzEstDemasque() {
        var mesure = FrequenceMesuree(annoncee: 48000)
        #expect(mesurer(annoncee: 48000, reelle: 16000, secondes: 1, &mesure) == 16000)
    }

    @Test func unFluxConformeGardeSaFrequence() {
        var mesure = FrequenceMesuree(annoncee: 48000)
        #expect(mesurer(annoncee: 48000, reelle: 48000, secondes: 2, &mesure) == 48000)
    }

    @Test func rienNestRetenuAvantLaPremiereFenetre() {
        var mesure = FrequenceMesuree(annoncee: 48000)
        #expect(mesurer(annoncee: 48000, reelle: 16000, secondes: 0.1, &mesure) == nil)
    }

    @Test func unCasquePasseEnModeAppelEnCoursDeReunionEstSuivi() {
        var mesure = FrequenceMesuree(annoncee: 48000)
        #expect(mesurer(annoncee: 48000, reelle: 48000, secondes: 1, &mesure) == 48000)
        #expect(mesurer(annoncee: 48000, reelle: 16000, secondes: 4, depart: 101, &mesure) == 16000)
    }

    @Test func unBlancNeFaitPasCroireAUneFrequenceBasse() {
        var mesure = FrequenceMesuree(annoncee: 48000)
        _ = mesurer(annoncee: 48000, reelle: 48000, secondes: 1, &mesure)
        #expect(mesurer(annoncee: 48000, reelle: 48000, secondes: 2, depart: 130, &mesure) == 48000)
    }

    @Test func unSeulAcoupNeChangeRien() {
        var mesure = FrequenceMesuree(annoncee: 48000)
        _ = mesurer(annoncee: 48000, reelle: 48000, secondes: 1, &mesure)
        #expect(mesurer(annoncee: 48000, reelle: 16000, secondes: 1.1, depart: 101, &mesure) == 48000)
        #expect(mesurer(annoncee: 48000, reelle: 48000, secondes: 2, depart: 102.1, &mesure) == 48000)
    }

    @Test func unTamponReetiqueteGardeSesEchantillons() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let tampon = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        tampon.frameLength = 4
        for i in 0..<4 { tampon.floatChannelData![0][i] = Float(i) }
        let juste = try #require(SystemAudioSource.reetiqueter(tampon, a: 16000))
        #expect(juste.format.sampleRate == 16000)
        #expect(juste.frameLength == 4)
        #expect(juste.floatChannelData![0][3] == 3)
    }
}
