import AppKit
import CoreText
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

public extension Color {
    // Écart local au brief : transcription plus claire dans le compte rendu, après squint test.
    static let transcriptionFond = dynamique("transcriptionFond", clair: 0xEDE2D8, sombre: 0x302722)
    static let transcriptionBulleMoi = dynamique("transcriptionBulleMoi", clair: 0xE2D2C5, sombre: 0x40342E)
    static let transcriptionBulleEux = dynamique("transcriptionBulleEux", clair: 0xF5EEE6, sombre: 0x392F2A)
    static let creme = dynamique("creme", clair: 0xF5EEE6, sombre: 0x2A211D)
    static let surface = dynamique("surface", clair: 0xE9D8C9, sombre: 0x231B18)
    static let encre = dynamique("encre", clair: 0x40332D, sombre: 0xF5EEE6)
    static let encreColonne = fixe(0x40332D)
    static let terracotta = fixe(0xA65F46)
    static let terracottaTexte = dynamique("terracottaTexte", clair: 0x8E4E38, sombre: 0xD4A88B)
    static let argile = fixe(0xD4A88B)
    static let encreDouce = dynamique("encreDouce", clair: 0x6E5A50, sombre: 0xD4A88B)
    static let filet = dynamique("filet", clair: 0xDCC7B6, sombre: 0x4A3C35)
    static let champ = dynamique("champ", clair: 0xFBF7F2, sombre: 0x231B18)
    static let colonneTexte = fixe(0xF5EEE6)
    static let colonneDoux = fixe(0xE9D8C9)
    static let colonneSignal = fixe(0xD4A88B)
    static let bulleEux = fixe(0x54443C)
    static let colonneFilet = fixe(0x5A4A42)
    static let chronoRepos = fixe(0xA08A7D)
}

/// Zalando Sans, JetBrains Mono et Doto ne sont pas encore embarquées : le système les remplace.
/// Les polices embarquées, lues dans leurs fichiers : une version installée sur le Mac ne peut pas
/// les remplacer. Si un fichier manque, `Typo` se replie sur la police système.
enum Polices {
    private final class Repere {}
    private static let axePoids = 0x77676874 // wght

    /// Le dossier d'un Aparté construit, ou celui des tests, à côté de leur bundle.
    static var dossier: URL? {
        let parents = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                       Bundle(for: Repere.self).bundleURL.deletingLastPathComponent()].compactMap { $0 }
        return parents.compactMap { Bundle(url: $0.appendingPathComponent("Aparte_DA.bundle"))?.url(forResource: "Polices", withExtension: nil) }.first
    }

    static func police(_ fichier: String, taille: CGFloat, poids: Int) -> CTFont? {
        guard let url = dossier?.appendingPathComponent(fichier),
              let descripteurs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descripteur = descripteurs.first else { return nil }
        let variation = [kCTFontVariationAttribute: [axePoids: poids]] as CFDictionary
        return CTFontCreateWithFontDescriptor(CTFontDescriptorCreateCopyWithAttributes(descripteur, variation), taille, nil)
    }

    static func font(_ fichier: String, taille: CGFloat, poids: Int, repli: Font) -> Font {
        police(fichier, taille: taille, poids: poids).map { Font($0) } ?? repli
    }
}

public enum Typo {
    public static let titreEcran = Font.system(size: 38, design: .serif)
    public static let titreSection = Font.system(size: 22, design: .serif)
    public static let titreListe = Font.system(size: 20, design: .serif)
    public static let titreLigne = Font.system(size: 17, design: .serif)
    public static let phraseEtat = Font.system(size: 16, design: .serif)
    public static let resume = Font.system(size: 20, design: .serif)
    public static let texte = Polices.font("ZalandoSans.ttf", taille: 14, poids: 400, repli: .system(size: 14))
    public static let texteDemiGras = Polices.font("ZalandoSans.ttf", taille: 14, poids: 600, repli: .system(size: 14, weight: .semibold))
    public static let texteGras = Polices.font("ZalandoSans.ttf", taille: 14, poids: 700, repli: .system(size: 14, weight: .bold))
    public static let note = Polices.font("ZalandoSans.ttf", taille: 16, poids: 400, repli: .system(size: 16))
    public static let libelle = Polices.font("JetBrainsMono.ttf", taille: 11, poids: 400, repli: .system(size: 11, design: .monospaced))
    public static let horodatage = libelle
    public static let chrono = Polices.font("Doto.ttf", taille: 68, poids: 800, repli: .system(size: 68, weight: .heavy, design: .monospaced))
    public static let grandChiffre = Polices.font("Doto.ttf", taille: 54, poids: 800, repli: .system(size: 54, weight: .heavy, design: .monospaced))
}

public struct Libelle: View {
    let texte: String
    let surColonne: Bool

    public init(_ texte: String, surColonne: Bool = false) {
        self.texte = texte
        self.surColonne = surColonne
    }

    public var body: some View {
        Text("// \(texte.lowercased())")
            .font(Typo.libelle)
            .tracking(0.22)
            .foregroundStyle(surColonne ? Color.colonneSignal : Color.encreDouce)
    }
}

public struct BoutonPrincipal: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.texteDemiGras)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.encreColonne)
            .foregroundStyle(Color.colonneTexte)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

public struct BoutonSignal: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.texteGras)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.argile)
            .foregroundStyle(Color.encreColonne)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

public struct BoutonSecondaire: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay { Rectangle().strokeBorder(Color.encre, lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

public struct LogoApparte: View {
    public init() {}
    public var body: some View {
        HStack(spacing: 9) {
            // Les niveaux sonores de l'icône : cinq colonnes de points, la centrale en crème.
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array([2, 4, 6, 4, 2].enumerated()), id: \.offset) { colonne, hauteur in
                    VStack(spacing: 1) {
                        ForEach(0..<hauteur, id: \.self) { _ in
                            Rectangle().fill(colonne == 2 ? Color.creme : Color.argile).frame(width: 3, height: 3)
                        }
                    }
                }
            }
            .padding(5)
            .background(Color.encre)
            .accessibilityHidden(true)
            Text("Aparté").font(.system(size: 21, design: .serif))
        }
    }
}

/// Le grain : une texture générée une fois, en mosaïque, jamais recalculée.
/// Le bruit reste clair, sinon la multiplication ternit la crème au lieu de la texturer.
public struct GrainOverlay: View {
    @Environment(\.colorScheme) private var theme
    @Environment(\.colorSchemeContrast) private var contraste
    @Environment(\.accessibilityReduceTransparency) private var transparenceReduite

    private static let texture: Image = {
        let cote = 256
        var generateur = SystemRandomNumberGenerator()
        var pixels = [UInt8](repeating: 0, count: cote * cote)
        for i in pixels.indices { pixels[i] = UInt8.random(in: 170...255, using: &generateur) }
        let contexte = CGContext(data: &pixels, width: cote, height: cote, bitsPerComponent: 8, bytesPerRow: cote,
                                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        guard let image = contexte?.makeImage() else { return Image(systemName: "circle") }
        return Image(decorative: image, scale: 2)
    }()

    public init() {}

    public var body: some View {
        if contraste == .standard, !transparenceReduite {
            Self.texture
                .resizable(resizingMode: .tile)
                .blendMode(theme == .dark ? .screen : .multiply)
                .opacity(theme == .dark ? 0.08 : 0.16)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

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
