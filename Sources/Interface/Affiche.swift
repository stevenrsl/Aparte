import Analyse
import AppKit
import DA
import SwiftUI
import Stockage

// Les pièces communes des écrans « Affiche » : l'aplat de titre, la page de lecture, le sommaire des
// réunions, les actions avec leurs pastilles. Voir docs/brief-da-reunions.md.

let francaisAffiche = Locale(identifier: "fr_FR")

/// Un surtitre : capitales en SF Pro Expanded, espacées.
struct Etiquette: View {
    let texte: String
    var couleur: Color = Couleur.texteDiscret

    init(_ texte: String, couleur: Color = Couleur.texteDiscret) {
        self.texte = texte
        self.couleur = couleur
    }

    var body: some View {
        Text(texte.uppercased(with: francaisAffiche)).font(Ecriture.etiquette).tracking(0.8).foregroundStyle(couleur)
    }
}

/// La taille du titre sur l'aplat : grande pour un titre court, plus petite pour un long.
func tailleTitreAffiche(_ titre: String, grand: CGFloat = 50) -> CGFloat {
    titre.count > 72 ? 32 : titre.count > 40 ? 40 : titre.count > 20 ? min(grand, 44) : grand
}

/// L'aplat de titre d'un écran : surtitre, titre en New York Black, ce qui se fait à droite, et dessous.
struct EnteteAffiche<Droite: View, Dessous: View>: View {
    var couleur: Color = Couleur.aplat
    let surtitre: String
    let titre: String
    var grand: CGFloat = 50
    @ViewBuilder var droite: Droite
    @ViewBuilder var dessous: Dessous

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.s4) {
            HStack(alignment: .bottom, spacing: Espace.s6) {
                VStack(alignment: .leading, spacing: Espace.s2) {
                    Etiquette(surtitre, couleur: Couleur.surAplat)
                    if !titre.isEmpty {
                        Text(titre).font(Ecriture.une(tailleTitreAffiche(titre, grand: grand)))
                            .lineSpacing(-6)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                Spacer(minLength: Espace.s4)
                droite
            }
            dessous
        }
        .padding(.horizontal, Espace.s10)
        .padding(.top, Espace.s10 + Espace.s4)
        .padding(.bottom, Espace.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(couleur)
        .foregroundStyle(Couleur.surAplat)
        .tint(Couleur.surAplat)
    }
}

extension EnteteAffiche where Dessous == EmptyView {
    init(couleur: Color = Couleur.aplat, surtitre: String, titre: String, grand: CGFloat = 50, @ViewBuilder droite: () -> Droite) {
        self.init(couleur: couleur, surtitre: surtitre, titre: titre, grand: grand, droite: droite, dessous: { EmptyView() })
    }
}

/// Une page : l'aplat, puis la lecture sur le papier.
struct PageAffiche<Entete: View, Contenu: View>: View {
    @ViewBuilder var entete: Entete
    @ViewBuilder var contenu: Contenu

    var body: some View {
        VStack(spacing: 0) {
            entete
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.s8) { contenu }
                    .frame(maxWidth: 1040, alignment: .leading)
                    .padding(.horizontal, Espace.s10)
                    .padding(.top, Espace.s8)
                    .padding(.bottom, Espace.s10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Couleur.papier)
    }
}

/// Le bouton secondaire, sur le papier : une capsule cerclée.
struct BoutonCercle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Ecriture.interfaceForte)
            .padding(.horizontal, Espace.s4)
            .padding(.vertical, Espace.s2)
            .overlay(Capsule().strokeBorder(Couleur.texte, lineWidth: 1))
            .foregroundStyle(Couleur.texte)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .fixedSize()
    }
}

/// Un lien d'interface, dans la couleur des liens.
struct BoutonLien: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Ecriture.interfaceForte)
            .foregroundStyle(Couleur.lien)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// « Garder sur ce Mac » posé sur l'aplat : une petite carte de papier, pour que l'interrupteur se lise.
