import Analyse
import AppKit
import Capture
import DA
import SwiftUI
import Stockage
import Transcription

// MARK: - Accueil

struct LigneReunion: View {
    let modele: ModeleApp
    let reunion: Reunion
    var montrerDossier = true

    private var date: String {
        reunion.meta.date.formatted(.dateTime.locale(Locale(identifier: "fr_FR")).weekday(.abbreviated).day().month(.abbreviated))
    }

    var body: some View {
        let compteRendu = modele.resumeEnregistre(de: reunion)
        Button { modele.ouvrir(reunion) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text("\(date) · \(Int(reunion.meta.duree / 60)) min")
                    .font(Typo.horodatage)
                    .foregroundStyle(Color.encreDouce)
                    .frame(width: 150, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reunion.meta.titre).font(Typo.titreLigne).lineLimit(1)
                    Text(modele.session?.reunion.id == reunion.id ? "En cours" : (compteRendu?.apercu ?? "Pas encore analysée."))
                        .foregroundStyle(Color.encreDouce)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    if montrerDossier, let dossier = reunion.dossier {
                        Text(dossier.lowercased()).font(Typo.horodatage)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Color.surface)
                    }
                    if let compteRendu {
                        Text("\(accord(compteRendu.decisions.count, "décision")) · \(accord(compteRendu.actions.count, "action"))")
                            .font(Typo.horodatage)
                            .foregroundStyle(Color.encreDouce)
                    }
                }
            }
            .padding(.vertical, 11)
            .overlay(alignment: .top) { Color.filet.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Une liste coupée à quelques lignes, qu'un clic déplie.
struct ListeRepliable<Element: Identifiable, Ligne: View>: View {
    let elements: [Element]
    var limite = 5
    @ViewBuilder let ligne: (Element) -> Ligne
    @State private var depliee = false

    var body: some View {
        ForEach(depliee ? elements : Array(elements.prefix(limite))) { ligne($0) }
        if !depliee, elements.count > limite {
            let reste = elements.count - limite
            Button(reste > 1 ? "Voir les \(reste) autres" : "Voir la dernière") { depliee = true }
                .buttonStyle(.plain)
                .foregroundStyle(Color.terracottaTexte)
                .padding(.top, 10)
        }
    }
}

struct LigneAction: View {
    let modele: ModeleApp
    let action: ActionOuverte
    var montrerReunion = true

    private var details: String {
        var morceaux = [action.element.responsable, action.element.echeance].compactMap { $0 }
        if montrerReunion { morceaux.append(action.reunion.meta.titre) }
        morceaux += action.element.sources.prefix(1).map { horodatage($0) }
        return morceaux.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { modele.cocher(action) } label: {
                Rectangle().strokeBorder(Color.encre, lineWidth: 2).frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel("Marquer comme fait : \(action.element.texte)")
            Button { modele.ouvrir(action.reunion, moment: action.element.sources.first) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.element.texte).multilineTextAlignment(.leading)
                    Text(details).font(Typo.horodatage).foregroundStyle(Color.encreDouce)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Color.filet.frame(height: 1) }
    }
}

/// Les actions ouvertes : celles dont une échéance a été dite d'abord, les autres repliées.
struct SectionActions: View {
    let modele: ModeleApp
    let actions: [ActionOuverte]
    var montrerReunion = true

    var body: some View {
        let rangees = rangerActions(actions)
        VStack(alignment: .leading, spacing: 18) {
            if actions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Libelle("à faire")
                    Text("Aucune action ouverte.").foregroundStyle(Color.encreDouce)
                }
            }
            if !rangees.avecEcheance.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Libelle("à faire · échéance dite · \(rangees.avecEcheance.count)").padding(.bottom, 8)
                    ForEach(rangees.avecEcheance) { LigneAction(modele: modele, action: $0, montrerReunion: montrerReunion) }
                }
            }
            if !rangees.sansEcheance.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Libelle("à faire · sans échéance · \(rangees.sansEcheance.count)").padding(.bottom, 8)
                    ListeRepliable(elements: rangees.sansEcheance) { LigneAction(modele: modele, action: $0, montrerReunion: montrerReunion) }
                }
            }
        }
    }
}

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
