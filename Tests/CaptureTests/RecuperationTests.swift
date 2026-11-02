import AVFoundation
import Capture
import Foundation
import Testing

private func ecrireSon(_ url: URL, secondes: Int) throws {
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
    let tampon = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
    tampon.frameLength = 48_000
    tampon.floatChannelData?[0].initialize(repeating: 0, count: 48_000)
    let fichier = try Recording.open(url, sampleRate: 48_000)
    for _ in 0..<secondes { try fichier.write(from: tampon) }
}

@Test func unM4ADeDureeDifferenteGardeLesDeuxFichiers() throws {
    let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dossier) }
    let aac = dossier.appendingPathComponent("micro.aac")
    let m4a = dossier.appendingPathComponent("micro.m4a")
    try ecrireSon(aac, secondes: 8)
    try Recording.remux(aac, to: m4a)
    let existant = try Data(contentsOf: m4a)
    try ecrireSon(aac, secondes: 1)
    let enCours = try Data(contentsOf: aac)

    #expect(throws: ErreurCapture.self) { try terminerEnregistrement(aac) }
    #expect(try Data(contentsOf: m4a) == existant)
    #expect(try Data(contentsOf: aac) == enCours)
}

@Test func unM4ADejaConvertiResteEtLeAACPartALaCorbeille() throws {
    let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dossier) }
    let aac = dossier.appendingPathComponent("micro.aac")
    let m4a = dossier.appendingPathComponent("micro.m4a")
    try ecrireSon(aac, secondes: 2)
    try Recording.remux(aac, to: m4a)
    let existant = try Data(contentsOf: m4a)

    try terminerEnregistrement(aac)
    #expect(try Data(contentsOf: m4a) == existant)
    #expect(!FileManager.default.fileExists(atPath: aac.path))
}

private final class SourceManuelle: AudioSource {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    func start() throws {}
    func stop() {}
}

private final class Journal: @unchecked Sendable {
    private let verrou = NSLock()
    private var etats: [Bool] = []
    private var erreurs = 0
    let ecrit = DispatchSemaphore(value: 0)
    func coupure(_ coupee: Bool) { verrou.withLock { etats.append(coupee) } }
    func erreur() { verrou.withLock { erreurs += 1 } }
    var coupures: [Bool] { verrou.withLock { etats } }
    var totalErreurs: Int { verrou.withLock { erreurs } }
}

private func silence(frequence: Double, secondes: Double) throws -> AVAudioPCMBuffer {
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: frequence, channels: 1, interleaved: false))
    let frames = AVAudioFrameCount(frequence * secondes)
    let tampon = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    tampon.frameLength = frames
    tampon.floatChannelData?[0].initialize(repeating: 0, count: Int(frames))
    return tampon
}

private func piste(_ aac: URL, source: SourceManuelle, journal: Journal, delai: TimeInterval = 5) throws -> PisteAudio {
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
    return PisteAudio(source: source, fichier: aac, formatCible: format, surConverti: { _ in journal.ecrit.signal() },
                      surNiveau: { _ in }, surPremierSon: { _ in }, surErreur: { _ in journal.erreur() },
                      surCoupure: { coupee, _ in journal.coupure(coupee) }, delaiCoupure: delai)
}

@Test func unMicroCoupeEstSignaleEtSonBlancComble() throws {
    let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dossier) }
    let aac = dossier.appendingPathComponent("micro.aac")
    let source = SourceManuelle()
    let journal = Journal()
    let audio = try piste(aac, source: source, journal: journal, delai: 0.5)
    try audio.demarrer()
    source.onBuffer?(try silence(frequence: 48_000, secondes: 1))
    Thread.sleep(forTimeInterval: 2.5)
    #expect(journal.coupures == [true])
    source.onBuffer?(try silence(frequence: 48_000, secondes: 1))
    audio.arreter()
    #expect(journal.coupures == [true, false])
    // Le premier tampon, environ 1,5 s de blanc comblé, puis le second : le fichier reste à l'heure.
    let duree = try #require(Recording.seconds(of: aac))
    #expect(duree > 3 && duree < 4)
}

@Test func uneNouvelleFrequenceSEcritDansLeMemeFichier() throws {
    let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dossier) }
    let aac = dossier.appendingPathComponent("micro.aac")
    let source = SourceManuelle()
    let journal = Journal()
    let audio = try piste(aac, source: source, journal: journal)
    try audio.demarrer()
    source.onBuffer?(try silence(frequence: 48_000, secondes: 1))
    source.onBuffer?(try silence(frequence: 44_100, secondes: 1))
    audio.arreter()
    #expect(journal.totalErreurs == 0)
    let duree = try #require(Recording.seconds(of: aac))
    #expect(duree > 1.8 && duree < 2.2)
}
