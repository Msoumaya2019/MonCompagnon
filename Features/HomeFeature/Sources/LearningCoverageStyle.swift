//
//  LearningCoverageStyle.swift
//  HomeFeature
//
//  Ce qu'une ligne de liste dit de l'avancement sur son groupe.
//

import LearningKit
import Localization
import QuranKit
import SwiftUI

/// Ce qu'une ligne de liste dit de l'avancement sur son groupe.
///
/// Deux choses, et une seule décision : la couleur du trait, et le texte de l'état. Les tenir
/// ensemble, dans une fonction unique, évite qu'ils divergent — un trait vert sur une ligne qui
/// annonce « rien d'appris » serait un mensonge visible.
///
/// Le trait réemploie `NoorListItem.leadingEdgeLineColor` : quatre points sur le bord gauche, que
/// le composant porte déjà et que l'application n'employait **nulle part**. Un trait ne parle pas à
/// VoiceOver : c'est le texte qui porte l'information, et le trait qui la donne d'un coup d'œil.
struct LearningCoverageStyle {
    /// La couleur du trait de bord, ou `nil` quand il n'y a rien à signaler.
    let edgeColor: Color?

    /// Le texte de l'état. C'est lui que VoiceOver annonce.
    let label: String

    /// Le style d'un groupe, ou `nil` si l'avancement n'est pas connu.
    ///
    /// `nil` n'est pas la même chose que « rien d'appris » : tant que le relevé n'a pas été fait,
    /// la ligne ne doit rien affirmer. Un groupe vide, lui aussi, ne dit rien — il n'existe pas
    /// dans ce mushaf.
    init?(report: LearningCoverageReport?, group: some QuranGroup) {
        guard let report else {
            return nil
        }
        let total = report.verseCount(of: group)
        guard total > 0 else {
            return nil
        }

        switch report.coverage(of: group) {
        case .inconnue:
            edgeColor = nil
            label = l("learning.coverage.none", table: .learning)
        case .partielle:
            edgeColor = Color(uiColor: .systemOrange)
            label = lFormat("learning.coverage.partial", table: .learning, report.coveredVerses(of: group), total)
        case .complete:
            edgeColor = Color(uiColor: .systemGreen)
            label = lFormat("learning.coverage.complete", table: .learning, total)
        }
    }
}
