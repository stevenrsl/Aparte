import Analyse
import Foundation
import Stockage
import Testing
import Transcription
@testable import Interface

/// Une analyse lancée sans clic qui échoue, ou réussit, sur commande : pas de vrai moteur ici.
private struct FausseAnalyste: Analyste {
    let nom = "Faux"
    var echoue: Bool

    func analyser(segments: [Segment], notes: [LigneDeNote], type: TypeReunion,
                  progression: @escaping @Sendable (Double) -> Void) async throws -> CompteRendu {
        if echoue { throw ErreurAnalyse.rienAAnalyser }
        return CompteRendu(fournisseur: nom, decisions: [], actions: [], questions: [], sujets: nil)
    }
}

@MainActor
@Test func uneAnalyseAutoQuiEchoueLeDitSansInterrompre() async throws {
    let racine = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "Fictive", type: .visio, dossier: nil)
    try reunion.enregistrer(segments: [Segment(debut: 0, fin: 1, piste: .micro, texte: "Bonjour")])

    setenv("APARTE_RACINE", racine.path, 1)
    defer { unsetenv("APARTE_RACINE") }
    let modele = ModeleApp()

    modele.analyser(reunion, avec: FausseAnalyste(echoue: true), signaler: false)
    while modele.analyses[reunion.id] != nil { await Task.yield() }

    // Lancée sans clic : aucune fenêtre d'erreur n'interrompt.
    #expect(modele.erreur == nil)
    // Mais l'écran « pas encore d'analyse » n'est plus muet sur ce qui s'est passé.
    #expect(modele.echecsAnalyseAuto[reunion.id]?.contains("transcription à analyser") == true)
    #expect(modele.compteRendu(de: reunion) == nil)

    // Un nouvel essai, réussi cette fois, efface le message et écrit le compte rendu.
    modele.analyser(reunion, avec: FausseAnalyste(echoue: false), signaler: false)
    while modele.analyses[reunion.id] != nil { await Task.yield() }
    #expect(modele.echecsAnalyseAuto[reunion.id] == nil)
    #expect(modele.compteRendu(de: reunion) != nil)
}

@MainActor
@Test func uneAnalyseAutoQuiReussitNeLaisseAucunMessage() async throws {
    let racine = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "Fictive", type: .visio, dossier: nil)
    try reunion.enregistrer(segments: [Segment(debut: 0, fin: 1, piste: .micro, texte: "Bonjour")])

    setenv("APARTE_RACINE", racine.path, 1)
    defer { unsetenv("APARTE_RACINE") }
    let modele = ModeleApp()

    modele.analyser(reunion, avec: FausseAnalyste(echoue: false), signaler: false)
    while modele.analyses[reunion.id] != nil { await Task.yield() }
    #expect(modele.echecsAnalyseAuto[reunion.id] == nil)
    #expect(modele.erreur == nil)
}

@MainActor
@Test func navigationEtRefusAnalysePendantLaReunion() throws {
    let racine = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "Fictive", type: .visio, dossier: nil)
    try reunion.enregistrer(segments: [Segment(debut: 0, fin: 1, piste: .micro, texte: "Bonjour")])
    let modele = ModeleApp()
    modele.session = SessionReunion(reunion: reunion)
    modele.ecran = .dossier("Projet")
    modele.ouvrir(reunion)
    #expect(modele.ecran == .enReunion)
    #expect(modele.dossierCourant == "Projet")
    modele.analyser(reunion, avec: FausseAnalyste(echoue: false))
    #expect(modele.analyses[reunion.id] == nil)
    #expect(modele.compteRendu(de: reunion) == nil)
    modele.revenir()
    #expect(modele.ecran == .dossier("Projet"))
    modele.session = nil
    modele.ouvrir(reunion, moment: 12)
    #expect(modele.ecran == .compteRendu(reunion, moment: 12))
    #expect(modele.libelleRetour == "Projet")
    modele.revenir()
    #expect(modele.ecran == .dossier("Projet"))
}

/// Mistral échoue : le modèle local rédige à sa place, et l'écran peut dire pourquoi.
@MainActor
@Test func siLeRedacteurEchoueLeRelaisRedigeEtLeDit() async throws {
    let racine = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "Fictive", type: .visio, dossier: nil)
    try reunion.enregistrer(segments: [Segment(debut: 0, fin: 1, piste: .micro, texte: "Bonjour")])
    setenv("APARTE_RACINE", racine.path, 1)
    defer { unsetenv("APARTE_RACINE") }
    let modele = ModeleApp()

    modele.analyser(reunion, avec: FausseAnalyste(echoue: true), relais: FausseAnalyste(echoue: false), signaler: false)
    while modele.analyses[reunion.id] != nil { await Task.yield() }
    #expect(modele.compteRendu(de: reunion)?.fournisseur == "Faux")
    #expect(modele.relaisLocal[reunion.id] != nil)
    #expect(modele.echecsAnalyseAuto[reunion.id] == nil)
}

/// « Garder sur ce Mac » se règle sur la réunion ou sur tout son dossier, et s'écrit sur le disque.
@MainActor
@Test func garderSurCeMacSeRegleSurLaReunionOuLeDossier() async throws {
    let racine = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: racine) }
    let bibliotheque = Bibliotheque(racine: racine)
    let client = try bibliotheque.creerDossier("Client sous NDA")
    let dansLeDossier = try bibliotheque.creerReunion(titre: "Point", type: .visio, dossier: client)
    let seule = try bibliotheque.creerReunion(titre: "Appel", type: .visio, dossier: nil)
    setenv("APARTE_RACINE", racine.path, 1)
    defer { unsetenv("APARTE_RACINE") }
    let modele = ModeleApp()

    #expect(!modele.gardeeSurCeMac(dansLeDossier))
    modele.garderSurCeMac(dossier: client, true)
    #expect(modele.gardeeSurCeMac(dansLeDossier))
    #expect(bibliotheque.reglages(dossier: client).gardeSurCeMac == true)
    // Le réglage du dossier ne fait pas de lui une réunion.
    #expect(bibliotheque.dossiers().contains(client))

    #expect(!modele.gardeeSurCeMac(seule))
    modele.garderSurCeMac(seule, true)
    let toutes = bibliotheque.reunions()
    let relue = try #require(toutes.first { $0.meta.titre == "Appel" })
    #expect(relue.meta.gardeSurCeMac == true)
    #expect(modele.gardeeSurCeMac(relue))
}
