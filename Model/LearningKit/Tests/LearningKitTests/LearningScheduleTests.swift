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
    /// « semaine » et « mois » dans les tests. Le jour de la semaine compte aussi pour la
    /// répartition : c'est lui qui rend vérifiable qu'un jeudi exclu est bien sauté.
    private var day0: Date {
        DateComponents(calendar: calendar, year: 2026, month: 9, day: 30, hour: 12).date!
    }

    /// Le mushaf où lire la taille d'un passage — celui de l'application.
    private let quran = Quran.hafsMadani1405

    /// Tous les jours ouvrés : le cas où l'utilisateur n'en exclut aucun.
    private var everyDay: Set<LearningDay> { Set(LearningDay.allCases) }

    private func date(daysAfter reference: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: reference)!
    }

    private func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Un programme de `count` passages, une sourate chacun, dans l'ordre du programme.
    ///
    /// Utile aux épreuves de **placement**, où la taille n'importe pas. Pour celles de
    /// **répartition**, voir `program(verseCounts:)` : une sourate entière porte jusqu'à 286 versets
    /// et ne partagerait donc jamais sa journée.
    private func program(count: Int) -> (program: LearningProgram, ids: [UUID]) {
        let items = (0 ..< count).map {
            LearningItem(range: QuranRange(quran.suras[$0]), label: nil, position: $0)
        }
        return (LearningProgram(items: items, generatedAt: day0), items.map(\.id))
    }

    /// Un programme dont on donne la taille de chaque passage, en versets, dans l'ordre.
    ///
    /// Les passages sont pris bout à bout dans la **même** sourate : deux passages ne se recouvrent
    /// donc pas, et le total reste lisible. An-Naba (78) en porte quarante, ce qui suffit aux cas
    /// d'ici.
    private func program(verseCounts: [Int], sura: Int = 78) -> (program: LearningProgram, ids: [UUID]) {
        var items: [LearningItem] = []
        var next = 1
        for (index, count) in verseCounts.enumerated() {
            let last = next + count - 1
            items.append(LearningItem(
                range: QuranRange(firstSura: sura, firstAyah: next, lastSura: sura, lastAyah: last),
                label: nil,
                position: index
            ))
            next = last + 1
        }
        return (LearningProgram(items: items, generatedAt: day0), items.map(\.id))
    }

    /// Le planning, avec la capacité du test.
    ///
    /// Le budget est **obligatoire** à chaque appel : c'est lui qui décide de la répartition, et un
    /// défaut caché ferait passer une épreuve sous une règle qu'elle ne nomme pas.
    ///
    /// - Note: le nom porte `make`, et non `plan` : une variable locale nommée `plan` masquerait la
    ///   méthode dans son propre initialiseur, ce que Swift refuse.
    private func makePlan(
        _ program: LearningProgram,
        from start: Date,
        through end: Date,
        now: Date,
        versesPerDay: Int,
        workingDays: Set<LearningDay> = Set(LearningDay.allCases)
    ) -> [LearningDayPlan] {
        program.schedule(
            from: start,
            through: end,
            now: now,
            versesPerDay: versesPerDay,
            workingDays: workingDays,
            quran: quran,
            calendar: calendar
        )
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

        let plan = makePlan(
            program,
            from: date(daysAfter: day0, 1),
            through: date(daysAfter: day0, 7),
            now: date(daysAfter: day0, 1),
            versesPerDay: 8
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

        let plan = makePlan(
            program,
            from: today,
            through: date(daysAfter: day0, 9),
            now: today,
            versesPerDay: 8
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

        let plan = makePlan(
            program,
            from: date(daysAfter: day0, -10),
            through: date(daysAfter: day0, 7),
            now: day0,
            versesPerDay: 8
        )

        XCTAssertEqual(plan.map(\.day), [startOfDay(day0), startOfDay(date(daysAfter: day0, 1))])
    }

    /// Un passage **jamais appris** n'a pas d'échéance : il n'appartient pas au planning.
    func test_schedule_excludesNeverLearnedItems() {
        let (program, _) = program(count: 3)

        let plan = makePlan(
            program,
            from: day0,
            through: date(daysAfter: day0, 30),
            now: day0,
            versesPerDay: 8
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

        let plan = makePlan(
            program,
            from: day0,
            through: date(daysAfter: day0, 400),
            now: day0,
            versesPerDay: 8
        )

        XCTAssertTrue(plan.isEmpty, "Un passage consolidé ne revient jamais au planning")
    }

    /// Ce qui tombe après la fin de la fenêtre n'y figure pas — sinon « Semaine » montrerait le mois.
    func test_schedule_excludesWhatFallsAfterTheEnd() {
        var (program, ids) = program(count: 1)
        program.markLearned(id: ids[0], at: day0, calendar: calendar)
        // Échéance à J+1, fenêtre limitée à J+2 : dedans.
        let inside = makePlan(
            program,
            from: day0,
            through: date(daysAfter: day0, 2),
            now: day0,
            versesPerDay: 8
        )
        XCTAssertEqual(inside.count, 1)

        // Puis on repousse l'échéance à J+4 en révisant à J+1, et la même fenêtre doit se vider.
        program.markReviewed(id: ids[0], at: date(daysAfter: day0, 1), calendar: calendar)
        let outside = makePlan(
            program,
            from: day0,
            through: date(daysAfter: day0, 2),
            now: day0,
            versesPerDay: 8
        )
        XCTAssertTrue(outside.isEmpty, "L'échéance a quitté la fenêtre")
    }

    /// Deux passages dus le même jour restent dans l'**ordre du programme** : le planning se lit
    /// comme le programme, pas dans l'ordre d'insertion d'un dictionnaire.
    ///
    /// Les passages sont **petits** à dessein : c'est la seule façon d'éprouver l'ordre *dans* une
    /// journée sans que la répartition par capacité les sépare d'abord.
    func test_schedule_keepsProgramOrderWithinADay() {
        var (program, ids) = program(verseCounts: [2, 2, 2])
        // Appris dans le désordre : c'est l'ordre du programme qui doit gagner, pas celui-ci.
        program.markLearned(id: ids[2], at: day0, calendar: calendar)
        program.markLearned(id: ids[0], at: day0, calendar: calendar)
        program.markLearned(id: ids[1], at: day0, calendar: calendar)

        let plan = makePlan(
            program,
            from: day0,
            through: date(daysAfter: day0, 3),
            now: day0,
            versesPerDay: 8
        )

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].items.map(\.id), [ids[0], ids[1], ids[2]], "L'ordre du programme est tenu")
    }

    /// Un jour sans rien à réviser ne produit pas de plan : la grille, elle, décide de le montrer
    /// vide, et une liste n'en parle pas.
    func test_schedule_omitsDaysWithNothingDue() {
        var (program, ids) = program(verseCounts: [2, 2])
        program.markLearned(id: ids[0], at: day0, calendar: calendar)
        program.markLearned(id: ids[1], at: day0, calendar: calendar)

        let plan = makePlan(
            program,
            from: day0,
            through: date(daysAfter: day0, 20),
            now: day0,
            versesPerDay: 8
        )

        XCTAssertEqual(plan.count, 1, "Les deux sont dus le même jour : un seul plan")
        XCTAssertEqual(plan[0].items.count, 2)
    }

    /// Une fenêtre à l'envers ne rend rien, plutôt que de boucler ou de tout rendre.
    func test_schedule_isEmptyWhenTheWindowIsReversed() {
        var (program, ids) = program(count: 1)
        program.markLearned(id: ids[0], at: day0, calendar: calendar)

        let plan = makePlan(
            program,
            from: date(daysAfter: day0, 5),
            through: date(daysAfter: day0, 1),
            now: day0,
            versesPerDay: 8
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

        let plan = makePlan(
            program,
            from: day0,
            through: date(daysAfter: day0, 3),
            now: day0,
            versesPerDay: 8
        )

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].day, startOfDay(day0), "Le jour est normalisé, malgré une fenêtre ouverte à midi")
    }

    // MARK: - La répartition par capacité

    /// Le retard se **répartit** au lieu de s'empiler sur aujourd'hui — et le budget d'un jour est
    /// reconstitué le lendemain.
    ///
    /// Cinq passages de deux versets, tous dus depuis longtemps, quatre versets par jour : deux
    /// tiennent le premier jour, deux le deuxième, un le troisième. C'est le cœur du changement de
    /// règle, et le seul endroit où la reconstitution du budget se voit.
    func test_schedule_spreadsOverdueItemsOverSeveralDays() {
        var (program, ids) = program(verseCounts: [2, 2, 2, 2, 2])
        for id in ids {
            program.markLearned(id: id, at: date(daysAfter: day0, -10), calendar: calendar)
        }

        let plan = makePlan(
            program,
            from: day0,
            through: date(daysAfter: day0, 6),
            now: day0,
            versesPerDay: 4
        )

        XCTAssertEqual(plan.map(\.day), [
            startOfDay(day0),
            startOfDay(date(daysAfter: day0, 1)),
            startOfDay(date(daysAfter: day0, 2)),
        ])
        XCTAssertEqual(plan[0].items.map(\.id), [ids[0], ids[1]])
        XCTAssertEqual(plan[1].items.map(\.id), [ids[2], ids[3]])
        XCTAssertEqual(plan[2].items.map(\.id), [ids[4]])
    }

    /// Un passage plus gros que le budget **ne se coupe pas** : il occupe sa journée seul.
    ///
    /// C'est la règle qui rend la répartition totale — sans elle, un passage trop gros ne pourrait
    /// être placé nulle part. Le petit passage qui suit prend donc la journée suivante, alors que le
    /// premier jour est vide à ses yeux : c'est exactement ce que « sa journée seule » veut dire.
    func test_schedule_givesAnOversizedItemItsOwnDay() {
        var (program, ids) = program(verseCounts: [7, 2])
        for id in ids {
            program.markLearned(id: id, at: date(daysAfter: day0, -10), calendar: calendar)
        }

        let plan = makePlan(
            program,
            from: day0,
            through: date(daysAfter: day0, 6),
            now: day0,
            versesPerDay: 4
        )

        XCTAssertEqual(plan.map(\.day), [startOfDay(day0), startOfDay(date(daysAfter: day0, 1))])
        XCTAssertEqual(plan[0].items.map(\.id), [ids[0]], "Le gros passage est seul sur sa journée")
        XCTAssertEqual(plan[1].items.map(\.id), [ids[1]])
    }

    /// Un budget nul place **un passage par jour** — la règle 4 appliquée à la lettre.
    ///
    /// Aucun passage ne tenant dans un budget nul, chacun prend sa journée. Le cas ne vient pas de
    /// l'application, où le rythme vaut au moins un verset : il est éprouvé pour que la règle reste
    /// totale, et pour qu'aucun budget ne puisse faire boucler le planning.
    func test_schedule_placesOneItemPerDayWhenTheBudgetIsZero() {
        var (program, ids) = program(verseCounts: [2, 2, 2])
        for id in ids {
            program.markLearned(id: id, at: date(daysAfter: day0, -10), calendar: calendar)
        }

        let plan = makePlan(
            program,
            from: day0,
            through: date(daysAfter: day0, 6),
            now: day0,
            versesPerDay: 0
        )

        XCTAssertEqual(plan.map(\.day), [
            startOfDay(day0),
            startOfDay(date(daysAfter: day0, 1)),
            startOfDay(date(daysAfter: day0, 2)),
        ])
        XCTAssertEqual(plan[0].items.count, 1)
        XCTAssertEqual(plan[1].items.count, 1)
        XCTAssertEqual(plan[2].items.count, 1)
    }

    /// Aucun passage n'est placé un jour que l'utilisateur a exclu.
    ///
    /// Le jeudi est exclu, et c'est précisément le jour qui suit le mercredi de référence : sans la
    /// règle, le troisième passage y tomberait.
    func test_schedule_neverPlacesOnANonWorkingDay() {
        var (program, ids) = program(verseCounts: [2, 2, 2])
        for id in ids {
            program.markLearned(id: id, at: date(daysAfter: day0, -10), calendar: calendar)
        }

        let plan = makePlan(
            program,
            from: day0,
            through: date(daysAfter: day0, 6),
            now: day0,
            versesPerDay: 4,
            workingDays: everyDay.subtracting([.jeudi])
        )

        XCTAssertEqual(plan.map(\.day), [
            startOfDay(day0),
            startOfDay(date(daysAfter: day0, 2)),
        ], "Le jeudi est sauté, le vendredi pris")
    }

    /// Une échéance qui tombe un jour exclu est **repoussée** au jour ouvré suivant, jamais avancée.
    ///
    /// Avancer ferait travailler avant l'échéance, ce que la règle 2 interdit. L'échéance tombe le
    /// jeudi, un jour exclu : le passage est donc placé le **vendredi**, après elle et non avant.
    func test_schedule_pushesADueDateOffANonWorkingDayForward() {
        var (program, ids) = program(verseCounts: [2])
        // Appris aujourd'hui : l'échéance tombe à J+1, un jeudi — le jour exclu.
        program.markLearned(id: ids[0], at: day0, calendar: calendar)

        let plan = makePlan(
            program,
            from: day0,
            through: date(daysAfter: day0, 6),
            now: day0,
            versesPerDay: 8,
            workingDays: everyDay.subtracting([.jeudi])
        )

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].day, startOfDay(date(daysAfter: day0, 2)), "Le vendredi, pas le jeudi")
    }

    /// Sans aucun jour ouvré, rien n'est planifiable.
    ///
    /// Il n'y aurait pas de « jour suivant » où reporter, et rendre `[]` vaut mieux que boucler.
    /// L'écran de configuration exige déjà un jour, donc ce cas ne vient pas de l'application.
    func test_schedule_plansNothingWithoutAWorkingDay() {
        var (program, ids) = program(verseCounts: [2])
        program.markLearned(id: ids[0], at: day0, calendar: calendar)

        let plan = makePlan(
            program,
            from: day0,
            through: date(daysAfter: day0, 6),
            now: day0,
            versesPerDay: 8,
            workingDays: []
        )

        XCTAssertTrue(plan.isEmpty)
    }

    /// Ce que le budget repousse **au-delà de la fenêtre** n'y figure pas.
    ///
    /// La répartition ne cherche pas à tout tenir dans la fenêtre : elle déborde, et c'est la borne
    /// de fin qui filtre. Le surplus n'est pas perdu pour autant — il est toujours dû, donc il
    /// réapparaîtra dans la période suivante.
    func test_schedule_dropsWhatTheBudgetPushesPastTheWindowEnd() {
        var (program, ids) = program(verseCounts: [2, 2, 2])
        for id in ids {
            program.markLearned(id: id, at: date(daysAfter: day0, -10), calendar: calendar)
        }

        // Un passage par jour, et une fenêtre de deux jours : le troisième n'a plus où aller.
        let plan = makePlan(
            program,
            from: day0,
            through: date(daysAfter: day0, 1),
            now: day0,
            versesPerDay: 2
        )

        XCTAssertEqual(plan.map(\.day), [startOfDay(day0), startOfDay(date(daysAfter: day0, 1))])
        XCTAssertEqual(plan[0].items.map(\.id), [ids[0]])
        XCTAssertEqual(plan[1].items.map(\.id), [ids[1]], "Le troisième est hors fenêtre")
    }

    /// Un budget **sans borne** redonne exactement l'empilement qui précédait cette règle : chaque
    /// passage sur son jour d'échéance, quelle que soit sa taille.
    ///
    /// C'est le cas limite de la répartition, et l'épreuve le fixe : trois sourates entières — dont
    /// une de 286 versets — dues le même jour y restent ensemble, là où un budget réel les
    /// séparerait. Ce n'est pas un chemin à part dans le code, c'est la même boucle.
    func test_schedule_keepsEveryItemOnItsDueDayWhenTheBudgetIsUnbounded() {
        var (program, ids) = program(count: 3)
        for id in ids {
            program.markLearned(id: id, at: day0, calendar: calendar)
        }

        let plan = makePlan(
            program,
            from: day0,
            through: date(daysAfter: day0, 6),
            now: day0,
            versesPerDay: Int.max
        )

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].items.map(\.id), [ids[0], ids[1], ids[2]], "Aucun passage n'est déplacé")
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
    /// période]`, et un passage dû avant aujourd'hui s'y ramasse sur aujourd'hui.
    func test_periodWindow_gathersOverdueItemsOnToday() {
        var (program, ids) = program(count: 1)
        // Appris dix jours plus tôt : l'échéance est loin derrière le début de la période.
        program.markLearned(id: ids[0], at: date(daysAfter: day0, -10), calendar: calendar)

        let period = LearningPeriod.week
        let last = period.lastDay(containing: day0, calendar: calendar)!
        let plan = makePlan(program, from: day0, through: last, now: day0, versesPerDay: 8)

        XCTAssertEqual(plan.map(\.day), [startOfDay(day0)], "Le retard tient sur aujourd'hui")
        XCTAssertTrue(
            period.days(containing: day0, calendar: calendar).contains(plan[0].day),
            "Et ce jour appartient bien à la période affichée"
        )
    }
}
