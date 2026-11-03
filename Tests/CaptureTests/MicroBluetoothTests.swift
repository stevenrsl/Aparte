import AVFoundation
@testable import Capture
import CaptureObjC
import Foundation
import Testing

private final class SourceFactice: AudioSource, @unchecked Sendable {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    func start() throws {}
    func stop() {}
}

private final class Compteur: @unchecked Sendable {
    private let verrou = NSLock()
    private var valeur = 0
    func ajouter() { verrou.withLock { valeur += 1 } }
    var total: Int { verrou.withLock { valeur } }
}

/// Un micro à cette fréquence s'enregistre, sans erreur, avec la bonne durée.
private func enregistreUneSeconde(a frequence: Double) throws {
    let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("aparte-bluetooth-\(UUID())")
    try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dossier) }
    let aac = dossier.appendingPathComponent("micro.aac")

    let source = SourceFactice()
    let erreurs = Compteur()
    let cible = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
    let piste = PisteAudio(source: source, fichier: aac, formatCible: cible,
                           surConverti: { _ in }, surNiveau: { _ in }, surPremierSon: { _ in },
                           surErreur: { _ in erreurs.ajouter() })
    try piste.demarrer()

    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: frequence, channels: 1, interleaved: false))
    let frames = AVAudioFrameCount(frequence / 10)
    for _ in 0..<10 {
        let tampon = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        tampon.frameLength = frames
        let canal = try #require(tampon.floatChannelData?[0])
        for i in 0..<Int(frames) { canal[i] = Float(sin(Double(i) * 2 * .pi * 440 / frequence)) * 0.1 }
        source.onBuffer?(tampon)
    }
    piste.arreter()

    #expect(erreurs.total == 0)
    try terminerEnregistrement(aac)
    let duree = try #require(Recording.seconds(of: aac.deletingPathExtension().appendingPathExtension("m4a")))
    #expect(abs(duree - 1) < 0.2)
}

@Test(arguments: [8_000.0, 16_000, 24_000, 44_100, 48_000, 96_000])
func unMicroSEnregistreAToutesLesFrequences(frequence: Double) throws {
    try enregistreUneSeconde(a: frequence)
}

@Test func uneExceptionObjectiveCEstAttrapee() {
    #expect(attraperException { NSException(name: .genericException, reason: "panne", userInfo: nil).raise() } == "panne")
    #expect(attraperException {} == nil)
}

/// Le plantage du 3 novembre 2026 : pendant qu'un casque change de profil, le format du micro n'est
/// plus celui du matériel. Le démarrage doit survivre et réessayer. Le moteur ne démarre jamais ici :
/// rien n'est capté.
@Test func unFormatRefuseParLeMicroNePlantePasEtSeraReessaye() async throws {
    let source = MicrophoneSource()
    let moteur = AVAudioEngine()
    let materiel = moteur.inputNode.outputFormat(forBus: 0)
    try #require(materiel.sampleRate > 0)
    source.formatImpose = AVAudioFormat(standardFormatWithSampleRate: materiel.sampleRate == 16_000 ? 48_000 : 16_000, channels: 1)

    try source.start()
    try await Task.sleep(for: .seconds(2.5))
    #expect(source.relances >= 1)
    source.stop()
    let apresArret = source.relances
    try await Task.sleep(for: .seconds(2.5))
    #expect(source.relances == apresArret)
}
