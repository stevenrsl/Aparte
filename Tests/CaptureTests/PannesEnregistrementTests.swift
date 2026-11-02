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

private func commande(_ executable: String, _ arguments: [String]) throws {
    let processus = Process()
    processus.executableURL = URL(fileURLWithPath: executable)
    processus.arguments = arguments
    try processus.run()
    processus.waitUntilExit()
    try #require(processus.terminationStatus == 0)
}

private func producteur(dans dossier: URL, disquePlein: Bool) throws -> Process {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let support = repo.appendingPathComponent("Tests/Support/Pannes")
    let binaire = dossier.appendingPathComponent("producteur")
    try commande("/usr/bin/xcrun", ["swiftc", "-swift-version", "5", "-module-cache-path", dossier.appendingPathComponent("cache").path,
        repo.appendingPathComponent("Sources/Capture/Recording.swift").path,
        repo.appendingPathComponent("Sources/Capture/Capture.swift").path,
        repo.appendingPathComponent("Sources/Capture/AudioBuffers.swift").path,
        support.appendingPathComponent("main.swift").path, "-o", binaire.path])
    let processus = Process()
    processus.executableURL = binaire
    processus.arguments = [dossier.path]
    var environnement = ProcessInfo.processInfo.environment
    environnement.removeValue(forKey: "APARTE_AUDIO_REFERENCE")
    environnement.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
    if disquePlein {
        let dylib = dossier.appendingPathComponent("plein.dylib")
        try commande("/usr/bin/xcrun", ["clang", "-dynamiclib", "-framework", "AudioToolbox", support.appendingPathComponent("disque-plein.c").path, "-o", dylib.path])
        environnement["DYLD_INSERT_LIBRARIES"] = dylib.path
        environnement["APARTE_PANNE_PLEIN"] = dossier.appendingPathComponent("plein").path
    }
    processus.environment = environnement
    try processus.run()
    return processus
}

private func nettoyer(_ processus: Process) {
    if processus.isRunning { _ = kill(processus.processIdentifier, SIGKILL) }
    processus.waitUntilExit()
}

private func attendre(_ fichier: URL, processus: Process) throws {
    let limite = Date().addingTimeInterval(15)
    while !FileManager.default.fileExists(atPath: fichier.path), processus.isRunning, Date() < limite {
        Thread.sleep(forTimeInterval: 0.01)
    }
    try #require(FileManager.default.fileExists(atPath: fichier.path))
}

@Test func panneKill9PendantEcriture() throws {
    let dossier = try temporaire()
    defer { try? FileManager.default.removeItem(at: dossier) }
    let processus = try producteur(dans: dossier, disquePlein: false)
    defer { nettoyer(processus) }
    try attendre(dossier.appendingPathComponent("pret"), processus: processus)
    let aac = dossier.appendingPathComponent("micro.aac")
    try #require(try Data(contentsOf: aac).count > 0)
    try #require(processus.isRunning)
    try #require(kill(processus.processIdentifier, SIGKILL) == 0)
    processus.waitUntilExit()
    #expect(processus.terminationReason == .uncaughtSignal)
    #expect(processus.terminationStatus == SIGKILL)
    let avant = try #require(Recording.seconds(of: aac))
    let m4a = dossier.appendingPathComponent("micro.m4a")
    try Recording.remux(aac, to: m4a)
    let apres = try #require(Recording.seconds(of: m4a))
    #expect(apres > 8 && abs(apres - avant) < 0.5)
}

@Test func panneDisquePleinPendantEcriture() throws {
    let dossier = try temporaire()
    defer { try? FileManager.default.removeItem(at: dossier) }
    let processus = try producteur(dans: dossier, disquePlein: true)
    defer { nettoyer(processus) }
    try attendre(dossier.appendingPathComponent("pret"), processus: processus)
    let aac = dossier.appendingPathComponent("micro.aac")
    let avant = try Data(contentsOf: aac)
    try #require(!avant.isEmpty)
    try Data().write(to: dossier.appendingPathComponent("plein"))
    try attendre(dossier.appendingPathComponent("erreurs"), processus: processus)
    processus.waitUntilExit()
    #expect(processus.terminationStatus == 0)
    #expect(try String(contentsOf: dossier.appendingPathComponent("erreurs"), encoding: .utf8) == "1")
    #expect(try Data(contentsOf: aac).starts(with: avant))
    let m4a = dossier.appendingPathComponent("micro.m4a")
    try Recording.remux(aac, to: m4a)
    #expect(try #require(Recording.seconds(of: m4a)) > 8)
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
