import Testing
import Foundation
@testable import DA

@Test func leModuleSeCharge() {}

@Test func unePersonneGardeSaCouleur() {
    #expect(Pastille.rang("Karim") == Pastille.rang(" karim "))
    #expect(Pastille.rang("Léa") == Pastille.rang("Léa"))
    #expect((0..<Pastille.palette.count).contains(Pastille.rang("Steven")))
}
