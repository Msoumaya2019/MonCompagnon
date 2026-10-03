//
//  LearningSchedule.swift
//  LearningKit
//
//  Ce qu'il y a à réviser, jour par jour.
//

import Foundation
import QuranKit

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

    /// Les passages placés ce jour-là.
    ///
    /// Dans l'ordre de la **répartition** — échéance croissante, puis ordre du programme — et non
    /// seulement dans l'ordre du programme : un passage en retard peut rejoindre un jour où un
    /// autre était déjà dû, et c'est son échéance qui le range après lui.
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
    /// Ce qu'il y a à réviser entre `start` et `end`, jour par jour, **réparti par capacité**.
    ///
    /// Chaque jour ouvré de la fenêtre dispose d'un budget de `versesPerDay` versets. Les passages
    /// dus sont parcourus par **échéance croissante**, et à échéance égale dans l'ordre du
    /// programme :
    ///
    /// 1. le premier jour de la fenêtre est `max(début de fenêtre, aujourd'hui)` — le passé n'est
    ///    jamais montré, aucune dette n'apparaît ;
    /// 2. un passage n'est jamais placé **avant** son échéance ;
    /// 3. si le budget du jour ne suffit pas **et que ce jour porte déjà quelque chose**, le passage
    ///    passe au jour ouvré suivant, dont le budget est intact ;
    /// 4. un passage **ne se coupe pas** : plus gros que le budget, il occupe sa journée seul.
    ///
    /// La règle 4 rend la répartition totale : un budget de `1` place un passage par jour, et un
    /// budget **sans borne** redonne exactement l'ancien empilement — chaque passage sur son jour
    /// d'échéance. C'est le cas limite de cette règle, pas un chemin à part, et c'est ce qui la rend
    /// compatible avec ce qui la précédait.
    ///
    /// **Ce qui déborde de la fenêtre n'y figure pas.** La répartition ne cherche pas à tout tenir
    /// dans la fenêtre : un passage dû lundi peut être repoussé après le dernier jour si le budget
    /// des jours qui précèdent est épuisé. La fin de fenêtre reste une borne d'**affichage**, et le
    /// surplus n'est pas perdu — il réapparaît dans la période suivante, où il est toujours dû.
    ///
    /// **Un jour non ouvré ne porte rien.** Une échéance qui tombe un jour que l'utilisateur a exclu
    /// est repoussée au jour ouvré suivant, jamais avancée : avancer ferait travailler avant
    /// l'échéance, ce que la règle 2 interdit.
    ///
    /// Ne sont planifiés que les passages **entrés dans le cycle de révision** : un passage jamais
    /// appris n'a pas d'échéance, et un passage consolidé n'en a plus. Les premiers appartiennent à
    /// « À venir », les seconds à « Terminés ».
    ///
    /// - Parameter versesPerDay: le budget d'un jour, en versets. C'est l'appelant qui le lit dans
    ///   le profil (`LearningProfile.versesPerSession`) : la fonction ne devine pas de rythme. Un
    ///   budget nul ou négatif place un passage par jour, par la règle 4.
    /// - Parameter workingDays: les jours où l'utilisateur travaille. **Vide, rien n'est
    ///   planifiable** : sans jour ouvré il n'y a pas de « jour suivant » où reporter, et rendre
    ///   `[]` vaut mieux que boucler. L'écran de configuration exige déjà au moins un jour, donc ce
    ///   cas ne vient pas de l'application.
    /// - Parameter quran: le mushaf où lire la taille d'un passage. Le budget s'exprime en versets,
    ///   et seul le mushaf dit combien de versets porte un intervalle.
    /// - Returns: les jours qui portent au moins un passage, dans l'ordre chronologique.
    func schedule(
        from start: Date,
        through end: Date,
        now: Date,
        versesPerDay: Int,
        workingDays: Set<LearningDay>,
        quran: Quran,
        calendar: Calendar = .current
    ) -> [LearningDayPlan] {
        // Le passé n'est pas planifiable : la fenêtre commence au plus tard aujourd'hui, même si
        // l'appelant demande une semaine ou un mois dont le début est déjà derrière.
        let first = max(calendar.startOfDay(for: start), calendar.startOfDay(for: now))
        let last = calendar.startOfDay(for: end)
        guard first <= last else { return [] }

        let weekdays = Set(workingDays.map(\.calendarWeekday))
        // Sans jour ouvré, aucun passage ne peut être placé : il n'y aurait pas de jour suivant où
        // reporter, et la boucle de report ne terminerait pas.
        guard !weekdays.isEmpty else { return [] }

        // Le budget est ramené à zéro au plus bas, pour que la soustraction du test d'ajustement ne
        // puisse pas déborder sur un entier négatif. Le sens ne change pas : la règle 4 fait déjà
        // d'un budget nul « un passage par jour ».
        let budget = max(0, versesPerDay)

        // Une seule passe sur `items` : le coût d'un passage se lit **une fois**, et non à chaque
        // comparaison de budget. `verseCount` parcourt les versets de l'intervalle, donc l'appeler
        // dans la boucle de répartition ferait un coût quadratique sur un programme entier.
        var dueItems: [(item: LearningItem, due: Date, cost: Int)] = []
        for item in items {
            guard item.storedStatus != .notLearned, let nextReview = item.nextReview else { continue }

            let deadline = calendar.startOfDay(for: nextReview)
            // La fin de fenêtre est un filtre de **candidature** : ce qui n'est pas dû dans la
            // fenêtre n'a rien à y faire. La répartition, elle, peut déborder — c'est plus bas.
            guard deadline <= last else { continue }

            dueItems.append((item, deadline, item.verseCount(in: quran)))
        }

        // Échéance croissante, puis ordre du programme. Le second critère n'est pas décoratif : le
        // tri de Swift n'est pas stable, donc deux passages dus le même jour pourraient permuter
        // sans lui — et le planning se lirait dans un ordre qui n'est celui de rien.
        dueItems.sort { ($0.due, $0.item.position) < ($1.due, $1.item.position) }

        var byDay: [Date: [LearningItem]] = [:]
        var usedByDay: [Date: Int] = [:]

        // Le jour qu'on remplit. Il ne recule jamais : la liste est triée par échéance, donc une
        // fois passé au jour suivant, plus rien ne peut revenir en arrière.
        var cursor = first

        for entry in dueItems {
            var day = nextWorkingDay(onOrAfter: max(cursor, entry.due), weekdays: weekdays, calendar: calendar)

            // Règle 3 : le budget épuisé ne fait changer de jour que si ce jour porte **déjà**
            // quelque chose. Le premier passage d'un jour y reste, même plus gros que le budget —
            // c'est la règle 4, et c'est elle qui garantit qu'aucun passage ne se coupe.
            //
            // La comparaison se fait par soustraction, jamais par `used + cost > budget` : le second
            // forme déborderait sur un budget sans borne.
            let used = usedByDay[day] ?? 0
            if used > 0, entry.cost > budget - used {
                day = nextWorkingDay(after: day, weekdays: weekdays, calendar: calendar)
            }

            // Le débordement s'arrête ici. Les jours ne font que croître, donc si celui-ci est
            // passé la fenêtre, aucun passage suivant n'y rentrerait non plus.
            guard day <= last else { break }

            usedByDay[day] = (usedByDay[day] ?? 0) + entry.cost
            byDay[day, default: []].append(entry.item)
            cursor = day
        }

        return byDay.keys.sorted().map { LearningDayPlan(day: $0, items: byDay[$0] ?? []) }
    }
}

/// Le premier jour ouvré à partir de `day`, `day` compris.
///
/// La borne de huit jours n'est pas une précaution de style : sept jours consécutifs couvrent les
/// sept index de `Calendar`, donc la boucle sort d'elle-même dès que `weekdays` n'est pas vide —
/// mais une borne rend la terminaison vérifiable sans raisonner sur le calendrier, et c'est aussi
/// ce qui évite une boucle infinie si l'appelant oubliait d'écarter l'ensemble vide.
private func nextWorkingDay(onOrAfter day: Date, weekdays: Set<Int>, calendar: Calendar) -> Date {
    var cursor = day
    var budget = 8
    while budget > 0, !weekdays.contains(calendar.component(.weekday, from: cursor)) {
        guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return cursor }
        cursor = next
        budget -= 1
    }
    return cursor
}

/// Le premier jour ouvré **strictement après** `day`.
///
/// Sert au report d'un budget épuisé : le passage ne partage pas la journée, il prend la suivante.
private func nextWorkingDay(after day: Date, weekdays: Set<Int>, calendar: Calendar) -> Date {
    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return day }
    return nextWorkingDay(onOrAfter: next, weekdays: weekdays, calendar: calendar)
}
