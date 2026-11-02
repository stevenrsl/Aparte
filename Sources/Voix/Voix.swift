import FluidAudio
import Foundation
import Transcription

/// Qui parle, et quand, dans un enregistrement : la segmentation et le regroupement de FluidAudio,
/// sur le Neural Engine. La première fois, les modèles (21 Mo) sont téléchargés puis gardés ; rien de
/// l'enregistrement ne part, tout le reste tourne sur le Mac.
public enum Voix {
    public static func trouver(dans url: URL) async throws -> [TourDeVoix] {
        Attribution.nommes(try await separateur.tours(dans: url))
    }

    private static let separateur = Separateur()

    /// Un seul séparateur pour l'app : ses modèles ne se chargent qu'une fois.
    private actor Separateur {
        private var gestionnaire: OfflineDiarizerManager?

        func tours(dans url: URL) async throws -> [TourDeVoix] {
            let gestionnaire = self.gestionnaire ?? OfflineDiarizerManager(config: OfflineDiarizerConfig())
            try await gestionnaire.prepareModels()
            self.gestionnaire = gestionnaire
            let resultat = try await gestionnaire.process(url)
            return resultat.segments.map {
                TourDeVoix(voix: $0.speakerId, debut: TimeInterval($0.startTimeSeconds), fin: TimeInterval($0.endTimeSeconds))
            }
        }
    }
}
