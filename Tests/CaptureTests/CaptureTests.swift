import AVFoundation
import Capture
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
