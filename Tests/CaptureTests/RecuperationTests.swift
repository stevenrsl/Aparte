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
