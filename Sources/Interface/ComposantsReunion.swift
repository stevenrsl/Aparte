import Analyse
import AppKit
import Capture
import DA
import SwiftUI
import Stockage
import Transcription

// MARK: - Les petits composants

func accord(_ nombre: Int, _ singulier: String, _ pluriel: String? = nil) -> String {
    "\(nombre) \(nombre > 1 ? (pluriel ?? singulier + "s") : singulier)"
}

/// « 12 minutes 3 secondes », là où VoiceOver lirait mal « 12:03 ».
func tempsParle(_ secondes: Double) -> String {
    let total = Int(secondes)
    return "\(total / 60) minutes \(total % 60) secondes"
}

/// Le nom d'une voix, et les noms déjà connus à reprendre d'un clic.
struct ChampNomDeVoix: View {
    let modele: ModeleApp
    let reunion: Reunion
    let voix: String

    private var nom: String { modele.reunions.first { $0.id == reunion.id }?.meta.nomsDesVoix?[voix] ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Nom de cette personne", text: Binding(
                get: { nom },
                set: { modele.nommer(voix, $0, dans: reunion) }))
            .textFieldStyle(.plain)
            .font(Ecriture.interfaceForte)
            .accessibilityLabel("Nom de \(voix)")
            let proposes = modele.nomsConnus.filter { $0 != nom }.prefix(5)
            if !proposes.isEmpty, nom.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(proposes), id: \.self) { connu in
                        Button(connu) { modele.nommer(voix, connu, dans: reunion) }
                            .buttonStyle(.plain)
                            .font(Ecriture.detail)
                            .foregroundStyle(Couleur.lien)
                            .accessibilityLabel("Appeler \(voix) \(connu)")
                    }
                }
            }
        }
    }
}
