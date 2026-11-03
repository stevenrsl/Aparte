import Analyse
import Foundation
import Testing
import Transcription

@Test func empreinteIgnoreLeDecoupageAMemeContenu() {
    let unSegment = [Segment(debut: 0, fin: 20, piste: .micro, texte: "On garde la version longue pour le festival.")]
    let deuxSegments = [
        Segment(debut: 0, fin: 10, piste: .micro, texte: "On garde la version longue"),
        Segment(debut: 10, fin: 20, piste: .micro, texte: "pour le festival."),
    ]
    #expect(CompteRendu.empreinte(de: unSegment) == CompteRendu.empreinte(de: deuxSegments))
}

@Test func empreinteChangeAvecUnMotUneVoixOuUneMarqueDEcho() {
    let base = [Segment(debut: 0, fin: 5, piste: .micro, texte: "On garde la version longue.", voix: "Voix 1", echoProbable: false)]
    let reference = CompteRendu.empreinte(de: base)

    let motDifferent = [Segment(debut: 0, fin: 5, piste: .micro, texte: "On garde la version courte.", voix: "Voix 1", echoProbable: false)]
    #expect(CompteRendu.empreinte(de: motDifferent) != reference)

    let voixDifferente = [Segment(debut: 0, fin: 5, piste: .micro, texte: "On garde la version longue.", voix: "Voix 2", echoProbable: false)]
    #expect(CompteRendu.empreinte(de: voixDifferente) != reference)

    let echoDifferent = [Segment(debut: 0, fin: 5, piste: .micro, texte: "On garde la version longue.", voix: "Voix 1", echoProbable: true)]
    #expect(CompteRendu.empreinte(de: echoDifferent) != reference)
}

// `nommer` ne réécrit jamais la transcription (voir nommerUneVoixNeReecritPasLaTranscription) : la
// substitution du nom affiché n'existe que dans une copie passée au modèle, jamais dans les segments
// sur le disque. L'empreinte, calculée sur ces segments bruts, ne peut donc jamais bouger à cause d'elle.
@Test func empreinteBruteNeDependPasDuNomAfficheApresCoup() {
    let brute = [Segment(debut: 0, fin: 5, piste: .micro, texte: "On garde la version longue.", voix: "Voix 1")]
    let empreinteBrute = CompteRendu.empreinte(de: brute)
    #expect(CompteRendu.empreinte(de: brute) == empreinteBrute)

    var affichee = brute
    affichee[0].voix = "Claire"
    #expect(CompteRendu.empreinte(de: affichee) != empreinteBrute)
}

@Test func etatRendLesTroisCas() {
    let segments = [Segment(debut: 0, fin: 5, piste: .micro, texte: "On garde la version longue.")]
    let empreinte = CompteRendu.empreinte(de: segments)
    let aJour = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [], empreinte: empreinte)
    #expect(aJour.etat(selon: segments) == .aJour)

    let changes = [Segment(debut: 0, fin: 5, piste: .micro, texte: "On garde la version courte.")]
    #expect(aJour.etat(selon: changes) == .perimee)

    let sansEmpreinte = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [])
    #expect(sansEmpreinte.etat(selon: segments) == .aVerifier)
}

@Test func uneAncienneAnalyseSansEmpreinteDecodeEtRestePerimeeAVerifier() throws {
    let ancienne = #"{"fournisseur":"Test","date":"2026-11-02T14:00:00Z","decisions":[],"actions":[],"questions":[],"passagesNonAnalyses":0,"elementsEcartes":0}"#
    let decodeur = JSONDecoder()
    decodeur.dateDecodingStrategy = .iso8601
    let relue = try decodeur.decode(CompteRendu.self, from: Data(ancienne.utf8))
    #expect(relue.empreinte == nil)
    #expect(relue.etat(selon: []) == .aVerifier)
}

