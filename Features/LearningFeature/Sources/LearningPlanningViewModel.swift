//
//  LearningPlanningViewModel.swift
//  LearningFeature
//
//  Le planning de l'apprentissage : ce qui vient, ce qui est fait, et ce qui est dû.
//

import Combine
import Foundation
import LearningKit
import LearningPersistence
import Localization
import QuranKit

/// Le planning de l'apprentissage.
///
/// Quatre vues d'un même programme. « À venir » et « Terminés » le lisent par **état** — ce qui
/// reste à apprendre, ce qui est appris. « Semaine » et « Mois » le lisent par **échéance**, sur la
/// période civile qui contient aujourd'hui.
///
/// Le modèle de vue ne décide de rien : il interroge `LearningKit`, qui sait seul ce qui est dû et
/// quel jour. Ce qui vit ici n'est que de la mise en forme — composer un libellé lisible, nommer un
/// jour, ranger des cases en lignes de sept.
@MainActor
final class LearningPlanningViewModel: ObservableObject {
    // MARK: Lifecycle

    init(persistence: LearningPersistence, calendar: Calendar = .current, now: Date = Date()) {
        self.persistence = persistence
        self.calendar = calendar
        self.now = now
        quran = persistence.quran
        program = persistence.loadProgram()
    }

    // MARK: Internal

    /// Les quatre vues du planning.
    enum Tab: String, CaseIterable {
        case upcoming
        case finished
        case week
        case month

        /// La période que l'onglet couvre, ou `nil` s'il lit le programme par état.
        ///
        /// C'est ce qui distingue les deux moitiés de l'écran, et c'est la seule chose qui les
        /// distingue : le reste — la grille, les listes — suit.
        var period: LearningPeriod? {
            switch self {
            case .upcoming, .finished: return nil
            case .week: return .week
            case .month: return .month
            }
        }
    }

    /// Une ligne du planning : un passage, sous son libellé lisible.
    struct Row: Identifiable {
        let id: UUID
        let title: String
        /// Ce que la ligne annonce sous son titre — l'état du passage, ou rien.
        let subtitle: String?
        let item: LearningItem
    }

    /// Une journée du planning, et ce qui y est dû.
    struct DaySection: Identifiable {
        let id: Date
        let title: String
        let rows: [Row]
    }

    /// Une case de la grille : un jour, et ce qu'il porte.
    struct DayCell: Identifiable {
        let id: Date
        let day: Date
        /// L'initiale du jour de la semaine, dans la langue de l'utilisateur.
        let weekday: String
        /// Le numéro du jour dans le mois.
        let number: String
        let dueCount: Int
        let isToday: Bool

        /// Ce qu'une case annonce à voix haute : le jour, puis ce qu'il porte.
        var accessibilityLabel: String {
            let jour = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
            guard dueCount > 0 else { return jour }
            return "\(jour), \(lFormat("learning.planning.due.count", table: .learning, dueCount))"
        }
    }

    @Published private(set) var tab: Tab = .upcoming

    var tabs: [Tab] { Tab.allCases }

    func title(of tab: Tab) -> String {
        switch tab {
        case .upcoming: return l("learning.planning.tab.upcoming", table: .learning)
        case .finished: return l("learning.planning.tab.finished", table: .learning)
        case .week: return l("learning.planning.tab.week", table: .learning)
        case .month: return l("learning.planning.tab.month", table: .learning)
        }
    }

    func select(_ tab: Tab) {
        self.tab = tab
    }

    /// Vrai quand l'onglet affiché lit le programme par échéance, et montre donc une grille.
    var showsCalendar: Bool { tab.period != nil }

    /// Les passages qui restent à apprendre, dans l'ordre du programme.
    var upcoming: [Row] {
        makeRows(for: program.items.filter { $0.storedStatus == .notLearned })
    }

    /// Les passages déjà appris, dans l'ordre du programme — avec leur état du jour.
    ///
    /// L'état est **déduit**, jamais stocké : un passage appris dont la révision est due s'annonce
    /// « à revoir » sans qu'on ait rien eu à réécrire. C'est ce que fait déjà `LearningStatus`.
    var finished: [Row] {
        makeRows(for: program.items.filter { $0.storedStatus != .notLearned })
    }

