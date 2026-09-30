//
//  LearningSetupDraft.swift
//  LearningKit
//
//  L'état de la configuration guidée, avant qu'il ne devienne un profil.
//

import Foundation
import QuranKit

/// Le brouillon d'une configuration guidée.
///
/// La configuration se corrige : on revient sur l'étape précédente, on décoche un juz', on change
/// d'allure. Ce type porte cet état intermédiaire et n'engendre le profil qu'une fois la dernière
/// étape validée.
///
/// Tout ce qui décide ici se vérifie sans interface — les choix, leur validité, le nombre de
/// séances, la date de fin estimée. La vue ne fait que rendre `juzChoices()` et appeler les
/// mutations.
public struct LearningSetupDraft: Equatable {
    // MARK: Lifecycle

    public init(
        quran: Quran = .hafsMadani1405,
        calendar: Calendar = .current,
        createdAt: Date = Date()
    ) {
        self.quran = quran
        self.calendar = calendar
        self.createdAt = createdAt
    }

    /// Reprend un profil existant pour le modifier.
    ///
    /// La date de création est **conservée** : modifier son programme n'est pas recommencer son
    /// apprentissage, et `LearningProfile.createdAt` est de toute façon immuable.
    public init(
        editing profile: LearningProfile,
        quran: Quran = .hafsMadani1405,
        calendar: Calendar = .current
    ) {
        self.init(quran: quran, calendar: calendar, createdAt: profile.createdAt)
        known = profile.knownRanges
        goals = profile.goals
        pace = profile.pace
        days = profile.days
        sessionMinutes = profile.sessionMinutes
    }

    // MARK: Public

    /// Les étapes de la configuration, dans l'ordre où elles se présentent.
    public enum Step: Int, CaseIterable, Equatable {
        /// Ce que l'utilisateur connaît déjà — étape que l'on peut passer.
        case known
        /// Ce qu'il veut apprendre.
        case goals
        /// À quel rythme.
        case pace
        /// Quels jours, et combien de temps par séance.
        case days
        /// Le récapitulatif, avant de commencer.
        case summary
    }

    /// Un choix proposé aux étapes « ce que je connais » et « ce que je veux apprendre ».
    public struct Choice: Equatable {
        /// Le numéro du juz' — sert aussi à composer son nom dans la langue de l'utilisateur,
        /// que ce module ne connaît pas.
        public let juzNumber: Int
        public let range: QuranRange
        public let verseCount: Int
        /// `nil` si l'utilisateur ne s'est pas prononcé sur ce juz'.
        public let solidity: KnownRange.Solidity?
        public let isGoal: Bool
    }

    /// Ce que le programme proposé contient, tel qu'on l'annonce avant de commencer.
    public struct Summary: Equatable {
        /// Nombre de passages à travailler, une séance chacun.
        public let sessionCount: Int
        /// Nombre de passages ajoutés en révision parce que déclarés fragiles.
        public let reviewCount: Int
        /// Versets restant à apprendre.
        public let remainingVerses: Int
        /// Date de fin estimée, ou `nil` si aucun jour de travail n'est choisi.
        public let estimatedEndDate: Date?

        /// Vrai s'il n'y a **rien** à programmer, ni à apprendre ni à revoir.
        ///
        /// Les deux comptes sont nécessaires : un objectif entièrement fragile n'a plus rien
        /// à apprendre mais reste un programme — il est à revoir. Ne regarder que les séances
        /// d'apprentissage ferait passer ce programme pour vide, et le bouton « Commencer »
        /// resterait éteint alors qu'il y a précisément quelque chose à faire.
        public var isEmpty: Bool { sessionCount == 0 && reviewCount == 0 }
    }

    /// Le mushaf de référence, qui définit les bornes et la taille des unités.
    public let quran: Quran

    /// Le calendrier qui définit ce qu'est « un jour », et donc les échéances.
    public let calendar: Calendar

    /// Date de création du profil — celle de l'appelant, jamais réécrite par la configuration.
    public let createdAt: Date

    /// L'étape affichée.
    public private(set) var step: Step = .known

    /// Les intervalles déclarés connus, triés par position dans le mushaf.
    public private(set) var known: [KnownRange] = []

