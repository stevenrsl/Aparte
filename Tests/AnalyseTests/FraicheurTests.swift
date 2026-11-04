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

// Sans voix renseignée, une phrase du micro et la même phrase du son du Mac ne disent pas la même
// chose (voir AnalysteLocal.invite : « moi » contre « eux » en visio) : l'empreinte doit le voir.
@Test func empreinteChangeAvecLaPisteSansVoixRenseignee() {
    let surMicro = [Segment(debut: 0, fin: 5, piste: .micro, texte: "Budget validé.")]
    let surSysteme = [Segment(debut: 0, fin: 5, piste: .systeme, texte: "Budget validé.")]
    #expect(CompteRendu.empreinte(de: surMicro) != CompteRendu.empreinte(de: surSysteme))
}

// Un segment sans aucun mot (un simple « … ») ne doit rien changer : ni son texte vide, ni ses
// marqueurs de piste, de voix ou d'écho, ne doivent faire bouger l'empreinte.
@Test func empreinteIgnoreUnSegmentSansAucunMot() {
    let sansPoints = [Segment(debut: 0, fin: 5, piste: .micro, texte: "Budget validé.", voix: "Voix 1")]
    let avecPointsEnPlus = sansPoints + [Segment(debut: 5, fin: 6, piste: .systeme, texte: "…", voix: "Voix 2", echoProbable: true)]
    #expect(CompteRendu.empreinte(de: sansPoints) == CompteRendu.empreinte(de: avecPointsEnPlus))
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

// Le titre d'un sujet périmé ou à vérifier doit encore être fait de mots dits dans ce moment
// (DecoupageSujets.titreDit) : sinon il revient aux six premiers mots dits du passage. Les bornes
// et l'id restent, seul le titre change ; le sujet n'est retiré que si ses bornes ne tombent plus
// sur un segment (couvert par uneAnalysePerimeeCacheEnBrefEtAvertitDansLaCopie, qui retire « Hors
// transcription »).
@Test func unSujetPerimeAvecUnTitreInventeRevientAuxMotsDitsDuPassage() {
    let inventeAuDepart = Sujet(titre: "TV à 999 €", debut: 0, fin: 10)
    let empreinteOriginale = CompteRendu.empreinte(de: segmentsOriginaux)
    let compteRendu = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [],
                                  sujets: [inventeAuDepart], empreinte: empreinteOriginale)
    let segmentsApresRelecture = [
        Segment(debut: 0, fin: 5, piste: .micro, texte: "On refuse le budget total."),
        Segment(debut: 20, fin: 25, piste: .systeme, texte: "Marie envoie la musique avant vendredi."),
    ]

    let relue = compteRendu.revalide(dans: segmentsApresRelecture)
    #expect(relue.fraicheur == .perimee)
    #expect(relue.sujets?.first?.id == inventeAuDepart.id)
    #expect(relue.sujets?.first?.debut == 0)
    #expect(relue.sujets?.first?.titre == "On refuse le budget total.")
}

// Un seul long segment peut englober tout le sujet : ni son début ni sa fin ne tombent dedans.
@Test func unSegmentQuiEnglobeLeSujetSertAussiAControlerSonTitre() {
    let invente = Sujet(titre: "TV à 999 €", debut: 10, fin: 20)
    let compteRendu = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [], sujets: [invente])
    let long = [Segment(debut: 0, fin: 60, piste: .micro, texte: "On refuse le budget total.")]

    let relue = compteRendu.revalide(dans: long)
    #expect(relue.sujets?.first?.id == invente.id)
    #expect(relue.sujets?.first?.titre == "On refuse le budget total.")
}

@Test func unSujetAuTitreRefuseSansAucunMotDitEstRetire() {
    let invente = Sujet(titre: "TV à 999 €", debut: 0, fin: 10)
    let compteRendu = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [], sujets: [invente])
    let vide = [Segment(debut: 0, fin: 5, piste: .micro, texte: "   ")]

    #expect(compteRendu.revalide(dans: vide).sujets?.isEmpty == true)
}

