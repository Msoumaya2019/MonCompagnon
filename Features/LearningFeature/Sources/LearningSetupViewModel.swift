//
//  LearningSetupViewModel.swift
//  LearningFeature
//
//  La configuration d'un programme d'apprentissage, en une page.
//

import Combine
import Foundation
import LearningKit
import LearningPersistence
import Localization
import QuranKit
import QuranLocalization

/// La configuration d'un programme d'apprentissage.
///
/// Le modèle de vue ne tient pas les règles : il porte le **brouillon**, qui sait seul ce qui est
/// valide, ce qu'un morceau du Coran est devenu, et ce que le programme contiendra. L'écran ne fait
/// que rendre ce que le brouillon propose et lui transmettre les gestes.
///
/// La configuration est une **page unique** — trois sections et un bouton — et non plus un
/// assistant : il n'y a donc plus d'étape à franchir, ni de navigation à tenir. Ce qui reste à
/// tenir, c'est la condition du bouton, et elle seule.
@MainActor
final class LearningSetupViewModel: ObservableObject {
    // MARK: Lifecycle

    init(persistence: LearningPersistence, calendar: Calendar = .current, now: Date = Date()) {
        self.persistence = persistence
        self.calendar = calendar
        // Conservé : l'annonce du récapitulatif et la génération du programme doivent partir de la
        // **même** date. Les recalculer chacune à l'heure courante les ferait diverger — un
        // franchissement de minuit suffit — et l'utilisateur verrait une fin estimée que le
        // programme engendré ne tiendrait pas.
        self.now = now
        quran = persistence.quran

        let profile = persistence.loadProfile()
        // Reprendre un profil déjà configuré n'est pas recommencer : ses choix sont tous là.
        let draft = profile.isConfigured
            ? LearningSetupDraft(editing: profile, quran: quran, calendar: calendar)
            : LearningSetupDraft(quran: quran, calendar: calendar, createdAt: now)
        self.draft = draft
        summary = draft.summary(from: now)
    }

    // MARK: Internal

    /// Une ligne de la liste des morceaux : ce que l'écran affiche, déjà composé.
    ///
    /// L'écran ne connaît ni les libellés, ni les unités : il rend cette ligne telle quelle.
    struct PieceRow: Identifiable {
        let id: String
        let range: QuranRange
        let title: String
        /// Ce que la ligne annonce sous son titre : l'état déclaré, ou la taille du morceau.
        ///
        /// Un seul texte pour les deux sections : un morceau dont l'état est déclaré l'annonce, et
        /// un morceau muet annonce sa taille — l'information qui manque pour le choisir.
        let subtitle: String
        let solidity: KnownRange.Solidity?
        let isGoal: Bool
    }

    /// Un morceau déjà désigné, montré en pastille et retirable d'un geste.
    struct Pill: Identifiable {
        /// Ce que la pastille désigne — et donc ce que la retirer défait.
        enum Kind: String {
            /// Un objectif, à retirer des objectifs.
            case goal
            /// Un acquis solide, à effacer des acquis.
            case solide
            /// Un acquis fragile, à effacer des acquis.
            case fragile
        }

        let id: String
        let range: QuranRange
        let title: String
        let kind: Kind
    }

    /// Les quatre étapes de la configuration.
    ///
    /// L'étape vit ici, et non dans la vue : l'écran « ne décide de rien », et c'est ce qui la rend
    /// éprouvable sans la rendre. **Aucune étape ne bloque le passage à la suivante** : le brief ne
    /// le demande nulle part, et `canStart` garde déjà la création — une règle que personne n'a
    /// demandée coûte plus qu'elle ne rapporte.
    enum Step: String, CaseIterable {
        case connu
        case rythme
        case sens
        case resume
    }

    @Published private(set) var draft: LearningSetupDraft

    /// L'étape affichée.
    @Published private(set) var step: Step = .connu

    /// Le récapitulatif du programme tel qu'il serait engendré.
    ///
    /// Stocké plutôt que calculé à l'affichage : le calcul engendre le programme, et l'écran
    /// l'interroge à deux endroits — le récapitulatif et l'état du bouton.
    @Published private(set) var summary: LearningSetupDraft.Summary

    /// Vrai si le bouton « Créer mon programme » mène quelque part.
    ///
    /// La règle vit dans le brouillon, qui la tient pour les deux : l'écran lui passe le
    /// récapitulatif qu'il a déjà en main, sans quoi le programme serait engendré une seconde fois
    /// à chaque rafraîchissement.
    var canStart: Bool { draft.canStart(with: summary) }

    // MARK: - L'unité des choix

    var units: [LearningUnit] { LearningUnit.allCases }

