import Foundation
import Stockage
import Testing
import Transcription
@testable import Analyse

/// Rédige le compte rendu d'une vraie réunion, pour le relire à la main. Rien n'est écrit dans la réunion.
/// Lancement : APARTE_REUNION=/dossier/de/la/reunion APARTE_SORTIE=/un/fichier.md \
///   [APARTE_REDACTEUR=local|mistral] swift test --filter redigerUneVraieReunion
/// Avec `mistral`, la transcription et les notes partent chez Mistral : à lancer seulement sur une réunion
/// que Steven a choisi d'envoyer.
@Test(.enabled(if: ProcessInfo.processInfo.environment["APARTE_REUNION"] != nil))
func redigerUneVraieReunion() async throws {
    let env = ProcessInfo.processInfo.environment
    let dossier = URL(fileURLWithPath: env["APARTE_REUNION"]!)
    let sortie = URL(fileURLWithPath: env["APARTE_SORTIE"] ?? "/tmp/aparte-mesure.md")
    var segments = try JSONDecoder().decode([Segment].self, from: Data(contentsOf: dossier.appendingPathComponent("transcription.json")))
    let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: dossier.appendingPathComponent("meta.json"))) as? [String: Any] ?? [:]
    let noms = (meta["nomsDesVoix"] as? [String: String] ?? [:]).filter { !$0.value.isEmpty }
    let type = TypeReunion(rawValue: meta["type"] as? String ?? "") ?? .visio
    let notes = (try? String(contentsOf: dossier.appendingPathComponent("notes.md"), encoding: .utf8)).map(FormatNotes.lire) ?? []
    for i in segments.indices { segments[i].voix = segments[i].voix.map { noms[$0] ?? $0 } }

    let analyste: any Analyste
    if env["APARTE_REDACTEUR"] == "mistral" {
        let cle = try #require(Trousseau.mistral.lire(), "Aucune clé Mistral dans le trousseau")
        let brut = URL(fileURLWithPath: sortie.path + ".brut.json")
        analyste = AnalysteMistral(cle: cle, envoi: { requete in
            let (donnees, reponse) = try await URLSession.shared.data(for: requete)
            try? donnees.write(to: brut)
            return (donnees, reponse as? HTTPURLResponse)
        })
    } else {
        analyste = AnalysteLocal()
    }
    let debut = Date()
    let compteRendu = try await analyste.analyser(segments: segments, notes: notes, type: type) { _ in }
    let duree = Date().timeIntervalSince(debut)
    let texte = compteRendu.markdown() + "\n\n---\n\(Int(duree)) s, \(compteRendu.elementsEcartes) éléments écartés\n"
    try texte.write(to: sortie, atomically: true, encoding: .utf8)
}

/// Dit, pour chaque élément d'une réponse brute de Mistral, pourquoi il est gardé, reformulé ou écarté.
/// Lancement : APARTE_REUNION=… APARTE_DIAG=/la/reponse.brut.json swift test --filter diagnostiquerLaValidation
@Test(.enabled(if: ProcessInfo.processInfo.environment["APARTE_DIAG"] != nil))
func diagnostiquerLaValidation() throws {
    let env = ProcessInfo.processInfo.environment
    let dossier = URL(fileURLWithPath: env["APARTE_REUNION"]!)
    var segments = try JSONDecoder().decode([Segment].self, from: Data(contentsOf: dossier.appendingPathComponent("transcription.json")))
    let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: dossier.appendingPathComponent("meta.json"))) as? [String: Any] ?? [:]
    let noms = (meta["nomsDesVoix"] as? [String: String] ?? [:]).filter { !$0.value.isEmpty }
    for i in segments.indices { segments[i].voix = segments[i].voix.map { noms[$0] ?? $0 } }
    let ordonnes = segments.sorted { $0.debut < $1.debut }
    let lignes = AnalysteLocal.lignes(de: ordonnes)
    let notes = (try? String(contentsOf: dossier.appendingPathComponent("notes.md"), encoding: .utf8)).map(FormatNotes.lire) ?? []
    let connus = ValidationSources.connus(segments: ordonnes, notes: notes)
    let completion = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: env["APARTE_DIAG"]!))) as? [String: Any]
    let contenu = ((completion?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
    let reponse = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: env["APARTE_DIAG"]!)).isEmpty ? Data() : Data(contenu.utf8)) as? [String: Any] ?? [:]
    var rapport = ""
    func examiner(_ categorie: String, _ propose: [String: Any]) {
        let ligne = propose["ligne"] as? Int ?? 0
        let texte = propose["texte"] as? String ?? ""
        guard let brut = AnalysteLocal.element(Gabarit.Puce(ligne: ligne, texte: texte), dans: lignes, rayon: AnalysteMistral.rayon) else {
            rapport += "ÉCARTÉ (aucune ligne ne le prouve) [\(categorie)] \(texte)\n    ligne \(ligne) : \(lignes.indices.contains(ligne - 1) ? lignes[ligne - 1].phrase : "?")\n"
            return
        }
        guard let valide = ValidationSources.valider(brut, dans: ordonnes, connus: connus, citationSiRefus: false) else {
            let lu = Set(ValidationSources.normaliser(connus).split(separator: " ").map(String.init))
            rapport += "ÉCARTÉ (validation) [\(categorie)] \(texte)\n    non dits : \(EnBref.motsNonDits(texte, lu: lu))\n"
            return
        }
        if valide.texte == texte.trimmingCharacters(in: .whitespacesAndNewlines) {
            rapport += "GARDÉ [\(categorie)] \(texte)\n"
        } else {
            let lu = Set(ValidationSources.normaliser(valide.citation ?? "").split(separator: " ").map(String.init))
            rapport += "CITATION À LA PLACE [\(categorie)] \(texte)\n    mots non dits près de la ligne (approx.) : \(EnBref.motsNonDits(texte, lu: lu))\n"
        }
    }
    for categorie in ["points_cles", "decisions", "actions", "questions"] {
        for propose in reponse[categorie] as? [[String: Any]] ?? [] { examiner(categorie, propose) }
    }
    for sujet in reponse["sujets"] as? [[String: Any]] ?? [] {
        for point in sujet["points"] as? [[String: Any]] ?? [] { examiner("sujet " + (sujet["titre"] as? String ?? ""), point) }
    }
    try rapport.write(to: URL(fileURLWithPath: env["APARTE_DIAG"]! + ".diag.txt"), atomically: true, encoding: .utf8)
}
