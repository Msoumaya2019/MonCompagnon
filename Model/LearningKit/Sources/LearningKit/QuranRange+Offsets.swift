//
//  QuranRange+Offsets.swift
//  LearningKit
//
//  Arithmétique d'intervalles sur le Coran : convertir, fusionner, retrancher.
//

import Foundation
import QuranKit

extension QuranRange {
    // MARK: Internal

    /// Le rang des bornes, ou `nil` si l'intervalle n'existe pas dans ce mushaf.
    ///
    /// Un intervalle dont la première borne suit la dernière est traité comme **vide**, au même
    /// titre qu'un intervalle aux coordonnées inexistantes : dans les deux cas il n'y a rien à
    /// programmer, et distinguer les deux cas n'apporterait rien à l'appelant.
    func offsets(in index: QuranVerseIndex) -> ClosedRange<Int>? {
        guard
            let first = index.offset(sura: firstSura, ayah: firstAyah),
            let last = index.offset(sura: lastSura, ayah: lastAyah),
            first <= last
        else {
            return nil
        }
        return first ... last
    }

    /// Construit un intervalle à partir de rangs, ou `nil` si un rang sort du mushaf.
    init?(offsets: ClosedRange<Int>, in index: QuranVerseIndex) {
        guard
            let first = index.verse(at: offsets.lowerBound),
            let last = index.verse(at: offsets.upperBound)
        else {
            return nil
        }
        self.init(
            firstSura: first.sura.suraNumber,
            firstAyah: first.ayah,
            lastSura: last.sura.suraNumber,
            lastAyah: last.ayah
        )
    }
}

/// Opérations ensemblistes sur des intervalles de rangs.
///
/// Séparées de `QuranRange` parce qu'elles ne manipulent que des entiers : on peut les éprouver
/// sur des cas tordus — intervalles vides, adjacents, imbriqués, trous hors bornes — sans
/// construire de mushaf ni de profil.
enum QuranRangeAlgebra {
    // MARK: Internal

    /// Fusionne les intervalles qui se chevauchent ou se touchent, dans l'ordre croissant.
    ///
    /// Deux intervalles **adjacents** (`1...3` et `4...6`) sont fusionnés, et non laissés côte à
    /// côte : ils couvrent des versets consécutifs, donc une seule lecture. Les séparer
    /// produirait deux séances pour un passage continu.
    static func merged(_ ranges: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var result: [ClosedRange<Int>] = []
        for range in sorted {
            guard let last = result.last else {
                result.append(range)
                continue
            }
            if range.lowerBound <= last.upperBound + 1 {
                result[result.count - 1] = last.lowerBound ... max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// Retranche `holes` de `range` et rend les morceaux restants, dans l'ordre croissant.
    ///
    /// C'est l'opération qui exclut les acquis : on retire du programme ce que l'utilisateur
    /// connaît déjà, et ce qui reste est exactement ce qu'il lui reste à apprendre.
    static func subtracting(_ holes: [ClosedRange<Int>], from range: ClosedRange<Int>) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        var cursor = range.lowerBound

        for hole in merged(holes) {
            // Trou entièrement avant le curseur : déjà dépassé.
            guard hole.upperBound >= cursor else { continue }
            // Trou entièrement après l'intervalle : plus rien à retrancher.
            guard hole.lowerBound <= range.upperBound else { break }

            if hole.lowerBound > cursor {
                result.append(cursor ... (hole.lowerBound - 1))
            }
            // `upperBound + 1` peut dépasser la borne haute : le `guard` suivant arrête la boucle.
            cursor = hole.upperBound + 1
            guard cursor <= range.upperBound else { break }
        }

        if cursor <= range.upperBound {
            result.append(cursor ... range.upperBound)
        }
        return result
    }
}
