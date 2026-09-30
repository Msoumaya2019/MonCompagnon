//
//  LearningProgramTests.swift
//  LearningKitTests
//

import LearningKit
import QuranKit
import XCTest

final class LearningProgramTests: XCTestCase {
    /// Calendrier figé pour des tests déterministes, quelle que soit la machine.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Un jour de référence stable : 2026-09-30 à midi UTC.
    private var day0: Date {
        DateComponents(calendar: calendar, year: 2026, month: 9, day: 30, hour: 12).date!
    }

    private func date(daysAfter reference: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: reference)!
    }

    /// La date de révision attendue : le **début** du jour J+`offsetDays`.
    ///
    /// Les échéances sont normalisées au début du jour : une révision due le 1ᵉʳ octobre est due
    /// dès le matin du 1ᵉʳ octobre, pas à midi. Comparer à midi ferait échouer le test alors que
    /// le comportement est correct.
    private func expectedReview(offsetDays: Int) -> Date {
        let startOfDay0 = calendar.startOfDay(for: day0)
        return calendar.date(byAdding: .day, value: offsetDays, to: startOfDay0)!
    }

    /// Un programme d'un seul passage : Al-Fatiha.
    private func program() -> (program: LearningProgram, id: UUID) {
        let quran = Quran.hafsMadani1405
        let sura = quran.suras[0]
        let item = LearningItem(range: QuranRange(sura), label: "Al-Fatiha", position: 0)
        return (LearningProgram(items: [item], generatedAt: day0), item.id)
    }

    // MARK: - Transitions

    func test_markLearned_schedulesFirstReviewAtJPlus1() {
        var (program, id) = program()
        program.markLearned(id: id, at: day0, calendar: calendar)

        let item = program.items[0]
        XCTAssertEqual(item.storedStatus, .learned)
        XCTAssertEqual(item.reviewStage, 0, "Aucune révision n'a encore eu lieu après l'apprentissage")
        XCTAssertEqual(item.lastWorkedAt, day0)
        XCTAssertEqual(item.nextReview, expectedReview(offsetDays: 1))
    }

    func test_markLearned_isIgnoredWhenAlreadyLearned() {
        var (program, id) = program()
        program.markLearned(id: id, at: day0, calendar: calendar)
        // Une seconde tentative, plus tard, ne doit pas repousser la révision ni repartir de zéro.
        program.markLearned(id: id, at: date(daysAfter: day0, 5), calendar: calendar)

        let item = program.items[0]
        XCTAssertEqual(item.reviewStage, 0, "Un passage déjà appris ne doit pas repartir de zéro")
        XCTAssertEqual(item.nextReview, expectedReview(offsetDays: 1))
    }

    func test_reviews_followJ1ThenJ3ThenJ7() {
        var (program, id) = program()
        program.markLearned(id: id, at: day0, calendar: calendar)
        XCTAssertEqual(program.items[0].nextReview, expectedReview(offsetDays: 1), "Après apprentissage : J+1")

        // J+1 → prochaine à J+1+3 = J+4
        let j1 = date(daysAfter: day0, 1)
        program.markReviewed(id: id, at: j1, calendar: calendar)
        XCTAssertEqual(program.items[0].reviewStage, 1)
        XCTAssertEqual(program.items[0].nextReview, expectedReview(offsetDays: 4), "Après 1ʳᵉ révision : J+3")

        // J+4 → prochaine à J+4+7 = J+11
        let j4 = date(daysAfter: day0, 4)
        program.markReviewed(id: id, at: j4, calendar: calendar)
        XCTAssertEqual(program.items[0].reviewStage, 2)
        XCTAssertEqual(program.items[0].nextReview, expectedReview(offsetDays: 11), "Après 2ᵉ révision : J+7")

        // Après la 3ᵉ révision : consolidé, plus de révision programmée.
        let j11 = date(daysAfter: day0, 11)
        program.markReviewed(id: id, at: j11, calendar: calendar)
        XCTAssertEqual(program.items[0].reviewStage, 3)
        XCTAssertNil(program.items[0].nextReview, "Après J+7, le passage est consolidé")
        XCTAssertTrue(program.items[0].isConsolidated)
    }

    func test_markReviewed_isIgnoredForNeverLearnedItem() {
        var (program, id) = program()
        program.markReviewed(id: id, at: day0, calendar: calendar)

        let item = program.items[0]
        XCTAssertEqual(item.storedStatus, .notLearned, "On ne peut pas réviser ce qu'on n'a pas appris")
        XCTAssertNil(item.lastWorkedAt, "Une révision refusée ne doit pas compter comme jour travaillé")
        XCTAssertEqual(program.streak(now: day0, calendar: calendar), 0)
    }

    func test_markNotLearned_clearsEverything() {
        var (program, id) = program()
        program.markLearned(id: id, at: day0, calendar: calendar)
        program.markNotLearned(id: id)

        let item = program.items[0]
        XCTAssertEqual(item.storedStatus, .notLearned)
        XCTAssertEqual(item.reviewStage, 0)
        XCTAssertNil(item.nextReview)
        XCTAssertNil(item.lastWorkedAt)
    }

    func test_update_withUnknownIdentifier_changesNothing() {
        var (program, _) = program()
        let before = program
        program.markLearned(id: UUID(), at: day0, calendar: calendar)
        XCTAssertEqual(program, before, "Un identifiant inconnu ne doit rien modifier")
    }

    // MARK: - Le verdict de fin de séance

    /// « Bien appris » fait monter l'échelle d'une marche — et doit tomber **sur les mêmes dates**
    /// que `markReviewed` : les deux enregistrent le même succès.
    func test_bienAppris_climbsTheWholeLadder() {
        var (program, id) = program()
        program.markLearned(id: id, at: day0, calendar: calendar)

        program.apply(.bienAppris, toItem: id, at: date(daysAfter: day0, 1), calendar: calendar)
        XCTAssertEqual(program.items[0].reviewStage, 1)
        XCTAssertEqual(program.items[0].nextReview, expectedReview(offsetDays: 4), "Après un succès : J+3")

        program.apply(.bienAppris, toItem: id, at: date(daysAfter: day0, 4), calendar: calendar)
        XCTAssertEqual(program.items[0].reviewStage, 2)
        XCTAssertEqual(program.items[0].nextReview, expectedReview(offsetDays: 11), "Après deux succès : J+7")

        program.apply(.bienAppris, toItem: id, at: date(daysAfter: day0, 11), calendar: calendar)
        XCTAssertEqual(program.items[0].reviewStage, 3)
        XCTAssertNil(program.items[0].nextReview, "Après trois succès, le passage est consolidé")
        XCTAssertTrue(program.items[0].isConsolidated)
    }

    /// « À consolider » ne touche ni l'étape ni l'échéance : le passage reste dû, donc à revoir.
    func test_aConsolider_leavesTheStepAndTheDueDateUntouched() {
        var (program, id) = program()
        program.markLearned(id: id, at: day0, calendar: calendar)

        let day1 = date(daysAfter: day0, 1)
        program.apply(.aConsolider, toItem: id, at: day1, calendar: calendar)

        let item = program.items[0]
        XCTAssertEqual(item.reviewStage, 0, "Un passage à consolider ne franchit pas d'étape")
        XCTAssertEqual(item.nextReview, expectedReview(offsetDays: 1), "Et ne repousse pas son échéance")
        XCTAssertEqual(item.status(now: day1, calendar: calendar), .toReview, "Il reste donc à revoir")
    }

    /// « Difficile » ramène l'échelle à zéro : la prochaine révision tombe à J+1, même si le
    /// passage avait déjà un succès derrière lui.
    func test_difficile_sendsThePassageBackToJPlus1() {
        var (program, id) = program()
        program.markLearned(id: id, at: day0, calendar: calendar)
        program.markReviewed(id: id, at: date(daysAfter: day0, 1), calendar: calendar)
        XCTAssertEqual(program.items[0].reviewStage, 1, "Le passage a bien un succès derrière lui")

        program.apply(.difficile, toItem: id, at: date(daysAfter: day0, 4), calendar: calendar)

        XCTAssertEqual(program.items[0].reviewStage, 0, "L'échelle repart du bas")
        XCTAssertEqual(program.items[0].nextReview, expectedReview(offsetDays: 5), "J+1 après le jour du verdict")
    }

    /// Un passage consolidé n'est pas hors d'atteinte : le juger difficile le rouvre.
    func test_difficile_reopensAConsolidatedPassage() {
        var (program, id) = program()
        program.markLearned(id: id, at: day0, calendar: calendar)
        program.markReviewed(id: id, at: date(daysAfter: day0, 1), calendar: calendar)
        program.markReviewed(id: id, at: date(daysAfter: day0, 4), calendar: calendar)
        program.markReviewed(id: id, at: date(daysAfter: day0, 11), calendar: calendar)
        XCTAssertTrue(program.items[0].isConsolidated)

        program.apply(.difficile, toItem: id, at: date(daysAfter: day0, 12), calendar: calendar)

        XCTAssertFalse(program.items[0].isConsolidated, "Ce qu'on croyait su revient dans le programme")
        XCTAssertEqual(program.items[0].nextReview, expectedReview(offsetDays: 13))
    }

    /// Les trois verdicts doivent donner trois résultats **différents**, depuis le même état :
    /// sinon ce serait trois boutons pour une seule action.
    func test_theThreeVerdicts_divergeFromTheSameState() {
        func verdict(_ outcome: LearningOutcome) -> (stage: Int, review: Date?) {
            var (program, id) = program()
            program.markLearned(id: id, at: day0, calendar: calendar)
            program.markReviewed(id: id, at: date(daysAfter: day0, 1), calendar: calendar)
            program.apply(outcome, toItem: id, at: date(daysAfter: day0, 4), calendar: calendar)
            return (program.items[0].reviewStage, program.items[0].nextReview)
        }

        let bienAppris = verdict(.bienAppris)
        XCTAssertEqual(bienAppris.stage, 2, "« Bien appris » monte d'une marche")
        XCTAssertEqual(bienAppris.review, expectedReview(offsetDays: 11))

        let aConsolider = verdict(.aConsolider)
        XCTAssertEqual(aConsolider.stage, 1, "« À consolider » laisse la marche où elle est")
        XCTAssertEqual(aConsolider.review, expectedReview(offsetDays: 4))

        let difficile = verdict(.difficile)
        XCTAssertEqual(difficile.stage, 0, "« Difficile » ramène au bas de l'échelle")
        XCTAssertEqual(difficile.review, expectedReview(offsetDays: 5))
    }

    /// Travailler un passage compte comme une journée de travail, **quel que soit** le verdict :
    /// sinon la série ignorerait une séance réellement faite.
    func test_aVerdict_recordsTheDayAsWorked() {
        let day1 = date(daysAfter: day0, 1)
        for outcome in LearningOutcome.allCases {
            var (program, id) = program()
            program.markLearned(id: id, at: day0, calendar: calendar)

            program.apply(outcome, toItem: id, at: day1, calendar: calendar)

            XCTAssertEqual(program.items[0].lastWorkedAt, day1, "« \(outcome.rawValue) » compte le jour du verdict")
            XCTAssertEqual(program.streak(now: day1, calendar: calendar), 2, "« \(outcome.rawValue) » : les deux jours comptent")
        }
    }

    /// Un verdict porte sur un passage **déjà appris** : sur un passage neuf il n'y a pas d'échelle
    /// à faire monter ni à raccourcir. C'est `markLearned` qui ouvre l'échelle, et lui seul sait que
    /// la première révision tombe à J+1.
    func test_aVerdict_isIgnoredForANeverLearnedPassage() {
        for outcome in LearningOutcome.allCases {
            var (program, id) = program()
            let before = program

            program.apply(outcome, toItem: id, at: day0, calendar: calendar)

            XCTAssertEqual(program, before, "« \(outcome.rawValue) » ne change rien sur un passage jamais appris")
            XCTAssertEqual(program.streak(now: day0, calendar: calendar), 0, "Et ne compte pas comme un jour travaillé")
        }
    }

    // MARK: - Consolidation déduite

    func test_status_becomesToReviewWhenRevisionIsDue() {
        var (program, id) = program()
        program.markLearned(id: id, at: day0, calendar: calendar)

        // Le jour même : encore « appris ».
        XCTAssertEqual(program.items[0].status(now: day0, calendar: calendar), .learned)
        // Tard le jour même : toujours « appris ».
        let lateOnDay0 = DateComponents(calendar: calendar, year: 2026, month: 9, day: 30, hour: 23, minute: 59).date!
        XCTAssertEqual(program.items[0].status(now: lateOnDay0, calendar: calendar), .learned)
        // Dès la première minute du jour d'échéance : « à revoir ».
        let earlyOnDueDate = DateComponents(calendar: calendar, year: 2026, month: 10, day: 1, hour: 0, minute: 1).date!
        XCTAssertEqual(program.items[0].status(now: earlyOnDueDate, calendar: calendar), .toReview)
        // Après : toujours « à revoir ».
        XCTAssertEqual(program.items[0].status(now: date(daysAfter: day0, 9), calendar: calendar), .toReview)
    }

    func test_dueReviews_listsOnlyMatureItems() {
        let quran = Quran.hafsMadani1405
        var first = LearningItem(range: QuranRange(quran.suras[0]), label: nil, position: 0)
        let second = LearningItem(range: QuranRange(quran.suras[1]), label: nil, position: 1)
        var program = LearningProgram(items: [first, second], generatedAt: day0)

        program.markLearned(id: first.id, at: day0, calendar: calendar)
        // Le second est appris un jour plus tard : sa révision n'est due qu'à J+2.
        program.markLearned(id: second.id, at: date(daysAfter: day0, 1), calendar: calendar)

        let due = program.dueReviews(now: date(daysAfter: day0, 1), calendar: calendar)
        XCTAssertEqual(due.map(\.id), [first.id], "Seul le passage échu doit être listé")

        first = program.items[0]
        XCTAssertTrue(first.isReviewDue(now: date(daysAfter: day0, 1), calendar: calendar))
    }

    func test_consolidatedItem_isNeverDue() {
        var (program, id) = program()
        program.markLearned(id: id, at: day0, calendar: calendar)
        for offset in [1, 4, 11] {
            program.markReviewed(id: id, at: date(daysAfter: day0, offset), calendar: calendar)
        }

        XCTAssertTrue(
            program.dueReviews(now: date(daysAfter: day0, 400), calendar: calendar).isEmpty,
            "Un passage consolidé ne redevient jamais à revoir"
        )
    }

    // MARK: - Progression et série

    func test_progress_countsLearnedButNotToReview() {
        let quran = Quran.hafsMadani1405
        let sura = quran.suras[0]
        let item = LearningItem(range: QuranRange(sura), label: nil, position: 0)
        var program = LearningProgram(items: [item], generatedAt: day0)

        XCTAssertEqual(program.progress(in: quran), 0)

        program.markLearned(id: item.id, at: day0, calendar: calendar)
        XCTAssertEqual(program.progress(in: quran), 1, "Un passage appris compte, même en attente de révision")

        program.markNotLearned(id: item.id)
        XCTAssertEqual(program.progress(in: quran), 0)
    }

    func test_nextToLearn_returnsFirstUnlearnedItem() {
        let quran = Quran.hafsMadani1405
        let first = LearningItem(range: QuranRange(quran.suras[0]), label: nil, position: 0)
        let second = LearningItem(range: QuranRange(quran.suras[1]), label: nil, position: 1)
        var program = LearningProgram(items: [first, second], generatedAt: day0)

        XCTAssertEqual(program.nextToLearn()?.id, first.id)

        program.markLearned(id: first.id, at: day0, calendar: calendar)
        XCTAssertEqual(program.nextToLearn()?.id, second.id)
    }

    // MARK: - Par où commencer

    /// Un programme neuf **a** quelque chose à commencer : tout reste à apprendre. C'est le premier
    /// passage, et c'est ce que « Commencer maintenant » doit proposer dès la configuration.
    func test_nextToWork_onAFreshProgram_startsAtTheFirstPassage() {
        let (program, id) = program()

        XCTAssertEqual(
            program.nextToWork(now: day0, calendar: calendar)?.id,
            id,
            "Tout reste à apprendre : la première séance est le premier passage"
        )
    }

    /// Le cas qui tranche : à J+1 la révision du premier est due, **et** il reste une séance à
    /// apprendre. Les deux sont possibles, et le programme doit choisir l'apprentissage.
    func test_nextToWork_prefersTheNextSessionOverADueReview() {
        let quran = Quran.hafsMadani1405
        let first = LearningItem(range: QuranRange(quran.suras[0]), label: nil, position: 0)
        let second = LearningItem(range: QuranRange(quran.suras[1]), label: nil, position: 1)
        var program = LearningProgram(items: [first, second], generatedAt: day0)
        program.markLearned(id: first.id, at: day0, calendar: calendar)

        let day1 = date(daysAfter: day0, 1)
        XCTAssertEqual(
            program.dueReviews(now: day1, calendar: calendar).map(\.id),
            [first.id],
            "La révision est bien due : le test porte donc sur la priorité, pas sur l'échéance"
        )
        XCTAssertEqual(
            program.nextToWork(now: day1, calendar: calendar)?.id,
            second.id,
            "Tant qu'il reste une séance à apprendre, c'est elle qui commence"
        )
    }

    func test_nextToWork_fallsBackToTheFirstDueReview() {
        let quran = Quran.hafsMadani1405
        let first = LearningItem(range: QuranRange(quran.suras[0]), label: nil, position: 0)
        let second = LearningItem(range: QuranRange(quran.suras[1]), label: nil, position: 1)
        var program = LearningProgram(items: [first, second], generatedAt: day0)
        program.markLearned(id: first.id, at: day0, calendar: calendar)
        program.markLearned(id: second.id, at: day0, calendar: calendar)

        // Plus rien à apprendre : la première révision due prend la suite, dans l'ordre du programme.
        XCTAssertNil(program.nextToLearn())
        XCTAssertEqual(
            program.nextToWork(now: date(daysAfter: day0, 1), calendar: calendar)?.id,
            first.id
        )
    }

    func test_nextToWork_isNilWhenThereIsNothingToDo() {
        XCTAssertNil(
            LearningProgram.empty.nextToWork(now: day0, calendar: calendar),
            "Un programme vide n'a rien à commencer"
        )

        var (program, id) = program()
        program.markLearned(id: id, at: day0, calendar: calendar)

        XCTAssertNil(
            program.nextToWork(now: day0, calendar: calendar),
            "Tout est appris et la révision n'est pas encore due : il n'y a rien à faire"
        )
    }

    func test_streak_countsConsecutiveDaysIncludingYesterday() {
        let quran = Quran.hafsMadani1405
        // Trois passages travaillés respectivement à J-2, J-1 et aujourd'hui.
        var items = [LearningItem]()
        for index in 0 ..< 3 {
            items.append(LearningItem(range: QuranRange(quran.suras[index]), label: nil, position: index))
        }
        var program = LearningProgram(items: items, generatedAt: day0)
        program.markLearned(id: items[0].id, at: date(daysAfter: day0, -2), calendar: calendar)
        program.markLearned(id: items[1].id, at: date(daysAfter: day0, -1), calendar: calendar)
        program.markLearned(id: items[2].id, at: day0, calendar: calendar)

        XCTAssertEqual(program.streak(now: day0, calendar: calendar), 3)
    }

    func test_streak_survivesUntilEndOfTodayWhenNotYetWorked() {
        let quran = Quran.hafsMadani1405
        let item = LearningItem(range: QuranRange(quran.suras[0]), label: nil, position: 0)
        var program = LearningProgram(items: [item], generatedAt: day0)
        program.markLearned(id: item.id, at: date(daysAfter: day0, -1), calendar: calendar)

        XCTAssertEqual(
            program.streak(now: day0, calendar: calendar),
            1,
            "Travaillé hier : la série tient encore aujourd'hui"
        )
        XCTAssertEqual(
            program.streak(now: date(daysAfter: day0, 2), calendar: calendar),
            0,
            "Après un jour manqué, la série est rompue"
        )
    }

    func test_streak_isZeroWhenNothingWorked() {
        let (program, _) = program()
        XCTAssertEqual(program.streak(now: day0, calendar: calendar), 0)
    }

    // MARK: - Sérialisation

    func test_program_survivesEncodingRoundTrip() throws {
        var (program, id) = program()
        program.markLearned(id: id, at: day0, calendar: calendar)

        let data = try JSONEncoder().encode(program)
        let decoded = try JSONDecoder().decode(LearningProgram.self, from: data)

        XCTAssertEqual(decoded, program, "Le programme doit survivre à un aller-retour JSON")
    }
}
