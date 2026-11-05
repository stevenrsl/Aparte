import Analyse
import AppKit
import Capture
import DA
import SwiftUI
import Stockage
import Transcription

// MARK: - Dossier

/// Quel sujet va dans quel dossier. Steven choisit, rien ne s'écrit avant son clic, et la réunion reste entière.
struct Repartition: View {
    let modele: ModeleApp
    let reunion: Reunion
    let sujets: [Sujet]
    @Environment(\.dismiss) private var fermer
    @State private var choix: [UUID: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Répartir entre dossiers").font(Typo.titreSection)
            Text("Chaque dossier choisi reçoit un extrait avec ses sujets, sans l'audio. La réunion reste telle quelle.")
                .foregroundStyle(Color.encreDouce)
            ForEach(sujets) { sujet in
                Picker(selection: Binding(get: { choix[sujet.id] ?? "" }, set: { choix[sujet.id] = $0.isEmpty ? nil : $0 })) {
                    Text("Ne pas répartir").tag("")
                    ForEach(modele.dossiers, id: \.self) { Text($0).tag($0) }
                } label: {
                    Text("\(horodatage(sujet.debut)) · \(sujet.titre)")
                }
            }
            HStack {
                Spacer()
                Button("Annuler") { fermer() }.buttonStyle(BoutonSecondaire())
                Button("Créer les extraits") {
                    modele.repartir(reunion, choix)
                    fermer()
                }
                .buttonStyle(BoutonPrincipal())
                .disabled(choix.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(Color.creme)
        .foregroundStyle(Color.encre)
        .font(Typo.texte)
    }
}

/// Renommer, ranger ou jeter une réunion. Rien de tout ça ne touche à ce qu'elle contient.
struct GestionReunion: View {
    let modele: ModeleApp
    let reunion: Reunion
    /// Avant de bouger les fichiers : la lecture en cours s'arrête.
    let avant: () -> Void
    @State private var titre = ""
    @State private var nomDossier = ""
    @State private var renomme = false
    @State private var nouveauDossier = false
    @State private var corbeille = false
    @State private var repartition = false

    var body: some View {
        Menu {
            Button("Renommer…") {
                titre = reunion.meta.titre
                renomme = true
            }
            Menu("Déplacer vers") {
                Button("Sans dossier") { avant(); modele.deplacer(reunion, vers: nil) }
                    .disabled(reunion.dossier == nil)
                ForEach(modele.dossiers, id: \.self) { dossier in
                    Button(dossier) { avant(); modele.deplacer(reunion, vers: dossier) }
                        .disabled(reunion.dossier == dossier)
                }
                Divider()
                Button("Nouveau dossier…") {
                    nomDossier = ""
                    nouveauDossier = true
                }
            }
            Button("Répartir entre dossiers…") { repartition = true }
                .disabled((modele.resumeEnregistre(de: reunion)?.sujets ?? []).isEmpty)
            Button("Relire l'enregistrement") { modele.relire(reunion) }
                .disabled(!FileManager.default.fileExists(atPath: reunion.micro.path))
            Divider()
            Button("Mettre à la corbeille…", role: .destructive) { corbeille = true }
        } label: {
            Libelle("gérer")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(modele.estEnCours(reunion))
        .accessibilityLabel("Gérer la réunion")
        .sheet(isPresented: $repartition) {
            Repartition(modele: modele, reunion: reunion, sujets: modele.compteRendu(de: reunion)?.sujets ?? [])
        }
        .alert("Renommer la réunion", isPresented: $renomme) {
            TextField("Titre", text: $titre)
            Button("Renommer") { avant(); modele.renommer(reunion, en: titre) }
            Button("Annuler", role: .cancel) {}
        }
        .alert("Nouveau dossier", isPresented: $nouveauDossier) {
            TextField("Nom du dossier", text: $nomDossier)
            Button("Créer et déplacer") { avant(); modele.deplacer(reunion, versNouveauDossier: nomDossier) }
            Button("Annuler", role: .cancel) {}
        }
        .alert("Mettre « \(reunion.meta.titre) » à la corbeille ?", isPresented: $corbeille) {
            Button("Mettre à la corbeille", role: .destructive) { avant(); modele.mettreALaCorbeille(reunion) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("L'audio, la transcription, tes notes et le compte rendu y partent ensemble. Tu pourras les récupérer depuis la Corbeille.")
        }
    }
}

struct EcranDossier: View {
    @Bindable var modele: ModeleApp
    let nom: String

    private var reunions: [Reunion] { modele.reunions.filter { $0.dossier == nom } }

    /// Une décision et la réunion où elle a été prise, de la plus récente à la plus ancienne.
    private struct DecisionDatee: Identifiable {
        let reunion: Reunion
        let decision: ElementSource
        var id: UUID { decision.id }
    }

    private var decisions: [DecisionDatee] {
        reunions.flatMap { reunion in
            (modele.resumeEnregistre(de: reunion)?.decisions ?? []).map { DecisionDatee(reunion: reunion, decision: $0) }
        }
    }

    var body: some View {
        let actions = modele.actionsOuvertes(dossier: nom)
        EcranLecture(phrase: "\(accord(actions.count, "action ouverte", "actions ouvertes")), \(accord(decisions.count, "décision")).") {
            Libelle("dossier · \(accord(reunions.count, "réunion"))")
            TitreEcran(debut: nom, fin: "")
        } commandes: {
            EmptyView()
        } contenu: {
            SectionActions(modele: modele, actions: actions, montrerReunion: reunions.count > 1)
            if !decisions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Libelle("dernières décisions").padding(.bottom, 8)
                    ListeRepliable(elements: decisions) { element in
                        Button { modele.ecran = .compteRendu(element.reunion) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(element.decision.texte).multilineTextAlignment(.leading)
                                Text(element.reunion.meta.titre + (element.decision.sources.first.map { " · \(horodatage($0))" } ?? ""))
                                    .font(Typo.horodatage)
                                    .foregroundStyle(Color.encreDouce)
                            }
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .top) { Color.filet.frame(height: 1) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Libelle("le fil").padding(.bottom, 8)
                ForEach(reunions) { LigneReunion(modele: modele, reunion: $0, montrerDossier: false) }
            }
        }
    }
}

