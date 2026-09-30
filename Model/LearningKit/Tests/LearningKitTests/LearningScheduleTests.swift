//
//  LearningScheduleTests.swift
//  LearningKitTests
//

import LearningKit
import QuranKit
import XCTest

final class LearningScheduleTests: XCTestCase {
    /// Calendrier figé pour des tests déterministes, quelle que soit la machine.
    ///
    /// `firstWeekday = 2` — lundi — parce que la semaine civile dépend de la région : sans le
    /// fixer, le test de « Semaine » passerait aux États-Unis et échouerait en France, sur le même
    /// code.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Un jour de référence stable : **mercredi** 2026-09-30 à midi UTC.
    ///
    /// Un mercredi, à dessein : la semaine civile qui le contient commence le lundi 28 septembre et
    /// finit le dimanche 4 octobre — elle **traverse donc deux mois**, ce qui interdit de confondre
    /// « semaine » et « mois » dans les tests.
    private var day0: Date {
        DateComponents(calendar: calendar, year: 2026, month: 9, day: 30, hour: 12).date!
    }

    private func date(daysAfter reference: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: reference)!
    }

    private func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Un programme de `count` passages, une sourate chacun, dans l'ordre du programme.
    private func program(count: Int) -> (program: LearningProgram, ids: [UUID]) {
        let quran = Quran.hafsMadani1405
        let items = (0 ..< count).map {
            LearningItem(range: QuranRange(quran.suras[$0]), label: nil, position: $0)
        }
        return (LearningProgram(items: items, generatedAt: day0), items.map(\.id))
    }

    // MARK: - Le planning, jour par jour

    /// Chaque passage tombe sur **son** jour d'échéance, et pas sur un autre.
    func test_schedule_placesEachItemOnItsDueDay() {
        var (program, ids) = program(count: 2)
        // Les deux appris le même jour : leur première révision tombe à J+1 pour tous les deux.
        program.markLearned(id: ids[0], at: day0, calendar: calendar)
        program.markLearned(id: ids[1], at: day0, calendar: calendar)
        // Le premier est révisé à J+1 : sa prochaine échéance passe à J+4. Le second reste dû à J+1.
        program.markReviewed(id: ids[0], at: date(daysAfter: day0, 1), calendar: calendar)

        let plan = program.schedule(
            from: date(daysAfter: day0, 1),
            through: date(daysAfter: day0, 7),
            now: date(daysAfter: day0, 1),
            calendar: calendar
        )

        XCTAssertEqual(plan.map(\.day), [
            startOfDay(date(daysAfter: day0, 1)),
            startOfDay(date(daysAfter: day0, 4)),
        ])
        XCTAssertEqual(plan[0].items.map(\.id), [ids[1]])
        XCTAssertEqual(plan[1].items.map(\.id), [ids[0]])
    }

    /// Un passage dû **avant** aujourd'hui est placé sur aujourd'hui.
    ///
    /// C'est la règle qui interdit d'afficher une dette : l'écran ne dit jamais « en retard ».
    func test_schedule_clampsOverdueToTheFirstDay() {
        var (program, ids) = program(count: 1)
        program.markLearned(id: ids[0], at: day0, calendar: calendar)
        // Échéance à J+1 ; on interroge trois jours plus tard.
        let today = date(daysAfter: day0, 3)

        let plan = program.schedule(
            from: today,
            through: date(daysAfter: day0, 9),
            now: today,
            calendar: calendar
        )

        XCTAssertEqual(plan.count, 1, "Le passage reste dû : il n'a pas disparu du planning")
        XCTAssertEqual(plan[0].day, startOfDay(today), "Il est dû aujourd'hui, pas à sa date dépassée")
    }

    /// Une fenêtre qui commence dans le passé est ramenée à aujourd'hui : le passé n'est pas
    /// planifiable.
    ///
    /// L'épreuve porte sur **deux** passages, et c'est ce qui la rend concluante : le premier est
    /// largement dépassé, le second n'est dû que demain. Si la fenêtre n'était pas ramenée à
    /// aujourd'hui, le premier se placerait dix jours en arrière — et si le retard était écrasé sur
    /// la borne par erreur, le second le serait aussi.
    func test_schedule_startsAtTodayWhenTheWindowStartsEarlier() {
        var (program, ids) = program(count: 2)
        program.markLearned(id: ids[0], at: date(daysAfter: day0, -10), calendar: calendar)
        program.markLearned(id: ids[1], at: day0, calendar: calendar)

        let plan = program.schedule(
            from: date(daysAfter: day0, -10),
            through: date(daysAfter: day0, 7),
            now: day0,
            calendar: calendar
        )

        XCTAssertEqual(plan.map(\.day), [startOfDay(day0), startOfDay(date(daysAfter: day0, 1))])
    }

    /// Un passage **jamais appris** n'a pas d'échéance : il n'appartient pas au planning.
    func test_schedule_excludesNeverLearnedItems() {
        let (program, _) = program(count: 3)

        let plan = program.schedule(
            from: day0,
            through: date(daysAfter: day0, 30),
            now: day0,
            calendar: calendar
        )

        XCTAssertTrue(plan.isEmpty, "Ce qui reste à apprendre se lit dans « À venir », pas ici")
    }

    /// Un passage **consolidé** n'a plus d'échéance : il n'apparaît nulle part.
    func test_schedule_excludesConsolidatedItems() {
        var (program, ids) = program(count: 1)
        program.markLearned(id: ids[0], at: day0, calendar: calendar)
        for offset in [1, 4, 11] {
            program.markReviewed(id: ids[0], at: date(daysAfter: day0, offset), calendar: calendar)
        }
        XCTAssertTrue(program.items[0].isConsolidated, "Le passage est bien consolidé avant l'épreuve")

        let plan = program.schedule(
            from: day0,
            through: date(daysAfter: day0, 400),
            now: day0,
            calendar: calendar
        )

        XCTAssertTrue(plan.isEmpty, "Un passage consolidé ne revient jamais au planning")
    }

    /// Ce qui tombe après la fin de la fenêtre n'y figure pas — sinon « Semaine » montrerait le mois.
    func test_schedule_excludesWhatFallsAfterTheEnd() {
        var (program, ids) = program(count: 1)
        program.markLearned(id: ids[0], at: day0, calendar: calendar)
        // Échéance à J+1, fenêtre limitée à J+2 : dedans.
        let inside = program.schedule(
            from: day0,
            through: date(daysAfter: day0, 2),
            now: day0,
            calendar: calendar
        )
        XCTAssertEqual(inside.count, 1)

        // Puis on repousse l'échéance à J+4 en révisant à J+1, et la même fenêtre doit se vider.
        program.markReviewed(id: ids[0], at: date(daysAfter: day0, 1), calendar: calendar)
        let outside = program.schedule(
            from: day0,
            through: date(daysAfter: day0, 2),
            now: day0,
            calendar: calendar
        )
        XCTAssertTrue(outside.isEmpty, "L'échéance a quitté la fenêtre")
    }

    /// Deux passages dus le même jour restent dans l'**ordre du programme** : le planning se lit
    /// comme le programme, pas dans l'ordre d'insertion d'un dictionnaire.
    func test_schedule_keepsProgramOrderWithinADay() {
        var (program, ids) = program(count: 3)
        // Appris dans le désordre : c'est l'ordre du programme qui doit gagner, pas celui-ci.
        program.markLearned(id: ids[2], at: day0, calendar: calendar)
        program.markLearned(id: ids[0], at: day0, calendar: calendar)
        program.markLearned(id: ids[1], at: day0, calendar: calendar)

        let plan = program.schedule(
            from: day0,
            through: date(daysAfter: day0, 3),
            now: day0,
            calendar: calendar
        )

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].items.map(\.id), [ids[0], ids[1], ids[2]], "L'ordre du programme est tenu")
    }

    /// Un jour sans rien à réviser ne produit pas de plan : la grille, elle, décide de le montrer
    /// vide, et une liste n'en parle pas.
    func test_schedule_omitsDaysWithNothingDue() {
        var (program, ids) = program(count: 2)
        program.markLearned(id: ids[0], at: day0, calendar: calendar)
        program.markLearned(id: ids[1], at: day0, calendar: calendar)

        let plan = program.schedule(
            from: day0,
            through: date(daysAfter: day0, 20),
            now: day0,
            calendar: calendar
        )

        XCTAssertEqual(plan.count, 1, "Les deux sont dus le même jour : un seul plan")
        XCTAssertEqual(plan[0].items.count, 2)
    }

    /// Une fenêtre à l'envers ne rend rien, plutôt que de boucler ou de tout rendre.
    func test_schedule_isEmptyWhenTheWindowIsReversed() {
        var (program, ids) = program(count: 1)
        program.markLearned(id: ids[0], at: day0, calendar: calendar)

        let plan = program.schedule(
            from: date(daysAfter: day0, 5),
            through: date(daysAfter: day0, 1),
            now: day0,
            calendar: calendar
        )

        XCTAssertTrue(plan.isEmpty)
    }

    /// Les jours rendus sont normalisés au **début** du jour, comme la clé des plans : sans quoi la
    /// grille ne retrouverait pas le plan d'un jour et l'afficherait vide.
    ///
    /// L'épreuve part d'une fenêtre ouverte **à midi** — la vraie : l'écran interroge le planning à
    /// l'heure où l'utilisateur le regarde, pas à minuit.
    func test_schedule_returnsDaysAtTheStartOfTheDay() {
        var (program, ids) = program(count: 1)
        // Appris la veille : l'échéance tombe donc le jour de référence lui-même.
        program.markLearned(id: ids[0], at: date(daysAfter: day0, -1), calendar: calendar)

        let plan = program.schedule(
            from: day0,
            through: date(daysAfter: day0, 3),
            now: day0,
            calendar: calendar
        )

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].day, startOfDay(day0), "Le jour est normalisé, malgré une fenêtre ouverte à midi")
    }

    // MARK: - La semaine et le mois civils

    /// « Semaine » couvre la semaine civile entière, du lundi au dimanche, **même à cheval sur deux
    /// mois** — c'est le cas du jour de référence.
    func test_weekPeriod_coversMondayThroughSunday() {
        let days = LearningPeriod.week.days(containing: day0, calendar: calendar)

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first, startOfDay(DateComponents(calendar: calendar, year: 2026, month: 9, day: 28).date!))
        XCTAssertEqual(days.last, startOfDay(DateComponents(calendar: calendar, year: 2026, month: 10, day: 4).date!))
        XCTAssertEqual(days, days.sorted(), "Les jours sont dans l'ordre")
    }

    /// « Mois » couvre le mois civil entier — et c'est bien **septembre** pour le jour de référence,
    /// pas octobre, alors que la semaine, elle, déborde sur octobre.
    func test_monthPeriod_coversTheWholeMonth() {
        let days = LearningPeriod.month.days(containing: day0, calendar: calendar)

        XCTAssertEqual(days.count, 30, "Septembre compte trente jours")
        XCTAssertEqual(days.first, startOfDay(DateComponents(calendar: calendar, year: 2026, month: 9, day: 1).date!))
        XCTAssertEqual(days.last, startOfDay(DateComponents(calendar: calendar, year: 2026, month: 9, day: 30).date!))
    }

    /// Un mois de trente et un jours est couvert en entier : le décalage d'un jour selon les mois
    /// est exactement ce qu'un calcul naïf rate.
    func test_monthPeriod_coversAThirtyOneDayMonth() {
        let firstOfOctober = DateComponents(calendar: calendar, year: 2026, month: 10, day: 1, hour: 12).date!

        let days = LearningPeriod.month.days(containing: firstOfOctober, calendar: calendar)

        XCTAssertEqual(days.count, 31)
        XCTAssertEqual(days.last, startOfDay(DateComponents(calendar: calendar, year: 2026, month: 10, day: 31).date!))
    }

    /// Les deux périodes ne se confondent pas, et chacune commence où elle doit : la semaine du
    /// 30 septembre ouvre le **lundi 28**, le mois le **1ᵉʳ septembre**.
    func test_bothPeriods_startWhereTheyShould() {
        let week = LearningPeriod.week.days(containing: day0, calendar: calendar)
        let month = LearningPeriod.month.days(containing: day0, calendar: calendar)

        XCTAssertEqual(week.first, startOfDay(DateComponents(calendar: calendar, year: 2026, month: 9, day: 28).date!))
        XCTAssertEqual(month.first, startOfDay(DateComponents(calendar: calendar, year: 2026, month: 9, day: 1).date!))
        XCTAssertNotEqual(week.first, month.first, "Les deux périodes ne se confondent pas")
    }

    /// Le dernier jour de la période est le dernier de ses jours — et non le premier instant de la
    /// suivante, que `dateInterval` rend comme fin **exclue**.
    func test_lastDay_isTheLastDayOfThePeriod() {
        let last = LearningPeriod.week.lastDay(containing: day0, calendar: calendar)

        XCTAssertEqual(last, startOfDay(DateComponents(calendar: calendar, year: 2026, month: 10, day: 4).date!))
        XCTAssertEqual(last, LearningPeriod.week.days(containing: day0, calendar: calendar).last)
    }

    // MARK: - Les deux ensemble

    /// Le cas qui commande tout : la fenêtre d'un onglet est `[aujourd'hui, dernier jour de la
    /// période]`, et ce qui est dû avant aujourd'hui s'y ramasse.
    func test_periodWindow_gathersOverdueItemsOnToday() {
        var (program, ids) = program(count: 1)
        // Appris dix jours plus tôt : l'échéance est loin derrière le début de la période.
        program.markLearned(id: ids[0], at: date(daysAfter: day0, -10), calendar: calendar)

        let period = LearningPeriod.week
        let last = period.lastDay(containing: day0, calendar: calendar)!
        let plan = program.schedule(from: day0, through: last, now: day0, calendar: calendar)

        XCTAssertEqual(plan.map(\.day), [startOfDay(day0)], "Tout le retard tient sur aujourd'hui")
        XCTAssertTrue(
            period.days(containing: day0, calendar: calendar).contains(plan[0].day),
            "Et ce jour appartient bien à la période affichée"
        )
    }
}