    /// Les intervalles déclarés à apprendre, triés par position dans le mushaf.
    public private(set) var goals: [LearningGoal] = []

    /// L'allure choisie.
    public var pace: LearningPace = .regulier

    /// Les jours de travail choisis.
    public var days: Set<LearningDay> = Set(LearningDay.allCases)

    /// Durée annoncée d'une séance, en minutes.
    public var sessionMinutes: Int = 15

    /// Vrai sur la première étape : « Précédent » n'y mène nulle part.
    public var isFirstStep: Bool { step == Step.allCases.first }

    /// Vrai sur la dernière étape : le bouton dit « Commencer » plutôt que « Suivant ».
    public var isLastStep: Bool { step == Step.allCases.last }

    /// Vrai si l'étape courante permet d'aller plus loin.
    ///
    /// Le brouillon **refuse** d'avancer tant que c'est faux. L'interface désactive le bouton, mais
    /// une vue fautive ne doit pas pouvoir sauter un choix obligatoire.
    public var canAdvance: Bool {
        switch step {
        case .known, .pace:
            return true
        case .goals:
            return !goals.isEmpty
        case .days, .summary:
            return !days.isEmpty
        }
    }

    /// Vrai si le programme proposé contient au moins un passage à travailler.
    ///
    /// Distinct de `canAdvance` : la navigation exige un jour de travail, le démarrage exige en
    /// plus qu'il reste quelque chose à apprendre. Un objectif entièrement déclaré connu passe donc
    /// l'étape des jours sans permettre de commencer.
    ///
    /// - Note: cette question **génère le programme** pour y répondre. Une vue ne doit donc pas
    ///   l'appeler à chaque rafraîchissement : elle calcule `summary(from:)` une fois et interroge
    ///   `isEmpty`, qui répond à la même question sur le résultat déjà obtenu.
    public func canStart(from date: Date = Date()) -> Bool {
        canAdvance && !summary(from: date).isEmpty
    }

    // MARK: - Navigation

    /// Avance d'une étape, sauf si l'étape courante est incomplète ou si c'est la dernière.
    @discardableResult
    public mutating func advance() -> Bool {
        guard canAdvance, let next = Step(rawValue: step.rawValue + 1) else { return false }
        step = next
        return true
    }

