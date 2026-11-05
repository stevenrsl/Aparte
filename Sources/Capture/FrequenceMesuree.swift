import Foundation

/// La fréquence réelle d'un flux audio, mesurée à l'horloge plutôt que crue sur parole.
///
/// Le son du Mac annonce son format une fois, au démarrage. Avec un casque Bluetooth passé en mode
/// appel, il peut arriver à 16 kHz sous l'étiquette 48 kHz : le fichier se lit alors trois fois trop vite
/// et la transcription devient illisible (une réunion de 59 min, écrite en 19 min 42). Rien d'autre ne le
/// signale : les tampons arrivent à l'heure, seule leur étiquette est fausse.
struct FrequenceMesuree {
    static let connues: [Double] = [8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000, 88200, 96000]
    /// Assez court pour que le premier son ne soit pas daté trop tard, assez long pour trancher.
    static let premiereFenetre = 0.3
    static let fenetre = 1.0
    /// Un blanc plus long n'est pas du son manquant à compter : la mesure repart.
    static let coupure = 0.5
    /// L'écart toléré autour d'une fréquence : la gigue des tampons reste bien en dessous.
    static let tolerance = 0.1

    let annoncee: Double
    /// Vide tant que la première fenêtre n'est pas écoulée.
    private(set) var frequence: Double?
    private var debut: Double?
    private var dernier: Double?
    private var images = 0
    private var candidate: Double?

    init(annoncee: Double) {
        self.annoncee = annoncee
    }

    /// La fréquence à retenir pour le tampon de `nombre` images qui commence à `temps`, en secondes.
    mutating func observer(images nombre: Int, a temps: Double) -> Double? {
        defer { dernier = temps }
        if let dernier, temps - dernier > Self.coupure || temps <= dernier { debut = nil }
        guard let debut else {
            self.debut = temps
            images = nombre
            return frequence
        }
        let ecoule = temps - debut
        if ecoule >= (frequence == nil ? Self.premiereFenetre : Self.fenetre) {
            retenir(Self.proche(Double(images) / ecoule, annoncee: annoncee))
            self.debut = temps
            images = 0
        }
        images += nombre
        return frequence
    }

    /// Une fois lancée, une fréquence ne change que sur deux mesures d'accord : un seul à-coup ne suffit pas.
    private mutating func retenir(_ mesure: Double?) {
        guard let actuelle = frequence else {
            frequence = mesure ?? annoncee
            return
        }
        guard let mesure, mesure != actuelle else {
            candidate = nil
            return
        }
        if candidate == mesure {
            frequence = mesure
            candidate = nil
        } else {
            candidate = mesure
        }
    }

    /// La fréquence annoncée si la mesure lui ressemble, sinon la fréquence connue la plus proche.
    static func proche(_ mesure: Double, annoncee: Double) -> Double? {
        guard mesure > 0 else { return nil }
        if abs(mesure / annoncee - 1) < tolerance { return annoncee }
        let voisine = connues.min { abs($0 - mesure) < abs($1 - mesure) }
        return voisine.flatMap { abs(mesure / $0 - 1) < tolerance ? $0 : nil }
    }
}
