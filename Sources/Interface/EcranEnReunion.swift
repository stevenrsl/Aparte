import Analyse
import AppKit
import Capture
import DA
import SwiftUI
import Stockage
import Transcription

// MARK: - En réunion

/// L'affiche de l'enregistrement : le seul moment d'audace. L'aplat `aplatDirect` porte le titre, le grand
/// chrono et la frise qui se remplit ; tes notes et la transcription en direct sont à droite, sur le papier.
struct EcranEnReunion: View {
    @Bindable var modele: ModeleApp
    let session: SessionReunion
    @FocusState private var ligneActive: UUID?
    @State private var fin = false

    private var statut: String {
        if !session.etat.isEmpty { return session.etat }
        return session.captureArretee ? (session.finalisationEnCours ? "Finalisation en cours" : "Enregistrement arrêté") : "Enregistrement en cours"
    }

    var body: some View {
        HStack(spacing: 0) {
            affiche
            Couleur.filet.frame(width: 1)
            VStack(spacing: 0) {
                notes
                Couleur.filet.frame(height: 1)
                VStack(alignment: .leading, spacing: Espace.s2) {
                    Etiquette("En direct").padding(.horizontal, Espace.s6).padding(.top, Espace.s4)
                    TranscriptionLue(segments: session.segmentsLisibles, sources: [], reunion: session.reunion, modele: modele,
                                     provisoires: session.provisoires, suivre: true)
                }
                .frame(height: 260)
            }
            .frame(width: 420)
            .background(Couleur.papier)
        }
    }

    // MARK: L'affiche

    private var affiche: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Espace.s2) {
                Circle().fill(Couleur.surAplat).frame(width: 10, height: 10)
                    .opacity(session.captureArretee ? 0.4 : 1)
                Etiquette(statut, couleur: Couleur.surAplat)
                Spacer(minLength: Espace.s3)
                Etiquette(session.reunion.dossier ?? (session.reunion.meta.type == .visio ? "Visio" : "Présentiel"), couleur: Couleur.surAplat)
            }
            .padding(.top, Espace.s10 + Espace.s4)
            .accessibilityElement(children: .combine)
            TextField("Titre de la réunion", text: Bindable(session).titre, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Ecriture.une(30).italic())
                .lineLimit(1...2)
                .padding(.top, Espace.s4)
                .accessibilityLabel("Titre de la réunion")
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: Espace.s2) {
                    Text(horodatage(session.temps))
                        .font(Ecriture.une(190).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .accessibilityLabel("Temps écoulé")
                        .accessibilityValue(tempsParle(session.temps))
                    FriseDirect(temps: session.temps, notes: session.lignes.filter { !$0.texte.isEmpty }.map(\.temps))
                }
            }
            .padding(.top, -Espace.s4)
            niveaux.padding(.top, Espace.s6)
            if let alerte = session.alerte {
                Label { Text(alerte).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .font(Ecriture.interfaceForte)
                    .foregroundStyle(Couleur.aplatDirect)
                    .padding(Espace.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Rayon.moyen).fill(Couleur.surAplat))
                    .padding(.top, Espace.s4)
                    .onChange(of: alerte, initial: true) { _, texte in
                        // Une alerte peut arriver écran caché ou yeux ailleurs : VoiceOver la lit aussitôt.
                        AccessibilityNotification.Announcement(texte).post()
                    }
            }
            Spacer(minLength: Espace.s6)
            HStack(alignment: .bottom, spacing: Espace.s4) {
                VStack(alignment: .leading, spacing: Espace.s2) {
                    Button {
                        fin = true
                        Task {
                            await modele.terminer()
                            fin = false
                        }
                    } label: {
                        Label(fin ? "Fin…" : "Terminer la réunion", systemImage: "stop.fill")
                            .font(Ecriture.lectureForte)
                            .fixedSize()
                            .padding(.horizontal, Espace.s6).padding(.vertical, Espace.s3)
                            .background(Capsule().fill(Couleur.surAplat))
                            .foregroundStyle(Couleur.aplatDirect)
                    }
                    .buttonStyle(.plain)
                    .disabled(fin || session.debut == nil)
                    Text("Pense à prévenir les participants que tu enregistres.").font(Ecriture.detail)
                }
                Spacer(minLength: Espace.s3)
                garder
            }
            .padding(.bottom, Espace.s8)
        }
        .padding(.horizontal, Espace.s10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Couleur.aplatDirect)
        .foregroundStyle(Couleur.surAplat)
        .tint(Couleur.surAplat)
    }

    /// Les niveaux d'entrée, sobres : une barre par source, le dernier niveau entendu.
    private var niveaux: some View {
        HStack(spacing: Espace.s8) {
            Niveau(nom: "Micro", valeur: session.niveauxMoi.last ?? 0, entree: session.entreeUtilisee ?? "Micro par défaut",
                   faible: session.alerteMicroFaible != nil)
            if session.reunion.meta.type == .visio {
                Niveau(nom: "Son du Mac", valeur: session.niveauxEux.last ?? 0)
            }
        }
    }

    private var garder: some View {
        let _ = modele.dossiersVersion
        let dossierGarde = session.reunion.dossier.map(modele.dossierGardeSurCeMac) == true
        let gardee = modele.gardeeSurCeMac(session.reunion)
        let detail: String = {
            if dossierGarde, let dossier = session.reunion.dossier { return "Tout le dossier « \(dossier) » reste sur ce Mac." }
            if gardee { return "Le compte rendu sera rédigé ici." }
            return "Mistral rédigera le compte rendu. L’audio reste ici."
        }()
        return CarteGarder(actif: gardee, detail: detail, desactive: dossierGarde) { modele.garderSurCeMac(session.reunion, $0) }
    }

    // MARK: Les notes

    private var notes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espace.s2) {
                Text("Tes notes").font(Ecriture.section).padding(.bottom, 2)
                Text("Chaque ligne prend l’heure où tu l’écris.").font(Ecriture.citation).foregroundStyle(Couleur.texteDoux)
                    .padding(.bottom, Espace.s3)
                ForEach(session.lignes) { ligne in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ligne.texte.isEmpty ? " " : horodatage(ligne.temps))
                            .font(Ecriture.horodatage)
                            .foregroundStyle(Couleur.texteDiscret)
                            .accessibilityHidden(ligne.texte.isEmpty)
                        TextField("Note ici, chaque ligne garde son moment.", text: Binding(
                            get: { ligne.texte },
                            set: { session.changer(ligne.id, texte: $0) }
                        ))
                        .textFieldStyle(.plain)
                        .font(Ecriture.lecture)
                        .focused($ligneActive, equals: ligne.id)
                        .onSubmit { ligneActive = session.ligneSuivante() }
                    }
                }
            }
            .padding(.horizontal, Espace.s6)
            .padding(.top, Espace.s10 + Espace.s4)
            .padding(.bottom, Espace.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { ligneActive = session.lignes.last?.id }
    }
}

