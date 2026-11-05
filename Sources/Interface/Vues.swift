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
        VStack(spacing: 0) {
            Color.surface.frame(height: 42)
                .overlay(alignment: .bottom) { Color.filet.frame(height: 1) }
            HStack(spacing: 0) {
                if modele.racine != nil {
                    BarreLaterale(modele: modele)
                }
                contenu
            }
        }
        .ignoresSafeArea()
        .background(Color.creme)
        .foregroundStyle(Color.encre)
        .font(Typo.texte)
        .overlay { GrainOverlay().ignoresSafeArea() }
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

struct PremierLancement: View {
    let modele: ModeleApp

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LogoApparte()
            Text("Où ranger tes réunions ?").font(Typo.titreEcran)
            Text("Chaque réunion est un dossier lisible sans l'app. Tu peux choisir un dossier dans iCloud Drive : ça reste ton choix, Aparté ne synchronise rien.")
                .frame(maxWidth: 480, alignment: .leading)
            Button("Choisir un dossier") { modele.choisirEmplacement() }
                .buttonStyle(BoutonPrincipal())
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

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
        VStack(alignment: .leading, spacing: 18) {
            LogoApparte()
            VStack(alignment: .leading, spacing: 8) {
                if let session = modele.session {
                    Text(session.titre).font(Typo.titreLigne).lineLimit(2)
                    Text("Enregistrement en cours").font(Typo.horodatage)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(horodatage(session.temps)).font(Typo.horodatage).monospacedDigit()
                    }
                    Button("Revenir à la réunion") { modele.ouvrirReunionEnCours() }
                } else {
                    if let dossier = modele.dossierCourant { Libelle("dans \(dossier)") }
                    Button("Démarrer en visio") { demarrer(.visio) }
                    Button("Démarrer en présentiel") { demarrer(.presentiel) }
                    Button("Préparer…") { modele.preparerReunion() }
                        .foregroundStyle(Color.terracottaTexte)
                }
            }
            .disabled(demarrage)
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                EntreeLaterale(titre: "Accueil", active: modele.origineNavigation == .accueil) { modele.ecran = .accueil }
                EntreeLaterale(titre: "Toutes les réunions", active: modele.origineNavigation == .toutes, compte: modele.reunions.count) { modele.ecran = .toutes }
            }
            VStack(alignment: .leading, spacing: 2) {
                Libelle("dossiers").padding(.bottom, 4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(modele.dossiers, id: \.self) { nom in
                            EntreeLaterale(titre: nom, active: modele.origineNavigation == .dossier(nom),
                                           compte: modele.reunions.filter { $0.dossier == nom }.count) { modele.ecran = .dossier(nom) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            EntreeLaterale(titre: "Réglages", active: modele.origineNavigation == .reglages) { modele.ecran = .reglages }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 22)
        .frame(width: 228)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.surface)
        .overlay(alignment: .trailing) { Color.filet.frame(width: 1) }
    }
}

struct EntreeLaterale: View {
    let titre: String
    let active: Bool
    var compte: Int?
    var enCours = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(active ? Color.argile : (enCours ? Color.terracotta : Color.clear))
                    .frame(width: 7, height: 7)
                Text(titre).lineLimit(1)
                Spacer(minLength: 0)
                if let compte {
                    Text("\(compte)").font(Typo.horodatage)
                        .foregroundStyle(active ? Color.colonneTexte : Color.encreDouce)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(active ? Color.encreColonne : Color.clear)
            .foregroundStyle(active ? Color.colonneTexte : Color.encre)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityValue(enCours ? "enregistrement en cours" : "")
    }
}

/// Les deux colonnes, leurs en-têtes de 172 pt fermés sur le même filet.
struct Colonnes<Entete: View, Contenu: View, EnteteEncre: View, ContenuEncre: View>: View {
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
                    .overlay(alignment: .bottom) { Color.colonneFilet.frame(height: 1) }
                contenuEncre.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: 420)
            .background(Color.encreColonne)
            .foregroundStyle(Color.colonneTexte)
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