    /// Les jours de la période affichée, rangés en lignes de sept.
    ///
    /// Vide pour « À venir » et « Terminés » : ces deux-là n'ont pas de période.
    var grid: [[DayCell]] {
        let counts = dueCountsByDay()
        let cells = days.map { day in
            DayCell(
                id: day,
                day: day,
                weekday: day.formatted(.dateTime.weekday(.narrow)),
                number: day.formatted(.dateTime.day()),
                dueCount: counts[day] ?? 0,
                isToday: calendar.isDate(day, inSameDayAs: now)
            )
        }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0 ..< min($0 + 7, cells.count)]) }
    }

    /// Les initiales des jours de la semaine, en tête de grille.
    var weekdayHeaders: [String] {
        Array(grid.first?.map(\.weekday) ?? [])
    }

    /// Ce qui est dû, jour par jour, sur la période affichée.
    var sections: [DaySection] {
        schedule().map { plan in
            DaySection(id: plan.day, title: dayTitle(plan.day), rows: makeRows(for: plan.items))
        }
    }

    /// Ce qu'il faut lire quand il n'y a rien à montrer.
    var emptyMessage: String {
        switch tab {
        case .upcoming: return l("learning.planning.upcoming.none", table: .learning)
        case .finished: return l("learning.planning.finished.none", table: .learning)
        case .week, .month: return l("learning.planning.due.none", table: .learning)
        }
    }

    /// Les lignes de la vue affichée, quand elle lit le programme par état.
    ///
    /// Vide pour « Semaine » et « Mois » : ces deux-là montrent des sections datées, pas une liste.
    var rows: [Row] {
        switch tab {
        case .upcoming: return upcoming
        case .finished: return finished
        case .week, .month: return []
        }
    }

    /// Vrai quand la vue affichée n'a rien à montrer.
    var isEmpty: Bool {
        showsCalendar ? sections.isEmpty : rows.isEmpty
    }

    /// Le premier verset d'un passage : là où ouvrir le Coran.
    func firstVerse(of item: LearningItem) -> AyahNumber? {
        item.range.bounds(in: quran)?.first
    }

    /// Relit le programme et rafraîchit l'instant de référence.
    ///
    /// L'instant est repris, et non conservé : un écran de planning laissé ouvert une nuit
    /// montrerait sinon la grille de la veille. Il est repris **une fois**, et les deux lectures —
    /// la grille et les listes — partagent le même, sans quoi elles se contrediraient.
    func reload() {
        now = Date()
        program = persistence.loadProgram()
    }

    // MARK: Private

    private let persistence: LearningPersistence
    private let calendar: Calendar
    private let quran: Quran
    private var now: Date
    private var program: LearningProgram

    /// Les jours de la période affichée, ou rien si l'onglet n'en a pas.
    private var days: [Date] {
        guard let period = tab.period else { return [] }
        return period.days(containing: now, calendar: calendar)
    }

    /// Le planning de la période affichée.
    ///
    /// La fenêtre va d'aujourd'hui au **dernier** jour de la période : le passé de la période n'est
    /// pas planifiable, et c'est `LearningProgram.schedule` qui ramène sur aujourd'hui tout ce qui
    /// était dû avant.
    private func schedule() -> [LearningDayPlan] {
        guard let period = tab.period, let last = period.lastDay(containing: now, calendar: calendar) else {
            return []
        }
        return program.schedule(from: now, through: last, now: now, calendar: calendar)
    }

    /// Combien de passages sont dus à chaque jour de la période.
    private func dueCountsByDay() -> [Date: Int] {
        schedule().reduce(into: [:]) { counts, plan in
            counts[plan.day] = plan.items.count
        }
    }

    /// Le titre d'un jour : « Aujourd'hui », « Demain », puis la date écrite en toutes lettres.
    ///
    /// Les deux premiers ont un nom, et ce sont ceux qu'on cherche des yeux. Le reste est daté par
    /// le formateur du système, qui connaît la langue et l'ordre des mots — aucune traduction à
    /// tenir.
    private func dayTitle(_ day: Date) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return l("learning.planning.today", table: .learning)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: tomorrow)
        {
            return l("learning.planning.tomorrow", table: .learning)
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func makeRows(for items: [LearningItem]) -> [Row] {
        items.compactMap { item in
            guard let title = learningItemLabel(item, in: quran) else { return nil }
            return Row(id: item.id, title: title, subtitle: subtitle(of: item), item: item)
        }
    }

    /// Ce qu'une ligne annonce : l'état du passage pour un acquis, rien pour un passage à venir.
    ///
    /// Un passage qu'on n'a pas encore appris n'a qu'un état possible, et le répéter sur chaque
    /// ligne n'apprendrait rien. Un acquis, lui, en a trois — et c'est celui-là qu'on vient lire.
    private func subtitle(of item: LearningItem) -> String? {
        switch item.status(now: now, calendar: calendar) {
        case .notLearned: return nil
        case .learned:
            return item.isConsolidated
                ? l("learning.planning.status.consolidated", table: .learning)
                : l("learning.planning.status.learned", table: .learning)
        case .toReview: return l("learning.planning.status.toReview", table: .learning)
        }
    }
}
