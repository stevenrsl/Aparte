import Analyse
import AppKit
import Capture
import DA
import SwiftUI
import Stockage
import Transcription

// MARK: - La charpente

/// Quitter pendant une réunion demande confirmation, et termine la réunion proprement.
@MainActor
public final class DelegueAparte: NSObject, NSApplicationDelegate {
    public var modele: ModeleApp?

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let modele, modele.session != nil else { return .terminateNow }
        let alerte = NSAlert()
        alerte.messageText = "Une réunion est en cours"
        alerte.informativeText = "Si tu quittes, Aparté termine la réunion d'abord et écrit les derniers mots."
        alerte.addButton(withTitle: "Continuer la réunion")
        alerte.addButton(withTitle: "Terminer la réunion et quitter")
        guard alerte.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        Task {
            await modele.terminer()
            // Si l'écriture a échoué, la session reste : on ne quitte pas, l'erreur est affichée.
            sender.reply(toApplicationShouldTerminate: modele.session == nil)
        }
        return .terminateLater
    }
}

public struct FenetreAparte: View {
    @Bindable var modele: ModeleApp

    public init(modele: ModeleApp) {
        self.modele = modele
    }

    public var body: some View {
        VStack(spacing: 0) {
            Color.surface.frame(height: 42)
                .overlay(alignment: .bottom) { Color.filet.frame(height: 1) }
            HStack(spacing: 0) {
                if modele.racine != nil {
                    BarreLaterale(modele: modele)
                }
                contenu
            }
        }
        .ignoresSafeArea()
        .background(Color.creme)
        .foregroundStyle(Color.encre)
        .font(Typo.texte)
        .overlay { GrainOverlay().ignoresSafeArea() }
        .alert("Un problème est survenu", isPresented: Binding(get: { modele.erreur != nil }, set: { if !$0 { modele.erreur = nil } })) {
            Button("Compris", role: .cancel) {}
        } message: {
            Text(modele.erreur ?? "")
        }
    }

    @ViewBuilder private var contenu: some View {
        if modele.racine == nil {
            PremierLancement(modele: modele)
        } else {
            switch modele.ecran {
            case .accueil: EcranAccueil(modele: modele)
            case .nouvelle: EcranNouvelle(modele: modele)
            case .enReunion:
                if let session = modele.session {
                    EcranEnReunion(modele: modele, session: session)
                } else {
                    EcranAccueil(modele: modele)
                }
            case let .compteRendu(reunion): EcranCompteRendu(modele: modele, reunion: reunion).id(reunion.id)
            case let .dossier(nom): EcranDossier(modele: modele, nom: nom).id(nom)
            case .reglages: EcranReglages(modele: modele)
            }
        }
    }
}

struct PremierLancement: View {
    let modele: ModeleApp

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LogoApparte()
            Text("Où ranger tes réunions ?").font(Typo.titreEcran)
            Text("Chaque réunion est un dossier lisible sans l'app. Tu peux choisir un dossier dans iCloud Drive : ça reste ton choix, Aparté ne synchronise rien.")
                .frame(maxWidth: 480, alignment: .leading)
            Button("Choisir un dossier") { modele.choisirEmplacement() }
                .buttonStyle(BoutonPrincipal())
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct BarreLaterale: View {
    @Bindable var modele: ModeleApp

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LogoApparte()
            VStack(alignment: .leading, spacing: 2) {
                EntreeLaterale(titre: "Accueil", active: modele.ecran == .accueil) { modele.ecran = .accueil }
                EntreeLaterale(titre: "Toutes les réunions", active: false) { modele.ecran = .accueil }
                if let session = modele.session {
                    EntreeLaterale(titre: session.reunion.meta.titre, active: modele.ecran == .enReunion, enCours: true) { modele.ecran = .enReunion }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Libelle("dossiers").padding(.bottom, 4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(modele.dossiers, id: \.self) { nom in
                            EntreeLaterale(titre: nom, active: modele.ecran == .dossier(nom),
                                           compte: modele.reunions.filter { $0.dossier == nom }.count) { modele.ecran = .dossier(nom) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            EntreeLaterale(titre: "Réglages", active: modele.ecran == .reglages) { modele.ecran = .reglages }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 22)
        .frame(width: 228)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.surface)
        .overlay(alignment: .trailing) { Color.filet.frame(width: 1) }
    }
}

struct EntreeLaterale: View {
    let titre: String
    let active: Bool
    var compte: Int?
    var enCours = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(active ? Color.argile : (enCours ? Color.terracotta : Color.clear))
                    .frame(width: 7, height: 7)
                Text(titre).lineLimit(1)
                Spacer(minLength: 0)
                if let compte {
                    Text("\(compte)").font(Typo.horodatage)
                        .foregroundStyle(active ? Color.colonneTexte : Color.encreDouce)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(active ? Color.encreColonne : Color.clear)
            .foregroundStyle(active ? Color.colonneTexte : Color.encre)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityValue(enCours ? "enregistrement en cours" : "")
    }
}

/// Les deux colonnes, leurs en-têtes de 172 pt fermés sur le même filet.
struct Colonnes<Entete: View, Contenu: View, EnteteEncre: View, ContenuEncre: View>: View {
    @ViewBuilder let entete: Entete
    @ViewBuilder let contenu: Contenu
    @ViewBuilder let enteteEncre: EnteteEncre
    @ViewBuilder let contenuEncre: ContenuEncre

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) { entete }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                    .frame(height: 172, alignment: .bottomLeading)
                    .overlay(alignment: .bottom) { Color.filet.frame(height: 1) }
                contenu.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Color.creme)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) { enteteEncre }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: 172, alignment: .topLeading)
                    .overlay(alignment: .bottom) { Color.colonneFilet.frame(height: 1) }
                contenuEncre.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: 420)
            .background(Color.encreColonne)
            .foregroundStyle(Color.colonneTexte)
        }
    }
}

