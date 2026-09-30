//
//  LearningProgressTransferTests.swift
//  LearningKitTests
//
//  Éprouve la reprise de progression d'un programme régénéré sur l'ancien.
//

import QuranKit
import XCTest
@testable import LearningKit

final class LearningProgressTransferTests: XCTestCase {
    // MARK: Internal

    func testNothingIsTransferredFromAnEmptyProgramme() {
        let program = LearningProgram(items: [item(range(from: (78, 1), to: (78, 3)))], generatedAt: day(0))
        XCTAssertEqual(LearningProgressTransfer.transfer(progressFrom: .empty, to: program, in: quran), program)
    }

    func testAnEmptyProgrammeStaysEmpty() {
        let previous = LearningProgram(items: [item(range(from: (78, 1), to: (78, 3)), stage: 0)], generatedAt: day(0))
        XCTAssertEqual(LearningProgressTransfer.transfer(progressFrom: previous, to: .empty, in: quran), .empty)
    }

    func testAnUnworkedPassageTransfersNothing() {
        let previous = LearningProgram(items: [item(range(from: (78, 1), to: (78, 40)))], generatedAt: day(0))
        let program = LearningProgram(items: [item(range(from: (78, 1), to: (78, 40)))], generatedAt: day(0))

        let result = LearningProgressTransfer.transfer(progressFrom: previous, to: program, in: quran)

        XCTAssertEqual(summary(of: result), ["78:1-78:40 neuf"])
    }

    func testAWholePageIsNamedByItsPageNumber() {
        // Page 582 du mushaf Madani 1405 : les trente premiers versets d'An-Naba, 78:1 à 78:30.
        let page = range(from: (78, 1), to: (78, 30))
        let program = LearningProgram(items: [item(page)], generatedAt: day(0))
        let result = LearningProgressTransfer.transfer(progressFrom: program, to: program, in: quran)
        XCTAssertEqual(result.items.first?.label, "page 582")
    }

    func testAFullyCoveredPassageKeepsItsProgress() {
        let previous = LearningProgram(
            items: [item(range(from: (78, 1), to: (78, 15)), stage: 1, nextReview: day(3), lastWorkedAt: day(0))],
            generatedAt: day(0)
        )
        let program = LearningProgram(items: [item(range(from: (78, 1), to: (78, 40)))], generatedAt: day(1))

        let result = LearningProgressTransfer.transfer(progressFrom: previous, to: program, in: quran)

        XCTAssertEqual(summary(of: result), ["78:1-78:15 appris/1", "78:16-78:40 neuf"])
        XCTAssertEqual(result.items.first?.nextReview, day(3))
        XCTAssertEqual(result.items.first?.lastWorkedAt, day(0))
        XCTAssertNil(result.items.last?.nextReview)
    }

    func testAnAcquisitionInTheMiddleSplitsThePassageInThree() {
        let previous = LearningProgram(
            items: [item(range(from: (78, 5), to: (78, 10)), stage: 0, nextReview: day(1))],
            generatedAt: day(0)
        )
        let program = LearningProgram(items: [item(range(from: (78, 1), to: (78, 40)))], generatedAt: day(1))

        let result = LearningProgressTransfer.transfer(progressFrom: previous, to: program, in: quran)

        XCTAssertEqual(summary(of: result), ["78:1-78:4 neuf", "78:5-78:10 appris/0", "78:11-78:40 neuf"])
    }

    func testASingleVerseAcquisitionDoesNotSplitAnything() {
        let previous = LearningProgram(
            items: [item(range(from: (78, 1), to: (78, 1)), stage: 0, nextReview: day(1))],
            generatedAt: day(0)
        )
        let program = LearningProgram(items: [item(range(from: (78, 1), to: (78, 1)))], generatedAt: day(1))

        let result = LearningProgressTransfer.transfer(progressFrom: previous, to: program, in: quran)

        XCTAssertEqual(summary(of: result), ["78:1-78:1 appris/0"])
    }

    func testTheStrongestAcquisitionWinsOnEveryAxis() {
        let previous = LearningProgram(items: [
            item(range(from: (78, 1), to: (78, 10)), position: 0, stage: 0, nextReview: day(5), lastWorkedAt: day(0)),
            item(range(from: (78, 5), to: (78, 15)), position: 1, stage: 2, nextReview: day(2), lastWorkedAt: day(1)),
        ], generatedAt: day(0))
        let program = LearningProgram(items: [item(range(from: (78, 1), to: (78, 20)))], generatedAt: day(1))

        let result = LearningProgressTransfer.transfer(progressFrom: previous, to: program, in: quran)

        XCTAssertEqual(summary(of: result), ["78:1-78:4 appris/0", "78:5-78:15 appris/2", "78:16-78:20 neuf"])
        // La révision due la plus proche, et le dernier travail le plus récent.
        XCTAssertEqual(result.items[1].nextReview, day(2))
        XCTAssertEqual(result.items[1].lastWorkedAt, day(1))
        XCTAssertEqual(result.items[0].nextReview, day(5))
    }

