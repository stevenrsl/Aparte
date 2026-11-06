import Analyse
import AppKit
import Capture
import DA
import SwiftUI
import Stockage
import Transcription

// MARK: - Accueil

struct EcranAccueil: View {
    @Bindable var modele: ModeleApp
    @State private var demarrage = false

    /// Les réunions de cette semaine et leur durée, pour le surtitre.
    private var semaine: String {
        let calendrier = Calendar(identifier: .iso8601)
        let cetteSemaine = modele.reunions.filter { calendrier.isDate($0.meta.date, equalTo: Date(), toGranularity: .weekOfYear) }
        guard !cetteSemaine.isEmpty else { return "Aucune réunion cette semaine" }
        let minutes = Int((cetteSemaine.map(\.meta.duree).reduce(0, +) / 60).rounded())
        let duree = minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
        return "Cette semaine : \(accord(cetteSemaine.count, "réunion")), \(duree)"
    }

    private func demarrer(_ type: TypeReunion) {
        demarrage = true
        Task {
            await modele.demarrer(titre: "", type: type, dossier: nil, entree: nil)
            demarrage = false
        }
    }

    var body: some View {
        let actions = modele.actionsOuvertes()
        PageAffiche {
            EnteteAffiche(surtitre: Date().formatted(.dateTime.locale(francaisAffiche).weekday(.wide).day().month(.wide)) + "  ·  " + semaine,
                          titre: "Bonjour, Steven.", grand: 64) {
                if let session = modele.session {
                    VStack(alignment: .trailing, spacing: Espace.s2) {
                        Button("Revenir à la réunion") { modele.ouvrirReunionEnCours() }
                            .buttonStyle(BoutonSurAplat(plein: true))
                        Etiquette("En cours : \(session.titre.isEmpty ? "réunion" : session.titre)", couleur: Couleur.surAplat)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: Espace.s2) {
                        Button { demarrer(.visio) } label: {
                            Label("Démarrer l’enregistrement", systemImage: "mic.fill")
                                .font(Ecriture.lectureForte)
                                .padding(.horizontal, Espace.s6).padding(.vertical, Espace.s3)
                                .background(Capsule().fill(Couleur.surAplat))
                                .foregroundStyle(Couleur.aplat)
                        }
                        .buttonStyle(.plain)
                        .disabled(demarrage)
                        .accessibilityHint("En visio : le micro et le son du Mac")
                        HStack(spacing: Espace.s4) {
                            Text("Visio, ⌘N").font(Ecriture.detail)
                            Button("En présentiel") { demarrer(.presentiel) }.buttonStyle(.plain).font(Ecriture.interfaceForte)
                            Button("Préparer…") { modele.preparerReunion() }.buttonStyle(.plain).font(Ecriture.interfaceForte)
                        }
                        .disabled(demarrage)
                    }
                }
            }
        } contenu: {
            HStack(alignment: .top, spacing: Espace.s10) {
                VStack(alignment: .leading, spacing: 0) {
                    TitreSection(numero: "\(actions.count)", titre: "À faire")
                    ListeActions(modele: modele, actions: actions)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    TitreSection(numero: "", titre: "Sommaire")
                    if modele.reunions.isEmpty {
                        Text("Pas encore de réunion. La première commence avec « Démarrer l’enregistrement ».")
                            .font(Ecriture.citation).foregroundStyle(Couleur.texteDoux).padding(.vertical, Espace.s2)
                    } else {
                        Sommaire(modele: modele, reunions: modele.reunions, limite: 6) { modele.ecran = .toutes }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct EcranToutes: View {
    @Bindable var modele: ModeleApp

    /// Les réunions par mois, du plus récent au plus ancien.
    private var parMois: [(mois: String, reunions: [Reunion])] {
        var groupes: [(String, [Reunion])] = []
        for reunion in modele.reunions.sorted(by: { $0.meta.date > $1.meta.date }) {
            let mois = reunion.meta.date.formatted(.dateTime.locale(francaisAffiche).month(.wide).year())
            let titre = mois.prefix(1).uppercased() + mois.dropFirst()
            if groupes.last?.0 == titre { groupes[groupes.count - 1].1.append(reunion) } else { groupes.append((titre, [reunion])) }
        }
        return groupes.map { (mois: $0.0, reunions: $0.1) }
    }

    var body: some View {
        let minutes = Int((modele.reunions.map(\.meta.duree).reduce(0, +) / 60).rounded())
        PageAffiche {
            EnteteAffiche(surtitre: modele.reunions.isEmpty ? "Aucune réunion" : "\(accord(modele.reunions.count, "réunion")) · \(minutes / 60) h \(String(format: "%02d", minutes % 60)) enregistrées",
                          titre: "Toutes les réunions") { EmptyView() }
        } contenu: {
            if modele.reunions.isEmpty {
                Text("Pas encore de réunion. La première commence avec « Démarrer en visio », dans la barre de gauche.")
                    .font(Ecriture.chapo).foregroundStyle(Couleur.texteDoux)
            }
            ForEach(parMois, id: \.mois) { groupe in
                VStack(alignment: .leading, spacing: 0) {
                    TitreSection(numero: "\(groupe.reunions.count)", titre: groupe.mois)
                    Sommaire(modele: modele, reunions: groupe.reunions)
                }
            }
        }
    }
}