struct TitreEcran: View {
    let debut: String
    let fin: String

    var body: some View {
        (Text(debut) + Text(fin).italic().foregroundStyle(Color.terracottaTexte))
            .font(Typo.titreEcran)
            .lineLimit(2)
    }
}

// MARK: - Les petits composants

func accord(_ nombre: Int, _ singulier: String, _ pluriel: String? = nil) -> String {
    "\(nombre) \(nombre > 1 ? (pluriel ?? singulier + "s") : singulier)"
}

struct PuceSource: View {
    let temps: Double
    var active = false
    let action: () -> Void

    var body: some View {
        Button(horodatage(temps), action: action)
            .buttonStyle(.plain)
            .font(Typo.horodatage)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(active ? Color.argile : Color.surface)
            .foregroundStyle(active ? Color.encreColonne : Color.encre)
            .accessibilityLabel("Écouter à \(tempsParle(temps))")
    }
}

/// « 12 minutes 3 secondes », là où VoiceOver lirait mal « 12:03 ».
func tempsParle(_ secondes: Double) -> String {
    let total = Int(secondes)
    return "\(total / 60) minutes \(total % 60) secondes"
}

struct Niveaux: View {
    let valeurs: [Float]
    let couleur: Color
    var point: CGFloat = 5
    var hauteur = 6

    var body: some View {
        Canvas { contexte, taille in
            let pas = point + 2
            for (x, valeur) in valeurs.enumerated() {
                let actifs = max(1, Int((valeur * Float(hauteur)).rounded()))
                for y in 0..<actifs {
                    let rect = CGRect(x: CGFloat(x) * pas, y: taille.height - CGFloat(y + 1) * pas, width: point, height: point)
                    contexte.fill(Path(ellipseIn: rect), with: .color(couleur))
                }
            }
        }
        .frame(width: CGFloat(valeurs.count) * (point + 2), height: CGFloat(hauteur) * (point + 2))
        .accessibilityHidden(true)
    }
}

struct Chrono: View {
    let session: SessionReunion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(horodatage(session.temps))
                .font(Typo.chrono)
                .monospacedDigit()
                .foregroundStyle(session.debut == nil ? Color.chronoRepos : Color.colonneTexte)
                .accessibilityLabel("Temps écoulé")
                .accessibilityValue(tempsParle(session.temps))
        }
    }
}

/// La transcription en bulles : eux à gauche, moi à droite. En présentiel, tout à gauche.
struct Bulles: View {
    let segments: [Segment]
    var provisoires: [Piste: String] = [:]
    let type: TypeReunion
    var sources: Set<Double> = []
    var suivre = false
    /// Pour nommer les voix, une fois la réunion relue.
    var reunion: Reunion?

    private func etiquette(_ segment: Segment) -> String {
        if let voix = segment.voix { return " · " + (reunion?.nom(de: voix) ?? voix) }
        if estMoi(segment.piste) { return " · moi" }
        return type == .visio ? " · eux" : ""
    }

