import AppKit
import SwiftUI

private func dynamique(_ nom: String, clair: UInt32, sombre: UInt32) -> Color {
    Color(nsColor: NSColor(name: NSColor.Name(nom)) { apparence in
        let estSombre = apparence.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(hex: estSombre ? sombre : clair)
    })
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

private func fixe(_ hex: UInt32) -> Color { Color(nsColor: NSColor(hex: hex)) }

// MARK: - Affiche (brief du 6 novembre 2026)

/// Les couleurs par rôle, chacune avec sa variante sombre. Contrastes mesurés dans le brief.
public enum Couleur {
    public static let papier = dynamique("papier", clair: 0xF4EFE5, sombre: 0x16140F)
    public static let marge = dynamique("marge", clair: 0xEAE3D5, sombre: 0x211E17)
    public static let texte = dynamique("texte", clair: 0x1B1915, sombre: 0xEFE8DA)
    public static let texteDoux = dynamique("texteDoux", clair: 0x4D473D, sombre: 0xC0B7A6)
    public static let texteDiscret = dynamique("texteDiscret", clair: 0x6B6457, sombre: 0x9C927F)
    public static let filet = dynamique("filetAffiche", clair: 0xD9D1C1, sombre: 0x37322A)
    /// L'aplat de l'affiche : un seul jeton, à décliner par dossier si Steven le décide.
    public static let aplat = dynamique("aplat", clair: 0x1F35B5, sombre: 0x3149C9)
    public static let surAplat = fixe(0xF4EFE5)
    public static let lien = dynamique("lien", clair: 0x1F35B5, sombre: 0x8FA2FF)
    public static let ocre = dynamique("ocre", clair: 0x8F5A12, sombre: 0xE0A64E)
    public static let direct = dynamique("direct", clair: 0xC8371B, sombre: 0xFF6A47)
    /// L'affiche de l'enregistrement en cours : un seul jeton, pour pouvoir l'adoucir si l'écran est partagé.
    public static let aplatDirect = dynamique("aplatDirect", clair: 0xB8301A, sombre: 0x9E2B15)
    public static let selection = dynamique("selection", clair: 0xE3E4F2, sombre: 0x23253A)
}

/// L'échelle typographique : New York pour lire, SF Pro Expanded pour étiqueter, SF Pro pour l'interface.
public enum Ecriture {
    public static func une(_ taille: CGFloat) -> Font { .system(size: taille, weight: .black, design: .serif) }
    public static let section = Font.system(size: 28, weight: .black, design: .serif)
    public static let numeroSection = Font.system(size: 28, weight: .black, design: .serif).italic()
    public static let chapo = Font.system(size: 17, design: .serif).italic()
    public static let lecture = Font.system(size: 16, design: .serif)
    public static let lectureForte = Font.system(size: 16, weight: .semibold, design: .serif)
    public static let personne = Font.system(size: 16, weight: .black, design: .serif).italic()
    public static let echeance = Font.system(size: 14, weight: .semibold, design: .serif).italic()
    public static let citation = Font.system(size: 14.5, design: .serif).italic()
    public static let transcription = Font.system(size: 14.5, design: .serif)
    public static let numero = Font.system(size: 17, weight: .black, design: .serif)
    public static let etiquette = Font.system(size: 10, weight: .semibold).width(.expanded)
    public static let horodatage = Font.system(size: 10.5, weight: .medium).width(.expanded).monospacedDigit()
    public static let horodatageFort = Font.system(size: 10.5, weight: .bold).width(.expanded).monospacedDigit()
    public static let interface = Font.system(size: 13)
    public static let interfaceForte = Font.system(size: 13, weight: .semibold)
    public static let detail = Font.system(size: 11.5)
}

/// La grille de 4 pt.
public enum Espace {
    public static let s1: CGFloat = 4
    public static let s2: CGFloat = 8
    public static let s3: CGFloat = 12
    public static let s4: CGFloat = 16
    public static let s6: CGFloat = 24
    public static let s8: CGFloat = 32
    public static let s10: CGFloat = 40
}

public enum Rayon {
    public static let petit: CGFloat = 4
    public static let moyen: CGFloat = 8
}

public enum Duree {
    public static let courte = 0.15
    public static let moyenne = 0.25
}

/// Une couleur stable par personne : le même nom a la même pastille dans toutes les réunions.
public enum Pastille {
    static let palette: [(fond: UInt32, texte: UInt32)] = [
        (0x1D55E0, 0xFFFFFF), (0xFF7A1A, 0x0A0A0A), (0x6C3BEB, 0xFFFFFF), (0x0E7A4E, 0xFFFFFF),
        (0xC81E5B, 0xFFFFFF), (0xE8B21C, 0x0A0A0A), (0x0B6E7A, 0xFFFFFF),
    ]

    /// Un hachage simple et stable d'une exécution à l'autre (`hashValue` change à chaque lancement).
    static func rang(_ nom: String) -> Int {
        let cle = nom.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var h: UInt32 = 5381
        for scalaire in cle.unicodeScalars { h = (h &* 33) &+ scalaire.value }
        return Int(h % UInt32(palette.count))
    }

    public static func couleurs(pour nom: String) -> (fond: Color, texte: Color) {
        let c = palette[rang(nom)]
        return (fixe(c.fond), fixe(c.texte))
    }
}

/// La pastille ronde d'une personne, son initiale dedans. Le nom est toujours écrit à côté.
public struct PastillePersonne: View {
    let nom: String
    let taille: CGFloat

    public init(_ nom: String, taille: CGFloat = 22) {
        self.nom = nom
        self.taille = taille
    }

    public var body: some View {
        let c = Pastille.couleurs(pour: nom)
        Text(String(nom.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.system(size: taille * 0.5, weight: .heavy, design: .rounded))
            .foregroundStyle(c.texte)
            .frame(width: taille, height: taille)
            .background(Circle().fill(c.fond))
            .accessibilityHidden(true)
    }
}