    /// L'unité de la section « je connais déjà ».
    var knownUnit: LearningUnit { draft.knownUnit }

    /// L'unité de la section « mon objectif ».
    var goalUnit: LearningUnit { draft.goalUnit }

    func select(knownUnit unit: LearningUnit) {
        update { $0.knownUnit = unit }
    }

    func select(goalUnit unit: LearningUnit) {
        update { $0.goalUnit = unit }
    }

    /// Vrai si au moins un jour de travail est choisi.
    ///
    /// L'écran s'en sert pour dire **pourquoi** le bouton est éteint : « aucun jour » se corrige
    /// dans la section du rythme, « rien à apprendre » dans celle des objectifs.
    var hasWorkingDays: Bool { !draft.days.isEmpty }

    // MARK: - Les morceaux

    /// Les morceaux de l'unité affichée dans la section « je connais déjà ».
    func knownRows() -> [PieceRow] {
        rows(of: draft.knownChoices())
    }

    /// Les morceaux de l'unité affichée dans la section « mon objectif ».
    func goalRows() -> [PieceRow] {
        rows(of: draft.goalChoices())
    }

    /// Fait tourner l'état d'un morceau : rien → solide → fragile → rien.
    func cycleSolidity(of row: PieceRow) {
        update { $0.cycleSolidity(for: row.range) }
    }

    /// Ajoute ou retire un morceau des objectifs.
    func toggleGoal(_ row: PieceRow) {
        update { $0.toggleGoal(row.range) }
    }

    /// Le libellé de l'état déclaré, ou `nil` s'il n'y en a pas.
    func solidityTitle(_ solidity: KnownRange.Solidity?) -> String? {
        switch solidity {
        case .none:
            return nil
        case .some(.solide):
            return l("learning.known.solid", table: .learning)
        case .some(.fragile):
            return l("learning.known.fragile", table: .learning)
        }
    }

    /// Le nom d'un morceau, dans la langue de l'utilisateur.
    ///
    /// L'intervalle est d'abord rapproché d'un morceau **nommé** — une sourate, un juz', un hizb —
    /// parce que c'est ainsi qu'on l'a désigné. À défaut, il s'écrit en coordonnées : « 78:1 → 114:6 ».
    func title(of range: QuranRange) -> String {
        if let sura = quran.suras.first(where: { QuranRange($0) == range }) {
            return sura.localizedName()
        }
        if let juz = quran.juzs.first(where: { QuranRange($0) == range }) {
            return juz.localizedName
        }
        if let hizb = quran.hizbs.first(where: { QuranRange($0) == range }) {
            return hizb.localizedName
        }
        guard let bounds = range.bounds(in: quran) else { return "" }
        return "\(bounds.first.localizedCoordinate()) → \(bounds.last.localizedCoordinate())"
    }

    // MARK: - Les pastilles

    /// Les morceaux déclarés objectifs, dans l'ordre du mushaf.
    var goalPills: [Pill] { pills(of: draft.goals.map(\.range), kind: .goal) }

    /// Les morceaux déclarés connus : d'abord ceux qu'on récite sans hésiter, puis ceux qu'on oublie.
    var knownPills: [Pill] {
        pills(of: draft.known.filter { $0.solidity == .solide }.map(\.range), kind: .solide)
            + pills(of: draft.known.filter { $0.solidity == .fragile }.map(\.range), kind: .fragile)
    }

    /// Retire ce que la pastille désigne.
    ///
    /// C'est le **type** de la pastille qui décide, et non la section où elle est posée : une
    /// pastille d'objectif retire un objectif, une pastille d'acquis efface une déclaration. Le
    /// geste ne peut donc pas se tromper de cible, même si l'écran les montrait ailleurs.
    func remove(_ pill: Pill) {
        update { draft in
            switch pill.kind {
            case .goal:
                draft.toggleGoal(pill.range)
            case .solide, .fragile:
                draft.setSolidity(nil, for: pill.range)
            }
        }
    }

    // MARK: - Repartir de zéro, continuer le Coran

    /// Efface les déclarations — sans toucher au rythme, qui n'a pas été remis en question.
    func startFromScratch() {
        update { $0.startFromScratch() }
    }

    /// Prend le Coran entier comme objectif, pour le reprendre là où l'on s'est arrêté.
    func continueThroughTheQuran() {
        update { $0.continueThroughTheQuran() }
    }

    // MARK: - Les objectifs d'un geste

    var goalPresets: [LearningGoalPreset] { LearningGoalPreset.allCases }

    func presetTitle(_ preset: LearningGoalPreset) -> String {
        l("learning.goal.preset.\(preset.rawValue)", table: .learning)
    }

