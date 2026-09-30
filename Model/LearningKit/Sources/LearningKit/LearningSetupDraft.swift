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
/// séances, la date de fin estimée, et son calcul inverse. La vue ne fait que rendre
/// `choices(for:)` et appeler les mutations.
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
        customVersesPerSession = profile.customVersesPerSession
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

    /// Un choix proposé aux sections « je connais déjà » et « mon objectif ».
    ///
    /// Le même type sert aux trois unités : un morceau du Coran est un morceau du Coran, et l'unité
    /// n'est qu'une façon de le désigner.
    public struct Choice: Equatable, Identifiable {
        /// L'unité désignée — une sourate, un hizb ou un juz'.
        public let unit: LearningUnit
        /// Le rang de l'unité dans le mushaf, à partir de 1.
        public let number: Int
        public let range: QuranRange
        public let verseCount: Int
        /// `nil` si l'utilisateur ne s'est pas prononcé sur ce morceau.
        public let solidity: KnownRange.Solidity?
        public let isGoal: Bool

        /// L'identité d'un choix : son unité **et** son rang.
        ///
        /// Le rang seul ne suffirait pas — le hizb 3 et le juz' 3 sont deux morceaux différents — et
        /// l'intervalle ne suffirait pas davantage : deux unités peuvent couvrir le même intervalle
        /// sans être le même morceau à désigner.
        public var id: String { "\(unit.rawValue)-\(number)" }
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

    /// L'unité dans laquelle l'utilisateur désigne les morceaux du Coran.
    ///
    /// Elle ne vaut que pour **désigner** : ce qui est déjà déclaré reste, quelle que soit l'unité
    /// affichée. Changer d'unité ne défait donc rien, et c'est ce qui permet de déclarer une sourate
    /// connue puis un juz' à apprendre sans repasser par le début.
    public var unit: LearningUnit = .juz

    /// L'allure choisie.
    ///
    /// En lecture seule : choisir une allure n'est pas seulement poser une valeur, c'est aussi
    /// **poser le nombre** qui va avec quand elle est personnalisée. Une écriture directe
    /// laisserait passer une allure sans nombre.
    public private(set) var pace: LearningPace = .regulier

    /// Le nombre de versets par séance quand l'allure est `.personnalise`.
    public private(set) var customVersesPerSession: Int?

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

    // MARK: - Repartir de zéro

    /// Efface toutes les déclarations : ni acquis, ni objectif.
    ///
    /// N'efface **pas** l'allure, les jours ni la durée de séance : repartir de zéro porte sur ce
    /// qu'on sait et sur ce qu'on vise, pas sur la manière dont on veut travailler. Tout effacer
    /// obligerait à rechoisir un rythme qu'on n'a pas remis en question.
    public mutating func startFromScratch() {
        known = []
        goals = []
    }

    // MARK: - Continuer le Coran

    /// Prend le Coran entier comme objectif, pour le reprendre là où l'on s'est arrêté.
    ///
    /// Un seul objectif qui couvre le mushaf : le découpage part donc du début, et c'est le relevé
    /// de progression qui marque comme appris tout ce qui l'est déjà. Le programme reprend alors
    /// exactement au verset suivant le dernier appris — sans qu'aucune date n'entre en jeu, et sans
    /// que les jours manqués n'ajoutent quoi que ce soit.
    ///
    /// Les objectifs déjà posés sont **remplacés** : le Coran entier les contient tous, et les
    /// garder à côté ferait compter deux fois les mêmes versets.
    public mutating func continueThroughTheQuran() {
        goals = [LearningGoal(range: QuranRange(quran), label: nil, targetDate: nil)]
    }

    // MARK: - Les choix proposés

    /// Les morceaux d'une unité, avec l'état du brouillon pour chacun.
    ///
    /// L'unité est un paramètre, et non une lecture de `self.unit` : l'écran doit pouvoir préparer
    /// la liste d'une autre unité que celle affichée — c'est ce qui lui permet de ne pas faire
    /// clignoter les pastilles au moment du changement.
    public func choices(for unit: LearningUnit) -> [Choice] {
        switch unit {
        case .sourate:
            return quran.suras.map { sura in
                makeChoice(unit: .sourate, number: sura.suraNumber, range: QuranRange(sura))
            }
        case .hizb:
            return quran.hizbs.map { hizb in
                makeChoice(unit: .hizb, number: hizb.hizbNumber, range: QuranRange(hizb))
            }
        case .juz:
            return quran.juzs.map { juz in
                makeChoice(unit: .juz, number: juz.juzNumber, range: QuranRange(juz))
            }
        }
    }

    /// Les morceaux de l'unité affichée.
    public func choices() -> [Choice] {
        choices(for: unit)
    }

    // MARK: - Le rythme

    /// Choisit une allure.
    ///
    /// Choisir « personnalisé » **pose** un nombre — celui de l'allure régulière — faute de quoi le
    /// programme serait découpé au repli du profil, un nombre que l'utilisateur n'a jamais vu. Le
    /// nombre est ensuite ajusté par l'écran, qui seul sait le montrer.
    ///
    /// Le nombre déjà posé n'est **pas** écrasé : revenir à « personnalisé » après un détour par
    /// une autre allure retrouve le nombre qu'on avait choisi.
    public mutating func select(pace: LearningPace) {
        self.pace = pace
        if pace == .personnalise, customVersesPerSession == nil {
            customVersesPerSession = LearningPace.regulier.versesPerSession
        }
    }

    /// Fixe le nombre de versets par séance d'une allure personnalisée.
    ///
    /// Sans effet sur une allure fixe : son rythme vient de l'allure, et l'écraser ici ferait
    /// croire à un choix qui ne serait pas appliqué. La valeur est bornée à un verset au moins,
    /// sans quoi le découpage n'avancerait pas.
    public mutating func setVersesPerSession(_ verses: Int) {
        guard pace == .personnalise else { return }
        customVersesPerSession = max(1, verses)
    }

    /// Le nombre de versets par séance, valeur personnalisée comprise.
    ///
    /// Passe par le profil, qui porte la règle : la réécrire ici la ferait diverger, et c'est
    /// exactement le genre d'écart qui ne se voit qu'une fois le programme engendré.
    public var versesPerSession: Int { makeProfile().versesPerSession }

    /// Le nombre de versets par séance qu'exige une échéance.
    ///
    /// C'est le calcul **inverse** de l'estimation de fin : au lieu de demander « quand aurai-je
    /// fini ? », on demande « que dois-je faire pour finir à cette date ? ».
    ///
    /// - Note: c'est une **cible**, pas une promesse. Le découpage arrondit chaque séance à une fin
    ///   de page, et certaines séances portent donc plus de versets que ce nombre ; l'échéance peut
    ///   s'en trouver avancée, jamais reculée.
    ///
    /// - Returns: `nil` s'il n'y a rien à apprendre, si aucun jour de travail n'est choisi, ou si
    ///   l'échéance ne laisse aucun jour de travail devant elle.
    public func requiredVersesPerSession(by deadline: Date, from date: Date = Date()) -> Int? {
        let remaining = summary(from: date).remainingVerses
        guard remaining > 0 else { return nil }

        let available = planner.workingDays(from: date, through: deadline, days: days)
        guard available > 0 else { return nil }
        // Arrondi au supérieur : une séance entamée est une séance à faire.
        return (remaining + available - 1) / available
    }

    // MARK: - Résultat

    /// Le profil correspondant au brouillon, marqué comme configuré.
    public func makeProfile() -> LearningProfile {
        LearningProfile(
            knownRanges: known,
            goals: goals,
            pace: pace,
            customVersesPerSession: customVersesPerSession,
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

    /// Compose un choix à partir de son unité, de son rang et de son intervalle.
    ///
    /// Les trois unités passent par ici : c'est ce qui garantit qu'elles rapportent le même genre
    /// d'état — la solidité déclarée et l'objectif — sans trois copies à faire diverger.
    private func makeChoice(unit: LearningUnit, number: Int, range: QuranRange) -> Choice {
        Choice(
            unit: unit,
            number: number,
            range: range,
            verseCount: range.verseCount(in: quran),
            solidity: solidity(of: range),
            isGoal: isGoal(range)
        )
    }
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
