//
//  LearningGoalPreset.swift
//  LearningKit
//
//  Les objectifs qu'on pose d'un geste.
//

import Foundation
import QuranKit

/// Un objectif proposé d'un geste, parmi les cinq que l'application offre.
///
/// Trois de ces choix **posent une étendue** — tout le Coran, la moitié, jusqu'à Yâsîn —, et deux
/// **laissent désigner le morceau** : un juz' n'est un objectif que lorsqu'on sait lequel. Les deux
/// derniers ne portent donc aucun intervalle, seulement une unité : ils ramènent à la liste, où le
/// morceau se désigne.
///
/// Le choix ne dit pas **quand** l'objectif doit être atteint : l'échéance se pose à part, avec le
/// rythme. Un preset ne désigne donc qu'une étendue du mushaf.
public enum LearningGoalPreset: String, CaseIterable, Sendable {
    /// Les 114 sourates, de la première à la dernière.
    case toutLeCoran
    /// La première moitié du mushaf : ses quinze premiers juz'.
    case laMoitieDuCoran
    /// D'Al-Fâtiha à la fin de Yâsîn, la trente-sixième sourate.
    case jusquAYasin
    /// Un juz', à désigner dans la liste.
    case unJuz
    /// Un hizb, à désigner dans la liste.
    case unHizb
}

// MARK: - Ce que le choix pose

public extension LearningGoalPreset {
    /// L'intervalle que ce choix pose, ou `nil` s'il laisse désigner le morceau.
    ///
    /// Les bornes sont **lues dans le mushaf**, jamais écrites en dur — comme le fait déjà
    /// `QuranRange(_:)` pour le mushaf entier. C'est ce qui garde « la moitié » et « jusqu'à Yâsîn »
    /// justes sur un mushaf où les juz' ne se coupent pas aux mêmes versets.
    ///
    /// - Returns: `nil` pour les deux choix qui désignent un morceau, et pour un mushaf qui ne
    ///   porterait pas Yâsîn. Un intervalle faux vaudrait moins que pas d'intervalle du tout.
    func range(in quran: Quran) -> QuranRange? {
        switch self {
        case .toutLeCoran:
            return QuranRange(quran)
        case .laMoitieDuCoran:
            guard let middle = Self.middleOfTheMushaf(in: quran) else { return nil }
            return Self.span(from: quran.firstVerse, to: middle)
        case .jusquAYasin:
            guard let yasin = Self.yasin(in: quran) else { return nil }
            return Self.span(from: quran.firstVerse, to: yasin.lastVerse)
        case .unJuz, .unHizb:
            return nil
        }
    }

    /// L'unité que ce choix pose au sélecteur, ou `nil` s'il ne touche pas à l'unité.
    ///
    /// C'est ce qui fait d'« un juz' » un **raccourci** et non un objectif : le choix ne désigne pas
    /// le morceau, il amène là où on le désigne.
    var unit: LearningUnit? {
        switch self {
        case .unJuz: return .juz
        case .unHizb: return .hizb
        case .toutLeCoran, .laMoitieDuCoran, .jusquAYasin: return nil
        }
    }
}

// MARK: - Private

private extension LearningGoalPreset {
    /// L'intervalle entre deux versets, bornes incluses.
    ///
    /// `QuranRange` sait construire le mushaf entier et un groupe, mais pas « d'un verset à
    /// l'autre ». Ces quelques lignes le composent, plutôt que d'élargir une API existante pour un
    /// seul usage.
    static func span(from first: AyahNumber, to last: AyahNumber) -> QuranRange {
        QuranRange(
            firstSura: first.sura.suraNumber,
            firstAyah: first.ayah,
            lastSura: last.sura.suraNumber,
            lastAyah: last.ayah
        )
    }

    /// Le dernier verset de la première moitié du mushaf.
    ///
    /// La moitié se compte en **juz'**, et non en versets : un mushaf en compte trente, donc la
    /// moitié est le quinzième. Compter en versets tomberait au milieu d'une sourate, et un objectif
    /// qui s'arrête au milieu d'une sourate ne se dit pas.
    static func middleOfTheMushaf(in quran: Quran) -> AyahNumber? {
        let juzs = quran.juzs
        guard juzs.count >= 2 else { return nil }
        return juzs[juzs.count / 2 - 1].lastVerse
    }

    /// La sourate Yâsîn, ou `nil` si ce mushaf ne la porte pas.
    ///
    /// Cherchée par son **numéro**, et non par son nom : le numéro tient au canon, alors que le nom
    /// est traduit dans seize langues.
    static func yasin(in quran: Quran) -> Sura? {
        quran.suras.first { $0.suraNumber == 36 }
    }
}
