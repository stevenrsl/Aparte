import Analyse
import AppKit
import Capture
import DA
import SwiftUI
import Stockage
import Transcription

// MARK: - La charpente

/// Quitter pendant une réunion demande confirmation, et termine la réunion proprement.
@MainActor
public final class DelegueAparte: NSObject, NSApplicationDelegate {
    public var modele: ModeleApp?

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let modele, modele.session != nil else { return .terminateNow }
        let alerte = NSAlert()
        alerte.messageText = "Une réunion est en cours"
        alerte.informativeText = "Si tu quittes, Aparté termine la réunion d'abord et écrit les derniers mots."
        alerte.addButton(withTitle: "Continuer la réunion")
        alerte.addButton(withTitle: "Terminer la réunion et quitter")
        guard alerte.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        Task {
            await modele.terminer()
            // Si l'écriture a échoué, la session reste : on ne quitte pas, l'erreur est affichée.
            sender.reply(toApplicationShouldTerminate: modele.session == nil)
        }
        return .terminateLater
    }
}

public struct FenetreAparte: View {
    @Bindable var modele: ModeleApp

    public init(modele: ModeleApp) {
        self.modele = modele
    }

    public var body: some View {
        HStack(spacing: 0) {
            if modele.racine != nil {
                BarreLaterale(modele: modele)
                Couleur.filet.frame(width: 1)
            }
            contenu
        }
        .ignoresSafeArea()
        .background(Couleur.papier)
        .foregroundStyle(Couleur.texte)
        .font(Ecriture.interface)
        .tint(Couleur.lien)
        .alert("Un problème est survenu", isPresented: Binding(get: { modele.erreur != nil }, set: { if !$0 { modele.erreur = nil } })) {
            Button("Compris", role: .cancel) {}
        } message: {
            Text(modele.erreur ?? "")
        }
    }

    @ViewBuilder private var contenu: some View {
        if modele.racine == nil {
            PremierLancement(modele: modele)
        } else {
            switch modele.ecran {
            case .accueil: EcranAccueil(modele: modele)
            case .toutes: EcranToutes(modele: modele)
            case .nouvelle: EcranNouvelle(modele: modele)
            case .enReunion:
                if let session = modele.session {
                    EcranEnReunion(modele: modele, session: session)
                } else {
                    EcranAccueil(modele: modele)
                }
            case let .compteRendu(reunion, moment): EcranCompteRendu(modele: modele, reunion: reunion, moment: moment).id(reunion.id)
            case let .dossier(nom): EcranDossier(modele: modele, nom: nom).id(nom)
            case .reglages: EcranReglages(modele: modele)
            }
        }
    }
}

/// Le nom de l'app, en New York Black italique : la marque tient dans sa typographie.
struct MarqueAparte: View {
    var taille: CGFloat = 26
    var body: some View {
        Text("Aparté").font(Ecriture.une(taille).italic()).accessibilityLabel("Aparté")
    }
}

struct PremierLancement: View {
    let modele: ModeleApp

    var body: some View {
        VStack(spacing: 0) {
            EnteteAffiche(surtitre: "Bienvenue dans Aparté", titre: "Où ranger tes réunions ?") { EmptyView() }
            VStack(alignment: .leading, spacing: Espace.s4) {
                Text("Chaque réunion est un dossier lisible sans l’app. Tu peux choisir un dossier dans iCloud Drive : ça reste ton choix, Aparté ne synchronise rien.")
                    .font(Ecriture.chapo).foregroundStyle(Couleur.texteDoux)
                    .frame(maxWidth: 560, alignment: .leading)
                Button("Choisir un dossier") { modele.choisirEmplacement() }
                    .buttonStyle(BoutonAplat())
            }
            .padding(Espace.s10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Couleur.papier)
    }
}

/// La barre latérale : démarrer, toujours à portée, puis où aller. Un dossier gardé sur ce Mac porte un cadenas.
struct BarreLaterale: View {
    @Bindable var modele: ModeleApp
    @State private var demarrage = false

    private func demarrer(_ type: TypeReunion) {
        demarrage = true
        let dossier = modele.dossierCourant
        Task {
            await modele.demarrer(titre: "", type: type, dossier: dossier, entree: nil)
            demarrage = false
        }
    }

