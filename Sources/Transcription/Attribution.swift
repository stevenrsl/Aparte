import Foundation

/// Un mot tel qu'il a été entendu. `texte` garde ses espaces, pour que les mots remis bout à bout
/// se lisent comme la phrase.
public struct Mot: Equatable, Sendable {
    public var texte: String
    public var debut: Double
    public var fin: Double

    public init(texte: String, debut: Double, fin: Double) {
        self.texte = texte
        self.debut = debut
        self.fin = fin
    }
}

/// Qui a parlé, de quand à quand.
public struct TourDeVoix: Equatable, Sendable {
    public var voix: String
    public var debut: Double
    public var fin: Double

    public init(voix: String, debut: Double, fin: Double) {
        self.voix = voix
        self.debut = debut
        self.fin = fin
    }
}

/// Coupe les phrases là où la voix change. Repris de Cairn, réglages compris, essayés sur de vraies
/// réunions. Les voix s'appellent « Voix 1 », « Voix 2 » : c'est Steven qui les nomme, rien ne devine.
public enum Attribution {
    /// Une voix entendue moins que ça, au total, est une toux ou deux voix mêlées : ses moments
    /// reviennent à la voix la plus proche.
    static let voixMinimum = 3.0
    /// Un mot hors de tout tour va à un tour aussi proche. Plus loin, il reste sans voix plutôt que
    /// d'en recevoir une au hasard.
    static let portee = 1.0
    /// De combien de mots une coupure peut glisser pour tomber sur une ponctuation.
    static let glissement = 3

    /// Les tours renommés par ordre d'apparition, sans les voix trop peu entendues.
    public static func nommes(_ tours: [TourDeVoix]) -> [TourDeVoix] {
        var parole: [String: Double] = [:]
        for tour in tours { parole[tour.voix, default: 0] += tour.fin - tour.debut }
        var noms: [String: String] = [:]
        return tours.sorted { $0.debut < $1.debut }.compactMap { tour in
            guard parole[tour.voix, default: 0] >= voixMinimum else { return nil }
            if noms[tour.voix] == nil { noms[tour.voix] = "Voix \(noms.count + 1)" }
            var nomme = tour
            nomme.voix = noms[tour.voix]!
            return nomme
        }
    }

    /// Les phrases coupées en segments là où la voix change. Avec une voix ou aucune, personne n'est
    /// distingué et les segments restent sans voix.
    public static func attribuer(_ phrases: [[Mot]], a tours: [TourDeVoix], piste: Piste) -> [Segment] {
        let voix = Set(tours.map(\.voix))
        var segments: [Segment] = []
        for mots in phrases where !mots.isEmpty {
            var qui: [String?] = mots.map { voix.count > 1 ? voixDu(mot: $0, dans: tours) : nil }
            if voix.count > 1 {
                // Un mot entre deux d'une autre voix, c'est le séparateur qui hésite, pas une interruption.
                if qui.count >= 3 {
                    for i in 1..<(qui.count - 1) where qui[i - 1] == qui[i + 1] && qui[i] != qui[i - 1] {
                        qui[i] = qui[i - 1]
                    }
                }
                qui = recale(qui, mots)
            }
            var debut = 0
            for i in 1...mots.count where i == mots.count || qui[i] != qui[debut] {
                let texte = mots[debut..<i].map(\.texte).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                if !texte.isEmpty {
                    segments.append(Segment(debut: mots[debut].debut, fin: mots[i - 1].fin, piste: piste, texte: texte, voix: qui[debut]))
                }
                debut = i
            }
        }
        return segments
    }

    /// Les tours et les temps des mots diffèrent d'un mot ou deux : une coupure en pleine phrase
    /// glisse vers la ponctuation la plus proche, où une personne passe presque toujours la parole.
    private static func recale(_ entree: [String?], _ mots: [Mot]) -> [String?] {
        var qui = entree
        func fin(_ coupure: Int) -> Bool {
            coupure == 0 || coupure == mots.count
                || mots[coupure - 1].texte.trimmingCharacters(in: .whitespaces).last.map { ".,;:?!…".contains($0) } == true
        }
        var coupure = 1
        while coupure < qui.count {
            defer { coupure += 1 }
            guard qui[coupure] != qui[coupure - 1], !fin(coupure) else { continue }
            let proches = (max(0, coupure - glissement)...min(mots.count, coupure + glissement)).filter(fin)
            guard let meilleure = proches.min(by: {
                abs($0 - coupure) != abs($1 - coupure) ? abs($0 - coupure) < abs($1 - coupure) : $0 > $1
            }) else { continue }
            if meilleure > coupure {
                for i in coupure..<meilleure { qui[i] = qui[coupure - 1] }
                coupure = meilleure
            } else {
                for i in meilleure..<coupure { qui[i] = qui[coupure] }
            }
        }
        return qui
    }

    private static func voixDu(mot: Mot, dans tours: [TourDeVoix]) -> String? {
        let milieu = (mot.debut + mot.fin) / 2
        if let dedans = tours.last(where: { $0.debut <= milieu && milieu <= $0.fin }) { return dedans.voix }
        func distance(_ tour: TourDeVoix) -> Double { milieu < tour.debut ? tour.debut - milieu : max(0, milieu - tour.fin) }
        return tours.min { distance($0) < distance($1) }.flatMap { distance($0) <= portee ? $0.voix : nil }
    }
}
