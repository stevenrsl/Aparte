import CoreAudio
import Foundation
import Testing
@testable import Capture

private let ecouteurs = EntreeAudio(id: 10, nom: "Nothing Ear", transport: kAudioDeviceTransportTypeBluetooth)
private let integre = EntreeAudio(id: 20, nom: "MacBook Pro Microphone", transport: kAudioDeviceTransportTypeBuiltIn)
private let usb = EntreeAudio(id: 30, nom: "Rode", transport: kAudioDeviceTransportTypeUSB)

@Test func enPresentielDesEcouteursParDefautCedentLaPlaceAuMicroDuMac() {
    #expect(EntreeAudio.choisir(choisie: nil, parDefaut: ecouteurs, toutes: [ecouteurs, integre], presentiel: true) == integre)
}

@Test func enVisioLesEcouteursRestent() {
    #expect(EntreeAudio.choisir(choisie: nil, parDefaut: ecouteurs, toutes: [ecouteurs, integre], presentiel: false) == ecouteurs)
}

@Test func unChoixDeStevenPasseToujours() {
    #expect(EntreeAudio.choisir(choisie: ecouteurs, parDefaut: usb, toutes: [ecouteurs, integre, usb], presentiel: true) == ecouteurs)
}

@Test func unMicroFilaireParDefautResteEnPresentiel() {
    #expect(EntreeAudio.choisir(choisie: nil, parDefaut: usb, toutes: [usb, integre], presentiel: true) == usb)
}

@Test func unMicroQuiNEntendQuUnSouffleEstSignaleApresTrenteSecondes() {
    var detecteur = DetecteurMicroFaible()
    let debut = Date()
    var faible = false
    for i in 0..<400 { faible = detecteur.ajouter(0.02, a: debut.addingTimeInterval(Double(i) * 0.1)) }
    #expect(faible)
    // Une voix revient : l'alerte tombe dès qu'assez de niveaux forts entrent dans la fenêtre.
    for i in 400..<700 { faible = detecteur.ajouter(0.6, a: debut.addingTimeInterval(Double(i) * 0.1)) }
    #expect(!faible)
}

@Test func unMicroNormalNEstPasSignale() {
    var detecteur = DetecteurMicroFaible()
    let debut = Date()
    var faible = true
    // Une conversation : des silences, mais une voix une fois sur cinq.
    for i in 0..<400 { faible = detecteur.ajouter(i % 5 == 0 ? 0.5 : 0.05, a: debut.addingTimeInterval(Double(i) * 0.1)) }
    #expect(!faible)
}

@Test func rienNEstSignaleAvantTrenteSecondes() {
    var detecteur = DetecteurMicroFaible()
    let debut = Date()
    var faible = false
    for i in 0..<200 { faible = detecteur.ajouter(0.0, a: debut.addingTimeInterval(Double(i) * 0.1)) }
    #expect(!faible)
}
