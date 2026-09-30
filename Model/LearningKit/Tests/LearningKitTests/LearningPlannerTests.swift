//
//  LearningPlannerTests.swift
//  LearningKitTests
//
//  Éprouve la génération du programme à partir du profil.
//

import QuranKit
import XCTest
@testable import LearningKit

final class LearningPlannerTests: XCTestCase {
    private let quran = Quran.hafsMadani1405

    /// Calendrier figé pour des tests déterministes, quelle que soit la machine.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Un jour de référence stable : mercredi 30 septembre 2026, midi UTC.
    private var day0: Date {
        DateComponents(calendar: calendar, year: 2026, month: 9, day: 30, hour: 12).date!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: day0)!
    }

    /// Table verset → rang, reconstruite **ici** à partir du mushaf.
    ///
    /// Elle sert d'oracle : réutiliser la table interne du planificateur ne prouverait rien,
    /// puisque la même erreur se retrouverait des deux côtés.
    private var offsetsByVerse: [AyahNumber: Int] = [:]

    override func setUp() {
        super.setUp()
        var offsets: [AyahNumber: Int] = [:]
        for (offset, verse) in quran.verses.enumerated() {
            offsets[verse] = offset
        }
        offsetsByVerse = offsets
    }

    private func verseOffsets(of range: QuranRange) -> ClosedRange<Int>? {
        guard
            let bounds = range.bounds(in: quran),
            let first = offsetsByVerse[bounds.first],
            let last = offsetsByVerse[bounds.last]
        else {
            return nil
        }
        return first ... last
    }

    private func planner() -> LearningPlanner {
        LearningPlanner(quran: quran, calendar: calendar)
    }

    /// Construit un profil d'essai.
    ///
    /// Le nom porte `make` : nommer la variable locale comme la méthode la masquerait dans son
    /// propre initialiseur, ce que Swift refuse.
    private func makeProfile(
        goals: [QuranRange],
        known: [KnownRange] = [],
        pace: LearningPace = .regulier,
        days: Set<LearningDay> = Set(LearningDay.allCases)
    ) -> LearningProfile {
        LearningProfile(
            knownRanges: known,
            goals: goals.map { LearningGoal(range: $0, label: nil, targetDate: nil) },
            pace: pace,
            days: days,
            createdAt: day0,
            isConfigured: true
        )
    }

    /// Les rangs couverts par un programme, dans l'ordre.
    private func coveredOffsets(of program: LearningProgram) -> [ClosedRange<Int>] {
        program.items.compactMap { verseOffsets(of: $0.range) }
    }

    private func assertContiguous(
        _ covered: [ClosedRange<Int>],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (previous, next) in zip(covered, covered.dropFirst()) {
            XCTAssertEqual(
                next.lowerBound,
                previous.upperBound + 1,
                "Le programme doit être continu : aucun trou, aucun recouvrement",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Couverture de l'objectif

    func test_program_coversTheGoalExactlyOnce() {
        let goal = QuranRange(quran.juzs[29])
        let program = planner().makeProgram(for: makeProfile(goals: [goal]), from: day0)

        let covered = coveredOffsets(of: program)
        XCTAssertFalse(covered.isEmpty)

        let total = covered.reduce(0) { $0 + ($1.upperBound - $1.lowerBound + 1) }
        XCTAssertEqual(total, goal.verseCount(in: quran), "Le programme doit couvrir l'objectif exactement")
        assertContiguous(covered)
    }

    func test_program_startsAndEndsOnTheGoalBounds() {
        let goal = QuranRange(quran.juzs[29])
        guard let bounds = verseOffsets(of: goal) else {
            return XCTFail("Le juz' 'Amma doit avoir des bornes dans ce mushaf")
        }
        let program = planner().makeProgram(for: makeProfile(goals: [goal]), from: day0)
        let covered = coveredOffsets(of: program)

        XCTAssertEqual(covered.first?.lowerBound, bounds.lowerBound)
        XCTAssertEqual(covered.last?.upperBound, bounds.upperBound)
    }

    func test_wholeQuranGoal_coversEveryVerseExactlyOnce() {
        let whole = QuranRange(firstSura: 1, firstAyah: 1, lastSura: 114, lastAyah: 6)
        let program = planner().makeProgram(for: makeProfile(goals: [whole], pace: .soutenu), from: day0)
        let covered = coveredOffsets(of: program)

        XCTAssertEqual(covered.first?.lowerBound, 0)
        XCTAssertEqual(covered.last?.upperBound, quran.verses.count - 1)
        XCTAssertEqual(program.totalVerses(in: quran), quran.verses.count)
        assertContiguous(covered)
    }

    func test_overlappingGoals_areProgrammedOnce() {
        // Al-Fatiha est comprise dans le premier juz' : l'union ne doit pas se répéter.
        let sura = QuranRange(quran.suras[0])
        let juz = QuranRange(quran.juzs[0])
        let program = planner().makeProgram(for: makeProfile(goals: [sura, juz]), from: day0)
        let covered = coveredOffsets(of: program)

        XCTAssertEqual(program.totalVerses(in: quran), juz.verseCount(in: quran))
        assertContiguous(covered)
    }

    // MARK: - Découpage en séances

    func test_sessions_neverExceedTwiceTheTarget() {
        // Le découpage cherche une fin de page : il peut dépasser la cible, mais jamais du double.
        for pace in LearningPace.allCases {
            let program = planner().makeProgram(for: makeProfile(goals: [QuranRange(quran.juzs[29])], pace: pace), from: day0)
            for item in program.items {
                XCTAssertLessThanOrEqual(
                    item.verseCount(in: quran),
                    pace.targetVersesPerSession * 2,
                    "Allure \(pace) : aucune séance ne dépasse le double de la cible"
                )
            }
        }
    }

    func test_sessions_endOnAPageBoundaryOrOnTheExactTarget() {
        let program = planner().makeProgram(for: makeProfile(goals: [QuranRange(quran.juzs[29])], pace: .regulier), from: day0)
        let pageEnds = Set(quran.pages.compactMap { verseOffsets(of: QuranRange($0))?.upperBound })
        let target = LearningPace.regulier.targetVersesPerSession

        // Toutes les séances sauf la dernière, qui peut être plus courte faute de matière.
        for item in program.items.dropLast() {
            guard let chunk = verseOffsets(of: item.range) else {
                return XCTFail("Chaque passage doit avoir des bornes")
            }
            let endsOnAPage = pageEnds.contains(chunk.upperBound)
            let isExactTarget = chunk.upperBound - chunk.lowerBound + 1 == target
            XCTAssertTrue(
                endsOnAPage || isExactTarget,
                "Une séance se termine sur une fin de page ou sur la cible exacte, jamais au hasard"
            )
        }
    }

    func test_aSinglePageGoal_yieldsExactlyOneWholePageSession() {
        // Toutes les pages ne conviennent pas : il faut que la page tienne dans la fenêtre de la
        // cible (entre une et deux fois). On prend la première qui convient plutôt que de figer un
        // numéro de page — c'est le mushaf qui fait référence, pas le test.
        let target = LearningPace.soutenu.targetVersesPerSession
        let fitting = quran.pages.filter { page in
            guard let chunk = verseOffsets(of: QuranRange(page)) else { return false }
            let size = chunk.upperBound - chunk.lowerBound + 1
            return size >= target && size <= target * 2
        }
        guard let page = fitting.first else {
            return XCTFail("Aucune page ne tient dans la fenêtre de la cible")
        }

        let range = QuranRange(page)
        let program = planner().makeProgram(for: makeProfile(goals: [range], pace: .soutenu), from: day0)

        XCTAssertEqual(program.items.count, 1, "Une page entière doit former une seule séance")
        XCTAssertEqual(program.items.first?.range, range)
        XCTAssertEqual(program.items.first?.label, "page \(page.pageNumber)")
    }

    // MARK: - Acquis solides

    func test_solidRanges_areNeverProgrammed() {
        let juz = QuranRange(quran.juzs[29])
        let solid = QuranRange(quran.suras[77]) // An-Naba, dans le juz' 'Amma
        guard let solidOffsets = verseOffsets(of: solid) else {
            return XCTFail("An-Naba doit avoir des bornes dans ce mushaf")
        }

        let program = planner().makeProgram(
            for: makeProfile(
                goals: [juz],
                known: [KnownRange(range: solid, label: "An-Naba", solidity: .solide)]
            ),
            from: day0
        )

        for item in program.items {
            guard let chunk = verseOffsets(of: item.range) else {
                return XCTFail("Chaque passage doit avoir des bornes")
            }
            XCTAssertFalse(chunk.overlaps(solidOffsets), "Un acquis solide ne doit jamais être programmé")
        }
    }

    func test_solidRanges_reduceTheProgramByTheirExactSize() {
        let juz = QuranRange(quran.juzs[29])
        let solid = QuranRange(quran.suras[77])

        let full = planner().makeProgram(for: makeProfile(goals: [juz]), from: day0)
        let reduced = planner().makeProgram(
            for: makeProfile(goals: [juz], known: [KnownRange(range: solid, label: nil, solidity: .solide)]),
            from: day0
        )

        XCTAssertEqual(
            full.totalVerses(in: quran) - reduced.totalVerses(in: quran),
            solid.verseCount(in: quran),
            "Retrancher un acquis solide retire exactement ses versets"
        )
        assertContiguous(coveredOffsets(of: reduced))
    }

    func test_goalEntirelyKnownSolid_yieldsAnEmptyProgram() {
        let sura = QuranRange(quran.suras[0])
        let program = planner().makeProgram(
            for: makeProfile(goals: [sura], known: [KnownRange(range: sura, label: nil, solidity: .solide)]),
            from: day0
        )

        XCTAssertTrue(program.isEmpty, "Tout est déjà connu : il n'y a rien à programmer")
    }

    /// Le pendant exact du test précédent, côté fragile : il reste une révision à faire.
    ///
    /// Le cas est étroit — l'objectif est **entièrement** couvert par un acquis fragile — et c'est
    /// précisément celui où une sortie anticipée sur « plus rien à apprendre » faisait disparaître
    /// la révision, alors que l'utilisateur venait de déclarer qu'il l'oublie.
    func test_goalEntirelyKnownFragile_yieldsTheReviewItem() {
        let sura = QuranRange(quran.suras[0])
        let fragile = KnownRange(range: sura, label: nil, solidity: .fragile)
        let profile = makeProfile(goals: [sura], known: [fragile])
        let program = planner().makeProgram(for: profile, from: day0)

        XCTAssertFalse(program.isEmpty, "Un acquis fragile reste un passage à revoir")
        XCTAssertEqual(program.items.count, 1, "La sourate fragile est le seul passage")
        XCTAssertEqual(program.items.first?.range, sura)
        XCTAssertEqual(
            program.items.first?.storedStatus,
            .learned,
            "Un acquis n'est jamais à apprendre"
        )
        XCTAssertEqual(
            program.dueReviews(now: day0, calendar: calendar).count,
            1,
            "Et il est dû dès aujourd'hui"
        )
    }

    // MARK: - Acquis fragiles

    func test_fragileRange_becomesAReviewItemAndLeavesTheNewMaterial() {
        let juz = QuranRange(quran.juzs[29])
        let fragile = QuranRange(quran.suras[77])
        guard let fragileOffsets = verseOffsets(of: fragile) else {
            return XCTFail("An-Naba doit avoir des bornes dans ce mushaf")
        }

        let program = planner().makeProgram(
            for: makeProfile(
                goals: [juz],
                known: [KnownRange(range: fragile, label: "An-Naba", solidity: .fragile)]
            ),
            from: day0
        )

        let reviewItems = program.items.filter { $0.range == fragile }
        XCTAssertEqual(reviewItems.count, 1, "Un acquis fragile revient exactement une fois, en révision")
        XCTAssertEqual(reviewItems.first?.storedStatus, .learned, "Un acquis fragile n'est jamais « à apprendre »")
        XCTAssertEqual(
            reviewItems.first?.status(now: day0, calendar: calendar),
            .toReview,
            "Il est dû en révision dès la génération : c'est ce que l'utilisateur a déclaré"
        )

        // Aucun autre passage ne recouvre la sourate fragile : elle n'est pas reproposée à neuf.
        for item in program.items where item.range != fragile {
            guard let chunk = verseOffsets(of: item.range) else {
                return XCTFail("Chaque passage doit avoir des bornes")
            }
            XCTAssertFalse(
                chunk.overlaps(fragileOffsets),
                "Un acquis fragile ne doit pas être reproposé à l'apprentissage"
            )
        }
    }

    func test_fragileRange_doesNotCountAsADayOfWorked() {
        let program = planner().makeProgram(
            for: makeProfile(
                goals: [QuranRange(quran.juzs[29])],
                known: [KnownRange(range: QuranRange(quran.suras[77]), label: nil, solidity: .fragile)]
            ),
            from: day0
        )

        XCTAssertEqual(
            program.streak(now: day0, calendar: calendar),
            0,
            "Déclarer un acquis fragile n'est pas un jour de travail"
        )
        XCTAssertEqual(
            program.dueReviews(now: day0, calendar: calendar).count,
            1,
            "L'acquis fragile est le seul passage dû"
        )
    }

    // MARK: - Profils sans matière

    func test_noGoal_yieldsAnEmptyProgram() {
        XCTAssertTrue(planner().makeProgram(for: makeProfile(goals: []), from: day0).isEmpty)
    }

    func test_emptyProfile_yieldsAnEmptyProgram() {
        XCTAssertTrue(planner().makeProgram(for: .empty, from: day0).isEmpty)
    }

    // MARK: - Déterminisme

    func test_sameProfileAndDate_produceTheSamePassages() {
        let profile = makeProfile(goals: [QuranRange(quran.juzs[29])], pace: .soutenu)
        let first = planner().makeProgram(for: profile, from: day0)
        let second = planner().makeProgram(for: profile, from: day0)

        // Les identifiants sont neufs à chaque génération : un programme régénéré repart de zéro.
        // Ce sont donc les passages, et non les identifiants, qui doivent être identiques.
        XCTAssertEqual(first.items.map(\.range), second.items.map(\.range))
        XCTAssertEqual(first.items.map(\.position), second.items.map(\.position))
        XCTAssertEqual(first.items.map(\.label), second.items.map(\.label))
    }

    func test_positions_areConsecutiveFromZero() {
        let program = planner().makeProgram(for: makeProfile(goals: [QuranRange(quran.juzs[29])]), from: day0)

        XCTAssertEqual(program.items.map(\.position), Array(0 ..< program.items.count))
    }

    func test_program_survivesEncodingRoundTrip() throws {
        let program = planner().makeProgram(for: makeProfile(goals: [QuranRange(quran.juzs[29])]), from: day0)

        let data = try JSONEncoder().encode(program)
        let decoded = try JSONDecoder().decode(LearningProgram.self, from: data)

        XCTAssertEqual(decoded, program, "Un programme généré doit survivre à un aller-retour JSON")
    }

    // MARK: - Date de fin estimée

    func test_estimatedEndDate_withEveryDayWorked_landsOnTheSessionCount() {
        let profile = makeProfile(goals: [QuranRange(quran.juzs[29])], pace: .regulier)
        let program = planner().makeProgram(for: profile, from: day0)
        let perSession = LearningPace.regulier.targetVersesPerSession
        let sessions = (program.totalVerses(in: quran) + perSession - 1) / perSession

        XCTAssertEqual(
            planner().estimatedEndDate(for: program, profile: profile, from: day0),
            calendar.date(byAdding: .day, value: sessions - 1, to: calendar.startOfDay(for: day0)),
            "Avec tous les jours travaillés, la fin tombe sur la n-ième séance"
        )
    }

    func test_estimatedEndDate_withOneWorkingDayPerWeek_countsOnlyThatDay() {
        let profile = makeProfile(goals: [QuranRange(quran.suras[1])], pace: .regulier, days: [.lundi])
        let program = planner().makeProgram(for: profile, from: day0)
        let perSession = LearningPace.regulier.targetVersesPerSession
        let sessions = (program.totalVerses(in: quran) + perSession - 1) / perSession

        guard let end = planner().estimatedEndDate(for: program, profile: profile, from: day0) else {
            return XCTFail("Une date de fin est attendue dès qu'un jour de travail est choisi")
        }
        XCTAssertEqual(calendar.component(.weekday, from: end), LearningDay.lundi.calendarWeekday)

        // Oracle indépendant : on compte les lundis écoulés entre le départ et la fin.
        var mondays = 0
        var cursor = calendar.startOfDay(for: day0)
        while cursor <= end {
            if calendar.component(.weekday, from: cursor) == LearningDay.lundi.calendarWeekday {
                mondays += 1
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        XCTAssertEqual(mondays, sessions, "Autant de séances que de lundis écoulés")
    }

    func test_estimatedEndDate_ofAFinishedProgram_isToday() {
        let profile = makeProfile(goals: [QuranRange(quran.suras[0])])
        var program = planner().makeProgram(for: profile, from: day0)
        for id in program.items.map(\.id) {
            program.markLearned(id: id, at: day0, calendar: calendar)
        }

        XCTAssertEqual(
            planner().estimatedEndDate(for: program, profile: profile, from: day0),
            calendar.startOfDay(for: day0)
        )
    }

    func test_estimatedEndDate_isNilWithoutWorkingDay() {
        let profile = makeProfile(goals: [QuranRange(quran.suras[0])], days: [])
        let program = planner().makeProgram(for: profile, from: day0)

        XCTAssertNil(
            planner().estimatedEndDate(for: program, profile: profile, from: day0),
            "Sans jour de travail, il n'y a pas de fin estimable"
        )
    }

    // MARK: - Reprise de la progression

    /// Le socle de tout le module : reprendre ne **retire** rien du programme.
    ///
    /// Un programme qui se raccourcirait à mesure qu'on apprend ferait retomber l'avancement à zéro
    /// à chaque reprise — l'utilisateur verrait sa progression s'effondrer après chaque séance.
    /// Le programme reste donc l'objectif entier ; c'est l'état des passages qui change.
    func test_progress_doesNotChangeTheShapeOfTheProgram() {
        let profile = makeProfile(goals: [QuranRange(quran.suras[77])], pace: .doux)
        let fresh = planner().makeProgram(for: profile, from: day0)
        let progress = progressAfter(learning: [0, 1], of: profile)

        let resumed = planner().makeProgram(for: profile, progress: progress, from: day0)

        XCTAssertEqual(resumed.items.map(\.range), fresh.items.map(\.range))
        XCTAssertEqual(resumed.items.map(\.position), fresh.items.map(\.position))
        XCTAssertEqual(resumed.items.map(\.label), fresh.items.map(\.label))
        XCTAssertEqual(resumed.totalVerses(in: quran), fresh.totalVerses(in: quran))
    }

    func test_progress_marksTheLearnedPassagesAndLeavesTheRestToLearn() {
        let profile = makeProfile(goals: [QuranRange(quran.suras[77])], pace: .doux)
        let fresh = planner().makeProgram(for: profile, from: day0)
        let progress = progressAfter(learning: [0, 1], of: profile)

        let resumed = planner().makeProgram(for: profile, progress: progress, from: day0)

        XCTAssertEqual(Array(resumed.items.prefix(2).map(\.storedStatus)), [.learned, .learned])
        XCTAssertEqual(
            resumed.items.dropFirst(2).map(\.storedStatus),
            Array(repeating: .notLearned, count: resumed.items.count - 2)
        )
        XCTAssertEqual(
            resumed.nextToLearn()?.range,
            fresh.items[2].range,
            "La reprise se fait au passage qui suit le repère, et à lui seul"
        )
        XCTAssertGreaterThan(resumed.learnedVerses(in: quran), 0)
    }

    /// La demande centrale : **aucun retard**.
    ///
    /// Trois jours passent sans rien faire. Le programme doit proposer exactement le même passage,
    /// et non « les trois séances manquées ».
    func test_missedDays_addNoBacklog() {
        let profile = makeProfile(goals: [QuranRange(quran.suras[77])], pace: .doux)
        let progress = progressAfter(learning: [0, 1], of: profile)

        let today = planner().makeProgram(for: profile, progress: progress, from: day0)
        let threeDaysLater = planner().makeProgram(for: profile, progress: progress, from: day(3))

        XCTAssertEqual(today.items.count, threeDaysLater.items.count)
        XCTAssertEqual(today.nextToLearn()?.range, threeDaysLater.nextToLearn()?.range)
        XCTAssertEqual(today.learnedVerses(in: quran), threeDaysLater.learnedVerses(in: quran))
    }

    /// La progression ne recule jamais : apprendre un passage de plus ne peut pas en faire
    /// disparaître un déjà appris.
    func test_learningAPassageNeverReducesTheProgress() {
        let profile = makeProfile(goals: [QuranRange(quran.suras[77])], pace: .doux)
        let progress = progressAfter(learning: [0, 1], of: profile)

        var resumed = planner().makeProgram(for: profile, progress: progress, from: day0)
        let before = resumed.learnedVerses(in: quran)
        let next = resumed.items[2].id
        resumed.markLearned(id: next, at: day(1), calendar: calendar)

        let after = LearningProgress(of: resumed, in: quran)
        XCTAssertGreaterThan(resumed.learnedVerses(in: quran), before)
        XCTAssertGreaterThanOrEqual(
            after.lastMemorizedVerse(inSurah: 78),
            progress.lastMemorizedVerse(inSurah: 78)
        )
    }

    func test_aProgramRegeneratedFromItsOwnProgress_isUnchanged() {
        let profile = makeProfile(goals: [QuranRange(quran.suras[77])], pace: .doux)
        let progress = progressAfter(learning: [0, 1, 2], of: profile)

        let once = planner().makeProgram(for: profile, progress: progress, from: day0)
        let twice = planner().makeProgram(for: profile, progress: LearningProgress(of: once, in: quran), from: day0)

        XCTAssertEqual(once.items.map(\.storedStatus), twice.items.map(\.storedStatus))
        XCTAssertEqual(once.nextToLearn()?.range, twice.nextToLearn()?.range)
    }

    func test_anEmptyProgress_leavesTheProgramUntouched() {
        let profile = makeProfile(goals: [QuranRange(quran.juzs[29])])
        let plain = planner().makeProgram(for: profile, from: day0)
        let explicit = planner().makeProgram(for: profile, progress: .empty, from: day0)

        XCTAssertEqual(plain.items.map(\.storedStatus), explicit.items.map(\.storedStatus))
        XCTAssertEqual(plain.items.map(\.range), explicit.items.map(\.range))
    }

    // MARK: - Un verset déclaré deux fois

    /// Les deux déclarations se contredisent, et c'est la plus forte qui décide.
    ///
    /// Sans ce retranchement, le verset serait proposé à revoir alors que l'utilisateur vient
    /// d'affirmer qu'il le récite sans hésiter — et le compte des révisions mentirait.
    func test_aSuraDeclaredBothSolidAndFragile_isNotReviewed() {
        let sura = QuranRange(quran.suras[77])
        let profile = makeProfile(
            goals: [sura],
            known: [
                KnownRange(range: sura, label: nil, solidity: .solide),
                KnownRange(range: sura, label: nil, solidity: .fragile),
            ]
        )

        XCTAssertTrue(
            planner().makeProgram(for: profile, from: day0).isEmpty,
            "Rien à apprendre, et rien à revoir : le solide l'emporte sur le fragile"
        )
    }

    func test_aSolidPartInsideAFragileRange_isNotReviewed() {
        let fragile = QuranRange(quran.suras[77])
        let solid = QuranRange(firstSura: 78, firstAyah: 1, lastSura: 78, lastAyah: 20)
        let profile = makeProfile(
            goals: [fragile],
            known: [
                KnownRange(range: fragile, label: nil, solidity: .fragile),
                KnownRange(range: solid, label: nil, solidity: .solide),
            ]
        )

        let program = planner().makeProgram(for: profile, from: day0)

        XCTAssertEqual(program.items.count, 1, "Il ne reste qu'un morceau à revoir")
        XCTAssertEqual(program.items.first?.range.firstAyah, 21)
        XCTAssertEqual(program.items.first?.range.lastAyah, sura.lastAyah)
    }

    /// Le relevé obtenu après avoir appris les passages désignés d'un programme neuf.
    ///
    /// L'allure n'est pas un paramètre : c'est celle du profil qui décide du découpage, et la
    /// répéter ici laisserait croire qu'elle peut en différer.
    private func progressAfter(learning indices: [Int], of profile: LearningProfile) -> LearningProgress {
        var program = planner().makeProgram(for: profile, from: day0)
        for index in indices {
            let id = program.items[index].id
            program.markLearned(id: id, at: day0, calendar: calendar)
        }
        return LearningProgress(of: program, in: quran)
    }
}
