import Foundation
import Stockage
import Testing
import Transcription
@testable import Analyse

private let reunion = [
    Segment(debut: 0, fin: 4, piste: .micro, texte: "Bonjour à tous, merci d'être là."),
    Segment(debut: 5, fin: 9, piste: .micro, texte: "On décide de garder la version longue."),
    Segment(debut: 10, fin: 14, piste: .micro, texte: "Marie envoie la musique avant vendredi."),
]

private final class Serveur: @unchecked Sendable {
    private let verrou = NSLock()
    private var requetes: [URLRequest] = []
    private var reponses: [(Int, String?, String)]
    init(_ reponses: [(Int, String?, String)]) { self.reponses = reponses }
    var recues: [URLRequest] { verrou.withLock { requetes } }
    func repondre(_ requete: URLRequest) -> (Data, HTTPURLResponse?) {
        verrou.withLock {
            requetes.append(requete)
            let (statut, limite, corps) = reponses.count > 1 ? reponses.removeFirst() : reponses[0]
            let http = HTTPURLResponse(url: requete.url!, statusCode: statut, httpVersion: nil,
                                       headerFields: limite.map { ["x-ratelimit-limit-req-minute": $0] })
            return (Data(corps.utf8), http)
        }
    }
}

private func analyste(_ serveur: Serveur) -> AnalysteMistral {
    AnalysteMistral(cle: "cle-de-test", envoi: { serveur.repondre($0) })
}

private func enveloppe(_ json: String) -> String {
    let contenu = String(data: try! JSONEncoder().encode(json), encoding: .utf8)!
    return #"{"choices":[{"message":{"content":\#(contenu)}}]}"#
}

// Ces tests partagent le modèle retenu dans les préférences : ils passent l'un après l'autre.
@Suite(.serialized) struct TestsMistral {
@Test func mistralRedigeEtGardeLaLignePourPreuve() async throws {
    UserDefaults.standard.removeObject(forKey: "modeleMistral")
    let json = #"{"decisions":[{"ligne":2,"texte":"Garder la version longue"},{"ligne":99,"texte":"Ligne inventée"}],"actions":[{"ligne":3,"texte":"Envoyer la musique","responsable":"Marie","echeance":"lundi"}],"questions":[],"points_cles":[{"ligne":2,"texte":"La version longue reste"}],"sujets":[{"titre":"Version longue","premiere":1,"derniere":3,"points":[{"ligne":2,"texte":"La version longue reste"}]}],"en_bref":[{"texte":"La version longue est retenue.","lignes":[2]},{"texte":"Paul finira lundi.","lignes":[3]}]}"#
    let serveur = Serveur([(200, nil, enveloppe(json))])
    let c = try await analyste(serveur).analyser(segments: reunion, notes: [], type: .presentiel, progression: { _ in })
    #expect(c.decisions.map(\.texte) == ["Garder la version longue"])
    #expect(c.decisions.first?.citation == "On décide de garder la version longue.")
    #expect(c.elementsEcartes == 1)
    #expect(c.pointsCles?.first?.citation == "On décide de garder la version longue.")
    #expect(c.sujets?.first?.points?.count == 1)
    #expect(c.actions.first?.responsable == "Marie")
    #expect(c.actions.first?.echeance == nil)
    #expect(c.sujets?.first?.titre == "Version longue")
    #expect(c.fournisseur == "Mistral · Medium")
    #expect(c.enBref?.map(\.texte) == ["La version longue est retenue."])

    let requete = try #require(serveur.recues.first)
    #expect(requete.url?.host == "api.mistral.ai")
    #expect(requete.value(forHTTPHeaderField: "Authorization") == "Bearer cle-de-test")
}

@Test func uneLimiteAZeroPasseAuModeleSuivantEtLaCleRefuseeSArrete() async throws {
    UserDefaults.standard.removeObject(forKey: "modeleMistral")
    let serveur = Serveur([(429, "0", ""), (200, nil, enveloppe(#"```json\#n{"decisions":[{"ligne":2,"texte":"Garder la version longue"}]}\#n```"#))])
    let c = try await analyste(serveur).analyser(segments: reunion, notes: [], type: .presentiel, progression: { _ in })
    #expect(c.fournisseur == "Mistral · Small")
    #expect(c.decisions.count == 1)
    UserDefaults.standard.removeObject(forKey: "modeleMistral")

    let refuse = Serveur([(401, nil, "")])
    await #expect(throws: ErreurMistral.self) {
        _ = try await analyste(refuse).analyser(segments: reunion, notes: [], type: .presentiel, progression: { _ in })
    }
    #expect(refuse.recues.count == 1)
}

@Test func unMessageDErreurDeMistralNEstPasAffiche() async {
    UserDefaults.standard.removeObject(forKey: "modeleMistral")
    let serveur = Serveur([(500, nil, #"{"message":"On décide de garder la version longue."}"#)])
    do {
        _ = try await analyste(serveur).analyser(segments: reunion, notes: [], type: .presentiel, progression: { _ in })
        Issue.record("une erreur était attendue")
    } catch {
        #expect(!error.localizedDescription.contains("version longue"))
    }
}

@Test func leTestDeLaCleNEnvoieAucuneReunion() async throws {
    UserDefaults.standard.removeObject(forKey: "modeleMistral")
    let serveur = Serveur([(200, nil, "{}")])
    #expect(await analyste(serveur).tester().contains("La clé marche"))
    let corps = try #require(serveur.recues.first?.httpBody)
    #expect(!String(decoding: corps, as: UTF8.self).contains("version longue"))
    UserDefaults.standard.removeObject(forKey: "modeleMistral")
}
}

@Test func laCleSeRangeEtSeRetireDuTrousseau() {
    let essai = Trousseau(service: "eu.stevenrsl.aparte.tests", compte: UUID().uuidString)
    #expect(essai.lire() == nil)
    #expect(essai.ecrire(" cle-inventee "))
    #expect(essai.lire() == "cle-inventee")
    #expect(essai.ecrire(nil))
    #expect(essai.lire() == nil)
}
