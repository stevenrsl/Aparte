import Analyse
import AppKit
import Capture
import DA
import SwiftUI
import Stockage
import Transcription

struct CibleDefilement: Equatable {
    let id: UUID
    private let demande = UUID()
}

func sourcePourMoment(_ moment: Double, compteRendu: CompteRendu?, notes: [LigneDeNote]) -> (element: ElementSource, cible: UUID?) {
    let elements = (compteRendu?.decisions ?? []) + (compteRendu?.actions ?? []) + (compteRendu?.questions ?? [])
    if let element = elements.first(where: { $0.sources.contains { abs($0 - moment) < 0.01 } }) {
        return (element, element.id)
    }
    if let note = notes.first(where: { abs($0.temps - moment) < 0.01 }) {
        return (ElementSource(texte: note.texte, sources: [note.temps]), note.id)
    }
    if let sujet = compteRendu?.sujets?.first(where: { $0.contient(moment) }) {
        return (ElementSource(texte: sujet.titre, sources: [sujet.debut, sujet.fin]), sujet.id)
    }
    return (ElementSource(texte: "", sources: [moment]), nil)
}

// MARK: - Compte rendu

struct EcranCompteRendu: View {
    @Bindable var modele: ModeleApp
    let reunion: Reunion
    var moment: Double? = nil
    @State private var compteRendu: CompteRendu?
    @State private var segments: [Segment] = []
    @State private var notes: [LigneDeNote] = []
    @State private var selection: ElementSource?
    @State private var cibleDefilement: CibleDefilement?
    @State private var confirmerMistral = false
    @State private var lecteur = Lecteur()
    @State private var copie = false
    @State private var titre = ""
    @FocusState private var titreActif: Bool

    private func enregistrerTitre() {
        let propre = titre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty, propre != reunion.meta.titre else { titre = reunion.meta.titre; return }
        modele.renommer(reunion, en: propre)
    }

