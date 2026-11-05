import Foundation
import Stockage
import Testing
import Transcription

private func racineTemporaire() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// `copyItem` garde le verrou d'immuabilité sur sa copie : sans ce déverrouillage récursif avant
/// `removeItem`, une archive copiée depuis un fichier verrouillé resterait sur le disque.
private func deverrouille(_ racine: URL) {
    guard let enumerateur = FileManager.default.enumerator(at: racine, includingPropertiesForKeys: nil) else { return }
    for element in enumerateur {
        guard let url = element as? URL else { continue }
        try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: url.path)
    }
    try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: racine.path)
}

@Test func uneReunionSeRelitDepuisSonDossier() throws {
    let racine = try racineTemporaire()
    defer { try? FileManager.default.removeItem(at: racine) }
    let biblio = Bibliotheque(racine: racine)
    let dossier = try biblio.creerDossier("Documentaire voile")
    let reunion = try biblio.creerReunion(titre: "Point: client", type: .visio, dossier: dossier)
    try reunion.enregistrer(segments: [Segment(debut: 1, fin: 2, piste: .micro, texte: "Bonjour")])
    try reunion.enregistrer(notes: [LigneDeNote(temps: 252, texte: "Musique avant vendredi")])

    let relue = try #require(biblio.reunions().first)
    #expect(relue.dossier == "Documentaire voile")
    #expect(relue.meta.titre == "Point: client")
    #expect(relue.segments().first?.texte == "Bonjour")
    #expect(relue.notes().first?.temps == 252)
    #expect(relue.notes().first?.texte == "Musique avant vendredi")
    #expect(biblio.dossiers() == ["Documentaire voile"])
}

@Test func lesNotesGardentLeurTexteExact() {
    let texte = "`04:12` Une note, avec `du code` et : deux points\n`1:02:03` Une autre\n"
    let lues = FormatNotes.lire(texte)
    #expect(FormatNotes.ecrire(lues) == texte)
}

@Test func uneNouvelleAnalyseGardeLaPrecedente() throws {
    let racine = try racineTemporaire()
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "R", type: .presentiel, dossier: nil)
    try reunion.enregistrer(analyseJSON: Data("{}".utf8), markdown: "un")
    try reunion.enregistrer(analyseJSON: Data("{}".utf8), markdown: "deux")
    let archives = try FileManager.default.contentsOfDirectory(atPath: reunion.url.appendingPathComponent("analyses").path)
    #expect(archives.count == 2)
}

/// Plusieurs analyses dans la même seconde ne doivent pas échouer sur un nom d'archive déjà pris :
/// `enregistrer` cherche un nom libre pour la paire .json/.md, avec un suffixe -2, -3…
@Test func plusieursAnalysesDansLaMemeSecondeGardentChacuneSonArchive() throws {
    let racine = try racineTemporaire()
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "R", type: .presentiel, dossier: nil)
    try reunion.enregistrer(analyseJSON: Data("{}".utf8), markdown: "un")
    try reunion.enregistrer(analyseJSON: Data("{}".utf8), markdown: "deux")
    try reunion.enregistrer(analyseJSON: Data("{}".utf8), markdown: "trois")
    let dossierArchives = reunion.url.appendingPathComponent("analyses")
    let archives = try FileManager.default.contentsOfDirectory(atPath: dossierArchives.path)
    #expect(archives.filter { $0.hasSuffix(".json") }.count == 2)
    #expect(archives.filter { $0.hasSuffix(".md") }.count == 2)
    #expect(Set(archives).count == archives.count)
}

/// Si l'archivage échoue, le compte rendu actuel reste lisible à sa place et rien de neuf n'est annoncé.
@Test func unArchivageImpossibleLaisseLeCompteRenduActuelEnPlace() throws {
    let racine = try racineTemporaire()
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "Archives", type: .presentiel, dossier: nil)
    try reunion.enregistrer(analyseJSON: Data("ancien".utf8), markdown: "ancien")
    let gestionnaire = FileManager.default
    let archives = reunion.url.appendingPathComponent("analyses")
    try gestionnaire.createDirectory(at: archives, withIntermediateDirectories: true)
    try gestionnaire.setAttributes([.posixPermissions: 0o500], ofItemAtPath: archives.path)
    defer { try? gestionnaire.setAttributes([.posixPermissions: 0o700], ofItemAtPath: archives.path) }

    #expect(throws: (any Error).self) { try reunion.enregistrer(analyseJSON: Data("nouveau".utf8), markdown: "nouveau") }

    #expect(reunion.analyseJSON() == Data("ancien".utf8))
    #expect(try String(contentsOf: reunion.url.appendingPathComponent("analyse.md"), encoding: .utf8) == "ancien")
}

