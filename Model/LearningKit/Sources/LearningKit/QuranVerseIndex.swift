//
//  QuranVerseIndex.swift
//  LearningKit
//
//  Table de correspondance entre un verset et son rang dans le mushaf.
//

import Foundation
import QuranKit

/// Table de correspondance verset ↔ rang (base 0) dans un mushaf.
///
/// L'arithmétique d'intervalles — retrancher les acquis, découper une séance — a besoin de
/// comparer et de parcourir des versets **par leur position**. `AyahNumber` est bien comparable,
/// mais n'expose aucune distance : compter les versets entre « 2:255 » et « 78:1 » obligerait à
/// suivre la chaîne des `next` un par un. Cette table ramène donc les coordonnées à un entier.
///
/// Elle est construite à partir de `Quran.verses`, que `Quran` met déjà en cache : la construire
/// deux fois ne relit pas le mushaf.
struct QuranVerseIndex {
    // MARK: Lifecycle

    init(quran: Quran) {
        let verses = quran.verses
        var offsets: [AyahNumber: Int] = [:]
        offsets.reserveCapacity(verses.count)
        for (offset, verse) in verses.enumerated() {
            offsets[verse] = offset
        }

        self.quran = quran
        self.verses = verses
        self.offsets = offsets
        // Le rang du dernier verset de chaque page, trié. Sert à arrêter une séance sur une page.
        pageEndOffsets = quran.pages.compactMap { offsets[$0.lastVerse] }.sorted()
    }

    // MARK: Internal

    let quran: Quran

    /// Le rang du dernier verset de chaque page, dans l'ordre croissant des pages.
    let pageEndOffsets: [Int]

    /// Nombre total de versets du mushaf.
    var count: Int { verses.count }

    /// Le rang d'un verset, ou `nil` s'il n'appartient pas à ce mushaf.
    func offset(of verse: AyahNumber) -> Int? {
        offsets[verse]
    }

    /// Le rang du verset désigné par ses coordonnées, ou `nil` s'il n'existe pas.
    func offset(sura: Int, ayah: Int) -> Int? {
        guard let verse = AyahNumber(quran: quran, sura: sura, ayah: ayah) else { return nil }
        return offsets[verse]
    }

    /// Le verset à un rang donné, ou `nil` si le rang sort du mushaf.
    func verse(at offset: Int) -> AyahNumber? {
        verses.indices.contains(offset) ? verses[offset] : nil
    }

    /// Les rangs couverts par un groupe du Coran — page, sourate, juz', hizb, rubu'.
    ///
    /// Rend `nil` pour un groupe dont les bornes n'appartiennent pas à ce mushaf, ou dont la
    /// première borne suit la dernière : dans les deux cas il n'y a rien à désigner.
    func offsets(of group: some QuranGroup) -> ClosedRange<Int>? {
        guard
            let first = offset(of: group.firstVerse),
            let last = offset(of: group.lastVerse),
            first <= last
        else {
            return nil
        }
        return first ... last
    }

    // MARK: Private

    private let verses: [AyahNumber]
    private let offsets: [AyahNumber: Int]
}
