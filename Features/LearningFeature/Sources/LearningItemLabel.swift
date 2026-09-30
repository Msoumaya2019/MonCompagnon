//
//  LearningItemLabel.swift
//  LearningFeature
//
//  Le libellé lisible d'un passage.
//

import LearningKit
import QuranKit
import QuranLocalization

/// Le libellé lisible d'un passage : sa sourate, puis la page où il commence.
///
/// Le libellé du modèle — « page 582 », « 78:1-78:40 » — est un repère technique, pas du texte
/// d'interface. Il est composé ici, dans la langue de l'utilisateur, à partir de la sourate et de
/// la page, dont les noms sont déjà traduits.
///
/// Partagé par le tableau de bord et le planning : les deux montrent les mêmes passages, et deux
/// compositions divergentes se verraient immédiatement. `LearningItem.bounds(in:)` est interne à
/// `LearningKit` — c'est `QuranRange` qui porte la conversion, et elle est publique.
func learningItemLabel(_ item: LearningItem, in quran: Quran) -> String? {
    guard let bounds = item.range.bounds(in: quran) else { return nil }
    let sura = bounds.first.sura
    return "\(sura.localizedName()) · \(bounds.first.page.localizedName)"
}