// Ce que `enregistrer` et `marquerSiPerimee` écrivent : le Markdown vient de la version revalidée.
// Une analyse dont la transcription a changé pendant qu'elle tournait s'écrit donc déjà périmée.
@Test func leMarkdownDUneAnalyseFinieApresUneRelectureNeGardeRienDePerime() {
    let avant = [Segment(debut: 0, fin: 5, piste: .micro, texte: "On garde la version longue.")]
    let apres = [Segment(debut: 0, fin: 5, piste: .micro, texte: "On garde la version courte.")]
    let decision = ElementSource(texte: "On garde la version longue.", sources: [1], citation: "version longue")
    var finie = CompteRendu(fournisseur: "Test", decisions: [decision], actions: [], questions: [],
                            enBref: [PhraseSourcee(texte: "La version longue est gardée.", sources: [1])])
    finie.empreinte = CompteRendu.empreinte(de: avant)

    let revalidee = finie.revalide(dans: apres)
    #expect(finie.empreinte == CompteRendu.empreinte(de: avant))
    #expect(revalidee.empreinte == finie.empreinte)
    let markdown = revalidee.markdown()
    #expect(markdown.contains("n'est plus à jour"))
    #expect(!markdown.contains("version longue"))
}

@Test func unSujetAVerifierAvecUnTitreDitResteInchange() {
    let titreDit = Sujet(titre: "Budget", debut: 0, fin: 10)
    let compteRendu = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [], sujets: [titreDit])
    #expect(compteRendu.empreinte == nil)

    let relue = compteRendu.revalide(dans: segmentsOriginaux)
    #expect(relue.fraicheur == .aVerifier)
    #expect(relue.sujets?.first?.titre == "Budget")
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

// `Sujet.chevauche` doit voir le même chevauchement que `revalide` : un seul long segment qui englobe
// tout le sujet, et aucun segment du tout.
@Test func chevaucheVoitUnLongSegmentQuiEnglobeLeSujetEtRienSansSegment() {
    let sujet = Sujet(titre: "Budget", debut: 10, fin: 20)
    let englobant = Segment(debut: 0, fin: 60, piste: .micro, texte: "On refuse le budget total.")
    #expect(sujet.chevauche(englobant))

    let ailleurs = Segment(debut: 100, fin: 110, piste: .micro, texte: "Autre chose.")
    #expect(!sujet.chevauche(ailleurs))
}

// Un extrait sans aucune transcription à lui (son sujet n'est couvert par aucun segment gardé) ne
// peut pas se déclarer à jour, même si l'original l'est : reproduit la décision de `Modele.repartir`.
@Test func unExtraitSansAucunSegmentNeRecoitAucuneEmpreinteMemeAJour() {
    let segmentsExtrait: [Segment] = []
    let empreinte = (true && !segmentsExtrait.isEmpty) ? CompteRendu.empreinte(de: segmentsExtrait) : nil
    #expect(empreinte == nil)
}

