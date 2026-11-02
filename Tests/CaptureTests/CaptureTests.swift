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
    do {
        let fichier = try Recording.open(aac, sampleRate: 48_000)
        try fichier.write(from: tampon)
    }
    try terminerEnregistrement(aac)
    let duree = try #require(Recording.seconds(of: dossier.appendingPathComponent("micro.m4a")))
    #expect(duree > 0.8)
    #expect(!FileManager.default.fileExists(atPath: aac.path))
}
