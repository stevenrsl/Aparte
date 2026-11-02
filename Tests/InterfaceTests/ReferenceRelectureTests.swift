import AVFoundation
import Capture
import Foundation
import Stockage
import Testing
import Transcription
@testable import Interface

private final class SourceFichier: AudioSource {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    func start() throws {}
    func stop() {}
}

@MainActor
private final class Recus: Sendable {
    var segments: [Segment] = []
}

private func mots(_ segments: [Segment]) -> [String] {
    segments.flatMap { $0.texte.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) }
}

/// N'affiche que des nombres : ce fichier est une vraie réunion. Ni le texte ni le chemin ne sortent d'ici.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["APARTE_AUDIO_REFERENCE"] != nil))
func relectureDuFichierDeReference() async throws {
    let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["APARTE_AUDIO_REFERENCE"]))
    let racine = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "Référence", type: .presentiel, dossier: nil)
    try FileManager.default.copyItem(at: source, to: reunion.micro)

    // Le chemin du direct, nourri depuis le fichier : même moteur, mêmes tampons qu'en réunion.
    let locale = try await Parole.preparer()
    let recus = Recus()
    let surFinal: @MainActor @Sendable (Segment) -> Void = { recus.segments.append($0) }
    let surProvisoire: @MainActor @Sendable (Piste, String) -> Void = { _, _ in }
    let transcripteur = try await TranscripteurDirect.demarrer(locale: locale, piste: .micro, surFinal: surFinal, surProvisoire: surProvisoire)
    let entree = SourceFichier()
    let piste = PisteAudio(source: entree, fichier: racine.appendingPathComponent("copie.aac"), formatCible: transcripteur.formatAttendu,
                           surConverti: { transcripteur.alimenter($0) }, surNiveau: { _ in }, surPremierSon: { _ in }, surErreur: { _ in })
    try piste.demarrer()
    let fichier = try AVAudioFile(forReading: source)
    while fichier.framePosition < fichier.length {
        let tampon = try #require(AVAudioPCMBuffer(pcmFormat: fichier.processingFormat, frameCapacity: 4096))
        try fichier.read(into: tampon, frameCount: 4096)
        entree.onBuffer?(tampon)
    }
    piste.arreter()
    await transcripteur.terminer()

    let direct = recus.segments
    let debut = Date()
    let resultat = try await Relecture.relire(reunion, vocabulaire: [], progression: { _ in })
    let voix = Set(resultat.segments.compactMap(\.voix))
    let enDirect = mots(direct), relus = mots(resultat.segments)
    print("relecture: direct \(enDirect.count) mots, \(direct.count) segments ; relu \(relus.count) mots, \(resultat.segments.count) segments ; mots communs \(Set(enDirect).intersection(relus).count) sur \(Set(enDirect).union(relus).count) distincts ; \(voix.count) voix ; \(resultat.voixEchouees == nil ? "voix réussies" : "voix échouées") ; \(Int(Date().timeIntervalSince(debut))) s")
    #expect(!resultat.segments.isEmpty)
}
