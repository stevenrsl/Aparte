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
        PageAffiche {
            EnteteAffiche(surtitre: "Nouvelle réunion", titre: "", grand: 44) {
                VStack(alignment: .trailing, spacing: Espace.s2) {
                    Button { demarrer() } label: {
                        Label(demarrage ? "Préparation…" : "Démarrer l’enregistrement", systemImage: "mic.fill")
                            .font(Ecriture.lectureForte)
                            .fixedSize()
                            .padding(.horizontal, Espace.s6).padding(.vertical, Espace.s3)
                            .background(Capsule().fill(Couleur.surAplat))
                            .foregroundStyle(Couleur.aplat)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(demarrage || modele.session != nil)
                    HStack(spacing: Espace.s4) {
                        Text("⌘↩").font(Ecriture.detail)
                        Button("Annuler") { modele.revenir() }.buttonStyle(.plain).font(Ecriture.interfaceForte)
                    }
                }
            } dessous: {
                TextField("Titre", text: $titre, prompt: Text("Titre de la réunion").foregroundStyle(Couleur.surAplat.opacity(0.6)), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Ecriture.une(44))
                    .lineLimit(1...2)
                    .accessibilityLabel("Titre de la réunion")
            }
        } contenu: {
            HStack(alignment: .top, spacing: Espace.s10) {
                VStack(alignment: .leading, spacing: Espace.s6) {
                    TitreSection(numero: "I", titre: "Où et comment")
                    VStack(alignment: .leading, spacing: Espace.s2) {
                        Etiquette("Dossier")
                        Picker("Dossier", selection: $dossier) {
                            Text("Aucun").tag("")
                            ForEach(modele.dossiers, id: \.self) { Text($0).tag($0) }
                            Text("Nouveau dossier…").tag(choixNouveau)
                        }
                        .labelsHidden()
                        .fixedSize()
                        if dossier == choixNouveau {
                            TextField("Nom du dossier", text: $nouveauDossier)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 320)
                        }
                        if !dossier.isEmpty, dossier != choixNouveau, modele.dossierGardeSurCeMac(dossier) {
                            Label("Ce dossier reste sur ce Mac : le compte rendu y sera rédigé.", systemImage: "lock.fill")
                                .font(Ecriture.detail).foregroundStyle(Couleur.texteDoux)
                        }
                    }
                    VStack(alignment: .leading, spacing: Espace.s2) {
                        Etiquette("Type")
                        Picker("Type", selection: $type) {
                            Text("Visio : micro et son du Mac").tag(TypeReunion.visio)
                            Text("Présentiel : micro").tag(TypeReunion.presentiel)
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                    }
                    VStack(alignment: .leading, spacing: Espace.s2) {
                        Etiquette("Micro")
                        Picker("Micro", selection: $entree) {
                            Text("Micro par défaut").tag(EntreeAudio?.none)
                            ForEach(entrees) { Text($0.nom).tag(EntreeAudio?.some($0)) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: Espace.s6) {
                    TitreSection(numero: "II", titre: "Avant de commencer")
                    VStack(alignment: .leading, spacing: Espace.s3) {
                        Etiquette("Test du micro")
                        HStack(alignment: .center, spacing: 3) {
                            ForEach(Array(niveaux.enumerated()), id: \.offset) { _, niveau in
                                Capsule().fill(Couleur.aplat).frame(width: 4, height: max(4, CGFloat(niveau) * 36))
                            }
                        }
                        .frame(height: 40)
                        .accessibilityHidden(true)
                        Text(test == nil ? "Le micro sera demandé au démarrage." : (entendu ? "Le micro t’entend bien." : "Parle pour vérifier."))
                            .font(Ecriture.citation).foregroundStyle(Couleur.texteDoux)
                    }
                    if type == .visio {
                        VStack(alignment: .leading, spacing: Espace.s2) {
                            Etiquette("Son du Mac")
                            Text("Le son de la visio sera capté dès qu’elle commence. L’autorisation est demandée au premier enregistrement.")
                                .font(Ecriture.citation).foregroundStyle(Couleur.texteDoux).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Label("Pense à prévenir les participants que tu enregistres. Une phrase au début suffit.", systemImage: "person.wave.2")
                        .font(Ecriture.interface).foregroundStyle(Couleur.texte)
                        .padding(Espace.s4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Rayon.moyen).fill(Couleur.marge))
                    Label("L’audio ne quitte jamais ce Mac.", systemImage: "lock.fill").font(Ecriture.detail).foregroundStyle(Couleur.texteDoux)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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

