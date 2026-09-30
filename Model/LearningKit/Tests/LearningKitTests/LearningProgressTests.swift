//
//  LearningProgressTests.swift
//  LearningKitTests
//
//  Éprouve le relevé de progression, sourate par sourate.
//

import QuranKit
import XCTest
@testable import LearningKit

final class LearningProgressTests: XCTestCase {
    // MARK: Internal

    // MARK: - Relevé

    func test_emptyProgress_isEmpty() {
        XCTAssertTrue(LearningProgress.empty.isEmpty)
        XCTAssertTrue(LearningProgress.empty.surahs.isEmpty)
        XCTAssertNil(LearningProgress.empty.record(forSurah: 78))
        XCTAssertEqual(LearningProgress.empty.lastMemorizedVerse(inSurah: 78), 0)
    }

    func test_aFreshProgram_hasNoWatermarkButKnowsWhatIsAimedAt() {
        let progress = LearningProgress(of: makeProgram(), in: quran)

        XCTAssertEqual(progress.surahs.map(\.surahId), [78])
        XCTAssertEqual(progress.lastMemorizedVerse(inSurah: 78), 0, "Rien n'est appris tant que rien n'est marqué")
        XCTAssertEqual(progress.record(forSurah: 78)?.targetVerse, lastAyah(ofSura: 78))
    }

    /// Le cas qui décide de tout : un passage sauté ne fait pas passer pour appris ce qui le suit.
    ///
    /// Sans l'arrêt au premier passage non appris, le repère courrait jusqu'au plus lointain des
    /// versets travaillés, et le programme reproposerait à neuf tout ce qui a été sauté — ou pire,
    /// tiendrait pour appris ce qui ne l'est pas.
    func test_theWatermarkStopsAtTheFirstUnlearnedPassage() {
        let planned = makeProgram(learned: [0, 1, 3])
        let progress = LearningProgress(of: planned, in: quran)

        let second = planned.items[1].range.lastAyah
        let fourth = planned.items[3].range.lastAyah
        XCTAssertLessThan(second, fourth, "Le passage sauté doit être plus loin, sans quoi ce test ne prouve rien")

        XCTAssertEqual(progress.lastMemorizedVerse(inSurah: 78), second)
    }

    func test_theWatermarkIsKeptPerSurah() {
        var planned = makeProgram(goals: [twoSuras], pace: .soutenu)
        for index in planned.items.indices {
            let id = planned.items[index].id
            planned.markLearned(id: id, at: day(0), calendar: calendar)
        }

        let progress = LearningProgress(of: planned, in: quran)

        XCTAssertEqual(progress.surahs.map(\.surahId), [78, 79])
        XCTAssertEqual(
            progress.lastMemorizedVerse(inSurah: 78),
            lastAyah(ofSura: 78),
            "La sourate traversée reçoit le repère qui la concerne, et non celui de la suivante"
        )
        XCTAssertEqual(progress.lastMemorizedVerse(inSurah: 79), twoSuras.lastAyah)
    }

    func test_aWatermarkCoversEveryVerseUpToIt() {
        let record = SurahLearningProgress(
            surahId: 78,
            lastMemorizedVerse: 6,
            targetVerse: 40,
            startedAt: day(0),
            updatedAt: day(0)
        )

        XCTAssertTrue(record.covers(verse: 1))
        XCTAssertTrue(record.covers(verse: 6))
        XCTAssertFalse(record.covers(verse: 7), "Le repère ne couvre pas ce qui le suit")
        XCTAssertFalse(record.covers(verse: 0), "Aucun verset ne porte le numéro 0")
    }

    // MARK: - Couverture d'un intervalle

    func test_learnedAt_takesTheEarliestOfTheSurasCrossed() throws {
        let index = QuranVerseIndex(quran: quran)
        let endOfNaba = try XCTUnwrap(index.offset(sura: 78, ayah: lastAyah(ofSura: 78)))
        let progress = LearningProgress(surahs: [
            record(78, watermark: lastAyah(ofSura: 78), updatedAt: day(5)),
            record(79, watermark: 1, updatedAt: day(2)),
        ])

        // Un passage qui chevauche la fin de la sourate 78 et le début de la 79.
        let span = endOfNaba ... (endOfNaba + 1)
        XCTAssertEqual(
            progress.learnedAt(span, in: index),
            day(2),
            "La plus ancienne des deux : une révision due ne doit jamais être repoussée"
        )
    }

    func test_learnedAt_isNilWhenAPartOfTheIntervalIsNotCovered() throws {
        let index = QuranVerseIndex(quran: quran)
        let firstOfNazi = try XCTUnwrap(index.offset(sura: 79, ayah: 1))
        let progress = LearningProgress(surahs: [record(79, watermark: 1, updatedAt: day(0))])

        XCTAssertEqual(progress.learnedAt(firstOfNazi ... firstOfNazi, in: index), day(0))
        XCTAssertNil(
            progress.learnedAt(firstOfNazi ... (firstOfNazi + 5), in: index),
            "Un seul verset non couvert suffit à rendre l'intervalle non appris"
        )
    }

    // MARK: - Fusion

