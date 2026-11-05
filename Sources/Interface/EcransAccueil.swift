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
    var body: some View {
        let actions = modele.actionsOuvertes()
        EcranLecture(phrase: phraseEtat(actions: actions, derniere: modele.reunions.first { $0.id != modele.session?.reunion.id },
                                        enCours: modele.session?.reunion.meta.titre)) {
            Libelle(Date().formatted(.dateTime.locale(Locale(identifier: "fr_FR")).weekday(.wide).day().month(.wide)))
            TitreEcran(debut: "Bonjour, ", fin: "Steven")
        } commandes: {
            EmptyView()
        } contenu: {
            SectionActions(modele: modele, actions: actions)
            VStack(alignment: .leading, spacing: 0) {
                Libelle("réunions récentes").padding(.bottom, 8)
                if modele.reunions.isEmpty {
                    Text("Pas encore de réunion.").foregroundStyle(Color.encreDouce)
                }
                ForEach(modele.reunions.prefix(5)) { LigneReunion(modele: modele, reunion: $0) }
                if modele.reunions.count > 5 {
                    Button("Voir toutes les réunions") { modele.ecran = .toutes }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.terracottaTexte)
                        .padding(.top, 10)
                }
            }
        }
    }
}

struct EcranToutes: View {
    @Bindable var modele: ModeleApp

    var body: some View {
        EcranLecture {
            Libelle(accord(modele.reunions.count, "réunion"))
            TitreEcran(debut: "Toutes les ", fin: "réunions")
        } commandes: {
            EmptyView()
        } contenu: {
            VStack(alignment: .leading, spacing: 0) {
                if modele.reunions.isEmpty {
                    Text("Pas encore de réunion.").foregroundStyle(Color.encreDouce)
                }
                ForEach(modele.reunions) { LigneReunion(modele: modele, reunion: $0) }
            }
        }
    }
}

