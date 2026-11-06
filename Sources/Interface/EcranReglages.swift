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
        PageAffiche {
            EnteteAffiche(surtitre: "Aparté", titre: "Réglages") { EmptyView() }
        } contenu: {
            HStack(alignment: .top, spacing: Espace.s10) {
                VStack(alignment: .leading, spacing: Espace.s8) {
                    VStack(alignment: .leading, spacing: Espace.s3) {
                        TitreSection(numero: "I", titre: "Qui rédige tes comptes rendus")
                        Text(modele.cleMistralPresente ? "Mistral, et ce Mac s’il ne répond pas." : "Ce Mac, avec Apple Intelligence.")
                            .font(Ecriture.chapo.bold())
                        Text(modele.cleMistralPresente
                             ? "Une réunion ou un dossier marqués « Garder sur ce Mac » ne partent jamais chez Mistral. L’écran du compte rendu dit toujours qui l’a rédigé."
                             : "Ajoute une clé Mistral pour des comptes rendus plus riches. Sans clé, tout reste sur ce Mac.")
                            .font(Ecriture.citation).foregroundStyle(Couleur.texteDoux).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: Espace.s3) {
                        TitreSection(numero: "II", titre: "La clé Mistral")
                        if modele.cleMistralPresente {
                            Label("Une clé est rangée dans le trousseau.", systemImage: "key.fill").foregroundStyle(Couleur.texteDoux)
                            HStack(spacing: Espace.s3) {
                                Button(enTest ? "Test en cours…" : "Tester la clé") { tester() }
                                    .buttonStyle(BoutonCercle())
                                    .disabled(enTest)
                                Button("Retirer la clé") {
                                    modele.enregistrerCleMistral(nil)
                                    resultatTest = nil
                                }
                                .buttonStyle(BoutonCercle())
                            }
                        } else {
                            SecureField("Colle ta clé d’API", text: $cle)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 420)
                                .accessibilityLabel("Clé d’API Mistral")
                            HStack(spacing: Espace.s3) {
                                Button("Enregistrer la clé") {
                                    modele.enregistrerCleMistral(cle)
                                    cle = ""
                                    resultatTest = nil
                                }
                                .buttonStyle(BoutonAplat())
                                .disabled(cle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("Reprendre la clé de Cairn") {
                                    let reprise = modele.reprendreCleDeCairn()
                                    resultatTest = reprise ? "La clé de Cairn est reprise. Tu peux la tester." : "Aucune clé de Cairn n’a pu être lue."
                                }
                                .buttonStyle(BoutonCercle())
                            }
                            Text("Elle est rangée dans le trousseau du Mac, jamais dans un fichier.").font(Ecriture.detail).foregroundStyle(Couleur.texteDiscret)
                        }
                        if let resultatTest { Text(resultatTest).font(Ecriture.citation).foregroundStyle(Couleur.texteDoux) }
                    }
                    VStack(alignment: .leading, spacing: Espace.s3) {
                        TitreSection(numero: "III", titre: "Où vivent tes réunions")
                        Text(modele.racine?.path ?? "").font(Ecriture.detail).foregroundStyle(Couleur.texteDoux).textSelection(.enabled)
                        Button("Changer de dossier") { modele.choisirEmplacement() }.buttonStyle(BoutonCercle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: Espace.s4) {
                    Etiquette("Ce qui quitte le Mac")
                    HStack(alignment: .firstTextBaseline, spacing: Espace.s3) {
                        Text("\(modele.reunionsEnvoyees)").font(Ecriture.une(72))
                        Text(modele.reunionsEnvoyees > 1 ? "réunions envoyées à Mistral" : "réunion envoyée à Mistral")
                            .font(Ecriture.chapo)
                    }
                    .accessibilityElement(children: .combine)
                    VStack(alignment: .leading, spacing: Espace.s3) {
                        ligne("L’audio", "jamais.")
                        ligne("La transcription et tes notes", "chez Mistral, pour rédiger le compte rendu, sauf ce que tu gardes sur ce Mac.")
                        ligne("Le reste", "aucune télémétrie, aucun compte.")
                    }
                }
                .padding(Espace.s6)
                .frame(width: 360, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Rayon.moyen).fill(Couleur.marge))
            }
        }
    }

    private func ligne(_ quoi: String, _ ou: String) -> some View {
        (Text(quoi + " : ").font(Ecriture.lectureForte) + Text(ou).font(Ecriture.lecture))
            .fixedSize(horizontal: false, vertical: true)
    }
}