    var body: some View {
        Colonnes(transcriptionClaire: true) {
            HStack {
                Button("← \(modele.libelleRetour)") { modele.revenir() }.buttonStyle(.plain)
                Libelle("compte rendu · \(reunion.meta.date.formatted(.dateTime.locale(Locale(identifier: "fr_FR")).day().month(.abbreviated))) · \(Int(reunion.meta.duree / 60)) min"
                       )
                if let origine = reunion.meta.origine { Libelle("extrait de \(origine)") }
                Spacer(minLength: 12)
                GestionReunion(modele: modele, reunion: reunion) { lecteur.arreter() }
            }
            TextField("Titre de la réunion", text: $titre)
                .textFieldStyle(.plain).font(Typo.titreEcran)
                .focused($titreActif)
                .onSubmit { enregistrerTitre() }
                .onChange(of: titreActif) { _, actif in if !actif { enregistrerTitre() } }
            etatCompteRendu
        } contenu: {
            ScrollViewReader { proxy in
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
                                Button { choisir(ElementSource(texte: note.texte, sources: [note.temps])) } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text(horodatage(note.temps)).font(Typo.horodatage)
                                        Text(note.texte).font(Typo.note).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }.contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(note.id)
                                .background(selection?.sources == [note.temps] ? Color.surface : Color.clear)
                                .accessibilityHint("Affiche le passage de la transcription")
                            }
                        }
                    }
                    if let compteRendu {
                        sectionSujets(compteRendu.sujets ?? [])
                        section("points clés", compteRendu.pointsCles ?? [])
                    }
                    voixANommer

                }
                .padding(.horizontal, 36)
                .padding(.vertical, 22)
            }
            .task(id: cibleDefilement) {
                guard let cibleDefilement else { return }
                await Task.yield()
                proxy.scrollTo(cibleDefilement.id, anchor: .center)
            }
            }
        } enteteEncre: {
            Libelle(selection == nil ? "transcription" : "passage · \(horodatage(selection?.sources.first ?? 0))")
            if selection != nil { Button("Voir toute la transcription") { selection = nil; lecteur.arreter() } }
            Spacer(minLength: 0)
            // Sans passage choisi, « Écouter ce passage » jouerait depuis le début sans rien sélectionner : on ne le montre pas.
            if let momentSelectionne = selection?.sources.first {
                HStack(alignment: .bottom) {
                    Text("Passage à \(horodatage(momentSelectionne))").font(Typo.horodatage)
                    Spacer()
                    if lecteur.enLecture {
                        Button("Arrêter") { lecteur.arreter() }.buttonStyle(BoutonSignal())
                    } else {
                        Button("Écouter ce passage") { lecteur.lire(a: momentSelectionne) }
                            .buttonStyle(BoutonEcouteDiscret())
                            .disabled(!lecteur.disponible)
                    }
                }
            }
        } contenuEncre: {
            Bulles(segments: passage, type: reunion.meta.type, sources: Set(selection?.sources ?? []), discret: true, reunion: reunion, modele: modele)
        }
        .onAppear {
            titre = reunion.meta.titre
            compteRendu = lireCompteRendu()
            segments = reunion.segments()
            notes = reunion.notes()
            lecteur.charger(reunion)
            if let moment { selectionnerMoment(moment) }
        }
        .onChange(of: moment) { _, nouveau in
            if let nouveau { selectionnerMoment(nouveau) }
        }
        .onExitCommand { selection = nil; lecteur.arreter() }
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

    @ViewBuilder private var etatCompteRendu: some View {
        if modele.relectures[reunion.id] != nil {
            Libelle("relecture de l’enregistrement")
            Text("Ton compte rendu arrive, tu peux fermer cet écran. Tes notes et la transcription sont déjà là.")
        } else if modele.analyses[reunion.id] != nil {
            Libelle("rédaction du compte rendu")
            Text("Ton compte rendu arrive, tu peux fermer cet écran. Tes notes et la transcription sont déjà là.")
        } else if let raison = modele.echecsAnalyseAuto[reunion.id] {
            Text("Le compte rendu n’a pas pu être rédigé : \(raison)")
        } else if compteRendu != nil {
            Libelle("compte rendu prêt")
            if let raison = modele.relaisLocal[reunion.id] {
                Text("Mistral n’a pas pu le rédiger (\(raison)). Il a été rédigé sur ce Mac.")
                    .foregroundStyle(Color.encreDouce)
            }
        } else {
            Libelle("réunion enregistrée")
        }
    }

    private func selectionnerMoment(_ moment: Double) {
        let resultat = sourcePourMoment(moment, compteRendu: compteRendu, notes: notes)
        cibleDefilement = resultat.cible.map { CibleDefilement(id: $0) }
        choisir(resultat.element)
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
            if !occupee {
                Text(segments.isEmpty ? "Aucune phrase n'a été transcrite." : "\(segments.count) phrases transcrites. Pas encore de compte rendu.")
                    .foregroundStyle(Color.encreDouce)
            }
            // Sans phrase, analyser ne fait rien : ces boutons ne seraient que des promesses.
            if !segments.isEmpty && !occupee {
                HStack(spacing: 10) {
                    Button("Rédiger le compte rendu") { modele.rediger(reunion) }
                        .buttonStyle(BoutonPrincipal())
                    if modele.gardeeSurCeMac(reunion) || !modele.cleMistralPresente {
                        Text("Rédigé sur ce Mac").foregroundStyle(Color.encreDouce)
                    } else {
                        boutonAnalyser("Rédiger sur ce Mac", style: BoutonSecondaire())
                    }
                }
            }
            if !modele.cleMistralPresente && !segments.isEmpty && !occupee {
                Button("Ajoute ta clé dans les réglages") { modele.ecran = .reglages }.buttonStyle(.link)
            }
            incidentsAudio
        }
    }

    private var occupee: Bool { modele.analyses[reunion.id] != nil || modele.relectures[reunion.id] != nil }

    private func boutonAnalyser<Style: ButtonStyle>(_ titre: String, style: Style) -> some View {
        Button(titre) {
            modele.analyser(reunion, avec: AnalysteLocal())
        }
        .buttonStyle(style)
        .disabled(occupee || segments.isEmpty)
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
                            PuceSource(temps: uneVoix.extrait.debut) { choisir(ElementSource(texte: "", sources: [uneVoix.extrait.debut])) }
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
        VStack(alignment: .leading, spacing: 8) {
            if let enBref = compteRendu.enBref, !enBref.isEmpty {
                Libelle("en bref · rédigé par \(compteRendu.fournisseur)")
            }
            HStack(alignment: .top, spacing: 14) {
                Color.terracotta.frame(width: 3)
                Text(compteRendu.apercu).font(Typo.resume).lineSpacing(7).textSelection(.enabled)
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
        bandeauFraicheur(compteRendu)
        if compteRendu.passagesNonAnalyses > 0 || compteRendu.elementsEcartes > 0 {
            Libelle("\(accord(compteRendu.passagesNonAnalyses, "passage non analysé", "passages non analysés")) · \(accord(compteRendu.elementsEcartes, "élément écarté", "éléments écartés")) faute de source")
        }
        if !occupee { HStack(spacing: 10) {
            Button(copie ? "Copié" : "Copier le compte rendu") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(compteRendu.texteACopier(incidents: reunion.meta.incidentsAudio ?? []), forType: .string)
                copie = true
            }
            .buttonStyle(BoutonSecondaire())
            menuRefaire
        } }
        incidentsAudio
        section("décisions", compteRendu.decisions)
        section("actions", compteRendu.actions)
        section("questions ouvertes", compteRendu.questions)

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

    /// Refaire l'analyse : chez Mistral (une réunion gardée sur ce Mac demande confirmation), ou sur ce Mac.
    private var menuRefaire: some View {
        Menu("Refaire le compte rendu") {
            Button(modele.gardeeSurCeMac(reunion) ? "Avec Mistral…" : "Avec Mistral") {
                if modele.gardeeSurCeMac(reunion) { confirmerMistral = true } else { modele.analyserAvecMistral(reunion) }
            }
            .disabled(!modele.cleMistralPresente)
            Button("Sur ce Mac") { modele.analyser(reunion, avec: AnalysteLocal()) }
            if !modele.cleMistralPresente {
                Button("Ajoute ta clé dans les réglages") { modele.ecran = .reglages }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .font(Typo.texte)
        .foregroundStyle(Color.encre)
        .disabled(occupee || segments.isEmpty)
        .confirmationMistral(presente: $confirmerMistral) { modele.analyserAvecMistral(reunion) }
    }

    /// Choisir un sujet montre son passage sans lancer le son.
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
                    .id(sujet.id)
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
                    HStack(alignment: .top) {
                    if titre == "actions" {
                        let action = ActionOuverte(reunion: reunion, element: element)
                        Toggle("Marquer comme faite : \(element.texte)", isOn: Binding(get: { modele.actionEstFaite(action) }, set: { modele.definirAction(action, faite: $0) }))
                            .labelsHidden().toggleStyle(.checkbox)
                            .overlay {
                                if !modele.actionEstFaite(action) {
                                    RoundedRectangle(cornerRadius: 4).stroke(Color.encre, lineWidth: 1)
                                        .allowsHitTesting(false).accessibilityHidden(true)
                                }
                            }
                    }
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
                    .id(element.id)
                }
            }
        }
    }

    private func choisir(_ element: ElementSource) {
        selection = element
        lecteur.arreter()
    }
}


private extension View {
    func confirmationMistral(presente: Binding<Bool>, envoyer: @escaping () -> Void) -> some View {
        alert("Cette réunion est gardée sur ce Mac. L'envoyer quand même à Mistral ?", isPresented: presente) {
            Button("Envoyer cette réunion", action: envoyer)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La transcription et tes notes partent chez Mistral pour ce compte rendu. L'audio reste sur ce Mac.")
        }
    }
}

// Écart local au brief : le contour réserve l'aplat argile au passage choisi.
private struct BoutonEcouteDiscret: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.texteDemiGras)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .foregroundStyle(Color.encre)
            .overlay { Rectangle().strokeBorder(Color.encreDouce, lineWidth: 1) }
    }
}
