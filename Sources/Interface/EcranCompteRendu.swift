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

/// « I », « II », « III »… pour les sections présentes, dans l'ordre.
func chiffreRomain(_ n: Int) -> String {
    ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"][max(0, min(n, 8) - 1)]
}

private let francais = Locale(identifier: "fr_FR")

/// Une raison d'erreur, sans son point final, pour la glisser dans une phrase.
func sansPoint(_ texte: String) -> String {
    var propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
    while propre.hasSuffix(".") { propre.removeLast() }
    return propre.prefix(1).lowercased() + propre.dropFirst()
}

// MARK: - Compte rendu

/// Le compte rendu, en affiche : un aplat porte le titre et la frise-règle, puis la lecture, et la marge
/// garde tes notes, les questions en suspens et la transcription. Voir docs/brief-da-reunions.md.
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
    @State private var vueMarge = VueMarge.notes
    @FocusState private var titreActif: Bool
    @Environment(\.accessibilityReduceMotion) private var animationsReduites

    enum VueMarge: Hashable { case notes, transcription }

    /// La réunion telle que le modèle la connaît maintenant : un réglage changé ici s'y voit aussitôt.
    private var courante: Reunion { modele.reunions.first { $0.id == reunion.id } ?? reunion }
    private var occupee: Bool { modele.analyses[reunion.id] != nil || modele.relectures[reunion.id] != nil }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                affiche
                ScrollViewReader { proxy in
                    ScrollView {
                        lecture
                            .frame(maxWidth: 760, alignment: .leading)
                            .padding(.horizontal, Espace.s10)
                            .padding(.top, Espace.s6)
                            .padding(.bottom, Espace.s10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .task(id: cibleDefilement) {
                        guard let cibleDefilement else { return }
                        await Task.yield()
                        proxy.scrollTo(cibleDefilement.id, anchor: .center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Couleur.papier)
            Couleur.filet.frame(width: 1)
            marge
                .frame(width: 320)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Couleur.marge)
        }
        .foregroundStyle(Couleur.texte)
        .font(Ecriture.interface)
        .tint(Couleur.lien)
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
        .onChange(of: courante.meta.nomsDesVoix) { _, _ in compteRendu = lireCompteRendu() }
    }

    // MARK: L'affiche

    private var surtitre: String {
        let debut = reunion.meta.date
        let fin = debut.addingTimeInterval(reunion.meta.duree)
        let heures = "\(debut.formatted(.dateTime.locale(francais).hour().minute())) – \(fin.formatted(.dateTime.locale(francais).hour().minute()))"
        let morceaux = [reunion.dossier, reunion.meta.origine.map { "extrait de \($0)" },
                        debut.formatted(.dateTime.locale(francais).weekday(.wide).day().month(.wide)),
                        heures, "\(Int((reunion.meta.duree / 60).rounded())) min"]
        return morceaux.compactMap { $0 }.joined(separator: "  ·  ").uppercased(with: francais)
    }

    private func enregistrerTitre() {
        let propre = titre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty, propre != reunion.meta.titre else { titre = reunion.meta.titre; return }
        modele.renommer(reunion, en: propre)
    }

    private var affiche: some View {
        VStack(alignment: .leading, spacing: Espace.s3) {
            HStack(spacing: Espace.s4) {
                Button { modele.revenir() } label: {
                    HStack(spacing: Espace.s1) {
                        Image(systemName: "chevron.left")
                        Text(modele.libelleRetour.prefix(1).uppercased() + modele.libelleRetour.dropFirst())
                    }
                    .font(Ecriture.interfaceForte)
                    .fixedSize()
                }
                .buttonStyle(.plain)
                Spacer(minLength: Espace.s3)
                if let compteRendu, !occupee {
                    MentionRedaction(fournisseur: compteRendu.fournisseur)
                    Button(copie ? "Copié" : "Copier le compte rendu") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(compteRendu.texteACopier(incidents: reunion.meta.incidentsAudio ?? []), forType: .string)
                        copie = true
                    }
                    .buttonStyle(BoutonSurAplat(plein: true))
                    menuRefaire
                }
                GestionReunion(modele: modele, reunion: reunion) { lecteur.arreter() }
                    .foregroundStyle(Couleur.surAplat)
            }
            .padding(.top, Espace.s6)
            Text(surtitre).font(Ecriture.etiquette).tracking(0.8).lineLimit(1).truncationMode(.middle)
                .padding(.top, Espace.s2)
            TextField("Titre de la réunion", text: $titre, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Ecriture.une(titre.count > 72 ? 32 : titre.count > 40 ? 40 : titre.count > 20 ? 44 : 50))
                .lineLimit(1...4)
                .lineSpacing(-6)
                .focused($titreActif)
                .onSubmit { enregistrerTitre() }
                .onChange(of: titreActif) { _, actif in if !actif { enregistrerTitre() } }
                .accessibilityLabel("Titre de la réunion")
            enPreparation
            if let compteRendu, reunion.meta.duree > 0 {
                FriseRegle(duree: reunion.meta.duree, compteRendu: compteRendu, choisi: selection?.id) { choisir($0) }
                    .padding(.top, Espace.s1)
            }
        }
        .padding(.horizontal, Espace.s10)
        .padding(.bottom, Espace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Couleur.aplat)
        .foregroundStyle(Couleur.surAplat)
        .tint(Couleur.surAplat)
    }

    /// Relecture puis rédaction : une phrase et une barre, sur l'aplat.
    @ViewBuilder private var enPreparation: some View {
        let etape: (String, Double)? = {
            if let avancee = modele.relectures[reunion.id] { return ("Relecture de l’enregistrement", avancee) }
            if let avancee = modele.analyses[reunion.id] {
                let local = modele.gardeeSurCeMac(courante) || !modele.cleMistralPresente
                return (local ? "Rédaction du compte rendu sur ce Mac" : "Mistral rédige le compte rendu", avancee)
            }
            return nil
        }()
        if let etape {
            VStack(alignment: .leading, spacing: Espace.s2) {
                Text(etape.0.uppercased(with: francais)).font(Ecriture.etiquette).tracking(0.8)
                ProgressView(value: min(max(etape.1, 0), 1))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 360)
                    .accessibilityLabel(etape.0)
                Text("Ton compte rendu arrive, tu peux fermer cet écran. Tes notes et la transcription sont déjà là.")
                    .font(Ecriture.interface)
                    .foregroundStyle(Couleur.surAplat.opacity(0.85))
            }
            .padding(.vertical, Espace.s2)
        }
    }

    /// Refaire le compte rendu : chez Mistral (une réunion gardée sur ce Mac demande confirmation), ou sur ce Mac.
    private var menuRefaire: some View {
        Menu("Refaire") {
            Button(modele.gardeeSurCeMac(courante) ? "Avec Mistral…" : "Avec Mistral") {
                if modele.gardeeSurCeMac(courante) { confirmerMistral = true } else { modele.analyserAvecMistral(reunion) }
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
        .foregroundStyle(Couleur.surAplat)
        .accessibilityLabel("Refaire le compte rendu")
        .disabled(occupee || segments.isEmpty)
        .confirmationMistral(presente: $confirmerMistral) { modele.analyserAvecMistral(reunion) }
    }

    // MARK: La lecture

    @ViewBuilder private var lecture: some View {
        VStack(alignment: .leading, spacing: Espace.s8) {
            avertissements
            if let compteRendu {
                if let enBref = compteRendu.enBref, !enBref.isEmpty {
                    VStack(alignment: .leading, spacing: Espace.s2) {
                        Text(compteRendu.apercu).font(Ecriture.chapo).foregroundStyle(Couleur.texteDoux)
                            .lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: Espace.s2) {
                            ForEach(Array(Set(enBref.flatMap(\.sources))).sorted(), id: \.self) { temps in
                                BoutonHeure(temps: temps) { choisir(ElementSource(texte: "", sources: [temps])); vueMarge = .transcription }
                            }
                        }
                    }
                }
                ForEach(Array(sections(compteRendu).enumerated()), id: \.offset) { rang, section in
                    sectionVue(numero: chiffreRomain(rang + 1), section)
                }
            } else if !occupee {
                // Pendant la préparation, l'aplat dit déjà que le compte rendu arrive : le corps commence par « Qui parle ».
                sansCompteRendu
            }
            voixANommer
        }
    }

    private enum Section {
        case decisions([ElementSource]), actions([ElementSource]), sujets([Sujet]), pointsCles([ElementSource])
    }

    /// Les sections présentes, dans l'ordre de lecture. Les questions vivent dans la marge.
    private func sections(_ compteRendu: CompteRendu) -> [Section] {
        var liste: [Section] = []
        if !compteRendu.decisions.isEmpty { liste.append(.decisions(compteRendu.decisions)) }
        // « À faire » reste, même vide : dire qu'il n'y a rien à faire est une information.
        liste.append(.actions(compteRendu.actions))
        if let sujets = compteRendu.sujets, !sujets.isEmpty { liste.append(.sujets(sujets)) }
        if let points = compteRendu.pointsCles, !points.isEmpty { liste.append(.pointsCles(points)) }
        return liste
    }

    @ViewBuilder private func sectionVue(numero: String, _ section: Section) -> some View {
        switch section {
        case let .decisions(decisions):
            VStack(alignment: .leading, spacing: Espace.s1) {
                TitreSection(numero: numero, titre: "Décidé")
                ForEach(Array(decisions.enumerated()), id: \.element.id) { rang, element in
                    ligne(element) {
                        Text("\(rang + 1)").font(Ecriture.numero).foregroundStyle(selection?.id == element.id ? Couleur.lien : Couleur.texte)
                            .frame(width: 22, alignment: .leading)
                    }
                }
            }
        case let .actions(actions):
            VStack(alignment: .leading, spacing: Espace.s1) {
                TitreSection(numero: numero, titre: "À faire")
                if actions.isEmpty {
                    Text("Personne ne s’est engagé à faire quelque chose pendant cette réunion.")
                        .font(Ecriture.citation).foregroundStyle(Couleur.texteDoux).padding(.vertical, Espace.s2)
                }
                ForEach(actions) { element in
                    let action = ActionOuverte(reunion: reunion, element: element)
                    let faite = modele.actionEstFaite(action)
                    ligne(element, faite: faite) {
                        HStack(spacing: Espace.s2) {
                            Toggle("Marquer comme faite : \(element.texte)", isOn: Binding(
                                get: { modele.actionEstFaite(action) }, set: { modele.definirAction(action, faite: $0) }))
                                .labelsHidden().toggleStyle(.checkbox)
                            if let responsable = element.responsable {
                                PastillePersonne(responsable)
                            } else {
                                // Une action sans responsable dit : un cercle vide, discret, sans nom.
                                Circle().strokeBorder(Couleur.texteDiscret, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                    .frame(width: 22, height: 22)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
        case let .sujets(sujets):
            VStack(alignment: .leading, spacing: Espace.s1) {
                TitreSection(numero: numero, titre: "Sujets")
                ForEach(sujets) { sujet in sujetVue(sujet) }
            }
        case let .pointsCles(points):
            VStack(alignment: .leading, spacing: Espace.s1) {
                TitreSection(numero: numero, titre: "Points clés")
                ForEach(points) { element in
                    ligne(element) { Text("–").font(Ecriture.numero).foregroundStyle(Couleur.texteDiscret).frame(width: 22, alignment: .leading) }
                }
            }
        }
    }

    /// Une ligne du compte rendu : son repère, son texte, son responsable et son échéance s'ils ont été dits,
    /// ses horodatages (règle 1). Choisie, elle ouvre sa citation dessous, sans lancer le son.
    private func ligne<Repere: View>(_ element: ElementSource, faite: Bool = false, @ViewBuilder repere: () -> Repere) -> some View {
        let choisi = selection?.id == element.id
        return VStack(alignment: .leading, spacing: Espace.s2) {
            HStack(alignment: .top, spacing: Espace.s3) {
                repere().padding(.top, 1)
                Button { choisir(element) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Espace.s3) {
                        if let responsable = element.responsable {
                            Text(responsable).font(Ecriture.personne).frame(minWidth: 64, alignment: .leading)
                        }
                        (Text(element.texte).font(choisi ? Ecriture.lectureForte : Ecriture.lecture).strikethrough(faite)
                         + (element.echeance.map { Text("  \($0)").font(Ecriture.echeance).foregroundStyle(Couleur.ocre) } ?? Text("")))
                            .foregroundStyle(faite ? Couleur.texteDiscret : Couleur.texte)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Espace.s3)
                        HStack(spacing: Espace.s2) {
                            ForEach(element.sources, id: \.self) { temps in
                                Text(horodatage(temps)).font(choisi ? Ecriture.horodatageFort : Ecriture.horodatage)
                                    .foregroundStyle(choisi ? Couleur.lien : Couleur.texteDiscret)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(([element.texte] + [element.responsable, element.echeance].compactMap { $0 }
                    + element.sources.map { "à \(tempsParle($0))" }).joined(separator: ", "))
                .accessibilityHint("Ouvre la citation, sans lancer le son")
                .accessibilityAddTraits(choisi ? [.isSelected, .isButton] : .isButton)
            }
            if choisi { citation(element).padding(.leading, 34) }
        }
        .padding(.vertical, Espace.s2)
        .padding(.horizontal, Espace.s3)
        .background(RoundedRectangle(cornerRadius: Rayon.moyen).fill(choisi ? Couleur.selection : .clear))
        .padding(.horizontal, -Espace.s3)
        .id(element.id)
    }

    /// La citation de l'élément choisi : ce qui a été dit, l'écouter, ou le retrouver dans la transcription.
    private func citation(_ element: ElementSource) -> some View {
        let temps = element.sources.first ?? 0
        return VStack(alignment: .leading, spacing: Espace.s2) {
            if let texte = element.citationAffichee {
                Text("« \(texte) »").font(Ecriture.citation).foregroundStyle(Couleur.texteDoux)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Espace.s4) {
                Text("À \(horodatage(temps))").font(Ecriture.horodatage).foregroundStyle(Couleur.texteDiscret)
                boutonEcoute(temps)
                Button("Voir dans la transcription") { vueMarge = .transcription }
                    .buttonStyle(.plain).font(Ecriture.interfaceForte).foregroundStyle(Couleur.lien)
            }
        }
        .padding(.leading, Espace.s3)
        .overlay(alignment: .leading) { Couleur.lien.frame(width: 2) }
        .transition(animationsReduites ? .identity : .opacity)
    }

    @ViewBuilder private func boutonEcoute(_ temps: Double) -> some View {
        if lecteur.enLecture {
            Button { lecteur.arreter() } label: { Label("Arrêter", systemImage: "stop.fill") }
                .buttonStyle(.plain).font(Ecriture.interfaceForte).foregroundStyle(Couleur.lien)
        } else {
            Button { lecteur.lire(a: temps) } label: { Label("Écouter ce passage", systemImage: "play.fill").fixedSize() }
                .buttonStyle(.plain).font(Ecriture.interfaceForte).foregroundStyle(Couleur.lien)
                .disabled(!lecteur.disponible)
        }
    }

    /// Choisir un sujet montre son passage dans la transcription, sans lancer le son.
    private func sujetVue(_ sujet: Sujet) -> some View {
        let choisi = selection?.sources == [sujet.debut, sujet.fin]
        return VStack(alignment: .leading, spacing: Espace.s1) {
            Button { choisir(ElementSource(texte: sujet.titre, sources: [sujet.debut, sujet.fin])); vueMarge = .transcription } label: {
                HStack(alignment: .firstTextBaseline, spacing: Espace.s3) {
                    Text(sujet.titre).font(Ecriture.lectureForte).multilineTextAlignment(.leading)
                    Spacer(minLength: Espace.s3)
                    Text(horodatage(sujet.debut)).font(Ecriture.horodatage).foregroundStyle(choisi ? Couleur.lien : Couleur.texteDiscret)
                }
                .padding(.vertical, Espace.s1)
                .padding(.horizontal, Espace.s3)
                .background(RoundedRectangle(cornerRadius: Rayon.moyen).fill(choisi ? Couleur.selection : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, -Espace.s3)
            .id(sujet.id)
            .accessibilityLabel("\(sujet.titre), à \(tempsParle(sujet.debut))")
            .accessibilityHint("Affiche le passage de la transcription")
            .accessibilityAddTraits(choisi ? [.isSelected, .isButton] : .isButton)
            ForEach(sujet.points ?? []) { point in
                Button { choisir(point) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Espace.s2) {
                        Text("–").foregroundStyle(Couleur.texteDiscret)
                        Text(point.texte).font(Ecriture.lecture).foregroundStyle(Couleur.texteDoux).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, Espace.s3)
                .accessibilityHint("Ouvre la citation, sans lancer le son")
                if selection?.id == point.id { citation(point).padding(.leading, Espace.s6) }
            }
        }
        .padding(.bottom, Espace.s2)
    }

    /// Ce qu'il faut savoir avant de lire : relais local, échec, fraîcheur, éléments écartés, audio incomplet.
    @ViewBuilder private var avertissements: some View {
        let lignes = avertissementsListe
        if !lignes.isEmpty {
            VStack(alignment: .leading, spacing: Espace.s2) {
                ForEach(Array(lignes.enumerated()), id: \.offset) { _, ligne in
                    Label { Text(ligne.texte).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: ligne.icone) }
                        .font(Ecriture.interface)
                        .foregroundStyle(ligne.couleur)
                        .accessibilityLabel(ligne.accessible ?? ligne.texte)
                }
            }
        }
    }

    private struct Avertissement {
        var icone: String
        var texte: String
        var couleur: Color
        var accessible: String? = nil
    }

    private var avertissementsListe: [Avertissement] {
        var liste: [Avertissement] = []
        if let raison = modele.relaisLocal[reunion.id], compteRendu != nil {
            liste.append(Avertissement(icone: "arrow.uturn.down", texte: "Mistral n’a pas pu le rédiger : \(sansPoint(raison)). Il a été rédigé sur ce Mac.", couleur: Couleur.texteDoux))
        }
        if let raison = modele.echecsAnalyseAuto[reunion.id], !occupee {
            liste.append(Avertissement(icone: "exclamationmark.triangle", texte: "Le compte rendu n’a pas pu être rédigé : \(sansPoint(raison)).", couleur: Couleur.direct))
        }
        if let compteRendu {
            switch compteRendu.fraicheur {
            case .perimee:
                liste.append(Avertissement(icone: "clock.arrow.circlepath", texte: "La transcription a changé depuis ce compte rendu. Refais-le pour le mettre à jour.", couleur: Couleur.ocre,
                                           accessible: "La transcription a changé depuis ce compte rendu. Utilise « Refaire » pour le mettre à jour."))
            case .aVerifier:
                liste.append(Avertissement(icone: "clock.arrow.circlepath", texte: "Compte rendu écrit avant ce contrôle : à vérifier.", couleur: Couleur.ocre,
                                           accessible: "Compte rendu écrit avant ce contrôle de fraîcheur : à vérifier. Utilise « Refaire » si besoin."))
            case .aJour:
                break
            }
            let manques = [compteRendu.passagesNonAnalyses > 0 ? accord(compteRendu.passagesNonAnalyses, "passage non analysé", "passages non analysés") : nil,
                           compteRendu.elementsEcartes > 0 ? accord(compteRendu.elementsEcartes, "élément écarté", "éléments écartés") + " faute de source" : nil]
                .compactMap { $0 }
            if !manques.isEmpty {
                liste.append(Avertissement(icone: "line.3.horizontal.decrease", texte: manques.joined(separator: " · ") + ".", couleur: Couleur.texteDiscret))
            }
        }
        if let incidents = reunion.meta.incidentsAudio, !incidents.isEmpty {
            liste.append(Avertissement(icone: "waveform.badge.exclamationmark", texte: "Audio incomplet : " + incidents.map(\.description).joined(separator: " · "), couleur: Couleur.ocre))
        }
        return liste
    }

    private var sansCompteRendu: some View {
        VStack(alignment: .leading, spacing: Espace.s4) {
            if segments.isEmpty {
                Text("Aucune phrase n’a été transcrite.").font(Ecriture.chapo).foregroundStyle(Couleur.texteDoux)
            } else {
                Text("\(segments.count) phrases transcrites. Pas encore de compte rendu.").font(Ecriture.chapo).foregroundStyle(Couleur.texteDoux)
                // Sans phrase, rédiger ne fait rien : ces boutons ne seraient que des promesses.
                HStack(spacing: Espace.s3) {
                    Button("Rédiger le compte rendu") { modele.rediger(reunion) }
                        .buttonStyle(BoutonAplat())
                    if modele.gardeeSurCeMac(courante) || !modele.cleMistralPresente {
                        Text("Il sera rédigé sur ce Mac.").foregroundStyle(Couleur.texteDoux)
                    } else {
                        Button("Rédiger sur ce Mac") { modele.analyser(reunion, avec: AnalysteLocal()) }
                            .buttonStyle(.plain).font(Ecriture.interfaceForte).foregroundStyle(Couleur.lien)
                    }
                }
                if !modele.cleMistralPresente {
                    Button("Ajoute ta clé dans les réglages") { modele.ecran = .reglages }
                        .buttonStyle(.plain).foregroundStyle(Couleur.lien)
                }
            }
        }
    }

    /// Les personnes à nommer : écouter un extrait, donner un nom. Deux voix, un même nom : une seule personne.
    @ViewBuilder private var voixANommer: some View {
        let voix = VoixDeLaReunion.liste(segments)
        if !voix.isEmpty {
            VStack(alignment: .leading, spacing: Espace.s2) {
                Text("QUI PARLE").font(Ecriture.etiquette).tracking(0.8).foregroundStyle(Couleur.texteDiscret)
                Text("Écoute un extrait et donne un nom à chaque voix. Si une personne a deux voix, donne-leur le même nom.")
                    .font(Ecriture.interface).foregroundStyle(Couleur.texteDoux)
                ForEach(voix) { uneVoix in
                    let nom = courante.meta.nomsDesVoix?[uneVoix.voix]
                    HStack(alignment: .top, spacing: Espace.s3) {
                        if let nom, !nom.isEmpty { PastillePersonne(nom) } else {
                            Circle().strokeBorder(Couleur.texteDiscret, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(width: 22, height: 22)
                        }
                        VStack(alignment: .leading, spacing: Espace.s1) {
                            HStack(spacing: Espace.s3) {
                                Text(uneVoix.voix).font(Ecriture.horodatage).foregroundStyle(Couleur.texteDiscret).frame(width: 64, alignment: .leading)
                                ChampNomDeVoix(modele: modele, reunion: reunion, voix: uneVoix.voix)
                                BoutonHeure(temps: uneVoix.extrait.debut) {
                                    choisir(ElementSource(texte: "", sources: [uneVoix.extrait.debut])); vueMarge = .transcription
                                }
                            }
                            Text("« \(uneVoix.extrait.texte) »").font(Ecriture.citation).foregroundStyle(Couleur.texteDoux).lineLimit(2)
                        }
                    }
                    .padding(.vertical, Espace.s2)
                    .overlay(alignment: .bottom) { Couleur.filet.frame(height: 1) }
                }
            }
        }
    }

    // MARK: La marge

    private var marge: some View {
        VStack(alignment: .leading, spacing: 0) {
            garderSurCeMac
                .padding(.horizontal, Espace.s6)
                .padding(.top, Espace.s10 + Espace.s2)
                .padding(.bottom, Espace.s4)
            Picker("Afficher", selection: $vueMarge) {
                Text("Tes notes").tag(VueMarge.notes)
                Text("Transcription").tag(VueMarge.transcription)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Espace.s6)
            .padding(.bottom, Espace.s3)
            Couleur.filet.frame(height: 1)
            switch vueMarge {
            case .notes: notesEtQuestions
            case .transcription: transcription
            }
        }
    }

    /// Une réunion, ou tout son dossier, peut rester sur ce Mac : Mistral ne la voit jamais (règle 2).
    private var garderSurCeMac: some View {
        let _ = modele.dossiersVersion
        let dossierGarde = reunion.dossier.map { modele.dossierGardeSurCeMac($0) } ?? false
        let gardee = modele.gardeeSurCeMac(courante)
        let detail: String = {
            if dossierGarde, let dossier = reunion.dossier { return "Tout le dossier « \(dossier) » reste sur ce Mac." }
            if gardee { return "Le compte rendu est rédigé ici. Rien ne part chez Mistral." }
            if !modele.cleMistralPresente { return "Pas de clé Mistral : le compte rendu est rédigé ici." }
            return "Mistral rédige le compte rendu. L’audio reste ici."
        }()
        return Toggle(isOn: Binding(get: { modele.gardeeSurCeMac(courante) }, set: { modele.garderSurCeMac(courante, $0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Garder sur ce Mac").font(Ecriture.interfaceForte).foregroundStyle(Couleur.texte)
                Text(detail).font(Ecriture.detail).foregroundStyle(Couleur.texteDoux).fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .tint(Couleur.aplat)
        .disabled(dossierGarde || modele.session?.reunion.id == reunion.id)
    }

    private var notesEtQuestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espace.s6) {
                if let questions = compteRendu?.questions, !questions.isEmpty {
                    VStack(alignment: .leading, spacing: Espace.s2) {
                        Text("EN SUSPENS").font(Ecriture.etiquette).tracking(0.8).foregroundStyle(Couleur.texteDiscret)
                        ForEach(questions) { question in
                            let choisie = selection?.id == question.id
                            VStack(alignment: .leading, spacing: Espace.s2) {
                                Button { choisir(question) } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: Espace.s2) {
                                        Text("?").font(Ecriture.numeroSection).foregroundStyle(Couleur.ocre)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(question.texte).font(Ecriture.lectureForte).multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Text(question.sources.map(horodatage).joined(separator: " · ")).font(Ecriture.horodatage)
                                                .foregroundStyle(choisie ? Couleur.lien : Couleur.texteDiscret)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(([question.texte] + question.sources.map { "à \(tempsParle($0))" }).joined(separator: ", "))
                                .accessibilityAddTraits(choisie ? [.isSelected, .isButton] : .isButton)
                                if choisie { citation(question) }
                            }
                            .id(question.id)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Espace.s3) {
                    Text("TES NOTES").font(Ecriture.etiquette).tracking(0.8).foregroundStyle(Couleur.texteDiscret)
                    if notes.isEmpty {
                        Text("Tu n’as pas pris de notes pendant cette réunion.").font(Ecriture.citation).foregroundStyle(Couleur.texteDoux)
                    }
                    ForEach(notes) { note in
                        // Tes notes, telles que tu les as écrites (règle 3). Choisir une note montre son passage.
                        Button { choisir(ElementSource(texte: note.texte, sources: [note.temps])); vueMarge = .transcription } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(horodatage(note.temps)).font(Ecriture.horodatage).foregroundStyle(Couleur.texteDiscret)
                                Text(note.texte).font(Ecriture.citation).foregroundStyle(Couleur.texte).multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(note.id)
                        .accessibilityLabel("\(note.texte), à \(tempsParle(note.temps))")
                        .accessibilityHint("Affiche le passage de la transcription")
                    }
                }
            }
            .padding(Espace.s6)
        }
    }

    /// Le passage autour de l'élément choisi, ou toute la transcription.
    private var passage: [Segment] {
        guard let sources = selection?.sources, let debut = sources.min(), let fin = sources.max() else { return segments }
        return segments.filter { $0.fin >= debut - 30 && $0.debut <= fin + 30 }
    }

    private var transcription: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Espace.s3) {
                if let temps = selection?.sources.first {
                    Text("PASSAGE À \(horodatage(temps))").font(Ecriture.etiquette).tracking(0.8).foregroundStyle(Couleur.texteDiscret)
                        .fixedSize()
                    Spacer(minLength: 0)
                    boutonEcoute(temps)
                } else {
                    Text("TOUTE LA TRANSCRIPTION").font(Ecriture.etiquette).tracking(0.8).foregroundStyle(Couleur.texteDiscret)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, Espace.s6)
            .padding(.vertical, Espace.s3)
            if selection != nil {
                Button("Voir toute la transcription") { selection = nil; lecteur.arreter() }
                    .buttonStyle(.plain).font(Ecriture.interfaceForte).foregroundStyle(Couleur.lien)
                    .padding(.horizontal, Espace.s6).padding(.bottom, Espace.s2)
            }
            TranscriptionLue(segments: passage, sources: Set(selection?.sources ?? []), reunion: courante, modele: modele)
        }
    }

    // MARK: Le choix

    private func selectionnerMoment(_ moment: Double) {
        let resultat = sourcePourMoment(moment, compteRendu: compteRendu, notes: notes)
        cibleDefilement = resultat.cible.map { CibleDefilement(id: $0) }
        choisir(resultat.element)
        // Une note ou un sujet n'a pas de citation : son passage se lit dans la transcription.
        let elements = (compteRendu?.decisions ?? []) + (compteRendu?.actions ?? []) + (compteRendu?.questions ?? [])
        if !elements.contains(where: { $0.id == resultat.element.id }) { vueMarge = .transcription }
    }

    /// Le compte rendu avec les noms donnés depuis l'analyse.
    private func lireCompteRendu() -> CompteRendu? {
        modele.compteRendu(de: reunion)?.avecNoms(courante.meta.nomsDesVoix ?? [:])
    }

    private func choisir(_ element: ElementSource) {
        withAnimation(animationsReduites ? nil : .easeOut(duration: Duree.moyenne)) { selection = element }
        lecteur.arreter()
    }
}

// MARK: - Les composants de l'affiche

/// « Rédigé par Mistral » ou « Rédigé sur ce Mac » : qui a écrit ce compte rendu se voit toujours.
struct MentionRedaction: View {
    let fournisseur: String
    private var mistral: Bool { fournisseur.hasPrefix("Mistral") }

    var body: some View {
        Label(mistral ? "Rédigé par Mistral" : "Rédigé sur ce Mac", systemImage: mistral ? "sparkle" : "lock.fill")
            .font(Ecriture.etiquette).tracking(0.6)
            .textCase(.uppercase)
            .padding(.horizontal, Espace.s2 + 2).padding(.vertical, 5)
            .overlay(Capsule().strokeBorder(Couleur.surAplat, lineWidth: 1.2))
            .fixedSize()
            .help(fournisseur)
    }
}

struct TitreSection: View {
    let numero: String
    let titre: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Espace.s3) {
            Text(numero).font(Ecriture.numeroSection).foregroundStyle(Couleur.ocre)
            Text(titre).font(Ecriture.section).fixedSize().layoutPriority(1)
            Couleur.texte.frame(minWidth: Espace.s4).frame(height: 1).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 8 }
        }
        .padding(.bottom, Espace.s2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(titre)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Une heure qui se clique, discrète.
struct BoutonHeure: View {
    let temps: Double
    let action: () -> Void

    var body: some View {
        Button(horodatage(temps), action: action)
            .buttonStyle(.plain)
            .font(Ecriture.horodatage)
            .foregroundStyle(Couleur.lien)
            .accessibilityLabel("Voir le passage à \(tempsParle(temps))")
    }
}

/// Le bouton principal, posé sur le papier.
struct BoutonAplat: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Ecriture.interfaceForte)
            .padding(.horizontal, Espace.s4)
            .padding(.vertical, Espace.s2)
            .background(Capsule().fill(Couleur.aplat))
            .foregroundStyle(Couleur.surAplat)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Un bouton posé sur l'aplat : plein (crème, texte de la couleur de l'aplat) ou cerclé.
struct BoutonSurAplat: ButtonStyle {
    var plein = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Ecriture.interfaceForte)
            .padding(.horizontal, Espace.s3)
            .padding(.vertical, 5)
            .background(Capsule().fill(plein ? Couleur.surAplat : .clear))
            .overlay(Capsule().strokeBorder(Couleur.surAplat, lineWidth: plein ? 0 : 1.2))
            .foregroundStyle(plein ? Couleur.aplat : Couleur.surAplat)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .fixedSize()
    }
}

/// La frise-règle : une graduation par minute, plus longue tous les quarts d'heure. Au-dessus, à leur
/// moment, les décisions numérotées, les actions en pastilles de personne, les questions en « ? ».
/// Deux marques trop proches passent sur une seconde rangée. Cliquer une marque choisit l'élément.
struct FriseRegle: View {
    let duree: Double
    let compteRendu: CompteRendu
    let choisi: UUID?
    let choisir: (ElementSource) -> Void
    @State private var largeur: CGFloat = 600

    private enum Genre { case decision(Int), action(String?), question }
    private struct Marque: Identifiable {
        let element: ElementSource
        let genre: Genre
        var id: UUID { element.id }
        var temps: Double { element.sources.first ?? 0 }
    }

    private static let cote: CGFloat = 24
    private static let rangee: CGFloat = 28

    private var marques: [Marque] {
        (compteRendu.decisions.enumerated().map { Marque(element: $1, genre: .decision($0 + 1)) }
         + compteRendu.actions.map { Marque(element: $0, genre: .action($0.responsable)) }
         + compteRendu.questions.map { Marque(element: $0, genre: .question) })
            .filter { !$0.element.sources.isEmpty }
            .sorted { $0.temps < $1.temps }
    }

    private func x(_ temps: Double) -> CGFloat { CGFloat(min(max(temps / duree, 0), 1)) * largeur }

    /// Chaque marque prend la première rangée où elle ne touche pas sa voisine.
    private func rangees(_ marques: [Marque]) -> [Int] {
        var fins: [CGFloat] = []
        return marques.map { marque in
            let debut = x(marque.temps) - Self.cote / 2
            if let libre = fins.firstIndex(where: { $0 + 4 <= debut }) {
                fins[libre] = debut + Self.cote
                return libre
            }
            fins.append(debut + Self.cote)
            return fins.count - 1
        }
    }

    var body: some View {
        let marques = marques
        let rangs = rangees(marques)
        let nombreRangees = CGFloat((rangs.max() ?? -1) + 1)
        let base = max(nombreRangees, 1) * Self.rangee + 4
        let minutes = Int(duree / 60)
        ZStack(alignment: .topLeading) {
            Canvas { contexte, taille in
                for minute in 0...max(minutes, 0) {
                    let quart = minute % 15 == 0
                    let px = x(Double(minute) * 60)
                    let hauteur: CGFloat = quart ? 14 : 7
                    contexte.fill(Path(CGRect(x: px - (quart ? 1 : 0.5), y: base - hauteur, width: quart ? 2 : 1, height: hauteur)),
                                  with: .color(Couleur.surAplat))
                }
                contexte.fill(Path(CGRect(x: 0, y: base, width: taille.width, height: 1.5)), with: .color(Couleur.surAplat))
            }
            .accessibilityHidden(true)
            ForEach(Array(stride(from: 0, through: minutes, by: 15)), id: \.self) { minute in
                Text("\(minute)′").font(Ecriture.etiquette).fixedSize()
                    .offset(x: x(Double(minute) * 60) + 3, y: base + 4)
                    .accessibilityHidden(true)
            }
            if minutes % 15 > 5 {
                Text("\(minutes)′").font(Ecriture.etiquette).fixedSize()
                    .frame(width: 40, alignment: .trailing)
                    .offset(x: largeur - 40, y: base + 4)
                    .accessibilityHidden(true)
            }
            ForEach(Array(marques.enumerated()), id: \.element.id) { rang, marque in
                Button { choisir(marque.element) } label: { vue(marque) }
                    .buttonStyle(.plain)
                    .offset(x: x(marque.temps) - Self.cote / 2,
                            y: base - Self.rangee * CGFloat(rangs[rang] + 1) + (Self.rangee - Self.cote) / 2 - 2)
                    .accessibilityLabel(libelle(marque))
                    .accessibilityHint("Ouvre la citation")
                    .accessibilityAddTraits(choisi == marque.id ? [.isSelected, .isButton] : .isButton)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: base + 20, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { largeur = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Déroulé de la réunion")
    }

    @ViewBuilder private func vue(_ marque: Marque) -> some View {
        let actif = choisi == marque.id
        switch marque.genre {
        case let .decision(n):
            Text("\(n)").font(Ecriture.numero).foregroundStyle(Couleur.aplat)
                .frame(width: Self.cote, height: Self.cote)
                .background(RoundedRectangle(cornerRadius: Rayon.petit).fill(Couleur.surAplat))
                .overlay(RoundedRectangle(cornerRadius: Rayon.petit + 3).strokeBorder(Couleur.surAplat, lineWidth: actif ? 2 : 0).padding(-3))
        case let .action(responsable):
            Group {
                if let responsable { PastillePersonne(responsable, taille: Self.cote) }
                else {
                    Circle().strokeBorder(Couleur.surAplat.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                        .frame(width: Self.cote - 6, height: Self.cote - 6)
                        .frame(width: Self.cote, height: Self.cote)
                }
            }
            .overlay(Circle().strokeBorder(Couleur.surAplat, lineWidth: actif ? 2.5 : (responsable == nil ? 0 : 1.5)).padding(actif ? -3 : 0))
        case .question:
            Text("?").font(Ecriture.une(20).italic())
                .frame(width: Self.cote, height: Self.cote)
                .overlay(Circle().strokeBorder(Couleur.surAplat, lineWidth: actif ? 2 : 0))
        }
    }

    private func libelle(_ marque: Marque) -> String {
        let quand = "à \(tempsParle(marque.temps))"
        switch marque.genre {
        case let .decision(n): return "Décision \(n), \(quand) : \(marque.element.texte)"
        case let .action(responsable): return "Action\(responsable.map { " de \($0)" } ?? ""), \(quand) : \(marque.element.texte)"
        case .question: return "Question, \(quand) : \(marque.element.texte)"
        }
    }
}

/// La transcription dans la marge : qui parle, à quelle heure, ce qui a été dit. Le passage choisi est
/// surligné. Le nom d'une voix se clique pour la nommer.
struct TranscriptionLue: View {
    let segments: [Segment]
    let sources: Set<Double>
    let reunion: Reunion
    let modele: ModeleApp
    /// Pendant la réunion : les phrases pas encore finies, et le défilement qui suit la dernière.
    var provisoires: [Piste: String] = [:]
    var suivre = false
    @State private var voixANommer: UUID?

    private func qui(_ segment: Segment) -> String {
        if let voix = segment.voix { return reunion.nom(de: voix) }
        if reunion.meta.type == .visio { return segment.piste == .micro ? "Moi" : "Eux" }
        return ""
    }

    var body: some View {
        ScrollViewReader { defilement in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Espace.s3) {
                if segments.isEmpty && provisoires.values.allSatisfy(\.isEmpty) {
                    Text(suivre ? "Les phrases arrivent ici dès qu’on parle." : "Aucune phrase n’a été transcrite.")
                        .font(Ecriture.citation).foregroundStyle(Couleur.texteDoux)
                }
                ForEach(segments) { segment in
                    let source = sources.contains { $0 >= segment.debut - 2 && $0 <= segment.fin + 2 }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Espace.s2) {
                            Text(horodatage(segment.debut)).font(Ecriture.horodatage).foregroundStyle(Couleur.texteDiscret)
                            enTete(segment)
                            if segment.echoProbable == true {
                                Text("écho probable").font(Ecriture.detail).italic().foregroundStyle(Couleur.texteDiscret)
                            }
                        }
                        Text(segment.texte).font(Ecriture.transcription).foregroundStyle(Couleur.texte)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, Espace.s1)
                    .padding(.horizontal, Espace.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Rayon.petit).fill(source ? Couleur.selection : .clear))
                    .overlay(alignment: .leading) { if source { Couleur.lien.frame(width: 2) } }
                }
                ForEach([Piste.micro, .systeme], id: \.self) { piste in
                    if let texte = provisoires[piste], !texte.isEmpty {
                        Text(texte).font(Ecriture.citation).foregroundStyle(Couleur.texteDoux)
                            .padding(.horizontal, Espace.s3)
                            .overlay(alignment: .leading) { Couleur.filet.frame(width: 2) }
                    }
                }
                Color.clear.frame(height: 1).id("fin")
            }
            .padding(.horizontal, Espace.s3)
            .padding(.bottom, Espace.s6)
        }
        .onChange(of: segments.count) { _, _ in
            if suivre { defilement.scrollTo("fin", anchor: .bottom) }
        }
        }
    }

    @ViewBuilder private func enTete(_ segment: Segment) -> some View {
        let nom = qui(segment)
        if let voix = segment.voix {
            Button { voixANommer = segment.id } label: {
                Text(nom.uppercased(with: Locale(identifier: "fr_FR"))).font(Ecriture.etiquette).tracking(0.6).foregroundStyle(Couleur.texteDoux)
            }
            .buttonStyle(.plain)
            .help("Donner un nom à cette voix")
            .accessibilityLabel("\(nom), à \(tempsParle(segment.debut))")
            .accessibilityHint("Donne un nom à cette voix")
            .popover(isPresented: Binding(get: { voixANommer == segment.id }, set: { if !$0 { voixANommer = nil } })) {
                VStack(alignment: .leading, spacing: Espace.s2) {
                    Text(voix).font(Ecriture.horodatage).foregroundStyle(Couleur.texteDiscret)
                    ChampNomDeVoix(modele: modele, reunion: reunion, voix: voix).frame(width: 220)
                }
                .padding(Espace.s4)
            }
        } else if !nom.isEmpty {
            Text(nom.uppercased(with: Locale(identifier: "fr_FR"))).font(Ecriture.etiquette).tracking(0.6).foregroundStyle(Couleur.texteDoux)
        }
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
