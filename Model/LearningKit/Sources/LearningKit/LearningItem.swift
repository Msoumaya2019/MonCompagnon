//
//  LearningItem.swift
//  LearningKit
//
//  Une unité de programme : le plus petit bloc qu'un utilisateur peut marquer comme appris.
//

import Foundation
import QuranKit

/// L'état d'un passage dans le programme, qui pilote les trois cases de l'écran d'apprentissage.
public enum LearningStatus: String, Codable, CaseIterable, Sendable {
    /// « Pas encore appris » — jamais travaillé.
    case notLearned
    /// « Appris » — travaillé et validé.
    case learned
    /// « À revoir » — travaillé, mais une révision est due (J+1, J+3 ou J+7 dépassé).
    case toReview

    // MARK: Public

    /// L'état tel qu'il doit être présenté, en tenant compte de la date du jour.
    ///
    /// C'est ici que vit la consolidation : un passage `learned` dont la prochaine révision est
    /// due devient `toReview`. Le modèle ne stocke donc pas « à revoir » — il le **déduit**, ce qui
    /// évite qu'un état stocké devienne faux en vieillissant.
    public static func resolve(stored: LearningStatus, nextReview: Date?, now: Date, calendar: Calendar) -> LearningStatus {
        guard stored == .learned else { return stored }
        guard let nextReview else { return .learned }
        return calendar.startOfDay(for: nextReview) <= calendar.startOfDay(for: now) ? .toReview : .learned
    }
}

/// Le verdict de fin de séance sur un passage.
///
/// Trois verdicts, et **aucun état de plus** : la difficulté n'est pas un état à stocker, c'est un
/// **raccourcissement de l'intervalle**. Un passage jugé difficile repart à J+1 au lieu de J+3 ou
/// J+7 — ce que `LearningConsolidation.nextReview(afterSuccessAt:)` sait déjà exprimer. Un
/// quatrième `LearningStatus` vieillirait mal : `toReview` est *déduit* d'une date, pas stocké.
public enum LearningOutcome: String, Codable, CaseIterable, Sendable {
    /// « Bien appris » — le passage franchit une étape : J+1, puis J+3, puis J+7, puis consolidé.
    case bienAppris
    /// « À consolider » — le passage ne franchit pas d'étape et reste dû, donc « à revoir ».
    case aConsolider
    /// « Difficile » — le passage repart du bas de l'échelle, avec une révision à J+1.
    case difficile
}

/// Un passage du programme.
public struct LearningItem: Codable, Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        range: QuranRange,
        label: String?,
        position: Int
    ) {
        self.id = id
        self.range = range
        self.label = label
        self.position = position
        storedStatus = .notLearned
        reviewStage = 0
        nextReview = nil
        lastWorkedAt = nil
    }

    // MARK: Public

    public let id: UUID
    public let range: QuranRange
    public let label: String?
    /// Rang dans le programme — permet de reprendre exactement où l'on s'est arrêté.
    public let position: Int

    /// État tel qu'enregistré. À confronter à `status(now:calendar:)` pour connaître l'état réel.
    public internal(set) var storedStatus: LearningStatus

    /// Combien de fois ce passage a été révisé avec succès : 0 → prochaine à J+1,
    /// 1 → J+3, 2 → J+7, 3 → consolidé (plus de révision programmée).
    public internal(set) var reviewStage: Int

    /// Date de la prochaine révision due. `nil` si consolidé ou jamais appris.
    public internal(set) var nextReview: Date?

    /// Dernière fois que ce passage a été travaillé.
    public internal(set) var lastWorkedAt: Date?

    /// Nombre de versets de ce passage, dans un mushaf donné.
    public func verseCount(in quran: Quran) -> Int {
        range.verseCount(in: quran)
    }

    /// La quantité à afficher (« 1 page », « 3 versets »).
    public func amount(in quran: Quran) -> QuranAmount {
        range.amount(in: quran)
    }

    /// L'état réel, aujourd'hui.
    public func status(now: Date, calendar: Calendar = .current) -> LearningStatus {
        LearningStatus.resolve(stored: storedStatus, nextReview: nextReview, now: now, calendar: calendar)
    }

    /// Vrai si une révision est due à cette date.
    public func isReviewDue(now: Date, calendar: Calendar = .current) -> Bool {
        status(now: now, calendar: calendar) == .toReview
    }

    /// Vrai si le passage est consolidé : appris et plus aucune révision programmée.
    public var isConsolidated: Bool {
        storedStatus == .learned && nextReview == nil && reviewStage >= LearningConsolidation.intervals.count
    }

    // MARK: Internal

    /// Les bornes, ou `nil` si l'intervalle n'est pas valide dans ce mushaf.
    func bounds(in quran: Quran) -> (first: AyahNumber, last: AyahNumber)? {
        range.bounds(in: quran)
    }

    /// Applique le verdict d'une séance à ce passage — la règle, en un seul endroit.
    ///
    /// Le verdict porte sur un passage **déjà appris** : les trois nombres du plan supposent une
    /// échelle entamée. C'est `markLearned` qui ouvre cette échelle, et lui seul sait que la
    /// première révision tombe à J+1. Un passage jamais appris est donc laissé intact, comme
    /// `LearningProgram.markReviewed` le refuse déjà.
    mutating func apply(_ outcome: LearningOutcome, at date: Date, calendar: Calendar) {
        guard storedStatus != .notLearned else { return }

        // Travailler le passage compte comme une journée de travail, quel que soit le verdict :
        // c'est ce que lit la série.
        lastWorkedAt = date

        switch outcome {
        case .bienAppris:
            let nextStage = reviewStage + 1
            reviewStage = nextStage
            nextReview = LearningConsolidation.nextReview(afterSuccessAt: nextStage, from: date, calendar: calendar)
        case .aConsolider:
            // Ni l'étape ni l'échéance ne bougent : le passage reste dû, donc toujours « à revoir ».
            break
        case .difficile:
            reviewStage = 0
            nextReview = LearningConsolidation.nextReview(afterSuccessAt: 0, from: date, calendar: calendar)
        }
    }
}

/// Les intervalles de consolidation, dans l'ordre.
///
/// Séparé du reste pour que la politique de révision soit lisible et vérifiable d'un coup d'œil :
/// c'est une règle pédagogique, pas un détail d'implémentation.
public enum LearningConsolidation {
    /// J+1, puis J+3, puis J+7.
    public static let intervals: [Int] = [1, 3, 7]

    /// Date de la prochaine révision après un succès à l'étape `stage`.
    ///
    /// - Parameter stage: nombre de révisions déjà réussies pour ce passage.
    /// - Returns: la date due, ou `nil` si le passage est consolidé.
    public static func nextReview(
        afterSuccessAt stage: Int,
        from date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard stage < intervals.count else { return nil }
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: intervals[stage], to: day)
    }
}
