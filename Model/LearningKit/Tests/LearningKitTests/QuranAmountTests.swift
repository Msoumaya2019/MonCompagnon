//
//  QuranAmountTests.swift
//  LearningKitTests
//

import LearningKit
import QuranKit
import XCTest

final class QuranAmountTests: XCTestCase {
    private let quran = Quran.hafsMadani1405

    // MARK: - Unité retenue

    func test_amount_ofOneJuz_isExpressedInJuz() {
        let juz = quran.juzs[0]
        let amount = QuranAmount(from: juz)
        XCTAssertEqual(amount.unit, .juz, "Un juz' entier doit s'afficher en juz'")
        XCTAssertEqual(amount.unitCount, 1)
    }

    func test_amount_ofOnePage_isExpressedInPage() {
        let page = quran.pages[0]
        let amount = QuranAmount(from: page)
        XCTAssertEqual(amount.unit, .page)
        XCTAssertEqual(amount.unitCount, 1)
    }

    func test_amount_ofOneVerse_isExpressedInVerse() {
        let verse = quran.suras[0].firstVerse
        let amount = QuranAmount(from: verse, to: verse)
        XCTAssertEqual(amount.unit, .verse)
        XCTAssertEqual(amount.unitCount, 1)
        XCTAssertEqual(amount.verseCountValue, 1)
    }

    func test_amount_ofEmptyRange_isEmpty() {
        let verse = quran.suras[0].firstVerse
        let amount = QuranAmount(verses: 0, quran: quran)
        XCTAssertTrue(amount.isEmpty)
        XCTAssertEqual(amount.unit, .verse)
        XCTAssertEqual(amount.unitCount, 0)
        // Une quantité négative est ramenée à zéro plutôt que de produire un compte négatif.
        XCTAssertEqual(QuranAmount(verses: -5, quran: quran).verseCountValue, 0)
        _ = verse
    }

    // MARK: - Divisibilité

    func test_amount_prefersLargestExactUnit() {
        let oneJuz = QuranUnit.juz.verseCount(in: quran)
        // Deux juz' doivent s'afficher « 2 juz' » et non « 120 versets ».
        let amount = QuranAmount(verses: oneJuz * 2, quran: quran)
        XCTAssertEqual(amount.unit, .juz)
        XCTAssertEqual(amount.unitCount, 2)
    }

    func test_amount_fallsBackToVerseWhenNoUnitDivides() {
        // Un juz' + 1 verset n'est divisible par aucune unité supérieure.
        let oneJuz = QuranUnit.juz.verseCount(in: quran)
        let amount = QuranAmount(verses: oneJuz + 1, quran: quran)
        XCTAssertEqual(amount.unit, .verse)
        XCTAssertEqual(amount.unitCount, oneJuz + 1)
    }

    // MARK: - Décomposition

    func test_brokenDown_decomposesIntoSeveralUnits() {
        let oneHizb = QuranUnit.hizb.verseCount(in: quran)
        let oneQuarter = QuranUnit.quarter.verseCount(in: quran)
        let amount = QuranAmount(verses: oneHizb + oneQuarter, quran: quran)

        let parts = amount.brokenDown()
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].unit, .hizb)
        XCTAssertEqual(parts[0].count, 1)
        XCTAssertEqual(parts[1].unit, .quarter)
        XCTAssertEqual(parts[1].count, 1)
    }

    func test_brokenDown_reportsRemainingVerses() {
        let oneJuz = QuranUnit.juz.verseCount(in: quran)
        let parts = QuranAmount(verses: oneJuz + 2, quran: quran).brokenDown()

        let total = parts.reduce(0) { partial, part in
            partial + part.count * part.unit.verseCount(in: quran)
        }
        XCTAssertEqual(total, oneJuz + 2, "La décomposition doit rendre exactement la quantité d'origine")
        XCTAssertEqual(parts.last?.unit, .verse)
        XCTAssertEqual(parts.last?.count, 2)
    }

    // MARK: - Cohérence avec le mushaf

    func test_verseCount_ofAllJuz_sumsToWholeQuran() {
        let total = quran.juzs.reduce(0) { $0 + QuranAmount(from: $1).verseCountValue }
        XCTAssertEqual(total, quran.verses.count, "La somme des juz' doit couvrir tout le Coran")
    }

    func test_verseCount_ofAllPages_sumsToWholeQuran() {
        let total = quran.pages.reduce(0) { $0 + QuranAmount(from: $1).verseCountValue }
        XCTAssertEqual(total, quran.verses.count, "La somme des pages doit couvrir tout le Coran")
    }
}
