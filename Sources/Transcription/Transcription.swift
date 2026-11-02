import AVFoundation
import Foundation
import Speech

/// La piste d'où vient une phrase. En visio, le micro c'est Steven et le système
/// ce sont les autres. En présentiel, tout passe par le micro.
public enum Piste: String, Codable, Sendable, Hashable {
    case micro
    case systeme
}

/// Une phrase que le transcripteur ne révisera plus, avec ses temps dans l'enregistrement.
public struct Segment: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var debut: Double
    public var fin: Double
    public var piste: Piste
    public var texte: String

    public init(id: UUID = UUID(), debut: Double, fin: Double, piste: Piste, texte: String) {
        self.id = id
        self.debut = debut
        self.fin = fin
        self.piste = piste
        self.texte = texte
    }
}

public enum ErreurTranscription: LocalizedError {
    case indisponible

    public var errorDescription: String? {
        "La transcription en français n'est pas disponible sur ce Mac."
    }
}

/// Le modèle de français, un élément du système qui tourne sur l'appareil.
public enum Parole {
    public static let identifiantLocale = "fr-FR"

    /// Rend la locale prête, en faisant installer le modèle par le système s'il manque.
    public static func preparer() async throws -> Locale {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifiantLocale))
        else { throw ErreurTranscription.indisponible }
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        if await AssetInventory.status(forModules: [module]) != .installed,
           let demande = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await demande.downloadAndInstall()
        }
        return locale
    }
}

/// Une piste transcrite pendant qu'on parle. Les tampons entrent par `alimenter`
/// depuis n'importe quel fil, les résultats sortent sur l'acteur principal.
public final class TranscripteurDirect: @unchecked Sendable {
    public let piste: Piste
    public let formatAttendu: AVAudioFormat

    private let analyseur: SpeechAnalyzer
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let flux: AsyncStream<AnalyzerInput>
    private var tacheResultats: Task<Void, Never>?

    private init(piste: Piste, analyseur: SpeechAnalyzer, format: AVAudioFormat) {
        self.piste = piste
        self.analyseur = analyseur
        self.formatAttendu = format
        (flux, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)
    }

    public static func demarrer(
        locale: Locale,
        piste: Piste,
        surFinal: @escaping @MainActor (Segment) -> Void,
        surProvisoire: @escaping @MainActor (Piste, String) -> Void
    ) async throws -> TranscripteurDirect {
        let transcripteur = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                              reportingOptions: [.volatileResults],
                                              attributeOptions: [.audioTimeRange])
        let analyseur = SpeechAnalyzer(modules: [transcripteur],
                                       options: .init(priority: .userInitiated, modelRetention: .lingering))
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcripteur]) else {
            throw ErreurTranscription.indisponible
        }
        try await analyseur.prepareToAnalyze(in: format)

        let direct = TranscripteurDirect(piste: piste, analyseur: analyseur, format: format)
        direct.tacheResultats = Task {
            do {
                for try await resultat in transcripteur.results {
                    let texte = String(resultat.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if resultat.isFinal {
                        await surProvisoire(piste, "")
                        guard !texte.isEmpty else { continue }
                        await surFinal(Segment(debut: resultat.range.start.seconds,
                                               fin: resultat.range.end.seconds,
                                               piste: piste, texte: texte))
                    } else {
                        await surProvisoire(piste, texte)
                    }
                }
            } catch {
                // Le flux ne finit en erreur qu'à l'annulation, et ce qui était final est déjà remis.
            }
        }
        try await analyseur.start(inputSequence: direct.flux)
        return direct
    }

    public func alimenter(_ tampon: AVAudioPCMBuffer) {
        continuation.yield(AnalyzerInput(buffer: tampon))
    }

    /// Ferme l'entrée et attend que les derniers mots soient finalisés.
    public func terminer() async {
        continuation.finish()
        do {
            try await analyseur.finalizeAndFinishThroughEndOfInput()
        } catch {
            await analyseur.cancelAndFinishNow()
        }
        await tacheResultats?.value
    }
}

/// Transcrit un enregistrement après coup.
public enum TranscripteurFichier {
    public static func transcrire(url: URL, piste: Piste) async throws -> [Segment] {
        let locale = try await Parole.preparer()
        let fichier = try AVAudioFile(forReading: url)
        let transcripteur = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                              attributeOptions: [.audioTimeRange])
        let analyseur = SpeechAnalyzer(modules: [transcripteur])
        let collecte = Task { () -> [Segment] in
            var segments: [Segment] = []
            for try await resultat in transcripteur.results where resultat.isFinal {
                let texte = String(resultat.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !texte.isEmpty else { continue }
                segments.append(Segment(debut: resultat.range.start.seconds, fin: resultat.range.end.seconds,
                                        piste: piste, texte: texte))
            }
            return segments
        }
        if let dernier = try await analyseur.analyzeSequence(from: fichier) {
            try await analyseur.finalizeAndFinish(through: dernier)
        } else {
            await analyseur.cancelAndFinishNow()
        }
        return try await collecte.value
    }
}
