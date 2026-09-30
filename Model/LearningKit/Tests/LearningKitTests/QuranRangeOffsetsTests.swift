//
//  QuranRangeOffsetsTests.swift
//  LearningKitTests
//
//  Éprouve l'arithmétique d'intervalles et la correspondance verset ↔ rang.
//

import QuranKit
import XCTest
@testable import LearningKit

final class QuranRangeOffsetsTests: XCTestCase {
    // MARK: - Fusion

    func test_merged_fusesOverlappingRanges() {
        XCTAssertEqual(QuranRangeAlgebra.merged([1 ... 5, 3 ... 8]), [1 ... 8])
    }

    func test_merged_fusesAdjacentRanges() {
        // 1...3 et 4...6 couvrent des versets consécutifs : c'est une seule lecture, pas deux.
        XCTAssertEqual(QuranRangeAlgebra.merged([1 ... 3, 4 ... 6]), [1 ... 6])
    }

    func test_merged_keepsSeparatedRangesApart() {
        XCTAssertEqual(QuranRangeAlgebra.merged([1 ... 3, 5 ... 6]), [1 ... 3, 5 ... 6])
    }

    func test_merged_sortsAndSwallowsNestedRanges() {
        XCTAssertEqual(QuranRangeAlgebra.merged([10 ... 20, 12 ... 15, 0 ... 2]), [0 ... 2, 10 ... 20])
    }

    func test_merged_ofNothing_isEmpty() {
        XCTAssertTrue(QuranRangeAlgebra.merged([]).isEmpty)
    }

    // MARK: - Soustraction

    func test_subtracting_removesAHoleInTheMiddle() {
        XCTAssertEqual(QuranRangeAlgebra.subtracting([10 ... 20], from: 0 ... 30), [0 ... 9, 21 ... 30])
    }

    func test_subtracting_removesAtBothEnds() {
        XCTAssertEqual(QuranRangeAlgebra.subtracting([0 ... 5, 26 ... 30], from: 0 ... 30), [6 ... 25])
    }

    func test_subtracting_aHoleCoveringEverything_leavesNothing() {
        XCTAssertTrue(QuranRangeAlgebra.subtracting([0 ... 30], from: 0 ... 30).isEmpty)
    }

    func test_subtracting_ignoresHolesEntirelyOutsideTheRange() {
        // Un trou avant la borne basse et un trou après la borne haute ne retirent rien.
        XCTAssertEqual(QuranRangeAlgebra.subtracting([100 ... 200, 0 ... 2], from: 10 ... 20), [10 ... 20])
    }

    func test_subtracting_clipsHolesThatOverlapAnEdge() {
        // Un trou qui déborde à gauche ne retire que la partie commune.
        XCTAssertEqual(QuranRangeAlgebra.subtracting([0 ... 12], from: 10 ... 20), [13 ... 20])
        // Idem à droite.
        XCTAssertEqual(QuranRangeAlgebra.subtracting([18 ... 30], from: 10 ... 20), [10 ... 17])
    }

    func test_subtracting_withNoHole_returnsTheRangeUnchanged() {
        XCTAssertEqual(QuranRangeAlgebra.subtracting([], from: 4 ... 9), [4 ... 9])
    }

    func test_subtracting_fusesOverlappingHoles() {
        XCTAssertEqual(QuranRangeAlgebra.subtracting([10 ... 15, 13 ... 20], from: 0 ... 30), [0 ... 9, 21 ... 30])
    }

    func test_subtracting_removesASingleVerse() {
        XCTAssertEqual(QuranRangeAlgebra.subtracting([5 ... 5], from: 4 ... 6), [4 ... 4, 6 ... 6])
    }

    func test_subtracting_keepsTheWholeRangeWhenTheHoleTouchesOnlyItsEdge() {
        XCTAssertEqual(QuranRangeAlgebra.subtracting([3 ... 3], from: 4 ... 9), [4 ... 9])
        XCTAssertEqual(QuranRangeAlgebra.subtracting([9 ... 9], from: 4 ... 8), [4 ... 8])
    }

    // MARK: - Correspondance avec le mushaf

    func test_offsets_ofWholeQuran_coversEveryVerse() {
        let quran = Quran.hafsMadani1405
        let index = QuranVerseIndex(quran: quran)
        let whole = QuranRange(firstSura: 1, firstAyah: 1, lastSura: 114, lastAyah: 6)

        XCTAssertEqual(whole.offsets(in: index), 0 ... (quran.verses.count - 1))
    }

    func test_offsets_ofReversedRange_isNil() {
        let index = QuranVerseIndex(quran: Quran.hafsMadani1405)
        let reversed = QuranRange(firstSura: 2, firstAyah: 1, lastSura: 1, lastAyah: 7)

        XCTAssertNil(reversed.offsets(in: index), "Un intervalle à l'envers n'a rien à programmer")
    }

    func test_offsets_ofUnknownCoordinates_isNil() {
        let index = QuranVerseIndex(quran: Quran.hafsMadani1405)
        // La sourate 114 (An-Nas) compte 6 versets : le 7ᵉ n'existe pas.
        let beyond = QuranRange(firstSura: 114, firstAyah: 1, lastSura: 114, lastAyah: 7)

        XCTAssertNil(beyond.offsets(in: index))
    }

    func test_offsets_roundTripsThroughQuranRange() {
        let quran = Quran.hafsMadani1405
        let index = QuranVerseIndex(quran: quran)

        for juz in quran.juzs {
            let range = QuranRange(juz)
            guard let offsets = range.offsets(in: index) else {
                return XCTFail("Le juz' \(juz.juzNumber) doit avoir des bornes dans ce mushaf")
            }
            XCTAssertEqual(QuranRange(offsets: offsets, in: index), range)
        }
    }

    func test_offsets_ofConsecutiveSuras_areContiguous() {
        let quran = Quran.hafsMadani1405
        let index = QuranVerseIndex(quran: quran)

        for (previous, next) in zip(quran.suras, quran.suras.dropFirst()) {
            guard
                let end = QuranRange(previous).offsets(in: index)?.upperBound,
                let start = QuranRange(next).offsets(in: index)?.lowerBound
            else {
                return XCTFail("Chaque sourate doit avoir des bornes dans ce mushaf")
            }
            XCTAssertEqual(start, end + 1, "Le Coran est continu : aucun trou entre deux sourates")
        }
    }

    func test_pageEndOffsets_areSortedAndComplete() {
        let quran = Quran.hafsMadani1405
        let index = QuranVerseIndex(quran: quran)

        XCTAssertEqual(index.pageEndOffsets.count, quran.pages.count, "Une fin de page par page")
        XCTAssertEqual(index.pageEndOffsets, index.pageEndOffsets.sorted())
        XCTAssertEqual(index.pageEndOffsets.last, quran.verses.count - 1, "La dernière page finit le mushaf")
    }
}