// Une relecture qui termine pendant qu'une analyse tourne encore change déjà la transcription :
// l'empreinte prise au tout début de l'analyse, avant cette relecture, doit le révéler dès que
// le compte rendu est enregistré, sans attendre un prochain affichage.
@Test func uneEmpreinteCaptureeAvantUneRelectureQuiChangeLaTranscriptionApparaitPerimee() {
    let avant = [Segment(debut: 0, fin: 5, piste: .micro, texte: "On garde la version courte.")]
    let empreinteAvantRelecture = CompteRendu.empreinte(de: avant)
    let apres = [Segment(debut: 0, fin: 5, piste: .micro, texte: "On garde la version longue.")]

    let resultat = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [], empreinte: empreinteAvantRelecture)
    #expect(resultat.etat(selon: apres) == .perimee)
    #expect(resultat.etat(selon: avant) == .aJour)
}

private let segmentsOriginaux = [
    Segment(debut: 0, fin: 5, piste: .micro, texte: "On parle du budget de la tournee."),
    Segment(debut: 20, fin: 25, piste: .systeme, texte: "Marie envoie la musique avant vendredi."),
]
private let budget = Sujet(titre: "Budget", debut: 0, fin: 10)
private let horsTranscription = Sujet(titre: "Hors transcription", debut: 100, fin: 110)

@Test func uneAnalysePerimeeCacheEnBrefEtAvertitDansLaCopie() {
    let empreinteOriginale = CompteRendu.empreinte(de: segmentsOriginaux)
    let compteRendu = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [],
                                  sujets: [budget, horsTranscription],
                                  enBref: [PhraseSourcee(texte: "On parle du budget de la tournee.", sources: [0])],
                                  empreinte: empreinteOriginale)
    let segmentsApresRelecture = [
        Segment(debut: 0, fin: 5, piste: .micro, texte: "On parle du budget du film."),
        Segment(debut: 20, fin: 25, piste: .systeme, texte: "Marie envoie la musique avant vendredi."),
    ]

    let relue = compteRendu.revalide(dans: segmentsApresRelecture)
    #expect(relue.fraicheur == .perimee)
    #expect(relue.enBref == nil)
    #expect(relue.sujets?.map(\.titre) == ["Budget"])
    #expect(relue.texteACopier().contains("n'est plus à jour"))
    #expect(relue.markdown().contains("n'est plus à jour"))
}

@Test func uneAnalyseAVerifierControleEnBrefEtFiltreLesSujets() {
    let compteRendu = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [],
                                  sujets: [budget, horsTranscription],
                                  enBref: [
                                      PhraseSourcee(texte: "On parle du budget de la tournee.", sources: [0]),
                                      PhraseSourcee(texte: "Il reste 3 sujets a traiter.", sources: [0]),
                                  ])
    #expect(compteRendu.empreinte == nil)

    let relue = compteRendu.revalide(dans: segmentsOriginaux)
    #expect(relue.fraicheur == .aVerifier)
    #expect(relue.enBref?.map(\.texte) == ["On parle du budget de la tournee."])
    #expect(relue.sujets?.map(\.titre) == ["Budget"])
    #expect(!relue.texteACopier().contains("n'est plus à jour"))
}

@Test func unExtraitDUneAnalyseAJourRecoitUneEmpreinteFraicheAutrementAucune() {
    let segmentsExtrait = [segmentsOriginaux[0]]
    let compteRenduAJour = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [], sujets: [budget])
    #expect(compteRenduAJour.fraicheur == .aJour)
    // Reproduit la décision prise dans `Modele.repartir` : seul un original à jour transmet une empreinte fraîche.
    let empreinteSiAJour = compteRenduAJour.fraicheur == .aJour ? CompteRendu.empreinte(de: segmentsExtrait) : nil
    let extraitAJour = compteRenduAJour.extrait([budget], empreinte: empreinteSiAJour)
    #expect(extraitAJour.empreinte == CompteRendu.empreinte(de: segmentsExtrait))

    var compteRenduPerimee = compteRenduAJour
    compteRenduPerimee.fraicheur = .perimee
    let empreinteSiPerimee = compteRenduPerimee.fraicheur == .aJour ? CompteRendu.empreinte(de: segmentsExtrait) : nil
    let extraitPerimee = compteRenduPerimee.extrait([budget], empreinte: empreinteSiPerimee)
    #expect(extraitPerimee.empreinte == nil)
}
