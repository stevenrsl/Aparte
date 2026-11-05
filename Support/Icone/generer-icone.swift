// Dessine l'icône d'Aparté : cinq colonnes de points, comme les niveaux sonores.
// Usage : swift Support/Icone/generer-icone.swift <dossier de sortie>
// Sortie : icone-1024.png (carré plein, pour Xcode) et Aparte.iconset (pour build.sh).
import AppKit

func couleur(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
let encre = couleur(0x40332D), argile = couleur(0xD4A88B), creme = couleur(0xF5EEE6)
let hauteurs = [2, 4, 6, 4, 2]

/// `corps` : côté du carré encre dans l'image. `arrondi` : rayon, 0 pour un carré plein.
func png(taille: Int, corps: CGFloat, arrondi: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: taille, pixelsHigh: taille, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let t = CGFloat(taille), marge = (t - corps) / 2
    encre.setFill()
    NSBezierPath(roundedRect: NSRect(x: marge, y: marge, width: corps, height: corps),
                 xRadius: arrondi, yRadius: arrondi).fill()
    // Grille dessinée sur 140 unités, d'après la piste 2.
    let u = corps / 140
    let point = 8 * u, pasLigne = 14 * u, pasColonne = 20 * u
    let largeur = 4 * pasColonne + point
    let haut = 5 * pasLigne + point
    let x0 = (t - largeur) / 2, bas = (t - haut) / 2
    for (c, n) in hauteurs.enumerated() {
        (c == 2 ? creme : argile).setFill()
        for k in 0..<n {
            NSRect(x: x0 + CGFloat(c) * pasColonne, y: bas + CGFloat(k) * pasLigne, width: point, height: point).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sortie = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let set = sortie.appendingPathComponent("Aparte.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
try png(taille: 1024, corps: 1024, arrondi: 0).write(to: sortie.appendingPathComponent("icone-1024.png"))
for base in [16, 32, 128, 256, 512] {
    for echelle in [1, 2] {
        let px = base * echelle
        let nom = "icon_\(base)x\(base)" + (echelle == 2 ? "@2x" : "") + ".png"
        let corps = CGFloat(px) * 824 / 1024
        try png(taille: px, corps: corps, arrondi: corps * 0.2237).write(to: set.appendingPathComponent(nom))
    }
}