struct CarteGarder: View {
    let actif: Bool
    let detail: String
    var desactive = false
    let changer: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { actif }, set: changer)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Garder sur ce Mac").font(Ecriture.interfaceForte).foregroundStyle(Couleur.texte)
                Text(detail).font(Ecriture.detail).foregroundStyle(Couleur.texteDoux)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .tint(Couleur.aplat)
        .disabled(desactive)
        .padding(.horizontal, Espace.s4)
        .padding(.vertical, Espace.s3)
        .frame(width: 280, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Rayon.moyen).fill(Couleur.papier))
    }
}

// MARK: - Le sommaire des réunions

/// Où en est une réunion, en quelques mots, et son avancée si son compte rendu se prépare.
@MainActor func etatReunion(_ modele: ModeleApp, _ reunion: Reunion) -> (texte: String, avancee: Double?) {
    if modele.session?.reunion.id == reunion.id { return ("Enregistrement en cours", nil) }
    if let avancee = modele.relectures[reunion.id] { return ("Relecture de l’enregistrement", avancee) }
    if let avancee = modele.analyses[reunion.id] { return ("Compte rendu en préparation", avancee) }
    if let compteRendu = modele.resumeEnregistre(de: reunion) {
        let decisions = compteRendu.decisions.isEmpty ? "aucune décision" : accord(compteRendu.decisions.count, "décision")
        let actions = compteRendu.actions.isEmpty ? "aucune action" : accord(compteRendu.actions.count, "action")
        return ("\(decisions) · \(actions)", nil)
    }
    if modele.echecsAnalyseAuto[reunion.id] != nil { return ("Compte rendu non rédigé", nil) }
    return ("Pas encore de compte rendu", nil)
}

/// Une réunion dans le sommaire : sa date, son titre, son dossier et son état, sa durée en grand.
struct LigneSommaire: View {
    let modele: ModeleApp
    let reunion: Reunion
    var montrerDossier = true

    var body: some View {
        let etat = etatReunion(modele, reunion)
        let gardee = modele.gardeeSurCeMac(reunion)
        Button { modele.ouvrir(reunion) } label: {
            HStack(alignment: .firstTextBaseline, spacing: Espace.s4) {
                Text(reunion.meta.date.formatted(.dateTime.locale(francaisAffiche).weekday(.abbreviated).day().month(.abbreviated)))
                    .font(Ecriture.horodatage).foregroundStyle(Couleur.texteDiscret)
                    .frame(width: 92, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(reunion.meta.titre).font(Ecriture.lectureForte).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: Espace.s2) {
                        let morceaux = [montrerDossier ? reunion.dossier : nil, etat.avancee == nil ? etat.texte : nil].compactMap { $0 }
                        if !morceaux.isEmpty {
                            Text(morceaux.joined(separator: " · ")).font(Ecriture.citation).foregroundStyle(Couleur.texteDoux).lineLimit(1)
                        }
                        if gardee {
                            Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Couleur.texteDiscret)
                                .accessibilityLabel("gardée sur ce Mac")
                        }
                    }
                    if let avancee = etat.avancee {
                        HStack(spacing: Espace.s2) {
                            Etiquette(etat.texte, couleur: Couleur.lien)
                            ProgressView(value: min(max(avancee, 0), 1)).progressViewStyle(.linear).tint(Couleur.lien).frame(width: 120)
                        }
                    }
                }
                Spacer(minLength: Espace.s3)
                Text("\(Int((reunion.meta.duree / 60).rounded()))′").font(Ecriture.une(20))
                    .accessibilityLabel(accord(Int((reunion.meta.duree / 60).rounded()), "minute"))
            }
            .padding(.vertical, Espace.s3)
            .overlay(alignment: .top) { Couleur.filet.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ouvre la réunion")
    }
}