/// Le scénario de la relecture : l'ancien Markdown ne peut pas être remplacé. Le JSON reste l'ancien,
/// et rien ne peut faire disparaître analyse.json de la racine.
@Test func unMarkdownImpossibleARemplacerNeFaitPasDisparaitreLeJSON() throws {
    let racine = try racineTemporaire()
    defer { deverrouille(racine); try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "Archives", type: .presentiel, dossier: nil)
    try reunion.enregistrer(analyseJSON: Data("ancien".utf8), markdown: "ancien")
    let gestionnaire = FileManager.default
    let lisible = reunion.url.appendingPathComponent("analyse.md")
    try gestionnaire.setAttributes([.immutable: true], ofItemAtPath: lisible.path)
    defer { try? gestionnaire.setAttributes([.immutable: false], ofItemAtPath: lisible.path) }

    #expect(throws: (any Error).self) { try reunion.enregistrer(analyseJSON: Data("nouveau".utf8), markdown: "nouveau") }

    #expect(reunion.analyseJSON() == Data("ancien".utf8))
    #expect(try String(contentsOf: lisible, encoding: .utf8) == "ancien")
}

/// Un archivage réussi garde bien l'ancien contenu aux archives et le nouveau à la racine.
@Test func unArchivageReussiGardeLAncienContenu() throws {
    let racine = try racineTemporaire()
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "Archives", type: .presentiel, dossier: nil)
    try reunion.enregistrer(analyseJSON: Data("ancien".utf8), markdown: "ancien md")
    try reunion.enregistrer(analyseJSON: Data("nouveau".utf8), markdown: "nouveau md")

    let archives = reunion.url.appendingPathComponent("analyses")
    let fichiers = try FileManager.default.contentsOfDirectory(at: archives, includingPropertiesForKeys: nil)
    let json = try #require(fichiers.first { $0.pathExtension == "json" })
    let md = try #require(fichiers.first { $0.pathExtension == "md" })
    #expect(try Data(contentsOf: json) == Data("ancien".utf8))
    #expect(try String(contentsOf: md, encoding: .utf8) == "ancien md")
    #expect(reunion.analyseJSON() == Data("nouveau".utf8))
    #expect(try String(contentsOf: reunion.url.appendingPathComponent("analyse.md"), encoding: .utf8) == "nouveau md")
}

/// Un nom d'archive n'est libre que si .json ET .md le sont. Sinon un `.md` isolé sous ce nom
/// bloquerait la copie du Markdown d'archive juste après celle du JSON, qui aurait déjà réussi :
/// l'enregistrement échouerait sans écrire le nouveau compte rendu, alors que l'ancien reste intact.
/// On prédit le nom de la seconde courante comme `enregistrer`, pour ne pas dépendre de l'horloge au-delà.
@Test func unMarkdownDArchiveIsoleNEmpecheNiNeDupliqueLaProchaineArchive() throws {
    let racine = try racineTemporaire()
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "R", type: .presentiel, dossier: nil)
    try reunion.enregistrer(analyseJSON: Data("{}".utf8), markdown: "un")

    let archives = reunion.url.appendingPathComponent("analyses")
    try FileManager.default.createDirectory(at: archives, withIntermediateDirectories: true)
    let base = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    try "orphelin".write(to: archives.appendingPathComponent("\(base).md"), atomically: true, encoding: .utf8)

    try reunion.enregistrer(analyseJSON: Data("{}".utf8), markdown: "deux")
    try reunion.enregistrer(analyseJSON: Data("{}".utf8), markdown: "trois")

    // Le nouveau compte rendu est bien écrit à la racine, jamais bloqué par l'archive isolée.
    #expect(try #require(String(data: reunion.analyseJSON() ?? Data(), encoding: .utf8)) == "{}")
    let fichiers = try FileManager.default.contentsOfDirectory(atPath: archives.path)
    #expect(fichiers.filter { $0.hasSuffix(".json") }.count == 2)
    #expect(fichiers.filter { $0.hasSuffix(".md") }.count == 3)
    #expect(Set(fichiers).count == fichiers.count)
    // L'archive isolée n'a jamais été écrasée : son nom n'a jamais pu être réutilisé.
    #expect(try String(contentsOf: archives.appendingPathComponent("\(base).md"), encoding: .utf8) == "orphelin")
}

@Test func uneAncienneReunionSansDecalageSeRelit() throws {
    let racine = try racineTemporaire()
    defer { try? FileManager.default.removeItem(at: racine) }
    let dossier = racine.appendingPathComponent("2026-11-02 Ancienne")
    try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    let ancienne = #"{"titre":"Ancienne","date":"2026-11-02T13:08:00Z","duree":10,"type":"visio","participants":[],"fournisseurs":[]}"#
    try Data(ancienne.utf8).write(to: dossier.appendingPathComponent("meta.json"))
    let relue = try #require(Bibliotheque(racine: racine).reunions().first)
    #expect(relue.decalage(.systeme) == 0)
}

