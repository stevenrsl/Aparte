import AVFoundation
import Capture
import Foundation
import Stockage
import Testing
@testable import Interface

@MainActor
@Test func panneDeuxReunionsInterrompuesAuMemeLancement() throws {
    let racine = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("aparte-lancement-\(UUID())")
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let bibliotheque = Bibliotheque(racine: racine)
    let reunions = try [
        bibliotheque.creerReunion(titre: "Fictive A", type: .presentiel, dossier: nil),
        bibliotheque.creerReunion(titre: "Fictive B", type: .visio, dossier: bibliotheque.creerDossier("Fictif"))
    ]
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
    let tampon = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
    tampon.frameLength = 48_000
    let canal = try #require(tampon.floatChannelData?[0])
    for i in 0..<48_000 { canal[i] = Float(sin(Double(i) * 2 * .pi * 440 / 48_000)) * 0.1 }
    for reunion in reunions {
        try reunion.enregistrer(notes: [LigneDeNote(temps: 0, texte: "Note inventée intacte")])
        let fichier = try Recording.open(reunion.microEnCours, sampleRate: 48_000)
        try fichier.write(from: tampon)
    }
    // Une piste illisible ne doit pas empêcher la récupération des deux micros.
    try Data().write(to: reunions[1].systemeEnCours)
    let notesAvant = try reunions.map { try Data(contentsOf: $0.url.appendingPathComponent("notes.md")) }
    let metaAvant = try reunions.map { try Data(contentsOf: $0.url.appendingPathComponent("meta.json")) }

    // Obligatoire AVANT init : celui-ci recharge immédiatement la bibliothèque.
    let ancienne = ProcessInfo.processInfo.environment["APARTE_RACINE"]
    setenv("APARTE_RACINE", racine.path, 1)
    defer {
        if let ancienne { setenv("APARTE_RACINE", ancienne, 1) }
        else { unsetenv("APARTE_RACINE") }
    }
    let modele = ModeleApp()
    #expect(modele.reunions.count == 2)
    #expect(Set(modele.reunions.map { $0.meta.titre }) == Set(reunions.map { $0.meta.titre }))
    #expect(modele.reunions.first { $0.meta.titre == "Fictive B" }?.dossier == "Fictif")
    for (i, reunion) in reunions.enumerated() {
        #expect(try #require(Recording.seconds(of: reunion.micro)) > 0.8)
        #expect(!FileManager.default.fileExists(atPath: reunion.microEnCours.path))
        #expect(try Data(contentsOf: reunion.url.appendingPathComponent("notes.md")) == notesAvant[i])
        #expect(try Data(contentsOf: reunion.url.appendingPathComponent("meta.json")) == metaAvant[i])
    }
    #expect(modele.erreur?.contains("Fictive B") == true)
    #expect(try Data(contentsOf: reunions[1].systemeEnCours).isEmpty)
    let audiosAvant = try reunions.map { try Data(contentsOf: $0.micro) }
    modele.erreur = nil
    modele.recharger()
    #expect(modele.erreur == nil) // Pas d'alerte répétée pour la même piste.
    #expect(try reunions.map { try Data(contentsOf: $0.micro) } == audiosAvant)
    // terminerEnregistrement met uniquement nos deux AAC à la corbeille.
    // Ne jamais parcourir ni vider la corbeille de l'utilisateur pour les nettoyer.
}
