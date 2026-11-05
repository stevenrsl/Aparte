import AppKit
import Analyse
import Foundation
import Stockage
import SwiftUI
import Testing
import Transcription
@testable import Interface

/// Rend les vrais écrans en images, sur une réunion inventée, pour les regarder sans lancer l'app.
/// Lancement : APARTE_RENDUS=/un/dossier swift test --filter rendreLesEcrans
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["APARTE_RENDUS"] != nil))
func rendreLesEcrans() async throws {
    let sortie = URL(fileURLWithPath: ProcessInfo.processInfo.environment["APARTE_RENDUS"]!)
    let racine = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let bibliotheque = Bibliotheque(racine: racine)
    let reunion = try bibliotheque.creerReunion(titre: "Point festival", type: .visio, dossier: bibliotheque.creerDossier("Documentaire voile"))
    let phrases: [(Piste, String?, String)] = [
        (.systeme, "Voix 1", "Bonjour à tous, on commence par le festival."), (.micro, nil, "Oui, on a deux versions du film."),
        (.systeme, "Voix 2", "On décide de garder la version longue pour le festival."), (.micro, nil, "Marie envoie la musique à Paul avant vendredi."),
        (.systeme, "Voix 1", "Est-ce qu'on sait qui prend les photos de plateau ?"), (.micro, nil, "Non, personne ne s'est proposé."),
    ]
    // Une ligne marquée (ici le « non » du micro) doit apparaître dans le rendu : c'est ce que ce
    // test d'écran vérifie, sans lancer l'app.
    let segments = phrases.enumerated().map {
        Segment(debut: Double($0.offset) * 40, fin: Double($0.offset) * 40 + 30, piste: $0.element.0, texte: $0.element.2,
                voix: $0.element.1, echoProbable: $0.offset == 5 ? true : nil)
    }
    try reunion.enregistrer(segments: segments)
    try reunion.enregistrer(notes: [LigneDeNote(temps: 85, texte: "Vérifier la musique avec Paul")])
    var meta = reunion
    meta.meta.duree = 600
    meta.meta.nomsDesVoix = ["Voix 1": "Claire"]
    try meta.enregistrerMeta()
    setenv("APARTE_RACINE", racine.path, 1)
    defer { unsetenv("APARTE_RACINE") }
    let modele = ModeleApp()
    var compteRendu = RendusCompteRendu.exemple(segments)
    compteRendu.empreinte = CompteRendu.empreinte(de: segments)
    try modele.enregistrer(compteRendu, pour: meta)
    modele.recharger()

    func rendre(_ nom: String, _ ecran: Ecran, sombre: Bool = false) async throws {
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
        try #require(image.representation(using: .png, properties: [:])).write(to: sortie.appendingPathComponent("\(nom).png"))
    }
    let relue = try #require(modele.reunions.first)
    try await rendre("accueil", .accueil)
    try await rendre("nouvelle", .nouvelle)
    try await rendre("compte-rendu", .compteRendu(relue))
    try await rendre("compte-rendu-sombre", .compteRendu(relue), sombre: true)
    try await rendre("dossier", .dossier("Documentaire voile"))
    try await rendre("reglages", .reglages)

    // Les états qu'on ne voit qu'en cas de pépin : analyse périmée, pas d'analyse, analyse automatique en échec.
    var changes = segments
    changes[1].texte = "Oui, on a trois versions du film."
    try relue.enregistrer(segments: changes)
    modele.recharger()
    let perimee = try #require(modele.reunions.first { $0.id == relue.id })
    try await rendre("compte-rendu-perimee", .compteRendu(perimee))
    try await rendre("compte-rendu-perimee-sombre", .compteRendu(perimee), sombre: true)

    let sansAnalyse = try bibliotheque.creerReunion(titre: "Point sans analyse", type: .visio, dossier: nil)
    try sansAnalyse.enregistrer(segments: segments)
    _ = try bibliotheque.creerReunion(titre: "Point muet", type: .presentiel, dossier: nil)
    modele.recharger()
    let aAnalyser = try #require(modele.reunions.first { $0.meta.titre == "Point sans analyse" })
    try await rendre("sans-analyse", .compteRendu(aAnalyser))
    modele.analyser(aAnalyser, avec: AnalysteEnPanne(), signaler: false)
    while modele.analyses[aAnalyser.id] != nil { try await Task.sleep(for: .milliseconds(20)) }
    try await rendre("sans-analyse-echec", .compteRendu(aAnalyser))
    try await rendre("sans-phrase", .compteRendu(try #require(modele.reunions.first { $0.meta.titre == "Point muet" })))
    modele.ecran = .accueil
}

enum RendusCompteRendu {
    static func exemple(_ segments: [Segment]) -> CompteRendu {
        func element(_ i: Int, responsable: String? = nil, echeance: String? = nil) -> ElementSource {
            ElementSource(texte: segments[i].texte, sources: [segments[i].debut], citation: segments[i].texte, responsable: responsable, echeance: echeance)
        }
        return CompteRendu(fournisseur: "Mistral · Medium", decisions: [element(2)], actions: [element(3, responsable: "Marie", echeance: "vendredi")], questions: [element(4)],
                           sujets: [Sujet(titre: "version longue", debut: 0, fin: 80), Sujet(titre: "photos de plateau", debut: 80, fin: 240)],
                           enBref: [PhraseSourcee(texte: "L'équipe garde la version longue pour le festival.", sources: [segments[2].debut]),
                                    PhraseSourcee(texte: "Marie envoie la musique à Paul avant vendredi, et les photos de plateau restent à attribuer.", sources: [segments[3].debut, segments[4].debut])])
    }
}

/// Une analyse qui échoue sur commande, pour rendre la ligne d'échec sans vrai moteur.
private struct AnalysteEnPanne: Analyste {
    let nom = "En panne"

    func analyser(segments: [Segment], notes: [LigneDeNote], type: TypeReunion,
                  progression: @escaping @Sendable (Double) -> Void) async throws -> CompteRendu {
        throw ErreurAnalyse.rienAAnalyser
    }
}