@Test func leDecalageDUnePisteSeRelit() throws {
    let racine = try racineTemporaire()
    defer { try? FileManager.default.removeItem(at: racine) }
    let biblio = Bibliotheque(racine: racine)
    var reunion = try biblio.creerReunion(titre: "R", type: .visio, dossier: nil)
    reunion.meta.decalages = ["systeme": 1.7]
    try reunion.enregistrerMeta()
    #expect(try #require(biblio.reunions().first).decalage(.systeme) == 1.7)
}

@Test func lireAvantLeDebutDUnePisteAttendSonDepart() {
    #expect(positionDeLecture(temps: 10, decalage: 1.5) == (8.5, 0))
    #expect(positionDeLecture(temps: 1, decalage: 1.5) == (0, 0.5))
}

private func bibliothequeDeGestion() throws -> (Bibliotheque, URL) {
    let racine = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
    return (Bibliotheque(racine: racine), racine)
}

@Test func renommerGardeLeContenuIntact() throws {
    let (bibliotheque, racine) = try bibliothequeDeGestion()
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try bibliotheque.creerReunion(titre: "Avant", type: .presentiel, dossier: nil)
    try reunion.enregistrer(notes: [LigneDeNote(temps: 3, texte: "Une note précieuse")])
    try Data("son".utf8).write(to: reunion.micro)
    let notesAvant = try Data(contentsOf: reunion.url.appendingPathComponent("notes.md"))

    let renommee = try bibliotheque.renommer(reunion, en: "Après : bilan")
    #expect(!FileManager.default.fileExists(atPath: reunion.url.path))
    #expect(renommee.url.lastPathComponent.hasSuffix("Après   bilan"))
    #expect(try Data(contentsOf: renommee.url.appendingPathComponent("notes.md")) == notesAvant)
    #expect(try Data(contentsOf: renommee.micro) == Data("son".utf8))
    #expect(bibliotheque.reunions().map(\.meta.titre) == ["Après : bilan"])
}

@Test func renommerSansChangerNeDeplaceRien() throws {
    let (bibliotheque, racine) = try bibliothequeDeGestion()
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try bibliotheque.creerReunion(titre: "Même", type: .presentiel, dossier: nil)
    #expect(try bibliotheque.renommer(reunion, en: " Même ").url == reunion.url)
    #expect(try bibliotheque.renommer(reunion, en: "   ").url == reunion.url)
}

@Test func renommerNEcrasePasUneAutreReunion() throws {
    let (bibliotheque, racine) = try bibliothequeDeGestion()
    defer { try? FileManager.default.removeItem(at: racine) }
    let date = Date()
    let a = try bibliotheque.creerReunion(titre: "A", type: .presentiel, dossier: nil, date: date)
    let b = try bibliotheque.creerReunion(titre: "B", type: .presentiel, dossier: nil, date: date)
    let renommee = try bibliotheque.renommer(b, en: "A")
    #expect(renommee.url != a.url)
    #expect(bibliotheque.reunions().count == 2)
}

@Test func deplacerVersEtDepuisUnDossier() throws {
    let (bibliotheque, racine) = try bibliothequeDeGestion()
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try bibliotheque.creerReunion(titre: "R", type: .presentiel, dossier: nil)
    let rangee = try bibliotheque.deplacer(reunion, vers: "Clients")
    #expect(bibliotheque.reunions().first?.dossier == "Clients")
    let revenue = try bibliotheque.deplacer(rangee, vers: nil)
    #expect(revenue.url.lastPathComponent == reunion.url.lastPathComponent)
    #expect(bibliotheque.reunions().first?.dossier == nil)
}

@Test func laCorbeilleRetireLaReunionDeLaBibliotheque() throws {
    let (bibliotheque, racine) = try bibliothequeDeGestion()
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try bibliotheque.creerReunion(titre: "Fictive à jeter", type: .presentiel, dossier: nil)
    try bibliotheque.mettreALaCorbeille(reunion)
    #expect(bibliotheque.reunions().isEmpty)
}

@Test func laSignatureDUneAnalyseChangeAvecSonAnalyseEtSaTranscription() throws {
    let racine = try racineTemporaire()
    defer { try? FileManager.default.removeItem(at: racine) }
    let reunion = try Bibliotheque(racine: racine).creerReunion(titre: "R", type: .visio, dossier: nil)
    try reunion.enregistrer(segments: [Segment(debut: 1, fin: 2, piste: .micro, texte: "Bonjour")])
    #expect(reunion.signatureAnalyse() == nil)

    try reunion.enregistrer(analyseJSON: Data("{}".utf8), markdown: "")
    let signature = try #require(reunion.signatureAnalyse())
    #expect(reunion.signatureAnalyse() == signature)

    // Même taille : seule la date peut trahir la réécriture.
    try reunion.enregistrer(segments: [Segment(debut: 1, fin: 2, piste: .micro, texte: "Bonsoir")])
    let apresRelecture = try #require(reunion.signatureAnalyse())
    #expect(apresRelecture != signature)

    try reunion.enregistrer(analyseJSON: Data("{}".utf8), markdown: "")
    #expect(reunion.signatureAnalyse() != apresRelecture)
}
