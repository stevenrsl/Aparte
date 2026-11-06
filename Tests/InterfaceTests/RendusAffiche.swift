import AppKit
import Analyse
import Foundation
import Stockage
import SwiftUI
import Testing
import Transcription
@testable import Interface

/// Rend tous les écrans « Affiche » et leurs états, en clair et en sombre, sur des réunions inventées.
/// Lancement : APARTE_RENDUS=/un/dossier swift test --filter rendreLAffiche
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["APARTE_RENDUS"] != nil))
func rendreLAffiche() async throws {
    let sortie = URL(fileURLWithPath: ProcessInfo.processInfo.environment["APARTE_RENDUS"]!)
    let racine = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let bibliotheque = Bibliotheque(racine: racine)
    let modele = ModeleApp(verifierCle: false, racineInitiale: racine)

    func rendre(_ nom: String, _ ecran: Ecran) async throws {
        for sombre in [false, true] {
            modele.ecran = ecran
            let fenetre = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 1280, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
            fenetre.appearance = NSAppearance(named: sombre ? .darkAqua : .aqua)
            let hote = NSHostingView(rootView: FenetreAparte(modele: modele).frame(width: 1280, height: 800))
            hote.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
            fenetre.contentView = hote
            fenetre.orderFrontRegardless()
            for _ in 0..<6 {
                try await Task.sleep(for: .milliseconds(150))
                hote.layoutSubtreeIfNeeded()
            }
            let image = try #require(hote.bitmapImageRepForCachingDisplay(in: hote.bounds))
            hote.cacheDisplay(in: hote.bounds, to: image)
            fenetre.orderOut(nil)
            try #require(image.representation(using: .png, properties: [:])).write(to: sortie.appendingPathComponent("\(nom)\(sombre ? "-sombre" : "").png"))
        }
    }

    // Vide : aucune réunion.
    try await rendre("accueil-vide", .accueil)
    try await rendre("toutes-vide", .toutes)

    let jour = 86_400.0
    @discardableResult
    func reunion(_ titre: String, dossier: String?, ilYa jours: Double, compteRendu: (([Segment]) -> CompteRendu)?) throws -> Reunion {
        let r = try bibliotheque.creerReunion(titre: titre, type: .visio, dossier: dossier.map { try bibliotheque.creerDossier($0) },
                                              date: Date().addingTimeInterval(-jours * jour))
        let lignes = RendusCompteRendu.phrasesDemo.map { Segment(debut: $0.0, fin: $0.0 + 12, piste: $0.1 == nil ? .micro : .systeme, texte: $0.2, voix: $0.1) }
        try r.enregistrer(segments: lignes)
        try r.enregistrer(notes: RendusCompteRendu.notesDemo.map { LigneDeNote(temps: $0.0, texte: $0.1) })
        var meta = r
        meta.meta.duree = 59 * 60
        meta.meta.nomsDesVoix = ["Voix 1": "Léa Morel", "Voix 2": "Karim Benali", "Voix 3": "Julie Faure"]
        try meta.enregistrerMeta()
        if let compteRendu {
            var cr = compteRendu(lignes)
            cr.empreinte = CompteRendu.empreinte(de: lignes)
            try modele.enregistrer(cr, pour: meta)
        }
        return meta
    }
    try reunion("Captation des Rencontres du vin", dossier: "Rencontres du vin", ilYa: 2, compteRendu: { RendusCompteRendu.demo($0) })
    try reunion("Point montage, épisode 3", dossier: "Documentaire voile", ilYa: 3, compteRendu: { RendusCompteRendu.demo($0, beaucoup: true) })
    try reunion("Appel devis, agence Lumen", dossier: "Clients", ilYa: 4, compteRendu: { RendusCompteRendu.demo($0, fournisseur: "Local · Apple Intelligence") })
    try reunion("Repérage Hangar 14", dossier: "Rencontres du vin", ilYa: 7, compteRendu: { RendusCompteRendu.demo($0, actions: false) })
    let brief = try reunion("Brief musique avec Théo", dossier: nil, ilYa: 8, compteRendu: nil)
    _ = try bibliotheque.creerDossier("Archives 2025")
    modele.recharger()
    modele.garderSurCeMac(dossier: "Clients", true)

    try await rendre("accueil", .accueil)
    try await rendre("toutes", .toutes)
    try await rendre("dossier", .dossier("Rencontres du vin"))
    try await rendre("dossier-garde", .dossier("Clients"))
    try await rendre("dossier-vide", .dossier("Archives 2025"))

    // Un compte rendu en préparation se voit dans le sommaire.
    let enAttente = try #require(modele.reunions.first { $0.meta.titre == brief.meta.titre })
    modele.analyser(enAttente, avec: AnalyseLente(), signaler: false)
    try await rendre("accueil-preparation", .accueil)
    while modele.analyses[enAttente.id] != nil { try await Task.sleep(for: .milliseconds(20)) }

    // En réunion : la frise se remplit, les notes prennent leur heure, la transcription arrive.
    let enCours = try bibliotheque.creerReunion(titre: "Point tournage, jour J", type: .visio, dossier: "Rencontres du vin")
    let session = SessionReunion(reunion: enCours)
    session.simulerDebut(Date().addingTimeInterval(-(23 * 60 + 41)))
    session.lignes = [LigneDeNote(temps: 252, texte: "Julie veut du « vivant », pas de plans figés"),
                      LigneDeNote(temps: 930, texte: "drone → autorisation mairie ?"),
                      LigneDeNote(temps: 1308, texte: "Karim : 2 FX6 + Mavic 3, il a les batteries"),
                      LigneDeNote(temps: 1421, texte: "")]
    for phrase in RendusCompteRendu.phrasesDemo.prefix(5) {
        session.ajouter(Segment(debut: phrase.0, fin: phrase.0 + 12, piste: phrase.1 == nil ? .micro : .systeme, texte: phrase.2))
    }
    modele.session = session
    try await rendre("en-reunion", .enReunion)
    session.signalerAudio("micro")
    try await rendre("en-reunion-alerte", .enReunion)
    let gardee = try bibliotheque.creerReunion(titre: "Négociation du devis", type: .presentiel, dossier: "Clients")
    let sessionGardee = SessionReunion(reunion: gardee)
    sessionGardee.simulerDebut(Date().addingTimeInterval(-(8 * 60 + 5)))
    modele.session = sessionGardee
    try await rendre("en-reunion-dossier-garde", .enReunion)
    modele.session = nil

    try await rendre("nouvelle", .nouvelle)
    try await rendre("reglages", .reglages)
    modele.ecran = .accueil
}