    var body: some View {
        let _ = modele.dossiersVersion
        VStack(alignment: .leading, spacing: 0) {
            MarqueAparte()
                .padding(.top, Espace.s10 + Espace.s4)
                .padding(.bottom, Espace.s6)
                .padding(.horizontal, Espace.s2)
            if let session = modele.session {
                reunionEnCours(session)
            } else {
                demarrage(modele.dossierCourant)
            }
            VStack(alignment: .leading, spacing: 2) {
                EntreeLaterale(titre: "Accueil", icone: "house", active: modele.origineNavigation == .accueil) { modele.ecran = .accueil }
                EntreeLaterale(titre: "Toutes les réunions", icone: "list.bullet", active: modele.origineNavigation == .toutes,
                               compte: modele.reunions.count) { modele.ecran = .toutes }
            }
            .padding(.top, Espace.s6)
            Etiquette("Dossiers").padding(.horizontal, Espace.s2).padding(.top, Espace.s6).padding(.bottom, Espace.s2)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if modele.dossiers.isEmpty {
                        Text("Pas encore de dossier.").font(Ecriture.detail).foregroundStyle(Couleur.texteDiscret).padding(.horizontal, Espace.s2)
                    }
                    ForEach(modele.dossiers, id: \.self) { nom in
                        EntreeLaterale(titre: nom, icone: "folder", active: modele.origineNavigation == .dossier(nom),
                                       compte: modele.reunions.filter { $0.dossier == nom }.count,
                                       garde: modele.dossierGardeSurCeMac(nom)) { modele.ecran = .dossier(nom) }
                    }
                }
            }
            Spacer(minLength: 0)
            EntreeLaterale(titre: "Réglages", icone: "gearshape", active: modele.origineNavigation == .reglages) { modele.ecran = .reglages }
                .padding(.bottom, Espace.s4)
        }
        .padding(.horizontal, Espace.s3)
        .frame(width: 236)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Couleur.marge)
    }

    /// Démarrer en visio d'un clic ; le présentiel et la préparation juste dessous.
    private func demarrage(_ dossier: String?) -> some View {
        VStack(alignment: .leading, spacing: Espace.s2) {
            Button { demarrer(.visio) } label: {
                Label("Démarrer en visio", systemImage: "record.circle").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(BoutonAplat())
            .keyboardShortcut("n", modifiers: .command)
            HStack(spacing: Espace.s4) {
                Button("En présentiel") { demarrer(.presentiel) }.buttonStyle(BoutonLien())
                Button("Préparer…") { modele.preparerReunion() }.buttonStyle(BoutonLien())
            }
            .padding(.horizontal, Espace.s2)
            if let dossier {
                Text("Dans « \(dossier) »").font(Ecriture.detail).foregroundStyle(Couleur.texteDiscret).padding(.horizontal, Espace.s2)
            }
        }
        .disabled(demarrage)
    }

    /// La réunion en cours : son chrono, et le chemin pour y revenir.
    private func reunionEnCours(_ session: SessionReunion) -> some View {
        Button { modele.ouvrirReunionEnCours() } label: {
            VStack(alignment: .leading, spacing: Espace.s1) {
                HStack(spacing: Espace.s2) {
                    Circle().fill(Couleur.surAplat).frame(width: 8, height: 8)
                    Etiquette(session.captureArretee ? (session.finalisationEnCours ? "Finalisation" : "Arrêté") : "En cours", couleur: Couleur.surAplat)
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(horodatage(session.temps)).font(Ecriture.horodatageFort)
                    }
                }
                Text(session.titre.isEmpty ? "Réunion" : session.titre).font(Ecriture.lectureForte).lineLimit(2).multilineTextAlignment(.leading)
                Text("Revenir à la réunion").font(Ecriture.detail).opacity(0.85)
            }
            .padding(Espace.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Rayon.moyen).fill(Couleur.aplatDirect))
            .foregroundStyle(Couleur.surAplat)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Réunion en cours : \(session.titre). Revenir à la réunion")
    }
}

struct EntreeLaterale: View {
    let titre: String
    var icone: String? = nil
    let active: Bool
    var compte: Int?
    var garde = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Espace.s2) {
                if let icone {
                    Image(systemName: icone).font(.system(size: 12)).frame(width: 18)
                        .foregroundStyle(active ? Couleur.lien : Couleur.texteDoux)
                }
                Text(titre).font(active ? Ecriture.interfaceForte : Ecriture.interface).lineLimit(1)
                if garde {
                    Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Couleur.texteDiscret)
                        .help("Gardé sur ce Mac")
                }
                Spacer(minLength: 0)
                if let compte {
                    Text("\(compte)").font(Ecriture.horodatage).foregroundStyle(Couleur.texteDiscret)
                }
            }
            .padding(.horizontal, Espace.s2)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Rayon.petit + 2).fill(active ? Couleur.selection : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Couleur.texte)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityValue(garde ? "gardé sur ce Mac" : "")
    }
}

/// Les deux colonnes, leurs en-têtes de 172 pt fermés sur le même filet.
struct Colonnes<Entete: View, Contenu: View, EnteteEncre: View, ContenuEncre: View>: View {
    var transcriptionClaire = false
    @ViewBuilder let entete: Entete
    @ViewBuilder let contenu: Contenu
    @ViewBuilder let enteteEncre: EnteteEncre
    @ViewBuilder let contenuEncre: ContenuEncre

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) { entete }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                    .frame(height: 172, alignment: .bottomLeading)
                    .overlay(alignment: .bottom) { Color.filet.frame(height: 1) }
                contenu.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Color.creme)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) { enteteEncre }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: 172, alignment: .topLeading)
                    .overlay(alignment: .bottom) { (transcriptionClaire ? Color.filet : Color.colonneFilet).frame(height: 1) }
                contenuEncre.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: 420)
            .background(transcriptionClaire ? Color.transcriptionFond : Color.encreColonne)
            .foregroundStyle(transcriptionClaire ? Color.encre : Color.colonneTexte)
        }
    }
}

struct TitreEcran: View {
    let debut: String
    let fin: String

    var body: some View {
        (Text(debut) + Text(fin).italic().foregroundStyle(Color.terracottaTexte))
            .font(Typo.titreEcran)
            .lineLimit(2)
    }
}

/// La charpente de lecture : une colonne dense, sans colonne encre, pour lire et retrouver.
struct EcranLecture<Entete: View, Commandes: View, Contenu: View>: View {
    var phrase: String?
    @ViewBuilder let entete: Entete
    @ViewBuilder let commandes: Commandes
    @ViewBuilder let contenu: Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) { entete }
                    Spacer(minLength: 0)
                    commandes
                }
                if let phrase {
                    Text(phrase).font(Typo.phraseEtat).italic().foregroundStyle(Color.encreDouce)
                }
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 20)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Color.filet.frame(height: 1) }
            ScrollView {
                VStack(alignment: .leading, spacing: 26) { contenu }
                    .frame(maxWidth: 1040, alignment: .leading)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.creme)
    }
}