    /// Vrai si l'étendue du preset est **posée** — c'est-à-dire si elle est un des objectifs.
    ///
    /// Les deux choix qui ne portent pas d'intervalle n'ont pas d'état : ils amènent à la liste, où
    /// le morceau se désigne, et c'est la liste qui montre alors ce qui est choisi.
    func isActive(_ preset: LearningGoalPreset) -> Bool {
        guard let range = preset.range(in: quran) else { return false }
        return draft.isGoal(range)
    }

    /// Pose un objectif d'un geste.
    func apply(_ preset: LearningGoalPreset) {
        update { $0.apply(preset) }
    }

    // MARK: - Le rythme

    var paces: [LearningPace] { LearningPace.allCases }

    var pace: LearningPace { draft.pace }

    func select(pace: LearningPace) {
        update { $0.select(pace: pace) }
    }

    func paceTitle(_ pace: LearningPace) -> String {
        l("learning.pace.\(pace.rawValue).title", table: .learning)
    }

    func paceDetail(_ pace: LearningPace) -> String {
        l("learning.pace.\(pace.rawValue).detail", table: .learning)
    }

    /// Le nombre de versets visés par séance, dans l'unité où l'utilisateur les compte.
    ///
    /// L'allure personnalisée n'a pas de nombre à elle : elle affiche celui du brouillon, qui est
    /// exactement ce qui sera appliqué.
    func paceAmount(_ pace: LearningPace) -> String {
        let verses = pace.versesPerSession ?? draft.versesPerSession
        return lFormat("verses", table: .android, verses)
    }

    /// Vrai si l'allure choisie est celle que l'utilisateur chiffre lui-même.
    var isCustomPace: Bool { draft.pace == .personnalise }

    /// Les valeurs proposées quand l'utilisateur chiffre son rythme.
    ///
    /// Une liste de valeurs plutôt qu'un compteur : c'est déjà ainsi que la durée d'une séance est
    /// choisie, et une valeur qu'on ne peut pas viser du doigt se règle mal d'un pouce.
    var customVersesChoices: [Int] { [2, 3, 5, 8, 12, 20] }

    var versesPerSession: Int { draft.versesPerSession }

    func isVersesPerSession(_ verses: Int) -> Bool {
        draft.customVersesPerSession == verses
    }

    func setVersesPerSession(_ verses: Int) {
        update { $0.setVersesPerSession(verses) }
    }

    // MARK: - Les jours

    var days: [LearningDay] { LearningDay.allCases }

    func isWorking(_ day: LearningDay) -> Bool {
        draft.days.contains(day)
    }

    func toggle(day: LearningDay) {
        update { draft in
            if draft.days.contains(day) {
                draft.days.remove(day)
            } else {
                draft.days.insert(day)
            }
        }
    }

    func dayTitle(_ day: LearningDay) -> String {
        l("learning.day.\(day.rawValue)", table: .learning)
    }

    var sessionMinutesChoices: [Int] { [10, 15, 20, 30, 45] }

    var sessionMinutes: Int { draft.sessionMinutes }

    func setSessionMinutes(_ minutes: Int) {
        update { $0.sessionMinutes = minutes }
    }

    func sessionMinutesTitle(_ minutes: Int) -> String {
        lFormat("learning.days.session-minutes", table: .learning, minutes)
    }

    // MARK: - L'échéance

    /// L'échéance visée pour le programme entier, ou `nil`.
    var deadline: Date? { draft.deadline }

    /// L'échéance proposée à l'ouverture du sélecteur : dans un mois.
    var defaultDeadline: Date {
        calendar.date(byAdding: .day, value: 30, to: now) ?? now
    }

    func setDeadline(_ date: Date?) {
        update { $0.deadline = date }
    }

    /// Le rythme qu'exige l'échéance, ou `nil` s'il n'y a rien à tenir.
    var requiredVersesPerSession: Int? {
        guard let deadline else { return nil }
        return draft.requiredVersesPerSession(by: deadline, from: now)
    }

    /// Ce que l'échéance impose, en clair, ou `nil` s'il n'y a rien à annoncer.
    var deadlineHint: String? {
        guard let required = requiredVersesPerSession else { return nil }
        return lFormat("learning.deadline.required", table: .learning, required)
    }

    /// Vrai si le rythme choisi tient déjà l'échéance — il n'y a alors rien à appliquer.
    var holdsDeadline: Bool {
        guard let required = requiredVersesPerSession else { return true }
        return required <= versesPerSession
    }

