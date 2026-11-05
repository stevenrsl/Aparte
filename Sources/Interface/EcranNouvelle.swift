import Analyse
import AppKit
import Capture
import DA
import SwiftUI
import Stockage
import Transcription

// MARK: - Nouvelle réunion

struct EcranNouvelle: View {
    @Bindable var modele: ModeleApp
    @State private var titre = ""
    @State private var type = TypeReunion.visio
    @State private var dossier = ""
    @State private var nouveauDossier = ""
    private let choixNouveau = "\u{0}nouveau"
    @State private var entree: EntreeAudio?
    @State private var entrees: [EntreeAudio] = []
    @State private var niveaux: [Float] = Array(repeating: 0, count: 28)
    @State private var test: TestMicro?
    @State private var demarrage = false

    private var entendu: Bool { (niveaux.max() ?? 0) > 0.2 }

    var body: some View {
        Colonnes {
            Libelle("nouvelle réunion")
            TitreEcran(debut: "Avant de ", fin: "commencer")
        } contenu: {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Libelle("titre")
                    TextField("Point montage, documentaire voile", text: $titre)
                        .textFieldStyle(.plain)
                        .font(Typo.titreListe)
                        .padding(12)
                        .background(Color.champ)
                        .overlay { Rectangle().strokeBorder(Color.encre, lineWidth: 1) }
                }
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Libelle("dossier")
                        Picker("Dossier", selection: $dossier) {
                            Text("Aucun").tag("")
                            ForEach(modele.dossiers, id: \.self) { Text($0).tag($0) }
                            Text("Nouveau dossier…").tag(choixNouveau)
                        }
                        .labelsHidden()
                        if dossier == choixNouveau {
                            TextField("Nom du dossier", text: $nouveauDossier)
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(Color.champ)
                                .overlay { Rectangle().strokeBorder(Color.filet, lineWidth: 1) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Libelle("type")
                        Picker("Type", selection: $type) {
                            Text("Visio · micro + son du Mac").tag(TypeReunion.visio)
                            Text("Présentiel · micro").tag(TypeReunion.presentiel)
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                    }
                }
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Libelle("micro")
                        Picker("Micro", selection: $entree) {
                            Text("Micro par défaut").tag(EntreeAudio?.none)
                            ForEach(entrees) { Text($0.nom).tag(EntreeAudio?.some($0)) }
                        }
                        .labelsHidden()
                    }
                }
                Button("Annuler") { modele.revenir() }
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 14) {
                    Rectangle().fill(Color.terracotta).frame(width: 8, height: 8).padding(.top, 6)
                    Text("Pense à prévenir les participants que tu enregistres. Une phrase au début suffit.")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 26)
        } enteteEncre: {
            Libelle("prêt à enregistrer", surColonne: true)
            Spacer(minLength: 0)
            Text("00:00").font(Typo.chrono).monospacedDigit().foregroundStyle(Color.chronoRepos)
        } contenuEncre: {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Libelle("test du micro · parle pour vérifier", surColonne: true)
                    Niveaux(valeurs: niveaux, couleur: .argile, point: 7, hauteur: 6)
                    Text(test == nil ? "Le micro sera demandé au démarrage." : (entendu ? "Le micro t'entend bien." : "Parle pour vérifier."))
                        .foregroundStyle(Color.colonneDoux)
                }
                if type == .visio {
                    VStack(alignment: .leading, spacing: 10) {
                        Libelle("son du mac", surColonne: true)
                        Text("Le son de la visio sera capté dès qu'elle commence. L'autorisation est demandée au premier enregistrement.")
                            .foregroundStyle(Color.colonneDoux)
                    }
                }
                Spacer(minLength: 0)
                Libelle("l'audio ne quitte jamais ce mac", surColonne: true)
                Button {
                    demarrer()
                } label: {
                    HStack {
                        Rectangle().fill(Color.terracotta).frame(width: 12, height: 12)
                        Text(demarrage ? "Préparation…" : "Démarrer l'enregistrement")
                        Spacer()
                        Text("⌘↩").font(Typo.horodatage)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BoutonSignal())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(demarrage || modele.session != nil)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
        }
        .onAppear {
            dossier = modele.dossierCourant ?? ""
            entrees = EntreeAudio.liste()
            lancerTest()
        }
        .onChange(of: entree) { _, _ in lancerTest() }
        .onDisappear {
            test?.arreter()
            test = nil
        }
    }

    private func lancerTest() {
        test?.arreter()
        test = nil
        guard MicrophoneSource.accesAccorde else { return }
        let niveauxBinding = $niveaux
        let nouveau = TestMicro(entree: entree?.id) { niveau in
            Task { @MainActor in
                niveauxBinding.wrappedValue.removeFirst()
                niveauxBinding.wrappedValue.append(niveau)
            }
        }
        if (try? nouveau.demarrer()) != nil { test = nouveau }
    }

    private func demarrer() {
        demarrage = true
        test?.arreter()
        test = nil
        Task {
            var choisi: String? = dossier.isEmpty || dossier == choixNouveau ? nil : dossier
            if dossier == choixNouveau {
                let nom = nouveauDossier.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !nom.isEmpty else { modele.erreur = "Donne un nom au dossier."; demarrage = false; return }
                do { choisi = try modele.bibliotheque?.creerDossier(nom) }
                catch { modele.erreur = error.localizedDescription; demarrage = false; return }
            }
            await modele.demarrer(titre: titre, type: type, dossier: choisi, entree: entree)
            demarrage = false
        }
    }
}