/// Le niveau d'une entrée : son nom, une barre crème.
private struct Niveau: View {
    let nom: String
    let valeur: Float
    /// L'entrée qui enregistre, dite en clair : un micro Bluetooth choisi par défaut se voit tout de suite.
    var entree: String? = nil
    var faible = false

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.s1) {
            HStack(spacing: Espace.s1) {
                if faible { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).respire() }
                Etiquette(nom, couleur: Couleur.surAplat)
            }
            if let entree {
                Text(entree).font(Ecriture.detail).lineLimit(1).truncationMode(.middle).frame(maxWidth: 220, alignment: .leading)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Couleur.surAplat.opacity(0.25))
                Capsule().fill(Couleur.surAplat).frame(width: 140 * CGFloat(min(max(valeur, 0.03), 1)))
            }
            .frame(width: 140, height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Niveau \(nom.lowercased())\(entree.map { ", \($0)" } ?? "")")
        .accessibilityValue(faible ? "n’entend presque rien" : (valeur > 0.05 ? "on t’entend" : "silence"))
    }
}

/// La frise-règle qui se remplit : une graduation par minute, jusqu'à l'heure pleine qui suit ; ce qui est
/// passé est plein, la suite pâle. Tes notes sont posées au-dessus, à leur moment.
struct FriseDirect: View {
    let temps: Double
    let notes: [Double]
    /// La longueur de la règle, en minutes. Sans elle : l'heure pleine qui suit, au moins 60.
    var echelle: Double? = nil
    @State private var largeur: CGFloat = 600

    var body: some View {
        let echelle = max(1, self.echelle ?? max(60.0, (temps / 60 / 15).rounded(.up) * 15))
        let x: (Double) -> CGFloat = { CGFloat(min(max($0 / 60 / echelle, 0), 1)) * largeur }
        let base: CGFloat = 26
        let pas = echelle > 120 ? 5 : 1
        ZStack(alignment: .topLeading) {
            Canvas { contexte, taille in
                for minute in stride(from: 0, through: Int(echelle), by: pas) {
                    let quart = minute % 15 == 0
                    let passe = Double(minute) * 60 <= temps
                    let px = x(Double(minute) * 60)
                    let hauteur: CGFloat = quart ? 14 : 7
                    contexte.fill(Path(CGRect(x: px - (quart ? 1 : 0.5), y: base - hauteur, width: quart ? 2 : 1, height: hauteur)),
                                  with: .color(Couleur.surAplat.opacity(passe ? 1 : 0.35)))
                }
                contexte.fill(Path(CGRect(x: 0, y: base, width: taille.width, height: 1.5)), with: .color(Couleur.surAplat.opacity(0.35)))
                contexte.fill(Path(CGRect(x: 0, y: base - 1, width: x(temps), height: 3)), with: .color(Couleur.surAplat))
                for note in notes {
                    contexte.fill(Path(ellipseIn: CGRect(x: x(note) - 3, y: 2, width: 6, height: 6)), with: .color(Couleur.surAplat))
                }
                contexte.fill(Path(CGRect(x: x(temps) - 1.5, y: 0, width: 3, height: base + 6)), with: .color(Couleur.surAplat))
            }
            ForEach(Array(stride(from: 0, through: Int(echelle), by: 15)), id: \.self) { minute in
                Text("\(minute)′").font(Ecriture.etiquette).fixedSize()
                    .offset(x: min(x(Double(minute) * 60) + 3, largeur - 30), y: base + 6)
            }
            if Int(echelle) % 15 > 5 {
                Text("\(Int(echelle))′").font(Ecriture.etiquette).fixedSize()
                    .frame(width: 30, alignment: .trailing)
                    .offset(x: largeur - 30, y: base + 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: base + 24, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { largeur = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Déroulé : \(tempsParle(temps)) sur \(Int(echelle)) minutes, \(accord(notes.count, "note"))")
    }
}
