import Foundation

/// Rend une transcription lisible : l'écho marqué, les noms corrigés, les phrases d'une même
/// personne réunies. Repris de Cairn, y compris ses seuils.
public enum Nettoyage {
    private static let francais = Locale(identifier: "fr_FR")

    /// Remet les deux pistes dans l'ordre et réunit les phrases proches d'une même personne : une page
    /// de lignes d'une phrase se lit comme un journal, pas comme une réunion.
    public static func fusionner(_ segments: [Segment], ecart: Double = 2.5, maximum: Int = 600) -> [Segment] {
        var sortie: [Segment] = []
        for segment in segments.sorted(by: { $0.debut < $1.debut }) {
            let texte = segment.texte.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !texte.isEmpty else { continue }
            if var dernier = sortie.last, dernier.piste == segment.piste, dernier.voix == segment.voix,
               (dernier.echoProbable ?? false) == (segment.echoProbable ?? false),
               segment.debut - dernier.fin <= ecart, dernier.texte.count + texte.count <= maximum {
                dernier.texte += " " + texte
                dernier.fin = max(dernier.fin, segment.fin)
                sortie[sortie.count - 1] = dernier
            } else {
                var copie = segment
                copie.texte = texte
                sortie.append(copie)
            }
        }
        return sortie
    }

    // MARK: - L'écho d'une visio sans casque

    /// Secondes de part et d'autre d'une ligne où les mots de l'autre piste comptent.
    static let fenetreEcho = 8.0
    /// La plus courte suite de mots communs prise pour de l'écho plutôt que pour une coïncidence.
    static let suiteEcho = 3

    /// Sans casque, les haut-parleurs du Mac jouent la visio et le micro la capte : presque tout ce que
    /// disent les autres revient sous « moi », une seconde ou deux plus tard, en d'autres mots. Une ligne
    /// du micro qui partage une suite de mots avec le son du Mac au même moment est marquée comme un
    /// écho probable, sur toute la ligne : aucun mot n'est retiré, car un vrai « non » dans cette ligne
    /// doit rester visible. L'audio n'est pas touché.
    public static func marquerEcho(_ segments: [Segment]) -> [Segment] {
        let eux = segments.filter { $0.piste == .systeme }
        guard !eux.isEmpty else { return segments }
        return segments.map { segment in
            guard segment.piste == .micro else { return segment }
            let proches = eux.filter { $0.debut <= segment.fin + fenetreEcho && $0.fin >= segment.debut - fenetreEcho }
            guard !proches.isEmpty else { return segment }
            let entendus = Set(suites(proches.flatMap { mots($0.texte) }))
            let miens = mots(segment.texte)
            guard miens.count >= suiteEcho else { return segment }

            var echo = false
            for i in 0...(miens.count - suiteEcho) {
                let suite = miens[i..<(i + suiteEcho)].joined(separator: " ")
                if entendus.contains(suite) { echo = true; break }
            }
            guard echo else { return segment }
            var marque = segment
            marque.echoProbable = true
            return marque
        }
    }

    /// Les mots d'un texte, pliés pour la comparaison (accents et casse ignorés, pluriel simplifié).
    private static func mots(_ texte: String) -> [String] {
        var sortie: [String] = []
        for morceau in texte.split(whereSeparator: \.isWhitespace) {
            var plie = String(morceau).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: francais)
                .trimmingCharacters(in: .punctuationCharacters)
            // Un « ? » ou un « : » isolé, à la française, n'est pas un mot : il ne décale pas la suite.
            guard !plie.isEmpty else { continue }
            // L'un entend « photographes », l'autre « photographe » : c'est le même mot ici.
            if plie.count > 3, plie.hasSuffix("s") || plie.hasSuffix("x") { plie.removeLast() }
            sortie.append(plie)
        }
        return sortie
    }

    private static func suites(_ mots: [String]) -> [String] {
        guard mots.count >= suiteEcho else { return [] }
        return (0...(mots.count - suiteEcho)).map { mots[$0..<($0 + suiteEcho)].joined(separator: " ") }
    }

    // MARK: - Les noms connus

    /// Remet les noms connus là où le transcripteur les a mal entendus, avec prudence : seul un mot à
    /// majuscule, de cinq lettres ou plus, à une lettre d'un nom connu (accents et casse mis à part)
    /// est remplacé. Dans Cairn, le vocabulaire donné au transcripteur n'a pas suffi : d'où cette passe.
    public static func corrigerNoms(_ texte: String, noms: [String]) -> String {
        let connus = noms.flatMap { $0.split(whereSeparator: { !$0.isLetter && $0 != "-" }).map(String.init) }
            .filter { $0.count >= 5 }
        guard !connus.isEmpty else { return texte }
        func plier(_ mot: String) -> String { mot.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: francais) }
        var sortie = ""
        var mot = ""
        func vider() {
            defer { mot = "" }
            guard mot.count >= 5, mot.first?.isUppercase == true else { sortie += mot; return }
            let plie = plier(mot)
            sortie += connus.first { plier($0) != plie && uneLettre(plier($0), plie) } ?? mot
        }
        for caractere in texte {
            if caractere.isLetter || caractere == "-" {
                mot.append(caractere)
            } else {
                vider()
                sortie.append(caractere)
            }
        }
        vider()
        return sortie
    }

    /// Vrai si une seule lettre change, s'ajoute ou manque.
    private static func uneLettre(_ a: String, _ b: String) -> Bool {
        let a = Array(a), b = Array(b)
        guard abs(a.count - b.count) <= 1 else { return false }
        var i = 0, j = 0, differences = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                i += 1
                j += 1
            } else {
                differences += 1
                if a.count > b.count { i += 1 } else if b.count > a.count { j += 1 } else { i += 1; j += 1 }
            }
        }
        return differences + (a.count - i) + (b.count - j) == 1
    }
}
