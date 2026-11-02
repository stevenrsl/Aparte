import AVFoundation
import Foundation

// Compilé avec les sources Capture par le test, sans accès à un périphérique audio.
final class Source: AudioSource {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    func start() throws {}
    func stop() {}
}
final class Suivi: @unchecked Sendable {
    let fin = DispatchSemaphore(value: 0)
    let verrou = NSLock()
    private var erreurs = 0
    func signaler() { verrou.withLock { erreurs += 1 } }
    var total: Int { verrou.withLock { erreurs } }
}
let dossier = URL(fileURLWithPath: CommandLine.arguments[1])
let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
let tampon = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
tampon.frameLength = 48_000
for i in 0..<48_000 { tampon.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 48_000)) * 0.1 }
let suivi = Suivi()
let source = Source()
let piste = PisteAudio(source: source, fichier: dossier.appendingPathComponent("micro.aac"), formatCible: format,
                      surConverti: { _ in suivi.fin.signal() }, surNiveau: { _ in },
                      surPremierSon: { _ in }, surErreur: { _ in suivi.signaler() })
try piste.demarrer()
for i in 0..<500 {
    source.onBuffer?(tampon)
    guard suivi.fin.wait(timeout: .now() + 5) == .success else { exit(2) }
    if i == 10 { try Data("prêt".utf8).write(to: dossier.appendingPathComponent("pret")) }
    if suivi.total > 0 {
        // Plusieurs écritures échouent, mais PisteAudio ne doit signaler qu'une fois.
        for _ in 0..<3 {
            source.onBuffer?(tampon)
            guard suivi.fin.wait(timeout: .now() + 5) == .success else { exit(3) }
        }
        piste.arreter()
        try Data(String(suivi.total).utf8).write(to: dossier.appendingPathComponent("erreurs"))
        exit(0)
    }
    Thread.sleep(forTimeInterval: 0.01)
}
piste.arreter()
exit(4) // Borne stricte : jamais un producteur infini si le parent échoue.
