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
        XCTAssertEqual(item.reviewStage, 1)
        XCTAssertEqual(item.lastWorkedAt, day0)
        XCTAssertEqual(item.nextReview, date(daysAfter: day0, 1))
    }

    func test_markLearned_isIgnoredWhenAlreadyLearned() {
        var (program, id) = program()
        program.markLearned(id: id, at: day0, calendar: calendar)
        // Une seconde tentative, plus tard, ne doit pas repousser la révision ni repartir de zéro.
        program.markLearned(id: id, at: date(daysAfter: day0, 5), calendar: calendar)

        let item = program.items[0]
        XCTAssertEqual(item.reviewStage, 1, "Une consolidation acquise ne doit pas être réinitialisée")
        XCTAssertEqual(item.nextReview, date(daysAfter: day0, 1))
    }

    func test_reviews_followJ1ThenJ3ThenJ7() {
        var (program, id) = program()
        program.markLearned(id: id, at: day0, calendar: calendar)

        // J+1 → prochaine à J+1+3 = J+4
        let j1 = date(daysAfter: day0, 1)
        program.markReviewed(id: id, at: j1, calendar: calendar)
        XCTAssertEqual(program.items[0].nextReview, date(daysAfter: j1, 3))

        // J+4 → prochaine à J+4+7 = J+11
        let j4 = date(daysAfter: day0, 4)
        program.markReviewed(id: id, at: j4, calendar: calendar)
        XCTAssertEqual(program.items[0].nextReview, date(daysAfter: j4, 7))

        // Après la 3ᵉ révision : consolidé, plus de révision programmée.
        let j11 = date(daysAfter: day0, 11)
        program.markReviewed(id: id, at: j11, calendar: calendar)
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

    // MARK: - Consolidation déduite

    func test_status_becomesToReviewWhenRevisionIsDue() {
        var (program, id) = program()
        program.markLearned(id: id, at: day0, calendar: calendar)

        // Le jour même : encore « appris ».
        XCTAssertEqual(program.items[0].status(now: day0, calendar: calendar), .learned)
        // La veille de l'échéance : encore « appris ».
        XCTAssertEqual(program.items[0].status(now: date(daysAfter: day0, 0), calendar: calendar), .learned)
        // Le jour de l'échéance : « à revoir ».
        XCTAssertEqual(program.items[0].status(now: date(daysAfter: day0, 1), calendar: calendar), .toReview)
        // Après : toujours « à revoir ».
        XCTAssertEqual(program.items[0].status(now: date(daysAfter: day0, 9), calendar: calendar), .toReview)
    }

    func test_dueReviews_listsOnlyMatureItems() {
        let quran = Quran.hafsMadani1405
        var first = LearningItem(range: QuranRange(quran.suras[0]), label: nil, position: 0)
        var second = LearningItem(range: QuranRange(quran.suras[1]), label: nil, position: 1)
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

        XCTAssertTrue(program.dueReviews(now: date(daysAfter: day0, 400), calendar: calendar).isEmpty,
                      "Un passage consolidé ne redevient jamais à revoir")
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

        XCTAssertEqual(program.streak(now: day0, calendar: calendar), 1,
                       "Travaillé hier : la série tient encore aujourd'hui")
        XCTAssertEqual(program.streak(now: date(daysAfter: day0, 2), calendar: calendar), 0,
                       "Après un jour manqué, la série est rompue")
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