    /// Recule d'une étape, sans jamais descendre sous la première.
    @discardableResult
    public mutating func back() -> Bool {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return false }
        step = previous
        return true
    }

    /// Va directement à une étape, dans les deux sens.
    public mutating func go(to step: Step) {
        self.step = step
    }

    // MARK: - Étape « ce que je connais »

    /// L'état déclaré pour un intervalle, ou `nil` s'il n'a pas été déclaré.
    public func solidity(of range: QuranRange) -> KnownRange.Solidity? {
        known.first { $0.range == range }?.solidity
    }

    /// Déclare un intervalle comme solide, comme fragile, ou ne déclare rien.
    ///
    /// L'identifiant et le libellé déjà posés sont conservés : passer de « solide » à « fragile »
    /// corrige une déclaration, ce n'est pas en effacer une pour en écrire une autre.
    public mutating func setSolidity(
        _ solidity: KnownRange.Solidity?,
        for range: QuranRange,
        label: String? = nil
    ) {
        let existing = known.first { $0.range == range }
        known.removeAll { $0.range == range }
        guard let solidity else { return }
        known.append(
            KnownRange(
                id: existing?.id ?? UUID(),
                range: range,
                label: label ?? existing?.label,
                solidity: solidity
            )
        )
        known = orderedByPosition(known, \.range)
    }

    /// Fait tourner l'état d'un intervalle : rien → solide → fragile → rien.
    public mutating func cycleSolidity(for range: QuranRange, label: String? = nil) {
        switch solidity(of: range) {
        case .none:
            setSolidity(.solide, for: range, label: label)
        case .some(.solide):
            setSolidity(.fragile, for: range, label: label)
        case .some(.fragile):
            setSolidity(nil, for: range, label: label)
        }
    }

    /// Fait tourner l'état d'un groupe du Coran — juz', sourate, hizb, page.
    public mutating func cycleSolidity(of group: some QuranGroup, label: String? = nil) {
        cycleSolidity(for: QuranRange(group), label: label)
    }

    // MARK: - Étape « ce que je veux apprendre »

    /// Vrai si l'intervalle est un objectif.
    public func isGoal(_ range: QuranRange) -> Bool {
        goals.contains { $0.range == range }
    }

    /// Ajoute ou retire un objectif, sans toucher à son échéance.
    public mutating func toggleGoal(_ range: QuranRange, label: String? = nil) {
        if goals.contains(where: { $0.range == range }) {
            goals.removeAll { $0.range == range }
            return
        }
        goals.append(LearningGoal(range: range, label: label, targetDate: nil))
        goals = orderedByPosition(goals, \.range)
    }

    /// Ajoute ou retire un objectif désigné par un groupe du Coran.
    public mutating func toggleGoal(of group: some QuranGroup, label: String? = nil) {
        toggleGoal(QuranRange(group), label: label)
    }

    /// L'échéance fixée pour un objectif, ou `nil` s'il n'y en a pas.
    public func deadline(for range: QuranRange) -> Date? {
        goals.first { $0.range == range }?.targetDate
    }

    /// Fixe — ou efface — l'échéance d'un objectif.
    ///
    /// Sans effet si l'intervalle n'est pas un objectif : une échéance orpheline serait invisible
    /// et survivrait au retrait de l'objectif.
    public mutating func setDeadline(_ date: Date?, for range: QuranRange) {
        guard let position = goals.firstIndex(where: { $0.range == range }) else { return }
        let goal = goals[position]
        goals[position] = LearningGoal(
            id: goal.id,
            range: goal.range,
            label: goal.label,
            targetDate: date
        )
    }

    // MARK: - Les choix proposés

    /// Les juz' du mushaf, avec l'état du brouillon pour chacun.
    ///
    /// Le juz' est la maille du choix : c'est l'unité dont un utilisateur dit « je le connais »,
    /// et elle tient en trente lignes. La sourate irait de 3 à 286 versets, la page en demanderait
    /// 604, et ni l'une ni l'autre ne se récite d'un trait.
    public func juzChoices() -> [Choice] {
        quran.juzs.map { juz in
            let range = QuranRange(juz)
            return Choice(
                juzNumber: juz.juzNumber,
                range: range,
                verseCount: range.verseCount(in: quran),
                solidity: solidity(of: range),
                isGoal: isGoal(range)
            )
        }
    }

    // MARK: - Résultat

    /// Le profil correspondant au brouillon, marqué comme configuré.
    public func makeProfile() -> LearningProfile {
        LearningProfile(
            knownRanges: known,
            goals: goals,
            pace: pace,
            days: days,
            sessionMinutes: sessionMinutes,
            createdAt: createdAt,
            isConfigured: true
        )
    }

    /// Le programme tel qu'il serait généré aujourd'hui, et ce qu'on en annonce.
    ///
    /// Le planificateur n'a pas d'état : annoncer trois séances puis en générer trois est le même
    /// calcul, donc l'annonce ne peut pas mentir sur ce qui suivra.
    public func summary(from date: Date = Date()) -> Summary {
        let profile = makeProfile()
        let program = planner.makeProgram(for: profile, from: date)
        let toLearn = program.items.filter { $0.storedStatus == .notLearned }.count
        return Summary(
            sessionCount: toLearn,
            reviewCount: program.items.count - toLearn,
            remainingVerses: program.totalVerses(in: quran) - program.learnedVerses(in: quran),
            estimatedEndDate: planner.estimatedEndDate(for: program, profile: profile, from: date)
        )
    }

    // MARK: Private

    private var planner: LearningPlanner { LearningPlanner(quran: quran, calendar: calendar) }
}

/// Range des intervalles dans l'ordre du mushaf.
///
/// L'ordre est fixé à la saisie plutôt qu'à l'affichage : deux brouillons qui portent les mêmes
/// déclarations doivent être égaux, quel que soit l'ordre dans lequel on les a saisies.
private func orderedByPosition<T>(_ values: [T], _ range: (T) -> QuranRange) -> [T] {
    values.sorted {
        let first = range($0)
        let second = range($1)
        return (first.firstSura, first.firstAyah) < (second.firstSura, second.firstAyah)
    }
}
