//
//  QuranAmount.swift
//  LearningKit
//
//  Une quantité de Coran exprimée dans l'unité la plus grande qui la divise exactement.
//
//  L'ordre de préférence suit la spécification : Verset → Page → Rubu' → Nisf → Hizb → Juz'.
//  On ne choisit jamais une unité « à peu près » : une unité n'est retenue que si elle
//  divise la quantité SANS reste, sinon l'affichage mentirait sur ce qui est appris.
//

import Foundation
import QuranKit

/// Une quantité de Coran, avec l'unité dans laquelle l'exprimer.
///
/// Les valeurs sont dérivées du `Quran` réel : 1 page = les versets qu'elle contient, et ainsi
/// de suite. Aucune constante n'est codée en dur, donc le type reste correct si l'on change de
/// mushaf (`hafsMadani1405`, `hafsMadani1440`, `hafsIndoPak`).
public struct QuranAmount: Equatable, Sendable {
    // MARK: Lifecycle

    /// Construit une quantité à partir d'un nombre de versets.
    public init(verses: Int, quran: Quran = .hafsMadani1405) {
        verseCountValue = max(0, verses)
        self.quran = quran
    }

    /// Construit une quantité à partir d'un intervalle de versets (bornes incluses).
    public init(from first: AyahNumber, to last: AyahNumber) {
        self.init(verses: Self.verseCount(from: first, to: last), quran: first.quran)
    }

    /// Construit une quantité à partir d'un groupe du Coran (sourate, page, rubu', hizb, juz').
    public init(from group: some QuranGroup) {
        self.init(verses: Self.verseCount(from: group.firstVerse, to: group.lastVerse), quran: group.firstVerse.quran)
    }

    // MARK: Public

    /// Nombre de versets couverts par cette quantité.
    public let verseCountValue: Int

    /// Le mushaf de référence, qui définit la taille des unités.
    public let quran: Quran

    /// L'unité retenue : la plus grande qui divise exactement la quantité, sinon `.verse`.
    ///
    /// - Note: l'ordre d'essai est celui de la spécification, et il est significatif : on préfère
    ///   « 1 rubu' » à « 50 versets », parce que c'est ainsi qu'un lecteur pense sa progression.
    public var unit: QuranUnit {
        for unit in QuranUnit.descendingOrder where unit != .verse {
            let size = unit.verseCount(in: quran)
            if size > 0, verseCountValue >= size, verseCountValue % size == 0 {
                return unit
            }
        }
        return .verse
    }

    /// Le nombre d'unités (par exemple 3 pour « 3 hizb »). Vaut `verseCountValue` si l'unité est
    /// `.verse`.
    public var unitCount: Int {
        let size = unit.verseCount(in: quran)
        guard size > 0 else { return verseCountValue }
        return verseCountValue / size
    }

    /// La quantité est-elle nulle ?
    public var isEmpty: Bool { verseCountValue == 0 }

    /// La quantité, décomposée dans les plus grandes unités possibles.
    ///
    /// Utilisé par l'affichage détaillé (« 1 hizb et 2 rubu' »), là où `unit` seul ne suffit pas.
    /// Le reste en versets est inclus uniquement s'il n'est divisible par aucune unité plus grande.
    public func brokenDown() -> [(unit: QuranUnit, count: Int)] {
        var remaining = verseCountValue
        var result: [(QuranUnit, Int)] = []
        for unit in QuranUnit.descendingOrder where unit != .verse {
            let size = unit.verseCount(in: quran)
            guard size > 0, remaining >= size else { continue }
            let count = remaining / size
            remaining -= count * size
            result.append((unit, count))
        }
        if remaining > 0 {
            result.append((.verse, remaining))
        }
        return result
    }

    // MARK: Private

    /// Nombre de versets entre deux bornes incluses. `0` si l'intervalle est vide.
    private static func verseCount(from first: AyahNumber, to last: AyahNumber) -> Int {
        guard first <= last else { return 0 }
        return first.array(to: last).count
    }
}

/// Les unités de quantité du Coran, de la plus petite à la plus grande.
public enum QuranUnit: String, CaseIterable, Sendable {
    case verse
    case page
    case quarter
    case hizb
    case juz

    // MARK: Public

    /// De la plus grande à la plus petite — l'ordre dans lequel on cherche l'unité d'affichage.
    public static var descendingOrder: [QuranUnit] {
        [.juz, .hizb, .quarter, .page, .verse]
    }

    /// Nombre de versets dans une unité, pour un mushaf donné. `0` si l'unité n'est pas mesurable.
    ///
    /// Mesure sur le **premier** groupe de l'unité. Lorsque les groupes ont des tailles
    /// irrégulières, la valeur reste celle du premier groupe — elle sert à découper une quantité
    /// de référence, pas à prétendre que tous les hizb sont identiques.
    public func verseCount(in quran: Quran) -> Int {
        switch self {
        case .verse:
            return 1
        case .page:
            return Self.count(quran.pages.first)
        case .quarter:
            return Self.count(quran.quarters.first)
        case .hizb:
            return Self.count(quran.hizbs.first)
        case .juz:
            return Self.count(quran.juzs.first)
        }
    }

    // MARK: Private

    /// Nombre de versets d'un groupe. `0` si le groupe est absent.
    private static func count(_ group: (some QuranGroup)?) -> Int {
        guard let group else { return 0 }
        return group.firstVerse.array(to: group.lastVerse).count
    }
}
