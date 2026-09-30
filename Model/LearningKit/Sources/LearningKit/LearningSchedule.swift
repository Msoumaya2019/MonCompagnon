//
//  LearningSchedule.swift
//  LearningKit
//
//  Ce qu'il y a à réviser, jour par jour.
//

import Foundation

/// Les passages à réviser un jour donné.
///
/// Un jour sans rien à réviser n'existe pas : la liste ne porte que les jours qui ont du travail, et
/// c'est à l'écran de décider comment montrer les jours vides — une grille les montre tous, une
/// liste n'en montre aucun.
public struct LearningDayPlan: Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(day: Date, items: [LearningItem]) {
        self.day = day
        self.items = items
    }

    // MARK: Public

    /// Le **début** du jour, normalisé.
    ///
    /// Normalisé, et non la date brute de l'échéance : deux passages dus le même jour à des heures
    /// différentes doivent tomber dans le même plan, sans quoi la grille en compterait deux.
    public let day: Date

    /// Les passages dus ce jour-là, dans l'ordre du programme.
    public let items: [LearningItem]

    public var id: Date { day }
}

/// Une période de planning : celle qui contient un jour donné.
///
/// C'est une règle de produit, et c'est pourquoi elle vit ici plutôt que dans une vue : « Semaine »
/// et « Mois » couvrent la semaine et le mois **civils**, ceux du calendrier de l'utilisateur — son
/// premier jour de semaine compris, qui n'est pas le même partout.
public enum LearningPeriod: String, CaseIterable, Sendable {
    /// La semaine civile qui contient le jour.
    case week
    /// Le mois civil qui contient le jour.
    case month

    // MARK: Public

    /// Les jours de la période, du premier au dernier **inclus**, au début du jour.
    ///
    /// - Returns: les jours dans l'ordre chronologique, ou `[]` si le calendrier ne sait pas
    ///   découper la période — un calendrier sans semaine ni mois n'existe pas, mais l'appel reste
    ///   sûr plutôt que de forcer un déballage.
    public func days(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let interval = calendar.dateInterval(of: component, for: date) else { return [] }

        // `interval.end` est **exclue** — c'est le premier instant de la période suivante. La boucle
        // s'arrête donc avant elle, ce qui donne le dernier jour inclus sans avoir à le reculer.
        let last = calendar.startOfDay(for: interval.end)
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: interval.start)

        while cursor < last {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// Le dernier jour de la période qui contient `date`, ou `nil` si elle n'a aucun jour.
    public func lastDay(containing date: Date, calendar: Calendar = .current) -> Date? {
        days(containing: date, calendar: calendar).last
    }

    // MARK: Private

    private var component: Calendar.Component {
        switch self {
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
}

public extension LearningProgram {
    /// Ce qu'il y a à réviser entre `start` et `end`, jour par jour.
    ///
    /// **Tout ce qui est dû aujourd'hui ou avant est placé sur le premier jour de la fenêtre.** Ce
    /// n'est pas un oubli mais une règle de lecture : l'écran ne dit jamais « en retard », et un
    /// passage dû hier reste dû aujourd'hui. Le montrer sur son jour d'échéance, dans le passé,
    /// reviendrait à présenter une dette — ce que le programme refuse depuis le début.
    ///
    /// Ne sont planifiés que les passages **entrés dans le cycle de révision** : un passage jamais
    /// appris n'a pas d'échéance, et un passage consolidé n'en a plus. Les premiers appartiennent à
    /// « À venir », les seconds à « Terminés ».
    ///
    /// - Returns: les jours qui portent au moins un passage, dans l'ordre chronologique. Les
    ///   passages d'un même jour restent dans l'ordre du programme.
    func schedule(
        from start: Date,
        through end: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> [LearningDayPlan] {
        // Le passé n'est pas planifiable : la fenêtre commence au plus tard aujourd'hui, même si
        // l'appelant demande une semaine ou un mois dont le début est déjà derrière.
        let first = max(calendar.startOfDay(for: start), calendar.startOfDay(for: now))
        let last = calendar.startOfDay(for: end)
        guard first <= last else { return [] }

        var byDay: [Date: [LearningItem]] = [:]
        for item in items {
            guard item.storedStatus != .notLearned, let nextReview = item.nextReview else { continue }

            let due = calendar.startOfDay(for: nextReview)
            let day = max(due, first)
            guard day <= last else { continue }

            // Parcourir `items` dans l'ordre suffit à garder l'ordre du programme dans chaque jour.
            byDay[day, default: []].append(item)
        }

        return byDay.keys.sorted().map { LearningDayPlan(day: $0, items: byDay[$0] ?? []) }
    }
}
