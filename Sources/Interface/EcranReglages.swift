import Analyse
import AppKit
import Capture
import DA
import SwiftUI
import Stockage
import Transcription

// MARK: - Réglages

struct EcranReglages: View {
    @Bindable var modele: ModeleApp
    @State private var cle = ""
    @State private var enTest = false
    @State private var resultatTest: String?

    /// Un seul mot part, aucune réunion.
    private func tester() {
        guard let cle = Trousseau.mistral.lire() else { return }
        enTest = true
        Task {
            resultatTest = await AnalysteMistral(cle: cle).tester()
            enTest = false
        }
    }

    var body: some View {
        Colonnes {
            Libelle("réglages")
            TitreEcran(debut: "Tes ", fin: "réglages")
        } contenu: {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Libelle("qui rédige tes comptes rendus")
                    Text(modele.cleMistralPresente ? "Mistral, et ce Mac s'il ne répond pas" : "Ce Mac · Apple Intelligence")
                    Text("Une réunion ou un dossier marqués « Garder sur ce Mac » ne partent jamais chez Mistral.").foregroundStyle(Color.encreDouce)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Libelle("clé mistral")
                    if modele.cleMistralPresente {
                        Text("Une clé est rangée dans le trousseau.").foregroundStyle(Color.encreDouce)
                        HStack(spacing: 10) {
                            Button(enTest ? "Test en cours…" : "Tester la clé") { tester() }
                                .buttonStyle(BoutonSecondaire())
                                .disabled(enTest)
                            Button("Retirer la clé") {
                                modele.enregistrerCleMistral(nil)
                                resultatTest = nil
                            }
                            .buttonStyle(BoutonSecondaire())
                        }
                    } else {
                        SecureField("Colle ta clé d'API", text: $cle)
                            .textFieldStyle(.plain)
                            .padding(6)
                            .background(Color.surface)
                            .accessibilityLabel("Clé d'API Mistral")
                        HStack(spacing: 10) {
                            Button("Enregistrer la clé") {
                                modele.enregistrerCleMistral(cle)
                                cle = ""
                                resultatTest = nil
                            }
                            .buttonStyle(BoutonPrincipal())
                            .disabled(cle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button("Reprendre la clé de Cairn") {
                                let reprise = modele.reprendreCleDeCairn()
                                resultatTest = reprise ? "La clé de Cairn est reprise. Tu peux la tester." : "Aucune clé de Cairn n'a pu être lue."
                            }
                            .buttonStyle(BoutonSecondaire())
                        }
                    }
                    if let resultatTest { Text(resultatTest).foregroundStyle(Color.encreDouce) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Libelle("emplacement des réunions")
                    Text(modele.racine?.path ?? "").textSelection(.enabled)
                    Button("Changer de dossier") { modele.choisirEmplacement() }
                        .buttonStyle(BoutonSecondaire())
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 26)
        } enteteEncre: {
            Libelle("réunions envoyées hors du mac", surColonne: true)
            Spacer(minLength: 0)
            Text("\(modele.reunionsEnvoyees)").font(Typo.grandChiffre)
                .accessibilityLabel("\(accord(modele.reunionsEnvoyees, "réunion envoyée", "réunions envoyées")) hors du Mac")
        } contenuEncre: {
            VStack(alignment: .leading, spacing: 14) {
                Text("L'audio : jamais.")
                Text("La transcription et tes notes : chez Mistral, pour rédiger le compte rendu, sauf ce que tu gardes sur ce Mac.")
                Text("Aucune télémétrie, aucun compte.")
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
        }
    }
}

