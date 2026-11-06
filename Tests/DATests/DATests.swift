import Testing
import CoreText
import Foundation
@testable import DA

@Test func leModuleSeCharge() {}

@Test(arguments: [("ZalandoSans.ttf", "Zalando Sans", 600), ("JetBrainsMono.ttf", "JetBrains Mono", 700), ("Doto.ttf", "Doto", 800)])
func unePoliceEmbarqueeVientDeSonFichier(fichier: String, famille: String, poids: Int) throws {
    let police = try #require(Polices.police(fichier, taille: 14, poids: poids))
    #expect(CTFontCopyFamilyName(police) as String == famille)
    let url = try #require(CTFontCopyAttribute(police, kCTFontURLAttribute) as? URL)
    #expect(url.path.contains("Aparte_DA.bundle") && url.path.contains("/Polices/"))
    let variation = try #require(CTFontCopyVariation(police) as? [Int: Double])
    #expect(variation[0x77676874] == Double(poids))
}

@Test(arguments: ["OFL-ZalandoSans.txt", "OFL-JetBrainsMono.txt", "OFL-Doto.txt"])
func chaquePoliceGardeSaLicence(fichier: String) throws {
    let dossier = try #require(Polices.dossier)
    #expect(FileManager.default.fileExists(atPath: dossier.appendingPathComponent(fichier).path))
}

@Test func unePersonneGardeSaCouleur() {
    #expect(Pastille.rang("Karim") == Pastille.rang(" karim "))
    #expect(Pastille.rang("Léa") == Pastille.rang("Léa"))
    #expect((0..<Pastille.palette.count).contains(Pastille.rang("Steven")))
}
