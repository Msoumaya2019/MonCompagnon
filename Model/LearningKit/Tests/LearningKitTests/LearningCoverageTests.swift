//
//  LearningCoverageTests.swift
//  LearningKitTests
//

import LearningKit
import QuranKit
import XCTest

final class LearningCoverageTests: XCTestCase {
    /// Calendrier figé, pour que les échéances ne dépendent pas de la machine.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Un jour de référence stable : mercredi 2026-09-30 à midi UTC.
    private var day0: Date {
        DateComponents(calendar: calendar, year: 2026, month: 9, day: 30, hour: 12).date!
    }

    private func date(daysAfter reference: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: reference)!
    }

    private var quran: Quran { .hafsMadani1405 }

    /// Un profil qui ne déclare que des acquis, sans objectif.
    private func profile(known ranges: [QuranRange], solidity: KnownRange.Solidity = .solide) -> LearningProfile {
        LearningProfile(knownRanges: ranges.map { KnownRange(range: $0, label: nil, solidity: solidity) })
    }

    /// Un programme d'un passage, appris ou non.
    ///
    /// Le nom porte `make` : une variable locale nommée `program` masquerait la méthode dans son
    /// propre initialiseur, ce que Swift refuse.
    private func makeProgram(of range: QuranRange, learned: Bool) -> LearningProgram {
        var program = LearningProgram(items: [LearningItem(range: range, label: nil, position: 0)])
        if learned {
            program.markLearned(id: program.items[0].id, at: day0, calendar: calendar)
        }
        return program
    }

    // MARK: - Le vide

    /// Rien d'appris : tout est inconnu, et aucun groupe n'échappe à la règle.
    func test_report_isEmptyWhenNothingIsLearned() {
        let report = LearningCoverageReport(profile: .empty, program: .empty, quran: quran)

        XCTAssertEqual(report.coverage(of: quran.suras[0]), .inconnue)
        XCTAssertEqual(report.coverage(of: quran.juzs[0]), .inconnue)
        XCTAssertEqual(report.coverage(of: quran.hizbs[0]), .inconnue)
        XCTAssertEqual(report.coveredVerses(of: quran.suras[0]), 0)
    }

    // MARK: - Les trois états

    /// Une sourate entièrement déclarée connue est **complète**.
    func test_coverage_aWholeSuraIsComplete() {
        let sura = quran.suras[113]
        let report = LearningCoverageReport(profile: profile(known: [QuranRange(sura)]), program: .empty, quran: quran)

        XCTAssertEqual(report.coverage(of: sura), .complete)
        XCTAssertEqual(report.coveredVerses(of: sura), report.verseCount(of: sura))
    }

    /// Un intervalle qui s'arrête **au milieu** d'une sourate la laisse partielle, et le compte de
    /// versets le dit — c'est ce qui évite de faire croire que toute la sourate est connue.
    func test_coverage_aRangeStoppingMidSuraIsPartial() {
        let sura = quran.suras[1]
        let half = QuranRange(firstSura: 2, firstAyah: 1, lastSura: 2, lastAyah: 141)
        let report = LearningCoverageReport(profile: profile(known: [half]), program: .empty, quran: quran)

        XCTAssertEqual(report.coverage(of: sura), .partielle)
        XCTAssertEqual(report.coveredVerses(of: sura), 141)
        XCTAssertEqual(report.verseCount(of: sura), 286)
    }

    /// Un groupe dont **aucun** verset n'est connu reste inconnu, même si le profil porte des
    /// acquis ailleurs.
    func test_coverage_untouchedGroupsStayUnknown() {
        let report = LearningCoverageReport(profile: profile(known: [QuranRange(quran.suras[0])]), program: .empty, quran: quran)

        XCTAssertEqual(report.coverage(of: quran.suras[0]), .complete)
        XCTAssertEqual(report.coverage(of: quran.suras[1]), .inconnue, "Rien d'Al-Baqarah n'est connu")
    }

    // MARK: - CAS A du brief : un juz' se répercute sur les sourates

    /// Le juz' 1 est déclaré connu. Al-Fatiha, qu'il contient entièrement, devient **complète** ;
    /// Al-Baqarah, qu'il **coupe**, reste **partielle** ; Al-Imran, qu'il ne touche pas, reste
    /// inconnue.
    ///
    /// C'est le cas A du brief, et c'est celui qui interdit de cocher une sourate parce qu'un juz'
    /// la traverse.
    func test_coverage_aJuzThatCutsASuraLeavesItPartial() {
        let juz = quran.juzs[0]
        // Les hypothèses du cas, écrites : si le mushaf changeait, l'épreuve le dirait ici plutôt
        // que de passer pour une mauvaise raison.
        XCTAssertEqual(juz.firstVerse.sura.suraNumber, 1)
        XCTAssertEqual(juz.lastVerse.sura.suraNumber, 2)
        XCTAssertLessThan(juz.lastVerse.ayah, quran.suras[1].lastVerse.ayah, "Le juz' 1 coupe Al-Baqarah")

        let report = LearningCoverageReport(profile: profile(known: [QuranRange(juz)]), program: .empty, quran: quran)

        XCTAssertEqual(report.coverage(of: juz), .complete)
        XCTAssertEqual(report.coverage(of: quran.suras[0]), .complete, "Al-Fatiha est entièrement dans le juz'")
        XCTAssertEqual(report.coverage(of: quran.suras[1]), .partielle, "Al-Baqarah est coupée")
        XCTAssertEqual(report.coverage(of: quran.suras[2]), .inconnue, "Al-Imran est hors du juz'")
        XCTAssertEqual(report.coveredVerses(of: quran.suras[1]), juz.lastVerse.ayah)
    }

    // MARK: - CAS B du brief : des sourates se répercutent sur les hizb

    /// Un hizb déclaré connu en entier est complet, et le suivant ne l'est pas.
    func test_coverage_aWholeHizbIsCompleteAndTheNextIsNot() {
        let hizb = quran.hizbs[0]
        let report = LearningCoverageReport(profile: profile(known: [QuranRange(hizb)]), program: .empty, quran: quran)

        XCTAssertEqual(report.coverage(of: hizb), .complete)
        XCTAssertEqual(report.coverage(of: quran.hizbs[1]), .inconnue, "Le hizb suivant n'a rien de connu")
    }

    /// Une moitié de hizb le laisse partiel — la frontière est lue dans le mushaf, pas approchée.
    func test_coverage_halfAHizbIsPartial() {
        let hizb = quran.hizbs[0]
        let verses = hizb.verses
        let middle = verses[verses.count / 2]
        let half = QuranRange(
            firstSura: hizb.firstVerse.sura.suraNumber,
            firstAyah: hizb.firstVerse.ayah,
            lastSura: middle.sura.suraNumber,
            lastAyah: middle.ayah
        )

        let report = LearningCoverageReport(profile: profile(known: [half]), program: .empty, quran: quran)

        XCTAssertEqual(report.coverage(of: hizb), .partielle)
        XCTAssertEqual(report.coveredVerses(of: hizb), verses.count / 2 + 1, "Les bornes sont incluses")
    }

    // MARK: - Ce que le programme apporte

    /// Un passage appris au fil du programme compte, sans que le profil ait rien déclaré.
    func test_coverage_countsAPassageLearnedThroughTheProgram() {
        let sura = quran.suras[113]
        let report = LearningCoverageReport(profile: .empty, program: makeProgram(of: QuranRange(sura), learned: true), quran: quran)

        XCTAssertEqual(report.coverage(of: sura), .complete)
    }

    /// Un passage **jamais appris** ne compte pas : le programme le porte, mais rien n'est su.
    func test_coverage_ignoresAPassageNotYetLearned() {
        let sura = quran.suras[113]
        let report = LearningCoverageReport(profile: .empty, program: makeProgram(of: QuranRange(sura), learned: false), quran: quran)

        XCTAssertEqual(report.coverage(of: sura), .inconnue)
    }

    /// **L'épreuve qui justifie les deux sources.** Un acquis déclaré au profil n'est jamais
    /// programmé — le planificateur le retranche de l'objectif. Lu dans le seul programme, il
    /// passerait donc pour inconnu, et l'utilisateur verrait s'effacer une sourate qu'il a déclarée
    /// connaître.
    func test_coverage_countsWhatTheProfileDeclaresKnownEvenThoughItIsNotProgrammed() {
        let known = QuranRange(quran.suras[113])
        let goal = QuranRange(firstSura: 112, firstAyah: 1, lastSura: 114, lastAyah: 6)
        let profile = LearningProfile(
            knownRanges: [KnownRange(range: known, label: nil, solidity: .solide)],
            goals: [LearningGoal(range: goal, label: nil, targetDate: nil)]
        )
        let program = LearningPlanner(quran: quran, calendar: calendar).makeProgram(for: profile, from: day0)

        XCTAssertFalse(program.items.isEmpty, "L'objectif reste à apprendre")
        XCTAssertFalse(
            program.items.contains { $0.range == known },
            "Un acquis solide n'est pas programmé — c'est tout l'enjeu"
        )

        let report = LearningCoverageReport(profile: profile, program: program, quran: quran)
        XCTAssertEqual(report.coverage(of: quran.suras[113]), .complete, "Déclaré connu, donc connu")
        XCTAssertEqual(report.coverage(of: quran.suras[112]), .inconnue, "Et le reste ne l'est pas pour autant")
    }

    /// Un acquis **fragile** compte aussi : « je l'oublie » reste « je le connais ». La solidité ne
    /// décide que de ce qu'on programme.
    func test_coverage_countsAFragileKnownRangeAsKnown() {
        let sura = quran.suras[113]
        let report = LearningCoverageReport(
            profile: profile(known: [QuranRange(sura)], solidity: .fragile),
            program: .empty,
            quran: quran
        )

        XCTAssertEqual(report.coverage(of: sura), .complete)
    }

    // MARK: - Ce que la couverture ignore, et ce qu'elle n'ignore pas

    /// **Être dû n'est pas être inconnu.** Un passage appris dont la révision est largement due
    /// reste connu : les deux tri-états répondent à des questions différentes, et les confondre
    /// ferait clignoter les pastilles au gré des échéances.
    func test_coverage_countsAVerseWhoseReviewIsDue() {
        let sura = quran.suras[113]
        let program = makeProgram(of: QuranRange(sura), learned: true)
        let later = date(daysAfter: day0, 10)

        XCTAssertEqual(
            program.items[0].status(now: later, calendar: calendar),
            .toReview,
            "Le passage est bien dû — sinon l'épreuve ne prouverait rien"
        )

        let report = LearningCoverageReport(profile: .empty, program: program, quran: quran)
        XCTAssertEqual(report.coverage(of: sura), .complete, "Dû n'est pas inconnu")
    }

    /// Un intervalle qui n'existe pas dans le mushaf est **ignoré**, et non fatal : un profil relu
    /// d'un autre mushaf ne doit pas faire tomber l'écran.
    func test_report_ignoresARangeThatDoesNotExistInTheMushaf() {
        let impossible = QuranRange(firstSura: 200, firstAyah: 1, lastSura: 200, lastAyah: 1)
        let report = LearningCoverageReport(profile: profile(known: [impossible]), program: .empty, quran: quran)

        XCTAssertEqual(report.coverage(of: quran.suras[0]), .inconnue)
    }

    /// Le compte de versets couverts et le verdict ne peuvent pas se contredire : c'est la même
    /// mesure, lue deux fois.
    func test_coverage_verdictAgreesWithTheVerseCount() {
        let sura = quran.suras[113]
        let report = LearningCoverageReport(profile: profile(known: [QuranRange(sura)]), program: .empty, quran: quran)

        let total = report.verseCount(of: sura)
        let covered = report.coveredVerses(of: sura)

        XCTAssertEqual(report.coverage(of: sura), .complete)
        XCTAssertEqual(covered, total)
        XCTAssertGreaterThan(total, 0, "Une sourate sans verset rendrait l'épreuve vide")
    }
}
