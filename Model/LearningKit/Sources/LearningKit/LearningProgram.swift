//
//  LearningProgram.swift
//  LearningKit
//
//  Le programme d'apprentissage : une suite ordonnée de passages, plus les transitions d'état.
//

import Foundation
import QuranKit

/// Le programme d'un utilisateur.
///
/// Type valeur : toute modification produit un nouveau programme. C'est ce qui rend les
/// transitions testables sans dépôt, et impossible de muter l'état affiché par accident.
public struct LearningProgram: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(items: [LearningItem] = [], generatedAt: Date? = nil) {
        self.items = items
        self.generatedAt = generatedAt
    }

    // MARK: Public

    /// Les passages, dans l'ordre du programme.
    public private(set) var items: [LearningItem]

    /// Date de génération — `nil` si le programme n'a jamais été produit.
    public private(set) var generatedAt: Date?

    /// Un programme vide.
    public static var empty: LearningProgram { LearningProgram() }

    /// Vrai tant qu'aucun programme n'a été généré.
    public var isEmpty: Bool { items.isEmpty }

    // MARK: - Lecture

    /// L'état de chaque passage à une date donnée, dans l'ordre du programme.
    public func statuses(now: Date, calendar: Calendar = .current) -> [UUID: LearningStatus] {
        items.reduce(into: [:]) { result, item in
            result[item.id] = item.status(now: now, calendar: calendar)
        }
    }

    /// Les passages dont la révision est due à cette date, dans l'ordre du programme.
    public func dueReviews(now: Date, calendar: Calendar = .current) -> [LearningItem] {
        items.filter { $0.isReviewDue(now: now, calendar: calendar) }
    }

    /// Le prochain passage non encore appris — là où reprendre.
    public func nextToLearn() -> LearningItem? {
        items.first { $0.storedStatus == .notLearned }
    }

    /// Nombre total de versets du programme.
    public func totalVerses(in quran: Quran) -> Int {
        items.reduce(0) { $0 + $1.verseCount(in: quran) }
    }

    /// Nombre de versets déjà appris (y compris ceux à revoir : ils ont été appris).
    public func learnedVerses(in quran: Quran) -> Int {
        items
            .filter { $0.storedStatus != .notLearned }
            .reduce(0) { $0 + $1.verseCount(in: quran) }
    }

    /// Avancement entre 0 et 1.
    public func progress(in quran: Quran) -> Double {
        let total = totalVerses(in: quran)
        guard total > 0 else { return 0 }
        return Double(learnedVerses(in: quran)) / Double(total)
    }

    /// Nombre de passages consolidés (toutes révisions réussies).
    public var consolidatedCount: Int {
        items.filter(\.isConsolidated).count
    }

    /// Série de jours consécutifs de travail, terminée aujourd'hui ou hier.
    ///
    /// « Terminée hier » compte encore : sinon la série paraîtrait rompue chaque matin avant que
    /// l'utilisateur ait travaillé, ce qui serait décourageant et faux.
    public func streak(now: Date, calendar: Calendar = .current) -> Int {
        let workedDays = Set(
            items
                .compactMap(\.lastWorkedAt)
                .map { calendar.startOfDay(for: $0) }
        )
        guard !workedDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        var cursor: Date
        if workedDays.contains(today) {
            cursor = today
        } else if workedDays.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var count = 0
        while workedDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    // MARK: - Écriture

    /// Marque un passage comme appris et programme sa première révision à J+1.
    ///
    /// Sans effet si le passage est déjà appris : on ne réinitialise pas une consolidation
    /// acquise par une relecture.
    public mutating func markLearned(id: UUID, at date: Date, calendar: Calendar = .current) {
        update(id: id) { item in
            guard item.storedStatus == .notLearned else { return }
            item.storedStatus = .learned
            item.reviewStage = 1
            item.lastWorkedAt = date
            item.nextReview = LearningConsolidation.nextReview(afterSuccessAt: 0, from: date, calendar: calendar)
        }
    }

    /// Enregistre une révision réussie : fait avancer d'une étape (J+1 → J+3 → J+7 → consolidé).
    ///
    /// Refusée pour un passage jamais appris : réviser ce qu'on n'a pas appris n'a pas de sens et
    /// fausserait le compteur de série.
    public mutating func markReviewed(id: UUID, at date: Date, calendar: Calendar = .current) {
        update(id: id) { item in
            guard item.storedStatus != .notLearned else { return }
            let nextStage = item.reviewStage + 1
            item.reviewStage = nextStage
            item.storedStatus = .learned
            item.lastWorkedAt = date
            item.nextReview = LearningConsolidation.nextReview(afterSuccessAt: nextStage, from: date, calendar: calendar)
        }
    }

    /// Marque un passage comme non appris, et efface sa consolidation.
    ///
    /// C'est l'action « je ne le connais finalement pas » : elle doit vraiment remettre à zéro,
    /// sinon un passage marqué par erreur resterait invisible dans le programme.
    public mutating func markNotLearned(id: UUID) {
        update(id: id) { item in
            item.storedStatus = .notLearned
            item.reviewStage = 0
            item.nextReview = nil
            item.lastWorkedAt = nil
        }
    }

    /// Remplace les passages et fixe la date de génération.
    public mutating func replace(items newItems: [LearningItem], generatedAt date: Date) {
        items = newItems
        generatedAt = date
    }

    // MARK: Private

    private mutating func update(id: UUID, _ body: (inout LearningItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        body(&items[index])
    }
}