/// Le sommaire, coupé à quelques lignes qu'un clic déplie.
struct Sommaire: View {
    let modele: ModeleApp
    let reunions: [Reunion]
    var limite: Int? = nil
    var montrerDossier = true
    var suite: (() -> Void)? = nil
    @State private var depliee = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let visibles = depliee || limite == nil ? reunions : Array(reunions.prefix(limite!))
            ForEach(visibles) { LigneSommaire(modele: modele, reunion: $0, montrerDossier: montrerDossier) }
            Couleur.filet.frame(height: 1)
            if let limite, !depliee, reunions.count > limite {
                Button(suite == nil ? "Voir les \(reunions.count - limite) autres" : "Voir toutes les réunions") {
                    if let suite { suite() } else { depliee = true }
                }
                .buttonStyle(BoutonLien())
                .padding(.top, Espace.s3)
            }
        }
    }
}

// MARK: - Les actions ouvertes

/// Une action à faire : la case, la pastille et le nom s'ils ont été dits, le texte, l'échéance, d'où elle vient.
struct LigneActionAffiche: View {
    let modele: ModeleApp
    let action: ActionOuverte
    var montrerReunion = true

    var body: some View {
        HStack(alignment: .top, spacing: Espace.s3) {
            Button { modele.cocher(action) } label: {
                Circle().strokeBorder(Couleur.texte, lineWidth: 1.3).frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel("Marquer comme fait : \(action.element.texte)")
            if let responsable = action.element.responsable {
                PastillePersonne(responsable, taille: 20)
            } else {
                Circle().strokeBorder(Couleur.texteDiscret, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
            Button { modele.ouvrir(action.reunion, moment: action.element.sources.first) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    (Text(action.element.responsable.map { "\($0)  " } ?? "").font(Ecriture.personne)
                     + Text(action.element.texte).font(Ecriture.lecture)
                     + (action.element.echeance.map { Text("  \($0)").font(Ecriture.echeance).foregroundStyle(Couleur.ocre) } ?? Text("")))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    let origine = [montrerReunion ? action.reunion.meta.titre : nil, action.element.sources.first.map { horodatage($0) }].compactMap { $0 }
                    if !origine.isEmpty {
                        Etiquette(origine.joined(separator: " · "))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(([action.element.texte] + [action.element.responsable, action.element.echeance].compactMap { $0 }
                                 + (montrerReunion ? [action.reunion.meta.titre] : [])).joined(separator: ", "))
            .accessibilityHint("Ouvre le compte rendu à ce moment")
        }
        .padding(.vertical, Espace.s3)
        .overlay(alignment: .top) { Couleur.filet.frame(height: 1) }
    }
}

/// Les actions ouvertes : celles dont une échéance a été dite d'abord, les autres ensuite, repliées.
struct ListeActions: View {
    let modele: ModeleApp
    let actions: [ActionOuverte]
    var montrerReunion = true
    var limite = 6
    @State private var depliee = false

    var body: some View {
        let rangees = rangerActions(actions)
        let toutes = rangees.avecEcheance + rangees.sansEcheance
        VStack(alignment: .leading, spacing: 0) {
            if actions.isEmpty {
                Text("Rien à faire pour l’instant.").font(Ecriture.citation).foregroundStyle(Couleur.texteDoux).padding(.vertical, Espace.s2)
            }
            ForEach(depliee ? toutes : Array(toutes.prefix(limite))) { LigneActionAffiche(modele: modele, action: $0, montrerReunion: montrerReunion) }
            if !actions.isEmpty { Couleur.filet.frame(height: 1) }
            if !depliee, toutes.count > limite {
                Button(toutes.count - limite > 1 ? "Voir les \(toutes.count - limite) autres" : "Voir la dernière") { depliee = true }
                    .buttonStyle(BoutonLien())
                    .padding(.top, Espace.s3)
            }
        }
    }
}