    private func estMoi(_ piste: Piste) -> Bool { type == .visio && piste == .micro }

    var body: some View {
        ScrollViewReader { defilement in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(segments) { segment in
                        bulle(segment).id(segment.id)
                    }
                    ForEach([Piste.micro, .systeme], id: \.self) { piste in
                        if let texte = provisoires[piste], !texte.isEmpty {
                            Text(texte)
                                .padding(10)
                                .overlay { Rectangle().strokeBorder(Color.argile, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
                                .frame(maxWidth: .infinity, alignment: estMoi(piste) ? .trailing : .leading)
                        }
                    }
                    Color.clear.frame(height: 1).id("fin")
                }
                .padding(24)
            }
            .onChange(of: segments.count) { _, _ in
                if suivre { defilement.scrollTo("fin", anchor: .bottom) }
            }
        }
    }

    private func bulle(_ segment: Segment) -> some View {
        let moi = estMoi(segment.piste)
        let source = sources.contains { $0 >= segment.debut - 2 && $0 <= segment.fin + 2 }
        return VStack(alignment: moi ? .trailing : .leading, spacing: 4) {
            Text(horodatage(segment.debut) + etiquette(segment))
                .font(Typo.horodatage)
                .foregroundStyle(Color.colonneSignal)
            Text(segment.texte)
                .textSelection(.enabled)
                .padding(10)
                .background(moi ? Color.argile : Color.bulleEux)
                .foregroundStyle(moi ? Color.encreColonne : Color.colonneTexte)
                .overlay(alignment: .leading) {
                    if source { Color.argile.frame(width: 3) }
                }
        }
        .frame(maxWidth: .infinity, alignment: moi ? .trailing : .leading)
        .padding(moi ? .leading : .trailing, 40)
    }
}

// MARK: - Accueil

struct LigneReunion: View {
    let modele: ModeleApp
    let reunion: Reunion

    private var date: String {
        reunion.meta.date.formatted(.dateTime.locale(Locale(identifier: "fr_FR")).weekday(.abbreviated).day().month(.abbreviated))
    }

    var body: some View {
        let compteRendu = modele.resumeEnregistre(de: reunion)
        Button { modele.ecran = .compteRendu(reunion) } label: {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(date)
                    Text("\(Int(reunion.meta.duree / 60)) min")
                }
                .font(Typo.horodatage)
                .foregroundStyle(Color.encreDouce)
                .frame(width: 92, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(reunion.meta.titre).font(Typo.titreListe)
                    Text(compteRendu?.resume ?? "Pas encore analysée.")
                        .foregroundStyle(Color.encreDouce)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    if let dossier = reunion.dossier {
                        Text(dossier.lowercased()).font(Typo.horodatage)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Color.surface)
                    }
                    if let compteRendu {
                        Text("\(accord(compteRendu.decisions.count, "décision")) · \(accord(compteRendu.actions.count, "action"))")
                            .font(Typo.horodatage)
                            .foregroundStyle(Color.encreDouce)
                    }
                }
            }
            .padding(.vertical, 16)
            .overlay(alignment: .top) { Color.filet.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ListeActions: View {
    let modele: ModeleApp
    let actions: [ActionOuverte]

    var body: some View {
        ForEach(actions) { action in
            HStack(alignment: .top, spacing: 12) {
                Button { modele.cocher(action) } label: {
                    Rectangle().strokeBorder(Color.argile, lineWidth: 2).frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Marquer comme fait : \(action.element.texte)")
                Button { modele.ecran = .compteRendu(action.reunion) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.element.texte).multilineTextAlignment(.leading)
                        Text(([action.element.echeance ?? "pas de date", action.reunion.meta.titre]
                              + action.element.sources.prefix(1).map { horodatage($0) }).joined(separator: " · "))
                            .font(Typo.horodatage)
                            .foregroundStyle(Color.colonneSignal)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Color.colonneFilet.frame(height: 1) }
        }
    }
}

struct EcranAccueil: View {
    @Bindable var modele: ModeleApp

    var body: some View {
        Colonnes {
            Libelle(Date().formatted(.dateTime.locale(Locale(identifier: "fr_FR")).weekday(.wide).day().month(.wide)))
            TitreEcran(debut: "Bonjour, ", fin: "Steven")
        } contenu: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Libelle("réunions récentes").padding(.bottom, 10)
                    if modele.reunions.isEmpty {
                        Text("Pas encore de réunion. Lance la première à droite.")
                            .foregroundStyle(Color.encreDouce)
                    }
                    ForEach(modele.reunions) { LigneReunion(modele: modele, reunion: $0) }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 22)
            }
        } enteteEncre: {
            HStack {
                Libelle("nouvelle réunion", surColonne: true)
                Spacer()
                Text("⌘N").font(Typo.horodatage).foregroundStyle(Color.colonneDoux)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                Text("00:00").font(Typo.chrono).monospacedDigit().foregroundStyle(Color.chronoRepos)
                Spacer()
                Button("Démarrer") { modele.ecran = .nouvelle }
                    .buttonStyle(BoutonSignal())
                    .disabled(modele.session != nil)
            }
        } contenuEncre: {
            let actions = modele.actionsOuvertes()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("À faire suite aux réunions").font(Typo.titreSection).italic()
                    Spacer()
                    Text("\(actions.count)").font(Typo.horodatage).foregroundStyle(Color.colonneSignal)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ListeActions(modele: modele, actions: actions)
                    }
                }
                Libelle("chaque action renvoie au moment où elle a été dite", surColonne: true)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
    }
}

