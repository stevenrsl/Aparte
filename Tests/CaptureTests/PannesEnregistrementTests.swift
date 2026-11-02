import AVFoundation
import Capture
import Darwin
import Foundation
import Testing

private func temporaire() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("aparte-pannes-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func son() throws -> AVAudioPCMBuffer {
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
    let tampon = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
    tampon.frameLength = 48_000
    let canal = try #require(tampon.floatChannelData?[0])
    for i in 0..<48_000 { canal[i] = Float(sin(Double(i) * 2 * .pi * 440 / 48_000)) * 0.1 }
    return tampon
}

private func ecrire(_ url: URL, secondes: Int = 6) throws {
    let fichier = try Recording.open(url, sampleRate: 48_000)
    let tampon = try son()
    for _ in 0..<secondes { try fichier.write(from: tampon) }
}

@Test func panneAACTronqueAuMilieuDUneTrame() throws {
    let dossier = try temporaire()
    defer { try? FileManager.default.removeItem(at: dossier) }
    let aac = dossier.appendingPathComponent("micro.aac")
    let m4a = dossier.appendingPathComponent("micro.m4a")
    try ecrire(aac)
    let original = try Data(contentsOf: aac)
    // Coupe au milieu d'une vraie trame ADTS, vers la moitié du fichier.
    var position = 0
    var trames = 0
    while position < original.count / 2 {
        let taille = (Int(original[position + 3] & 3) << 11)
            | (Int(original[position + 4]) << 3) | Int(original[position + 5] >> 5)
        try #require(taille > 7 && position + taille <= original.count)
        position += taille
        trames += 1
    }
    let taille = (Int(original[position + 3] & 3) << 11)
        | (Int(original[position + 4]) << 3) | Int(original[position + 5] >> 5)
    let coupe = original.prefix(position + taille / 2)
    try coupe.write(to: aac)
    try Recording.remux(aac, to: m4a)
    let duree = try #require(Recording.seconds(of: m4a))
    #expect(duree > 0)
    #expect(abs(duree - Double(trames * 1024) / 48_000) < 0.5)
    #expect(try Data(contentsOf: aac) == coupe)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dossier.path).sorted() == ["micro.aac", "micro.m4a"])
}

@Test func panneAACVideEstConserveSansM4A() throws {
    let dossier = try temporaire()
    defer { try? FileManager.default.removeItem(at: dossier) }
    let aac = dossier.appendingPathComponent("micro.aac")
    try Data().write(to: aac)
    #expect(throws: ErreurCapture.self) { try terminerEnregistrement(aac) }
    #expect(try Data(contentsOf: aac).isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dossier.path) == ["micro.aac"])
}

@Test func panneM4AExistantNeDoitPasEtreEcrase() throws {
    let dossier = try temporaire()
    defer { try? FileManager.default.removeItem(at: dossier) }
    let aac = dossier.appendingPathComponent("micro.aac")
    let m4a = dossier.appendingPathComponent("micro.m4a")
    try ecrire(aac, secondes: 8)
    try Recording.remux(aac, to: m4a)
    let avant = try Data(contentsOf: m4a)
    try ecrire(aac, secondes: 2)
    try Recording.remux(aac, to: m4a)
    let apres = try Data(contentsOf: m4a)
    withKnownIssue("Défaut connu : remux remplace un M4A existant, même plus long (rapport pannes).") {
        #expect(apres == avant)
    }
    #expect(try #require(Recording.seconds(of: m4a)) < 3)
    #expect(FileManager.default.fileExists(atPath: aac.path))
}

private final class SourcePanne: AudioSource {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    func start() throws {}
    func stop() {}
}

private final class SuiviPanne: @unchecked Sendable {
    private let verrou = NSLock()
    private var erreurs = 0
    let ecrit = DispatchSemaphore(value: 0)
    func erreur() { verrou.withLock { erreurs += 1 } }
    var total: Int { verrou.withLock { erreurs } }
}

@Test func panneDossierSupprimePendantEcriture() throws {
    let dossier = try temporaire()
    defer { try? FileManager.default.removeItem(at: dossier) }
    let aac = dossier.appendingPathComponent("micro.aac")
    let source = SourcePanne()
    let suivi = SuiviPanne()
    let tampon = try son()
    let piste = PisteAudio(source: source, fichier: aac, formatCible: tampon.format,
                          surConverti: { _ in suivi.ecrit.signal() }, surNiveau: { _ in },
                          surPremierSon: { _ in }, surErreur: { _ in suivi.erreur() })
    try piste.demarrer()
    defer { piste.arreter() }
    source.onBuffer?(tampon)
    try #require(suivi.ecrit.wait(timeout: .now() + 5) == .success)
    try #require(FileManager.default.fileExists(atPath: aac.path))
    try FileManager.default.removeItem(at: dossier)
    source.onBuffer?(tampon)
    try #require(suivi.ecrit.wait(timeout: .now() + 5) == .success)
    withKnownIssue("Défaut connu : le fichier ouvert mais supprimé reste inscriptible sans alerte.") {
        #expect(suivi.total == 1)
    }
    #expect(!FileManager.default.fileExists(atPath: aac.path))
}