    func test_merging_keepsTheFurthestReading() {
        let early = LearningProgress(surahs: [record(78, watermark: 6, updatedAt: day(0))])
        let late = LearningProgress(surahs: [
            SurahLearningProgress(
                surahId: 78,
                lastMemorizedVerse: 9,
                targetVerse: 40,
                startedAt: day(1),
                updatedAt: day(1)
            ),
        ])

        let merged = early.merging(late)

        XCTAssertEqual(merged.surahs.count, 1, "Une même sourate donne un seul enregistrement")
        XCTAssertEqual(merged.lastMemorizedVerse(inSurah: 78), 9)
        XCTAssertEqual(merged.record(forSurah: 78)?.startedAt, day(0), "Le premier commencement est conservé")
        XCTAssertEqual(merged.record(forSurah: 78)?.updatedAt, day(1), "Et le dernier passage")
        XCTAssertEqual(late.merging(early), merged, "Fusionner ne dépend pas de l'ordre")
    }

    func test_merging_keepsASurahTheOtherReadingIgnores() {
        let merged = LearningProgress(surahs: [record(2, watermark: 12, updatedAt: day(0))])
            .merging(LearningProgress(surahs: [record(78, watermark: 6, updatedAt: day(0))]))

        XCTAssertEqual(
            merged.surahs.map(\.surahId),
            [2, 78],
            "L'avancement d'une sourate que l'autre relevé ignore doit survivre : c'est ce qui "
                + "permet de retirer un objectif puis de le rajouter sans repartir de zéro"
        )
    }

    // MARK: - Persistance

    func test_progressSurvivesEncodingRoundTrip() throws {
        let progress = LearningProgress(surahs: [
            record(78, watermark: 6, updatedAt: day(2)),
            record(2, watermark: 12, updatedAt: day(1)),
        ])

        let data = try JSONEncoder().encode(progress)
        let decoded = try JSONDecoder().decode(LearningProgress.self, from: data)

        XCTAssertEqual(decoded, progress)
        XCTAssertEqual(decoded.surahs.map(\.surahId), [2, 78], "Et il reste rangé par sourate")
    }

    /// Le décodage passe par l'initialiseur qui range et fusionne : un relevé écrit à la main, dans
    /// le désordre et avec un doublon, doit être relu sans faillir et sans perdre le repère le plus
    /// avancé. Un relevé corrompu ne doit jamais empêcher l'application de démarrer.
    func test_aDecodedProgressIsSortedAndDeduplicated() throws {
        let json = """
        [
          {"surahId": 79, "lastMemorizedVerse": 10, "targetVerse": 46, "startedAt": 0, "updatedAt": 0},
          {"surahId": 78, "lastMemorizedVerse": 6, "targetVerse": 40, "startedAt": 0, "updatedAt": 0},
          {"surahId": 79, "lastMemorizedVerse": 25, "targetVerse": 46, "startedAt": 0, "updatedAt": 0}
        ]
        """

        let progress = try JSONDecoder().decode(LearningProgress.self, from: Data(json.utf8))

        XCTAssertEqual(progress.surahs.map(\.surahId), [78, 79])
        XCTAssertEqual(progress.lastMemorizedVerse(inSurah: 79), 25, "Le repère le plus avancé l'emporte")
    }

    func test_aCorruptedProgressFailsToDecode() {
        for corrupted in ["pas du json", "{}", "{\"surahs\": 3}"] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(LearningProgress.self, from: Data(corrupted.utf8)),
                "« \(corrupted) » ne décrit pas un relevé"
            )
        }
    }

    // MARK: Private

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

    /// An-Naba — l'objectif de la plupart de ces tests.
    private var naba: QuranRange { QuranRange(quran.suras[77]) }

    /// An-Naba puis An-Nazi'at : de quoi éprouver un repère qui se partage entre deux sourates.
    private var twoSuras: QuranRange {
        QuranRange(firstSura: 78, firstAyah: 1, lastSura: 79, lastAyah: lastAyah(ofSura: 79))
    }

    private func lastAyah(ofSura suraNumber: Int) -> Int {
        quran.suras.first { $0.suraNumber == suraNumber }!.lastVerse.ayah
    }

    private func record(_ surahId: Int, watermark: Int, updatedAt: Date) -> SurahLearningProgress {
        SurahLearningProgress(
            surahId: surahId,
            lastMemorizedVerse: watermark,
            targetVerse: lastAyah(ofSura: surahId),
            startedAt: day(0),
            updatedAt: updatedAt
        )
    }

    /// Un programme d'essai, avec les passages désignés déjà appris.
    private func makeProgram(
        goals: [QuranRange]? = nil,
        pace: LearningPace = .doux,
        learned: [Int] = []
    ) -> LearningProgram {
        let profile = LearningProfile(
            goals: (goals ?? [naba]).map { LearningGoal(range: $0, label: nil, targetDate: nil) },
            pace: pace,
            days: Set(LearningDay.allCases),
            createdAt: day0,
            isConfigured: true
        )
        var planned = LearningPlanner(quran: quran, calendar: calendar).makeProgram(for: profile, from: day0)
        for index in learned {
            let id = planned.items[index].id
            planned.markLearned(id: id, at: day0, calendar: calendar)
        }
        return planned
    }
}