// MARK: - Nouvelle réunion

struct EcranNouvelle: View {
    @Bindable var modele: ModeleApp
    @State private var titre = ""
    @State private var type = TypeReunion.visio
    @State private var dossier = ""
    @State private var nouveauDossier = ""
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
                        }
                        .labelsHidden()
                        TextField("Ou un nouveau dossier", text: $nouveauDossier)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.champ)
                            .overlay { Rectangle().strokeBorder(Color.filet, lineWidth: 1) }
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
                    VStack(alignment: .leading, spacing: 8) {
                        Libelle("analyse à la fin")
                        Text("Locale · Apple Intelligence")
                    }
                }
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
            var choisi: String? = dossier.isEmpty ? nil : dossier
            let nom = nouveauDossier.trimmingCharacters(in: .whitespacesAndNewlines)
            if !nom.isEmpty { choisi = try? modele.bibliotheque?.creerDossier(nom) }
            await modele.demarrer(titre: titre, type: type, dossier: choisi, entree: entree)
            demarrage = false
        }
    }
}

// MARK: - En réunion

struct EcranEnReunion: View {
    @Bindable var modele: ModeleApp
    let session: SessionReunion
    @FocusState private var ligneActive: UUID?
    @State private var fin = false

    var body: some View {
        Colonnes {
            Libelle(session.reunion.dossier?.lowercased() ?? "réunion en cours")
            TitreEcran(debut: session.reunion.meta.titre, fin: "")
        } contenu: {
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
        } enteteEncre: {
            HStack {
                Rectangle().fill(Color.argile).frame(width: 9, height: 9)
                Libelle(session.etat.isEmpty ? "enregistrement en cours" : session.etat, surColonne: true)
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

// MARK: - Compte rendu

struct EcranCompteRendu: View {
    @Bindable var modele: ModeleApp
    let reunion: Reunion
    @State private var compteRendu: CompteRendu?
    @State private var segments: [Segment] = []
    @State private var notes: [LigneDeNote] = []
    @State private var selection: ElementSource?
    @State private var confirmerPCC = false
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
            Bulles(segments: passage, type: reunion.meta.type, sources: Set(selection?.sources ?? []), reunion: reunion)
        }
        .onAppear {
            compteRendu = modele.compteRendu(de: reunion)
            segments = reunion.segments()
            notes = reunion.notes()
            lecteur.charger(reunion)
        }
        .onDisappear { lecteur.arreter() }
        .onChange(of: occupee) { _, encore in
            guard !encore else { return }
            compteRendu = modele.compteRendu(de: reunion)
            segments = reunion.segments()
            lecteur.charger(reunion)
        }
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
            relecture
            boutonAnalyser("Analyser sur ce Mac", style: BoutonPrincipal())
            Libelle("rien ne quitte ce mac pour cette analyse")
            boutonPCC
            boutonMistral
            incidentsAudio
        }
    }

    private var occupee: Bool { modele.analyses[reunion.id] != nil || modele.relectures[reunion.id] != nil }

    private func boutonAnalyser<Style: ButtonStyle>(_ titre: String, style: Style) -> some View {
        Button(modele.analyses[reunion.id].map { "Analyse en cours · \(Int($0 * 100)) %" } ?? titre) {
            modele.analyser(reunion, avec: AnalysteApple.local)
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
            .alert("Envoyer cette réunion à Mistral ?", isPresented: $confirmerMistral) {
                Button("Envoyer cette réunion") { modele.analyserAvecMistral(reunion) }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("La transcription et tes notes partent chez Mistral pour cette analyse. L'audio reste sur ce Mac.")
            }
    }

    /// PCC : un envoi hors du Mac, donc une confirmation à chaque fois, pour cette réunion seule (règle 2).
    private var boutonPCC: some View {
        Button("Analyser avec Private Cloud Compute…") { confirmerPCC = true }
            .buttonStyle(BoutonSecondaire())
            .disabled(occupee || segments.isEmpty || !AnalysteApple.pccAutorise)
            .help(AnalysteApple.pccAutorise ? "" : "Apple doit d'abord autoriser Aparté à utiliser Private Cloud Compute.")
            .alert("Envoyer cette réunion à Private Cloud Compute ?", isPresented: $confirmerPCC) {
                Button("Envoyer cette réunion") { modele.analyser(reunion, avec: AnalysteApple.pcc) }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("La transcription et tes notes partent chez Apple pour cette analyse. L'audio reste sur ce Mac.")
            }
    }

    /// La relecture en cours, puis les voix à nommer.
    @ViewBuilder private var relecture: some View {
        if let avancee = modele.relectures[reunion.id] {
            Libelle("relecture de l'enregistrement · \(Int(avancee * 100)) %")
        }
        let voix = Array(Set(segments.compactMap(\.voix))).sorted()
        if !voix.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Libelle("les voix")
                ForEach(voix, id: \.self) { uneVoix in
                    HStack(spacing: 12) {
                        Text(uneVoix).font(Typo.horodatage).frame(width: 60, alignment: .leading)
                        TextField("Nom de cette personne", text: Binding(
                            get: { reunion.meta.nomsDesVoix?[uneVoix] ?? "" },
                            set: { modele.nommer(uneVoix, $0, dans: reunion) }))
                        .textFieldStyle(.plain)
                        .padding(6)
                        .background(Color.surface)
                        .accessibilityLabel("Nom de \(uneVoix)")
                    }
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
        HStack(alignment: .top, spacing: 14) {
            Color.terracotta.frame(width: 3)
            Text(compteRendu.resume).font(Typo.resume).textSelection(.enabled)
        }
        .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 10) {
            Button(copie ? "Copié" : "Copier le compte rendu") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(compteRendu.texteACopier(incidents: reunion.meta.incidentsAudio ?? []), forType: .string)
                copie = true
            }
            .buttonStyle(BoutonPrincipal())
            boutonAnalyser("Relancer l'analyse", style: BoutonSecondaire())
            boutonPCC
            boutonMistral
        }
        if compteRendu.passagesNonAnalyses > 0 || compteRendu.elementsEcartes > 0 {
            Libelle("\(accord(compteRendu.passagesNonAnalyses, "passage non analysé", "passages non analysés")) · \(accord(compteRendu.elementsEcartes, "élément écarté", "éléments écartés")) faute de source")
        }
        incidentsAudio
        relecture
        sectionSujets(compteRendu.sujets ?? [])
        section("décisions", compteRendu.decisions)
        section("actions", compteRendu.actions)
        section("questions ouvertes", compteRendu.questions)
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
                        .padding(10)
                        .background(choisi ? Color.encreColonne : Color.clear)
                        .foregroundStyle(choisi ? Color.colonneTexte : Color.encre)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(sujet.titre), à \(tempsParle(sujet.debut))")
                    .accessibilityHint("Affiche le passage de la transcription")
                    .accessibilityAddTraits(choisi ? [.isSelected, .isButton] : .isButton)
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
                            Rectangle().fill(choisi ? Color.argile : Color.clear).frame(width: 7, height: 7).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(element.texte).multilineTextAlignment(.leading)
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
                        .padding(10)
                        .background(choisi ? Color.encreColonne : Color.clear)
                        .foregroundStyle(choisi ? Color.colonneTexte : Color.encre)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
            Text("Répartir entre dossiers").font(Typo.titreSection)
            Text("Chaque dossier choisi reçoit un extrait avec ses sujets, sans l'audio. La réunion reste telle quelle.")
                .foregroundStyle(Color.encreDouce)
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
                Button("Annuler") { fermer() }.buttonStyle(BoutonSecondaire())
                Button("Créer les extraits") {
                    modele.repartir(reunion, choix)
                    fermer()
                }
                .buttonStyle(BoutonPrincipal())
                .disabled(choix.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(Color.creme)
        .foregroundStyle(Color.encre)
        .font(Typo.texte)
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
                .disabled((modele.compteRendu(de: reunion)?.sujets ?? []).isEmpty)
            Button("Relire l'enregistrement") { modele.relire(reunion) }
                .disabled(!FileManager.default.fileExists(atPath: reunion.micro.path))
            Divider()
            Button("Mettre à la corbeille…", role: .destructive) { corbeille = true }
        } label: {
            Libelle("gérer")
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

    var body: some View {
        Colonnes {
            Libelle("dossier · \(accord(reunions.count, "réunion"))")
            TitreEcran(debut: nom, fin: "")
        } contenu: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Libelle("le fil").padding(.bottom, 10)
                    ForEach(reunions) { LigneReunion(modele: modele, reunion: $0) }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 22)
            }
        } enteteEncre: {
            let actions = modele.actionsOuvertes(dossier: nom)
            Libelle("actions ouvertes", surColonne: true)
            Spacer(minLength: 0)
            Text("\(actions.count)").font(Typo.grandChiffre).monospacedDigit()
        } contenuEncre: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Dernières décisions").font(Typo.titreSection).italic().padding(.bottom, 12)
                    ForEach(reunions) { reunion in
                        ForEach(modele.resumeEnregistre(de: reunion)?.decisions ?? []) { decision in
                            Button { modele.ecran = .compteRendu(reunion) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(decision.texte).multilineTextAlignment(.leading)
                                    Text(reunion.meta.titre + (decision.sources.first.map { " · \(horodatage($0))" } ?? ""))
                                        .font(Typo.horodatage)
                                        .foregroundStyle(Color.colonneSignal)
                                }
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(alignment: .top) { Color.colonneFilet.frame(height: 1) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !modele.actionsOuvertes(dossier: nom).isEmpty {
                        Text("Actions").font(Typo.titreSection).italic().padding(.vertical, 12)
                        ListeActions(modele: modele, actions: modele.actionsOuvertes(dossier: nom))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            }
        }
    }
}

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
                    Libelle("analyste par défaut")
                    Text("Local · Apple Intelligence")
                    Text("Une réunion ne part chez Private Cloud Compute ou Mistral que si tu le demandes, une par une.").foregroundStyle(Color.encreDouce)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Libelle("clé mistral")
                    Text(modele.cleMistralPresente ? "Une clé est rangée dans le trousseau." : "Aucune clé pour l'instant.")
                        .foregroundStyle(Color.encreDouce)
                    SecureField("Colle ta clé d'API", text: $cle)
                        .textFieldStyle(.plain)
                        .padding(6)
                        .background(Color.surface)
                        .accessibilityLabel("Clé d'API Mistral")
                    HStack(spacing: 10) {
                        if !modele.cleMistralPresente {
                            Button("Reprendre la clé de Cairn") {
                                let reprise = modele.reprendreCleDeCairn()
                                resultatTest = reprise ? "La clé de Cairn est reprise. Tu peux la tester." : "Aucune clé de Cairn n'a pu être lue."
                            }
                            .buttonStyle(BoutonSecondaire())
                        }
                        Button("Enregistrer la clé") {
                            modele.enregistrerCleMistral(cle)
                            cle = ""
                            resultatTest = nil
                        }
                        .buttonStyle(BoutonPrincipal())
                        .disabled(cle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button(enTest ? "Test en cours…" : "Tester la clé") { tester() }
                            .buttonStyle(BoutonSecondaire())
                            .disabled(enTest || !modele.cleMistralPresente)
                        Button("Retirer la clé") {
                            modele.enregistrerCleMistral(nil)
                            resultatTest = nil
                        }
                        .buttonStyle(BoutonSecondaire())
                        .disabled(!modele.cleMistralPresente)
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
            Libelle("ce qui quitte le mac", surColonne: true)
            Spacer(minLength: 0)
            Text("\(modele.reunionsEnvoyees)").font(Typo.grandChiffre)
                .accessibilityLabel("\(accord(modele.reunionsEnvoyees, "réunion envoyée", "réunions envoyées")) hors du Mac")
        } contenuEncre: {
            VStack(alignment: .leading, spacing: 14) {
                Text("L'audio : jamais.")
                Text("La transcription et tes notes : seulement si tu lances toi-même une analyse avec Private Cloud Compute ou Mistral, pour cette réunion.")
                Text("Aucune télémétrie, aucun compte.")
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
        }
    }
}