/// Une rédaction qui prend son temps, pour voir l'état « en préparation », puis échoue sans bruit.
private struct AnalyseLente: Analyste {
    let nom = "Lente"
    func analyser(segments: [Segment], notes: [LigneDeNote], type: TypeReunion,
                  progression: @escaping @Sendable (Double) -> Void) async throws -> CompteRendu {
        progression(0.4)
        try await Task.sleep(for: .seconds(4))
        throw ErreurAnalyse.rienAAnalyser
    }
}

/// La préparation du compte rendu à 10, 60 et 95 %, et l'alerte micro faible en réunion.
/// Lancement : APARTE_RENDUS=/un/dossier swift test --filter rendreLaPreparation
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["APARTE_RENDUS"] != nil))
func rendreLaPreparation() async throws {
    let sortie = URL(fileURLWithPath: ProcessInfo.processInfo.environment["APARTE_RENDUS"]!)
    let racine = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let bibliotheque = Bibliotheque(racine: racine)
    let modele = ModeleApp(verifierCle: false, racineInitiale: racine)

    func rendre(_ nom: String, _ ecran: Ecran) async throws {
        for sombre in [false, true] {
            modele.ecran = ecran
            let fenetre = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 1280, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
            fenetre.appearance = NSAppearance(named: sombre ? .darkAqua : .aqua)
            let hote = NSHostingView(rootView: FenetreAparte(modele: modele).frame(width: 1280, height: 800))
            hote.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
            fenetre.contentView = hote
            fenetre.orderFrontRegardless()
            for _ in 0..<6 {
                try await Task.sleep(for: .milliseconds(150))
                hote.layoutSubtreeIfNeeded()
            }
            let image = try #require(hote.bitmapImageRepForCachingDisplay(in: hote.bounds))
            hote.cacheDisplay(in: hote.bounds, to: image)
            fenetre.orderOut(nil)
            try #require(image.representation(using: .png, properties: [:])).write(to: sortie.appendingPathComponent("\(nom)\(sombre ? "-sombre" : "").png"))
        }
    }

    let r = try bibliotheque.creerReunion(titre: "Captation des Rencontres du vin", type: .visio, dossier: try bibliotheque.creerDossier("Rencontres du vin"))
    let lignes = RendusCompteRendu.phrasesDemo.map { Segment(debut: $0.0, fin: $0.0 + 12, piste: $0.1 == nil ? .micro : .systeme, texte: $0.2, voix: $0.1) }
    try r.enregistrer(segments: lignes)
    try r.enregistrer(notes: RendusCompteRendu.notesDemo.map { LigneDeNote(temps: $0.0, texte: $0.1) })
    var meta = r
    meta.meta.duree = 59 * 60
    try meta.enregistrerMeta()
    modele.recharger()
    let reunion = try #require(modele.reunions.first)
    modele.simulerPreparation(reunion, relecture: 0.1)
    try await rendre("preparation-10", .compteRendu(reunion))
    modele.simulerPreparation(reunion, relecture: 0.6)
    try await rendre("preparation-60", .compteRendu(reunion))
    modele.simulerPreparation(reunion, redaction: 0.95)
    try await rendre("preparation-95", .compteRendu(reunion))
    modele.simulerPreparation(reunion)

    let enCours = try bibliotheque.creerReunion(titre: "Point tournage, jour J", type: .presentiel, dossier: nil)
    let session = SessionReunion(reunion: enCours)
    session.simulerDebut(Date().addingTimeInterval(-(4 * 60 + 12)), entree: "AirPods Pro de Steven", microFaible: true)
    session.lignes = [LigneDeNote(temps: 95, texte: "on commence par le planning"), LigneDeNote(temps: 252, texte: "")]
    modele.session = session
    try await rendre("en-reunion-micro-faible", .enReunion)
    let normale = SessionReunion(reunion: enCours)
    normale.simulerDebut(Date().addingTimeInterval(-(4 * 60 + 12)), entree: "MacBook Pro Microphone")
    modele.session = normale
    try await rendre("en-reunion-entree", .enReunion)
    modele.session = nil
    modele.ecran = .accueil
}
