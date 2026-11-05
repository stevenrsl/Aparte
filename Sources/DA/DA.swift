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
