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
    let modele = ModeleApp(verifierCle: false, racineInitiale: racine)
    var compteRendu = RendusCompteRendu.exemple(segments)
    compteRendu.empreinte = CompteRendu.empreinte(de: segments)
    try modele.enregistrer(compteRendu, pour: meta)
    // Une autre réunion, avec des citations longues et sans échéance, comme sur une vraie transcription.
    let seconde = try bibliotheque.creerReunion(titre: "Réunion client", type: .presentiel, dossier: nil, date: Date().addingTimeInterval(-86_400 * 3))
    let longues = ["Du coup il faudrait que quelqu'un reprenne le devis parce que les chiffres ont un peu bougé depuis la dernière fois.",
                   "Je regarde avec la production pour voir si on peut décaler le tournage d'une semaine.",
                   "On doit renvoyer les droits musicaux signés.", "Il faut que je rappelle le loueur pour la caméra.",
                   "On garde une journée pour les retours.", "Je t'envoie le lien du montage.", "Il faudra relire le contrat ensemble."]
    let lignes = longues.enumerated().map { Segment(debut: Double($0.offset) * 60, fin: Double($0.offset) * 60 + 30, piste: .micro, texte: $0.element) }
    try seconde.enregistrer(segments: lignes)
    try modele.enregistrer(CompteRendu(fournisseur: "Local", decisions: [], actions: lignes.map { ElementSource(texte: $0.texte, sources: [$0.debut], citation: $0.texte) }, questions: []), pour: seconde)
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
    let relue = try #require(modele.reunions.first { $0.meta.titre == reunion.meta.titre })
    try await rendre("accueil", .accueil)
    try await rendre("accueil-sombre", .accueil, sombre: true)
    try await rendre("toutes", .toutes)
    try await rendre("nouvelle", .nouvelle)
    try await rendre("compte-rendu", .compteRendu(relue))
    try await rendre("compte-rendu-sombre", .compteRendu(relue), sombre: true)
    try await rendre("passage-selectionne", .compteRendu(relue, moment: 80))
    try await rendre("passage-selectionne-sombre", .compteRendu(relue, moment: 80), sombre: true)
    // Une nouvelle vue sans moment présente toute la transcription.
    try await rendre("transcription-complete", .compteRendu(relue))
    let action = try #require(compteRendu.actions.first)
    modele.definirAction(ActionOuverte(reunion: relue, element: action), faite: true)
    try await rendre("action-cochee", .compteRendu(relue))
    modele.erreur = "L’état de l’action n’a pas pu être enregistré : erreur d’écriture simulée."
    try await rendre("erreur-ecriture", .compteRendu(relue))
    modele.erreur = nil
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
    modele.analyser(aAnalyser, avec: AnalysteSuspendu(), signaler: false)
    try await rendre("redaction", .compteRendu(aAnalyser))
    try await rendre("redaction-sombre", .compteRendu(aAnalyser), sombre: true)
    // L'analyse simulée est annulée par son propre délai, sans réseau ni moteur réel.
    while modele.analyses[aAnalyser.id] != nil { try await Task.sleep(for: .milliseconds(20)) }
    modele.analyser(aAnalyser, avec: AnalysteEnPanne(), signaler: false)
    while modele.analyses[aAnalyser.id] != nil { try await Task.sleep(for: .milliseconds(20)) }
    try await rendre("sans-analyse-echec", .compteRendu(aAnalyser))
    try await rendre("sans-phrase", .compteRendu(try #require(modele.reunions.first { $0.meta.titre == "Point muet" })))
    let enCours = try #require(modele.bibliotheque).creerReunion(titre: "Point en cours", type: .visio, dossier: nil)
    modele.session = SessionReunion(reunion: enCours)
    try await rendre("en-reunion", .enReunion)
    try await rendre("accueil-en-reunion", .accueil)
    // Arrêt sans capture, puis échec de renommage simulé pour exposer l'état conservé.
    _ = try await modele.session?.terminer()
    modele.erreur = "Le titre n’a pas pu être enregistré : erreur d’écriture simulée."
    try await rendre("capture-arretee-erreur-renommage", .enReunion)
    modele.erreur = nil
    modele.session = nil
    modele.ecran = .accueil

    // Le compte rendu « Affiche » sur une réunion de 59 minutes, en clair et en sombre.
    func lesDeux(_ nom: String, _ ecran: Ecran) async throws {
        try await rendre("cr-\(nom)", ecran)
        try await rendre("cr-\(nom)-sombre", ecran, sombre: true)
    }
    func reunionDemo(_ titre: String, dossier: String?, compteRendu: (([Segment]) -> CompteRendu)?, garder: Bool = false) throws -> Reunion {
        let r = try bibliotheque.creerReunion(titre: titre, type: .visio, dossier: dossier.map { try bibliotheque.creerDossier($0) })
        let lignes = RendusCompteRendu.phrasesDemo.map { Segment(debut: $0.0, fin: $0.0 + 12, piste: $0.1 == nil ? .micro : .systeme, texte: $0.2, voix: $0.1) }
        try r.enregistrer(segments: lignes)
        try r.enregistrer(notes: RendusCompteRendu.notesDemo.map { LigneDeNote(temps: $0.0, texte: $0.1) })
        var meta = r
        meta.meta.duree = 59 * 60
        meta.meta.nomsDesVoix = ["Voix 1": "Léa Morel", "Voix 2": "Karim Benali", "Voix 3": "Julie Faure"]
        meta.meta.gardeSurCeMac = garder ? true : nil
        try meta.enregistrerMeta()
        if let compteRendu {
            var cr = compteRendu(lignes)
            cr.empreinte = CompteRendu.empreinte(de: lignes)
            try modele.enregistrer(cr, pour: meta)
        }
        return meta
    }
    func relu(_ r: Reunion) throws -> Reunion {
        modele.recharger()
        return try #require(modele.reunions.first { $0.meta.titre == r.meta.titre })
    }
    let demo = try relu(reunionDemo("Captation des Rencontres du vin", dossier: "Rencontres du vin", compteRendu: { RendusCompteRendu.demo($0) }))
    try await lesDeux("mistral", .compteRendu(demo))
    try await lesDeux("citation-ouverte", .compteRendu(demo, moment: 760))
    try await lesDeux("transcription", .compteRendu(demo, moment: 930))
    let local = try relu(reunionDemo("Captation des Rencontres du vin, sur ce Mac", dossier: nil, compteRendu: { RendusCompteRendu.demo($0, fournisseur: "Local · Apple Intelligence") }, garder: true))
    try await lesDeux("sur-ce-mac", .compteRendu(local))
    let long = try relu(reunionDemo("Point de production avec l’agence Lumen sur la captation multicaméra des Rencontres du vin et le teaser", dossier: "Clients",
                                    compteRendu: { RendusCompteRendu.demo($0, beaucoup: true) }))
    try await lesDeux("titre-long-beaucoup-actions", .compteRendu(long))
    let vide = try relu(reunionDemo("Repérage Hangar 14", dossier: nil, compteRendu: { RendusCompteRendu.demo($0, actions: false) }))
    try await lesDeux("aucune-action", .compteRendu(vide))
    // Mistral échoue, le modèle local prend le relais : l'écran le dit.
    let relais = try relu(reunionDemo("Brief musique avec Théo", dossier: nil, compteRendu: nil))
    modele.analyser(relais, avec: AnalysteEnPanne(), relais: AnalysteFixe(compteRendu: RendusCompteRendu.demo(relais.segments(), fournisseur: "Local · Apple Intelligence")), signaler: false)
    while modele.analyses[relais.id] != nil { try await Task.sleep(for: .milliseconds(20)) }
    try await lesDeux("relais-local", .compteRendu(try relu(relais)))
    let attente = try relu(reunionDemo("Point montage, épisode 3", dossier: nil, compteRendu: nil))
    try await lesDeux("pas-encore", .compteRendu(attente))
    modele.analyser(attente, avec: AnalysteSuspendu(), signaler: false)
    try await lesDeux("redaction", .compteRendu(attente))
    while modele.analyses[attente.id] != nil { try await Task.sleep(for: .milliseconds(20)) }
    modele.analyser(attente, avec: AnalysteEnPanne(), signaler: false)
    while modele.analyses[attente.id] != nil { try await Task.sleep(for: .milliseconds(20)) }
    try await lesDeux("echec", .compteRendu(try relu(attente)))
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

extension RendusCompteRendu {
    /// La réunion de démonstration des directions : un tournage d'événement, 59 minutes.
    static let phrasesDemo: [(Double, String?, String)] = [
        (60, "Voix 1", "Bonjour à tous, on fait le point sur la captation des Rencontres du vin."),
        (252, "Voix 3", "Je voudrais quelque chose de vivant, pas de plans figés."),
        (760, "Voix 1", "Bon, on part sur deux caméras. Et Karim, tu prends le drone pour les extérieurs, on en a besoin pour l’arrivée du public."),
        (930, nil, "Pour le drone, il faudra sans doute une autorisation de la mairie."),
        (1102, "Voix 2", "Je réserve le drone et je demande l’autorisation de vol avant vendredi."),
        (1670, "Voix 1", "J’envoie le planning de la journée à l’équipe demain."),
        (1865, "Voix 3", "Le teaser de soixante secondes, on le veut pour le lundi 23 novembre."),
        (2658, "Voix 1", "Pas d’interview pendant la plénière, on les fait dans le salon VIP."),
        (2762, nil, "Je prépare la liste des quatre interviews."),
        (3130, "Voix 3", "Par contre, qui s’occupe de la musique du teaser ?"),
    ]
    static let notesDemo: [(Double, String)] = [
        (252, "Julie veut du « vivant », pas de plans figés"), (930, "drone → autorisation mairie ?"),
        (1860, "teaser 60 s, lundi 23"), (2840, "interviews : salon VIP, 4 personnes max"), (3302, "musique ??"),
    ]

    static func demo(_ s: [Segment], fournisseur: String = "Mistral · Medium", beaucoup: Bool = false, actions: Bool = true) -> CompteRendu {
        func e(_ i: Int, _ texte: String, responsable: String? = nil, echeance: String? = nil) -> ElementSource {
            ElementSource(texte: texte, sources: [s[i].debut], citation: s[i].texte, responsable: responsable, echeance: echeance)
        }
        var liste = [e(4, "Réserver le drone et demander l’autorisation de vol", responsable: "Karim Benali", echeance: "avant vendredi"),
                     e(5, "Envoyer le planning de la journée à l’équipe", responsable: "Léa Morel", echeance: "demain"),
                     e(8, "Préparer la liste des quatre interviews", responsable: "Steven")]
        if beaucoup {
            liste += [e(3, "Vérifier auprès de la mairie si une déclaration suffit pour le vol en ville, ou s’il faut une autorisation préfectorale complète", responsable: "Karim Benali"),
                      e(6, "Monter une première version du teaser", responsable: "Steven", echeance: "lundi 23 novembre"),
                      e(7, "Réserver le salon VIP pour les interviews", responsable: "Julie Faure"),
                      e(9, "Trouver un compositeur pour la musique du teaser"),
                      e(1, "Envoyer des références de plans « vivants »", responsable: "Julie Faure", echeance: "mercredi")]
        }
        return CompteRendu(fournisseur: fournisseur,
                           decisions: [e(2, "On tourne à deux caméras, plus un drone pour les extérieurs."),
                                       e(6, "Le teaser de 60 secondes est livré le lundi 23 novembre."),
                                       e(7, "Pas d’interview pendant la plénière : on les fait dans le salon VIP.")],
                           actions: actions ? liste : [], questions: [e(9, "Qui s’occupe de la musique du teaser ?")],
                           sujets: beaucoup ? [Sujet(titre: "Le dispositif de tournage", debut: 600, fin: 1200), Sujet(titre: "Le teaser", debut: 1800, fin: 2400)] : nil,
                           enBref: [PhraseSourcee(texte: "Le tournage se fait à deux caméras plus un drone. Le teaser de 60 secondes est attendu le 23 novembre.", sources: [s[2].debut, s[6].debut]),
                                    PhraseSourcee(texte: "Il reste à trouver qui s’occupe de la musique.", sources: [s[9].debut])])
    }
}

/// Une analyse qui rend un compte rendu tout prêt, pour simuler le relais local.
private struct AnalysteFixe: Analyste {
    let nom = "Fixe"
    let compteRendu: CompteRendu
    func analyser(segments: [Segment], notes: [LigneDeNote], type: TypeReunion,
                  progression: @escaping @Sendable (Double) -> Void) async throws -> CompteRendu { compteRendu }
}

/// Une analyse qui échoue sur commande, pour rendre la ligne d'échec sans vrai moteur.
private struct AnalysteEnPanne: Analyste {
    let nom = "En panne"

    func analyser(segments: [Segment], notes: [LigneDeNote], type: TypeReunion,
                  progression: @escaping @Sendable (Double) -> Void) async throws -> CompteRendu {
        throw ErreurAnalyse.rienAAnalyser
    }
}

/// Garde l'état de rédaction visible le temps du rendu, sans accès externe.
private struct AnalysteSuspendu: Analyste {
    let nom = "Simulé"
    func analyser(segments: [Segment], notes: [LigneDeNote], type: TypeReunion,
                  progression: @escaping @Sendable (Double) -> Void) async throws -> CompteRendu {
        try await Task.sleep(for: .seconds(3))
        throw ErreurAnalyse.rienAAnalyser
    }
}