// Un sujet dont la fin dépasse largement la fin de la transcription (relecture qui a raccourci la
// réunion) s'arrête à cette fin, sans être retiré. Un léger dépassement dans la tolérance, ou une fin
// qui tombe dans un silence entre deux segments, garde ses bornes. Un sujet dont le DÉBUT dépasse la
// fin de la transcription, lui, est retiré : sinon il resterait affiché après la dernière parole,
// ramené à une durée nulle (voir unSujetDontLeDebutDepasseLaTranscriptionEstRetire).
@Test func unSujetDontLaFinDepasseLaTranscriptionSArreteASaFinSaufDansLaToleranceOuUnSilence() {
    let segments = [Segment(debut: 0, fin: 5, piste: .micro, texte: "On parle du budget.")]

    let loinDevant = Sujet(titre: "Budget", debut: 0, fin: 900)
    let compteRenduLoin = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [], sujets: [loinDevant])
    let ramene = compteRenduLoin.revalide(dans: segments).sujets?.first
    #expect(ramene?.id == loinDevant.id)
    #expect(ramene?.titre == "Budget")
    #expect(ramene?.fin == 5)

    // Une relecture peut finir la transcription quelques secondes plus tôt : cinq minutes dites restent un sujet.
    let dernier = Sujet(titre: "Budget", debut: 600, fin: 900)
    let relue = [Segment(debut: 600, fin: 890, piste: .micro, texte: "On parle du budget.")]
    let compteRenduDernier = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [], sujets: [dernier])
    #expect(compteRenduDernier.revalide(dans: relue).sujets?.first?.fin == 890)

    // `ValidationSources.marge` est interne (2 secondes) : 1 seconde de dépassement reste dans la tolérance.
    let dansLaTolerance = Sujet(titre: "Budget", debut: 0, fin: 6)
    let compteRenduTolerance = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [], sujets: [dansLaTolerance])
    #expect(compteRenduTolerance.revalide(dans: segments).sujets?.first?.fin == 6)

    let segmentsAvecSilence = [
        Segment(debut: 0, fin: 5, piste: .micro, texte: "On parle du budget."),
        Segment(debut: 50, fin: 55, piste: .micro, texte: "On conclut la reunion."),
    ]
    let finDansLeSilence = Sujet(titre: "Budget", debut: 0, fin: 20)
    let compteRenduSilence = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [], sujets: [finDansLeSilence])
    #expect(compteRenduSilence.revalide(dans: segmentsAvecSilence).sujets?.first?.fin == 20)
}

// Même avec la tolérance de segmentsSources (2 secondes), un sujet qui commence après la fin de la
// transcription n'est pas un bon sujet : il resterait affiché ramené à une durée nulle, après la
// dernière parole (« Budget (00:06) » alors que la réunion s'arrête à 5 s).
@Test func unSujetDontLeDebutDepasseLaTranscriptionEstRetire() {
    let segments = [Segment(debut: 0, fin: 5, piste: .micro, texte: "On parle du budget.")]
    let apresLaFin = Sujet(titre: "Budget", debut: 6, fin: 900)
    let compteRendu = CompteRendu(fournisseur: "Test", decisions: [], actions: [], questions: [], sujets: [apresLaFin])
    #expect(compteRendu.revalide(dans: segments).sujets?.isEmpty == true)
}

// Le flux par piste de `empreinte` ne doit pas dépendre de l'entrecroisement entre pistes : un
// redécoupage d'une piste autour d'un mot de l'autre piste, aux mêmes mots et aux mêmes attributions,
// doit rendre la même empreinte.
@Test func empreinteIgnoreLEntrecroisementEntrePistes() {
    let unSeulSegmentParPiste = [
        Segment(debut: 0, fin: 10, piste: .micro, texte: "Budget valide."),
        Segment(debut: 3, fin: 4, piste: .systeme, texte: "Oui."),
    ]
    let redecoupeAutourDuMot = [
        Segment(debut: 0, fin: 2, piste: .micro, texte: "Budget"),
        Segment(debut: 3, fin: 4, piste: .systeme, texte: "Oui."),
        Segment(debut: 5, fin: 10, piste: .micro, texte: "valide."),
    ]
    #expect(CompteRendu.empreinte(de: unSeulSegmentParPiste) == CompteRendu.empreinte(de: redecoupeAutourDuMot))

    // Mais une vraie phrase déplacée d'une piste à l'autre doit toujours changer l'empreinte.
    let deplacee = [
        Segment(debut: 0, fin: 2, piste: .systeme, texte: "Budget"),
        Segment(debut: 3, fin: 4, piste: .systeme, texte: "Oui."),
        Segment(debut: 5, fin: 10, piste: .micro, texte: "valide."),
    ]
    #expect(CompteRendu.empreinte(de: deplacee) != CompteRendu.empreinte(de: unSeulSegmentParPiste))
}
