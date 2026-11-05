import Analyse
import AppKit
import Capture
import DA
import SwiftUI
import Stockage
import Transcription

// MARK: - En réunion

struct EcranEnReunion: View {
    @Bindable var modele: ModeleApp
    let session: SessionReunion
    @FocusState private var ligneActive: UUID?
    @State private var fin = false

    var body: some View {
        Colonnes {
            Libelle(session.reunion.dossier?.lowercased() ?? "réunion en cours")
            TextField("Titre de la réunion", text: Bindable(session).titre)
                .textFieldStyle(.plain).font(Typo.titreEcran)
        } contenu: {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mes notes").font(Typo.titreSection).italic().padding(.bottom, 6)
                        ForEach(session.lignes) { ligne in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(horodatage(ligne.temps))
                                    .font(Typo.horodatage)
                                    .foregroundStyle(ligne.texte.isEmpty ? Color.clear : Color.terracottaTexte)
                                    .frame(width: 52, alignment: .leading)
                                TextField("Note ici, chaque ligne garde son moment.", text: Binding(
                                    get: { ligne.texte },
                                    set: { session.changer(ligne.id, texte: $0) }
                                ))
                                .textFieldStyle(.plain)
                                .font(Typo.note)
                                .focused($ligneActive, equals: ligne.id)
                                .onSubmit { ligneActive = session.ligneSuivante() }
                            }
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 24)
                }
                .onAppear { ligneActive = session.lignes.last?.id }
                Text("Pense à prévenir les participants que tu enregistres.")
                    .foregroundStyle(Color.encreDouce)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Color.filet.frame(height: 1) }
            }
        } enteteEncre: {
            HStack {
                Rectangle().fill(Color.argile).frame(width: 9, height: 9)
                Libelle(session.etat.isEmpty ? (session.captureArretee ? "enregistrement arrêté" : "enregistrement en cours") : session.etat, surColonne: true)
                Spacer()
                Button(fin ? "Fin…" : "Terminer") {
                    fin = true
                    Task {
                        await modele.terminer()
                        fin = false
                    }
                }
                .buttonStyle(BoutonSignal())
                .disabled(fin || session.debut == nil)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 16) {
                Chrono(session: session)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    if session.reunion.meta.type == .visio {
                        Niveaux(valeurs: Array(session.niveauxEux.suffix(14)), couleur: .colonneTexte, hauteur: 3)
                    }
                    Niveaux(valeurs: Array(session.niveauxMoi.suffix(14)), couleur: .argile, hauteur: 3)
                }
            }
        } contenuEncre: {
            VStack(alignment: .leading, spacing: 0) {
                if let alerte = session.alerte {
                    Text(alerte)
                        .foregroundStyle(Color.encreColonne)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.argile)
                        .onChange(of: alerte, initial: true) { _, texte in
                            // Une alerte peut arriver écran caché ou yeux ailleurs : VoiceOver la lit aussitôt.
                            AccessibilityNotification.Announcement(texte).post()
                        }
                }
                Bulles(segments: session.segmentsLisibles, provisoires: session.provisoires, type: session.reunion.meta.type, suivre: true)
            }
        }
    }
}