    /// Applique le rythme qu'exige l'échéance.
    ///
    /// C'est ce qui fait d'une date de fin un rythme : l'utilisateur dit quand il veut finir, et
    /// c'est le programme qui en déduit combien il doit faire chaque jour.
    func applyRequiredPace() {
        guard let required = requiredVersesPerSession else { return }
        update { draft in
            draft.select(pace: .personnalise)
            draft.setVersesPerSession(required)
        }
    }

    /// La fin estimée, dans la langue de l'utilisateur.
    func endDateTitle(_ date: Date) -> String {
        Self.endDateFormatter.string(from: date)
    }

    // MARK: - Le sens

    var directions: [LearningDirection] { LearningDirection.allCases }

    /// Le sens dans lequel l'objectif sera parcouru.
    var direction: LearningDirection { draft.direction }

    func select(direction: LearningDirection) {
        update { $0.direction = direction }
    }

    func directionTitle(_ direction: LearningDirection) -> String {
        l("learning.direction.\(direction.rawValue).title", table: .learning)
    }

    func directionDetail(_ direction: LearningDirection) -> String {
        l("learning.direction.\(direction.rawValue).detail", table: .learning)
    }

    // MARK: - Terminer

    /// Enregistre le profil et engendre le programme correspondant.
    ///
    /// Le magasin est la seule source de vérité : c'est lui qui garde le profil et le programme, et
    /// l'écran d'accueil les relira au retour. Le programme est engendré ici, et non à l'ouverture
    /// du programme, pour qu'aucune configuration ne reste sans programme.
    func start() {
        let profile = draft.makeProfile()
        persistence.saveProfile(profile)
        persistence.regenerateProgram(for: profile, from: now)
    }

    // MARK: - Les étapes

    var isFirstStep: Bool { step == .connu }

    var isLastStep: Bool { step == .resume }

    /// Le titre de l'étape, avec sa place dans le parcours.
    ///
    /// La place est écrite **dans chaque libellé** plutôt que composée à partir d'un format : la
    /// table de localisation du dépôt ne porte que des formats à un seul argument (`verses`,
    /// `%d min`), et un titre entier se traduit mieux qu'un assemblage de morceaux.
    var stepTitle: String { l("learning.step.\(step.rawValue)", table: .learning) }

    /// Avance d'une étape. Sans effet sur la dernière : c'est la création, et elle est gardée.
    func advance() {
        let steps = Step.allCases
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return }
        step = steps[index + 1]
    }

    /// Revient d'une étape. Sans effet sur la première.
    func goBack() {
        let steps = Step.allCases
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        step = steps[index - 1]
    }

    // MARK: Private

    private static let endDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    private let persistence: LearningPersistence
    private let quran: Quran
    private let calendar: Calendar

    /// Le moment où l'écran s'est ouvert — la même date pour l'annonce et pour le programme.
    private let now: Date

    /// Compose les lignes d'une liste de choix.
    ///
    /// L'état déclaré prime sur la taille : quand l'utilisateur s'est prononcé, c'est ce qu'il a dit
    /// qu'il faut lui rappeler, et non le nombre de versets qu'il connaît déjà.
    private func rows(of choices: [LearningSetupDraft.Choice]) -> [PieceRow] {
        choices.map { choice in
            PieceRow(
                id: choice.id,
                range: choice.range,
                title: title(of: choice.range),
                subtitle: solidityTitle(choice.solidity) ?? lFormat("verses", table: .android, choice.verseCount),
                solidity: choice.solidity,
                isGoal: choice.isGoal
            )
        }
    }

    /// Compose les pastilles d'une liste d'intervalles.
    ///
    /// L'identité combine le type et les bornes : deux pastilles ne peuvent donc pas se confondre,
    /// même si le même morceau est à la fois un objectif et un acquis — ce qui arrive dès qu'on
    /// déclare fragile ce qu'on vient de se donner comme objectif.
    private func pills(of ranges: [QuranRange], kind: Pill.Kind) -> [Pill] {
        ranges.map { range in
            Pill(
                id: "\(kind.rawValue)-\(range.firstSura):\(range.firstAyah)-\(range.lastSura):\(range.lastAyah)",
                range: range,
                title: title(of: range),
                kind: kind
            )
        }
    }

    /// Applique une modification au brouillon, et remet le récapitulatif à jour.
    ///
    /// Le brouillon est un type valeur : le réécrire est ce qui prévient l'écran du changement, et
    /// c'est aussi ce qui garantit qu'aucune modification n'oublie de recalculer l'annonce.
    private func update(_ body: (inout LearningSetupDraft) -> Void) {
        var updated = draft
        body(&updated)
        draft = updated
        summary = updated.summary(from: now)
    }
}
