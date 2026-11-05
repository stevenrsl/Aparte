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

struct PuceSource: View {
    let temps: Double
    var active = false
    let action: () -> Void

    var body: some View {
        Button(horodatage(temps), action: action)
            .buttonStyle(.plain)
            .font(Typo.horodatage)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(active ? Color.argile : Color.surface)
            .foregroundStyle(active ? Color.encreColonne : Color.encre)
            .accessibilityLabel("Écouter à \(tempsParle(temps))")
    }
}

/// « 12 minutes 3 secondes », là où VoiceOver lirait mal « 12:03 ».
func tempsParle(_ secondes: Double) -> String {
    let total = Int(secondes)
    return "\(total / 60) minutes \(total % 60) secondes"
}

struct Niveaux: View {
    let valeurs: [Float]
    let couleur: Color
    var point: CGFloat = 5
    var hauteur = 6

    var body: some View {
        Canvas { contexte, taille in
            let pas = point + 2
            for (x, valeur) in valeurs.enumerated() {
                let actifs = max(1, Int((valeur * Float(hauteur)).rounded()))
                for y in 0..<actifs {
                    let rect = CGRect(x: CGFloat(x) * pas, y: taille.height - CGFloat(y + 1) * pas, width: point, height: point)
                    contexte.fill(Path(ellipseIn: rect), with: .color(couleur))
                }
            }
        }
        .frame(width: CGFloat(valeurs.count) * (point + 2), height: CGFloat(hauteur) * (point + 2))
        .accessibilityHidden(true)
    }
}

struct Chrono: View {
    let session: SessionReunion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(horodatage(session.temps))
                .font(Typo.chrono)
                .monospacedDigit()
                .foregroundStyle(session.debut == nil ? Color.chronoRepos : Color.colonneTexte)
                .accessibilityLabel("Temps écoulé")
                .accessibilityValue(tempsParle(session.temps))
        }
    }
}

/// La transcription en bulles : eux à gauche, moi à droite. En présentiel, tout à gauche.
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
            .accessibilityLabel("Nom de \(voix)")
            let proposes = modele.nomsConnus.filter { $0 != nom }.prefix(5)
            if !proposes.isEmpty, nom.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(proposes), id: \.self) { connu in
                        Button(connu) { modele.nommer(voix, connu, dans: reunion) }
                            .buttonStyle(.plain)
                            .font(Typo.horodatage)
                            .foregroundStyle(Color.encreDouce)
                            .accessibilityLabel("Appeler \(voix) \(connu)")
                    }
                }
            }
        }
    }
}

struct Bulles: View {
    let segments: [Segment]
    var provisoires: [Piste: String] = [:]
    let type: TypeReunion
    var sources: Set<Double> = []
    var suivre = false
    /// Pour nommer les voix, une fois la réunion relue.
    var reunion: Reunion?
    var modele: ModeleApp?
    @State private var voixANommer: UUID?

    private func etiquette(_ segment: Segment) -> String {
        var etiquette: String
        if let voix = segment.voix { etiquette = " · " + (reunion?.nom(de: voix) ?? voix) }
        else if estMoi(segment.piste) { etiquette = " · moi" }
        else { etiquette = type == .visio ? " · eux" : "" }
        if segment.echoProbable == true { etiquette += " · écho probable" }
        return etiquette
    }

    private func estMoi(_ piste: Piste) -> Bool { type == .visio && piste == .micro }

    var body: some View {
        ScrollViewReader { defilement in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(segments) { segment in
                        bulle(segment).id(segment.id)
                    }
                    ForEach([Piste.micro, .systeme], id: \.self) { piste in
                        if let texte = provisoires[piste], !texte.isEmpty {
                            Text(texte)
                                .padding(10)
                                .overlay { Rectangle().strokeBorder(Color.argile, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
                                .frame(maxWidth: .infinity, alignment: estMoi(piste) ? .trailing : .leading)
                        }
                    }
                    Color.clear.frame(height: 1).id("fin")
                }
                .padding(24)
            }
            .onChange(of: segments.count) { _, _ in
                if suivre { defilement.scrollTo("fin", anchor: .bottom) }
            }
        }
    }

    /// L'en-tête d'une voix se clique pour la nommer, sur place, en lisant ce qu'elle dit.
    @ViewBuilder private func enTete(_ segment: Segment) -> some View {
        let texte = Text(horodatage(segment.debut) + etiquette(segment))
            .font(Typo.horodatage)
            .foregroundStyle(Color.colonneSignal)
        if let voix = segment.voix, let reunion, let modele {
            Button { voixANommer = segment.id } label: { texte }
                .buttonStyle(.plain)
                .help("Donner un nom à cette voix")
                .accessibilityLabel("\(reunion.nom(de: voix)), à \(tempsParle(segment.debut))")
                .accessibilityHint("Donne un nom à cette voix")
                .popover(isPresented: Binding(get: { voixANommer == segment.id }, set: { if !$0 { voixANommer = nil } })) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(voix).font(Typo.horodatage).foregroundStyle(Color.encreDouce)
                        ChampNomDeVoix(modele: modele, reunion: reunion, voix: voix)
                            .frame(width: 220)
                    }
                    .padding(14)
                }
        } else {
            texte
        }
    }

    private func bulle(_ segment: Segment) -> some View {
        let moi = estMoi(segment.piste)
        let source = sources.contains { $0 >= segment.debut - 2 && $0 <= segment.fin + 2 }
        return VStack(alignment: moi ? .trailing : .leading, spacing: 4) {
            enTete(segment)
            Text(segment.texte)
                .textSelection(.enabled)
                .padding(10)
                .background(moi ? Color.argile : Color.bulleEux)
                .foregroundStyle(moi ? Color.encreColonne : Color.colonneTexte)
                .overlay(alignment: .leading) {
                    if source { Color.argile.frame(width: 3) }
                }
        }
        .frame(maxWidth: .infinity, alignment: moi ? .trailing : .leading)
        .padding(moi ? .leading : .trailing, 40)
    }
}

