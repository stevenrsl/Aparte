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
            Text("Répartir entre dossiers").font(Ecriture.section)
            Text("Chaque dossier choisi reçoit un extrait avec ses sujets, sans l’audio. La réunion reste telle quelle.")
                .font(Ecriture.citation).foregroundStyle(Couleur.texteDoux)
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
                Button("Annuler") { fermer() }.buttonStyle(BoutonCercle())
                Button("Créer les extraits") {
                    modele.repartir(reunion, choix)
                    fermer()
                }
                .buttonStyle(BoutonAplat())
                .disabled(choix.isEmpty)
            }
        }
        .padding(Espace.s6)
        .frame(width: 560)
        .background(Couleur.papier)
        .foregroundStyle(Couleur.texte)
        .font(Ecriture.interface)
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
            Button("Réécouter l’enregistrement pour séparer les voix") { modele.relire(reunion) }
                .disabled(!FileManager.default.fileExists(atPath: reunion.micro.path))
            Divider()
            Button("Mettre à la corbeille…", role: .destructive) { corbeille = true }
        } label: {
            Text("Gérer…")
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
        let _ = modele.dossiersVersion
        let actions = modele.actionsOuvertes(dossier: nom)
        let garde = modele.dossierGardeSurCeMac(nom)
        PageAffiche {
            EnteteAffiche(surtitre: "Dossier · \(accord(reunions.count, "réunion")) · \(accord(actions.count, "action ouverte", "actions ouvertes"))",
                          titre: nom) {
                CarteGarder(actif: garde,
                            detail: garde ? "Les comptes rendus de ce dossier sont rédigés ici. Rien ne part chez Mistral."
                                          : "Mistral rédige les comptes rendus de ce dossier. L’audio reste ici.") {
                    modele.garderSurCeMac(dossier: nom, $0)
                }
            }
        } contenu: {
            if reunions.isEmpty {
                Text("Ce dossier est vide. Une réunion démarrée d’ici y sera rangée.")
                    .font(Ecriture.chapo).foregroundStyle(Couleur.texteDoux)
            } else {
                HStack(alignment: .top, spacing: Espace.s10) {
                    VStack(alignment: .leading, spacing: Espace.s8) {
                        VStack(alignment: .leading, spacing: 0) {
                            TitreSection(numero: "I", titre: "À faire")
                            ListeActions(modele: modele, actions: actions, montrerReunion: reunions.count > 1)
                        }
                        if !decisions.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                TitreSection(numero: "II", titre: "Décisions")
                                ListeDecisions(modele: modele, decisions: decisions.map { ($0.reunion, $0.decision) })
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        TitreSection(numero: decisions.isEmpty ? "II" : "III", titre: "Le fil")
                        Sommaire(modele: modele, reunions: reunions, montrerDossier: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Les décisions d'un dossier, chacune avec sa réunion et son heure, repliées au-delà de six.
struct ListeDecisions: View {
    let modele: ModeleApp
    let decisions: [(reunion: Reunion, decision: ElementSource)]
    @State private var depliee = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array((depliee ? decisions : Array(decisions.prefix(6))).enumerated()), id: \.offset) { _, element in
                Button { modele.ouvrir(element.reunion, moment: element.decision.sources.first) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(element.decision.texte).font(Ecriture.lecture).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Etiquette(([element.reunion.meta.titre] + element.decision.sources.prefix(1).map { horodatage($0) }).joined(separator: " · "))
                    }
                    .padding(.vertical, Espace.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Couleur.filet.frame(height: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvre le compte rendu à ce moment")
            }
            Couleur.filet.frame(height: 1)
            if !depliee, decisions.count > 6 {
                Button("Voir les \(decisions.count - 6) autres") { depliee = true }.buttonStyle(BoutonLien()).padding(.top, Espace.s3)
            }
        }
    }
}
