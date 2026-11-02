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

public extension Color {
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
public enum Typo {
    public static var titreEcran: Font { .system(size: 38, design: .serif) }
    public static var titreSection: Font { .system(size: 22, design: .serif) }
    public static var titreListe: Font { .system(size: 20, design: .serif) }
    public static var resume: Font { .system(size: 20, design: .serif) }
    public static var texte: Font { .system(size: 14) }
    public static var note: Font { .system(size: 16) }
    public static var libelle: Font { .system(size: 11, design: .monospaced) }
    public static var horodatage: Font { .system(size: 11, design: .monospaced) }
    public static var chrono: Font { .system(size: 68, weight: .heavy, design: .monospaced) }
    public static var grandChiffre: Font { .system(size: 54, weight: .heavy, design: .monospaced) }
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
            .fontWeight(.semibold)
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
            .fontWeight(.bold)
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
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                GridRow {
                    Rectangle().fill(Color.encre).frame(width: 7, height: 7)
                    Rectangle().fill(Color.terracotta).frame(width: 7, height: 7)
                }
                GridRow {
                    Rectangle().fill(Color.argile).frame(width: 7, height: 7)
                    Rectangle().fill(Color.encre).frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
            Text("Aparté").font(.system(size: 21, design: .serif))
        }
    }
}

/// Le grain : une texture générée une fois, en mosaïque, jamais recalculée.
public struct GrainOverlay: View {
    @Environment(\.colorScheme) private var theme
    @Environment(\.colorSchemeContrast) private var contraste
    @Environment(\.accessibilityReduceTransparency) private var transparenceReduite

    private static let texture: Image = {
        let cote = 256
        var generateur = SystemRandomNumberGenerator()
        var pixels = [UInt8](repeating: 0, count: cote * cote)
        for i in pixels.indices { pixels[i] = UInt8.random(in: 0...255, using: &generateur) }
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