    func testTheEarliestReviewIsNeverPostponed() {
        let previous = LearningProgram(items: [
            item(range(from: (78, 1), to: (78, 10)), position: 0, stage: 0, nextReview: day(5)),
            item(range(from: (78, 1), to: (78, 10)), position: 1, stage: 0, nextReview: day(1)),
        ], generatedAt: day(0))
        let program = LearningProgram(items: [item(range(from: (78, 1), to: (78, 10)))], generatedAt: day(1))

        let result = LearningProgressTransfer.transfer(progressFrom: previous, to: program, in: quran)

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.nextReview, day(1))
    }

    func testAFragileReviewKeepsItsOwnDueDateWhenNothingPrecedesIt() {
        let previous = LearningProgram(items: [item(range(from: (78, 1), to: (78, 3)))], generatedAt: day(0))
        let program = LearningProgram(items: [
            item(range(from: (78, 1), to: (78, 3)), position: 0),
            item(range(from: (2, 1), to: (2, 5)), position: 1, stage: 0, nextReview: day(0)),
        ], generatedAt: day(1))

        let result = LearningProgressTransfer.transfer(progressFrom: previous, to: program, in: quran)

        XCTAssertEqual(summary(of: result), ["78:1-78:3 neuf", "2:1-2:5 appris/0"])
        XCTAssertEqual(result.items.last?.nextReview, day(0))
    }

    func testTheGenerationDateIsTheNewOne() {
        let previous = LearningProgram(items: [item(range(from: (78, 1), to: (78, 3)), stage: 0)], generatedAt: day(0))
        let program = LearningProgram(items: [item(range(from: (78, 1), to: (78, 3)))], generatedAt: day(7))

        let result = LearningProgressTransfer.transfer(progressFrom: previous, to: program, in: quran)

        XCTAssertEqual(result.generatedAt, day(7))
    }

    func testPositionsFollowTheOrderOfTheNewProgramme() {
        let previous = LearningProgram(items: [
            item(range(from: (78, 5), to: (78, 10)), stage: 0),
        ], generatedAt: day(0))
        let program = LearningProgram(items: [item(range(from: (78, 1), to: (78, 40)))], generatedAt: day(1))

        let result = LearningProgressTransfer.transfer(progressFrom: previous, to: program, in: quran)

        XCTAssertEqual(result.items.map(\.position), Array(0 ..< result.items.count))
    }

    func testIdentifiersAreUnique() {
        let previous = LearningProgram(items: [
            item(range(from: (78, 5), to: (78, 10)), position: 0, stage: 0),
            item(range(from: (78, 20), to: (78, 25)), position: 1, stage: 1),
        ], generatedAt: day(0))
        let program = LearningProgram(items: [item(range(from: (78, 1), to: (78, 40)))], generatedAt: day(1))

        let result = LearningProgressTransfer.transfer(progressFrom: previous, to: program, in: quran)

        XCTAssertEqual(Set(result.items.map(\.id)).count, result.items.count)
    }

    func testProgressOutsideTheNewProgrammeIsNotResurrected() {
        let previous = LearningProgram(
            items: [item(range(from: (2, 1), to: (2, 10)), stage: 2, nextReview: day(7))],
            generatedAt: day(0)
        )
        let program = LearningProgram(items: [item(range(from: (78, 1), to: (78, 40)))], generatedAt: day(1))

        let result = LearningProgressTransfer.transfer(progressFrom: previous, to: program, in: quran)

        XCTAssertEqual(summary(of: result), ["78:1-78:40 neuf"])
    }

    func testBoundsAbsentFromTheMushafAreKeptAsIs() {
        let previous = LearningProgram(
            items: [item(range(from: (78, 1), to: (78, 3)), stage: 0, nextReview: day(1))],
            generatedAt: day(0)
        )
        let absent = range(from: (200, 1), to: (200, 3))
        let program = LearningProgram(items: [
            item(absent, position: 0),
            item(range(from: (78, 1), to: (78, 3)), position: 1),
        ], generatedAt: day(1))

        let result = LearningProgressTransfer.transfer(progressFrom: previous, to: program, in: quran)

        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0].range, absent)
        XCTAssertEqual(result.items[0].storedStatus, .notLearned)
        XCTAssertEqual(result.items[1].storedStatus, .learned)
        XCTAssertEqual(result.items.map(\.position), [0, 1])
    }

    // MARK: - Reprise d'un programme réellement planifié

    func testRegeneratingAnUnchangedProfileKeepsTheSameProgramme() {
        let profile = makeProfile(pace: .doux)
        var marked = planner.makeProgram(for: profile, from: day(0))
        marked.markLearned(id: marked.items[0].id, at: day(0), calendar: calendar)
        marked.markLearned(id: marked.items[1].id, at: day(0), calendar: calendar)

        // Un programme régénéré porte des identifiants neufs ; la reprise doit rendre l'ancien.
        let regenerated = LearningProgressTransfer.transfer(
            progressFrom: marked,
            to: planner.makeProgram(for: profile, from: day(0)),
            in: quran
        )

        XCTAssertEqual(regenerated, marked)
    }

    func testTheAcquiredVerseCountSurvivesAChangeOfPace() {
        var profile = makeProfile(pace: .doux)
        var program = planner.makeProgram(for: profile, from: day(0))

        // L'allure « doux » vise 3 versets par séance : les cinq premières séances font 15 versets.
        for item in program.items.prefix(5) {
            program.markLearned(id: item.id, at: day(0), calendar: calendar)
        }
        let acquired = program.learnedVerses(in: quran)
        XCTAssertEqual(acquired, 15)

        // À l'allure « soutenu », la sourate tient en deux séances — 78:1 à 78:30, puis 78:31 à
        // 78:40. L'acquis de 15 versets tombe au milieu de la première : sans découpage, la reprise
        // effacerait ces 15 versets.
        profile.pace = .soutenu
        let regenerated = LearningProgressTransfer.transfer(
            progressFrom: program,
            to: planner.makeProgram(for: profile, from: day(0)),
            in: quran
        )

        XCTAssertEqual(summary(of: regenerated), ["78:1-78:15 appris/0", "78:16-78:30 neuf", "78:31-78:40 neuf"])
        XCTAssertEqual(regenerated.learnedVerses(in: quran), acquired)
        XCTAssertEqual(regenerated.totalVerses(in: quran), 40)
    }

    // MARK: Private

    private let quran = Quran.hafsMadani1405

    /// Calendrier figé pour des tests déterministes, quelle que soit la machine.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var planner: LearningPlanner { LearningPlanner(quran: quran, calendar: calendar) }

    /// Le jour `offset` après le mercredi 30 septembre 2026, midi UTC.
    private func day(_ offset: Int) -> Date {
        let reference = DateComponents(calendar: calendar, year: 2026, month: 9, day: 30, hour: 12).date!
        return calendar.date(byAdding: .day, value: offset, to: reference)!
    }

    private func range(from first: (sura: Int, ayah: Int), to last: (sura: Int, ayah: Int)) -> QuranRange {
        QuranRange(
            firstSura: first.sura,
            firstAyah: first.ayah,
            lastSura: last.sura,
            lastAyah: last.ayah
        )
    }

    /// Un passage. `stage` à `nil` veut dire « jamais travaillé ».
    private func item(
        _ range: QuranRange,
        position: Int = 0,
        stage: Int? = nil,
        nextReview: Date? = nil,
        lastWorkedAt: Date? = nil
    ) -> LearningItem {
        var item = LearningItem(range: range, label: nil, position: position)
        guard let stage else { return item }
        item.storedStatus = .learned
        item.reviewStage = stage
        item.nextReview = nextReview
        item.lastWorkedAt = lastWorkedAt
        return item
    }

    /// Un profil dont le seul objectif est la sourate An-Naba entière, 78:1 à 78:40.
    ///
    /// Le nom porte `make` : nommer la variable locale comme la méthode la masquerait dans son
    /// propre initialiseur, et Swift refuse `let profile = profile(...)`.
    private func makeProfile(pace: LearningPace) -> LearningProfile {
        LearningProfile(
            goals: [LearningGoal(range: range(from: (78, 1), to: (78, 40)), label: "An-Naba", targetDate: nil)],
            pace: pace,
            days: [.lundi],
            isConfigured: true
        )
    }

    /// Les passages d'un programme, en une ligne chacun — lisible dans un échec de test.
    private func summary(of program: LearningProgram) -> [String] {
        program.items.map { item in
            let range = item.range
            let state = item.storedStatus == .notLearned ? "neuf" : "appris/\(item.reviewStage)"
            return "\(range.firstSura):\(range.firstAyah)-\(range.lastSura):\(range.lastAyah) \(state)"
        }
    }
}
