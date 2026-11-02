import Foundation
import Stockage
import Testing
import Transcription

private func racineTemporaire() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
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
