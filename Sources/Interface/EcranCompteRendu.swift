import Analyse
import AppKit
import Capture
import DA
import SwiftUI
import Stockage
import Transcription

// MARK: - Compte rendu

struct EcranCompteRendu: View {
    @Bindable var modele: ModeleApp
    let reunion: Reunion
    @State private var compteRendu: CompteRendu?
    @State private var segments: [Segment] = []
    @State private var notes: [LigneDeNote] = []
    @State private var selection: ElementSource?
    @State private var confirmerMistral = false
    @State private var lecteur = Lecteur()
    @State private var copie = false

    var body: some View {
        Colonnes {
            HStack {
                Libelle("compte rendu · \(reunion.meta.date.formatted(.dateTime.locale(Locale(identifier: "fr_FR")).day().month(.abbreviated))) · \(Int(reunion.meta.duree / 60)) min"
                        + (compteRendu.map { " · \($0.fournisseur.lowercased())" } ?? ""))
                if let origine = reunion.meta.origine { Libelle("extrait de \(origine)") }
                Spacer(minLength: 12)
                GestionReunion(modele: modele, reunion: reunion) { lecteur.arreter() }
            }
            TitreEcran(debut: reunion.meta.titre, fin: reunion.dossier.map { ", \($0.lowercased())" } ?? "")
        } contenu: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let compteRendu {
                        analyse(compteRendu)
                    } else {
                        sansAnalyse
                    }
                    if !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Mes notes").font(Typo.titreSection).italic()
                            ForEach(notes) { note in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    PuceSource(temps: note.temps) { lecteur.lire(a: note.temps) }
                                    Text(note.texte).font(Typo.note).textSelection(.enabled)
                                }
                            }
                        }
                    }
                    if compteRendu == nil { voixANommer }
                    if let compteRendu, compteRendu.passagesNonAnalyses > 0 || compteRendu.elementsEcartes > 0 {
                        Libelle("\(accord(compteRendu.passagesNonAnalyses, "passage non analysé", "passages non analysés")) · \(accord(compteRendu.elementsEcartes, "élément écarté", "éléments écartés")) faute de source")
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 22)
            }
        } enteteEncre: {
            Libelle(selection == nil ? "écoute" : "écoute du passage source", surColonne: true)
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                Text(horodatage(selection?.sources.first ?? 0)).font(Typo.chrono).monospacedDigit()
                Spacer()
                if lecteur.enLecture {
                    Button("Arrêter") { lecteur.arreter() }.buttonStyle(BoutonSignal())
                } else {
                    Button("Écouter") { lecteur.lire(a: selection?.sources.first ?? 0) }
                        .buttonStyle(BoutonSignal())
                        .disabled(!lecteur.disponible)
                }
            }
        } contenuEncre: {
            Bulles(segments: passage, type: reunion.meta.type, sources: Set(selection?.sources ?? []), reunion: reunion, modele: modele)
        }
        .onAppear {
            compteRendu = lireCompteRendu()
            segments = reunion.segments()
            notes = reunion.notes()
            lecteur.charger(reunion)
        }
        .onDisappear { lecteur.arreter() }
        .onChange(of: occupee) { _, encore in
            guard !encore else { return }
            compteRendu = lireCompteRendu()
            segments = reunion.segments()
            lecteur.charger(reunion)
        }
        // L'analyse démarre dès la fin de la relecture : `occupee` ne repasse pas par faux entre les deux,
        // et l'écran dirait « aucune phrase » pendant toute l'analyse, sans sa progression.
        .onChange(of: modele.relectures[reunion.id] == nil) { _, finie in
            if finie { segments = reunion.segments() }
        }
        .onChange(of: reunion.meta.nomsDesVoix) { _, _ in compteRendu = lireCompteRendu() }
    }

    /// Le compte rendu avec les noms donnés depuis l'analyse.
    private func lireCompteRendu() -> CompteRendu? {
        modele.compteRendu(de: reunion)?.avecNoms(reunion.meta.nomsDesVoix ?? [:])
    }

    /// Le passage autour de l'élément choisi, ou toute la transcription.
    private var passage: [Segment] {
        guard let sources = selection?.sources, let debut = sources.min(), let fin = sources.max() else { return segments }
        return segments.filter { $0.fin >= debut - 30 && $0.debut <= fin + 30 }
    }

    private var sansAnalyse: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(segments.isEmpty ? "Aucune phrase n'a été transcrite." : "\(segments.count) phrases transcrites. Pas encore d'analyse.")
                .foregroundStyle(Color.encreDouce)
            echecAnalyseAuto
            relecture
            // Sans phrase, analyser ne fait rien : ces boutons ne seraient que des promesses.
            if !segments.isEmpty {
                HStack(spacing: 10) {
                    boutonAnalyser("Analyser sur ce Mac", style: BoutonPrincipal())
                    boutonMistral
                }
            }
            incidentsAudio
        }
    }

    /// Une analyse lancée sans clic (après une relecture) qui a échoué : silencieuse pour ne pas
    /// interrompre, mais pas invisible non plus.
    @ViewBuilder private var echecAnalyseAuto: some View {
        if let raison = modele.echecsAnalyseAuto[reunion.id] {
            Libelle("l'analyse automatique n'a pas abouti : \(raison)")
        }
    }

    private var occupee: Bool { modele.analyses[reunion.id] != nil || modele.relectures[reunion.id] != nil }

    private func boutonAnalyser<Style: ButtonStyle>(_ titre: String, style: Style) -> some View {
        Button(modele.analyses[reunion.id].map { "Analyse en cours · \(Int($0 * 100)) %" } ?? titre) {
            modele.analyser(reunion, avec: AnalysteLocal())
        }
        .buttonStyle(style)
        .disabled(occupee || segments.isEmpty)
    }

    /// Mistral : un envoi hors du Mac, confirmé à chaque fois, pour cette réunion seule (règle 2).
    private var boutonMistral: some View {
        Button("Analyser avec Mistral…") { confirmerMistral = true }
            .buttonStyle(BoutonSecondaire())
            .disabled(occupee || segments.isEmpty || !modele.cleMistralPresente)
            .help(modele.cleMistralPresente ? "" : "Ajoute ta clé Mistral dans les réglages.")
            .confirmationMistral(presente: $confirmerMistral) { modele.analyserAvecMistral(reunion) }
    }

    @ViewBuilder private var relecture: some View {
        if let avancee = modele.relectures[reunion.id] {
            Libelle("relecture de l'enregistrement · \(Int(avancee * 100)) %")
        }
    }

    /// Les personnes à nommer, juste sous le résumé : les noms changent toute la lecture qui suit.
    /// Un extrait à écouter pour reconnaître la voix. Deux voix, un même nom : c'est une seule personne.
    @ViewBuilder private var voixANommer: some View {
        let voix = VoixDeLaReunion.liste(segments)
        if !voix.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Libelle("qui parle")
                Text("Écoute un extrait et donne un nom à chaque voix. Si une personne a deux voix, donne-leur le même nom.")
                    .font(Typo.note)
                    .foregroundStyle(Color.encreDouce)
                    .padding(.bottom, 4)
                ForEach(voix) { uneVoix in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 12) {
                            Text(uneVoix.voix).font(Typo.horodatage).foregroundStyle(Color.encreDouce).frame(width: 60, alignment: .leading)
                            ChampNomDeVoix(modele: modele, reunion: reunion, voix: uneVoix.voix)
                            PuceSource(temps: uneVoix.extrait.debut) { lecteur.lire(a: uneVoix.extrait.debut) }
                        }
                        Text("« \(uneVoix.extrait.texte) »")
                            .font(Typo.note)
                            .italic()
                            .foregroundStyle(Color.encreDouce)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) { Color.filet.frame(height: 1) }
                }
            }
        }
    }

    /// Il manque un moment de la réunion : le compte rendu le dit, y compris après une relance.
    @ViewBuilder private var incidentsAudio: some View {
        if let incidents = reunion.meta.incidentsAudio, !incidents.isEmpty {
            Libelle("audio incomplet : " + incidents.map(\.description).joined(separator: " · "))
        }
    }

    @ViewBuilder private func analyse(_ compteRendu: CompteRendu) -> some View {
        relecture
        bandeauFraicheur(compteRendu)
        VStack(alignment: .leading, spacing: 8) {
            if let enBref = compteRendu.enBref, !enBref.isEmpty {
                Libelle("en bref · rédigé par \(compteRendu.fournisseur)")
            }
            HStack(alignment: .top, spacing: 14) {
                Color.terracotta.frame(width: 3)
                Text(compteRendu.apercu).font(Typo.resume).textSelection(.enabled)
            }
            .fixedSize(horizontal: false, vertical: true)
            if let enBref = compteRendu.enBref, !enBref.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(Set(enBref.flatMap(\.sources))).sorted(), id: \.self) { temps in
                        PuceSource(temps: temps) { choisir(ElementSource(texte: "", sources: [temps])) }
                    }
                }
            }
        }
        HStack(spacing: 10) {
            Button(copie ? "Copié" : "Copier le compte rendu") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(compteRendu.texteACopier(incidents: reunion.meta.incidentsAudio ?? []), forType: .string)
                copie = true
            }
            .buttonStyle(BoutonPrincipal())
            menuRefaire
        }
        incidentsAudio
        section("points clés", compteRendu.pointsCles ?? [])
        voixANommer
        section("décisions", compteRendu.decisions)
        section("actions", compteRendu.actions)
        section("questions ouvertes", compteRendu.questions)
        sectionSujets(compteRendu.sujets ?? [])
    }

    /// La transcription a pu changer depuis cette analyse (relecture) ou n'avoir jamais été comparée
    /// (analyse écrite avant ce contrôle) : le bouton « Refaire l'analyse » existant reste la seule issue.
    @ViewBuilder private func bandeauFraicheur(_ compteRendu: CompteRendu) -> some View {
        switch compteRendu.fraicheur {
        case .perimee:
            Libelle("la transcription a changé depuis cette analyse")
                .accessibilityLabel("La transcription a changé depuis cette analyse. Utilise « Refaire l'analyse » pour la mettre à jour.")
        case .aVerifier:
            Libelle("analyse faite avant ce contrôle : à vérifier")
                .accessibilityLabel("Analyse faite avant ce contrôle de fraîcheur : à vérifier. Utilise « Refaire l'analyse » si besoin.")
        case .aJour:
            EmptyView()
        }
    }

    /// Refaire l'analyse : sur ce Mac, ou chez Mistral après confirmation.
    private var menuRefaire: some View {
        Menu(modele.analyses[reunion.id].map { "Analyse en cours · \(Int($0 * 100)) %" } ?? "Refaire l'analyse") {
            Button("Sur ce Mac") { modele.analyser(reunion, avec: AnalysteLocal()) }
            Button("Avec Mistral…") { confirmerMistral = true }
                .disabled(!modele.cleMistralPresente)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .font(Typo.texte)
        .foregroundStyle(Color.encre)
        .disabled(occupee || segments.isEmpty)
        .confirmationMistral(presente: $confirmerMistral) { modele.analyserAvecMistral(reunion) }
    }

    /// Choisir un sujet montre son passage et le fait écouter.
    @ViewBuilder private func sectionSujets(_ sujets: [Sujet]) -> some View {
        if !sujets.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Libelle("sujets").padding(.bottom, 6)
                ForEach(sujets) { sujet in
                    let choisi = selection?.sources == [sujet.debut, sujet.fin]
                    Button { choisir(ElementSource(texte: sujet.titre, sources: [sujet.debut, sujet.fin])) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(sujet.titre).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Text(horodatage(sujet.debut)).font(Typo.horodatage)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(choisi ? Color.encreColonne : Color.clear)
                        .foregroundStyle(choisi ? Color.colonneTexte : Color.encre)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, -10)
                    .accessibilityLabel("\(sujet.titre), à \(tempsParle(sujet.debut))")
                    .accessibilityHint("Affiche le passage de la transcription")
                    .accessibilityAddTraits(choisi ? [.isSelected, .isButton] : .isButton)
                    ForEach(sujet.points ?? []) { point in
                        Button { choisir(point) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("–").foregroundStyle(Color.encreDouce)
                                Text(point.texte).font(Typo.note).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Affiche le passage de la transcription")
                    }
                    .padding(.bottom, 6)
                }
            }
        }
    }

    @ViewBuilder private func section(_ titre: String, _ elements: [ElementSource]) -> some View {
        if !elements.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Libelle(titre).padding(.bottom, 6)
                ForEach(elements) { element in
                    let choisi = selection?.id == element.id
                    Button { choisir(element) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(element.texte).multilineTextAlignment(.leading)
                                if let citation = element.citationAffichee {
                                    Text("« \(citation) »")
                                        .font(Typo.note)
                                        .italic()
                                        .opacity(0.7)
                                        .multilineTextAlignment(.leading)
                                }
                                let details = [element.responsable, element.echeance].compactMap { $0 }
                                if !details.isEmpty {
                                    Text(details.joined(separator: " · ")).font(Typo.horodatage)
                                }
                            }
                            Spacer(minLength: 0)
                            HStack(spacing: 4) {
                                ForEach(element.sources, id: \.self) { temps in
                                    Text(horodatage(temps)).font(Typo.horodatage)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(choisi ? Color.argile : Color.surface)
                                        .foregroundStyle(choisi ? Color.encreColonne : Color.encre)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(choisi ? Color.encreColonne : Color.clear)
                        .foregroundStyle(choisi ? Color.colonneTexte : Color.encre)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, -10)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(([element.texte] + [element.responsable, element.echeance].compactMap { $0 }
                        + element.sources.map { "à \(tempsParle($0))" }).joined(separator: ", "))
                    .accessibilityHint("Affiche le passage de la transcription")
                    .accessibilityAddTraits(choisi ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }

    private func choisir(_ element: ElementSource) {
        selection = element
        if let temps = element.sources.first { lecteur.lire(a: temps) }
    }
}


private extension View {
    func confirmationMistral(presente: Binding<Bool>, envoyer: @escaping () -> Void) -> some View {
        alert("Envoyer cette réunion à Mistral ?", isPresented: presente) {
            Button("Envoyer cette réunion", action: envoyer)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La transcription et tes notes partent chez Mistral pour cette analyse. L'audio reste sur ce Mac.")
        }
    }
}
