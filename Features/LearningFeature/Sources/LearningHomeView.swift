//
//  LearningHomeView.swift
//  LearningFeature
//
//  Le récapitulatif du programme d'apprentissage.
//

import LearningKit
import Localization
import NoorUI
import SwiftUI
import UIx

/// Le récapitulatif du programme : où en est l'utilisateur, et ce qu'il lui reste à faire.
///
/// Tant que la configuration n'est pas terminée, l'écran n'a rien à récapituler : il propose de la
/// commencer. C'est le seul état où il n'y a pas de programme à montrer.
///
/// `@MainActor` comme la vue d'accueil : ses sections interrogent le modèle de vue, qui est isolé
/// sur l'acteur principal.
@MainActor
struct LearningHomeView: View {
    @StateObject var viewModel: LearningHomeViewModel

    /// Ouvre la configuration guidée.
    ///
    /// Renseignée par le contrôleur une fois la vue construite : capturer `self` dans
    /// l'initialiseur du contrôleur serait refusé par Swift.
    var editProgram: Action = {}

    var body: some View {
        NoorList {
            if !viewModel.isConfigured {
                NoorBasicSection {
                    editItem
                }
            } else if viewModel.isProgramEmpty {
                NoorBasicSection {
                    NoorListItem(title: .text(l("learning.dashboard.empty", table: .learning)))
                    editItem
                }
            } else {
                programSection
                nextSection
                NoorBasicSection {
                    editItem
                }
            }
        }
    }

    // MARK: Private

    /// Le bouton qui ouvre la configuration guidée.
    private var editItem: some View {
        let title = l("learning.setup.title", table: .learning)
        let detail = l("learning.row.detail", table: .learning)
        return NoorListItem(
            title: .text(title),
            subtitle: .init(text: .text(detail), location: .bottom),
            accessory: .disclosureIndicator,
            action: .sync { editProgram() }
        )
    }

    private var programSection: some View {
        NoorBasicSection(title: l("learning.title", table: .learning), footer: reviewFooter) {
            NoorListItem(
                title: .text(l("learning.dashboard.progress", table: .learning)),
                accessory: .text(progressText)
            )
            NoorListItem(
                title: .text(l("learning.dashboard.streak", table: .learning)),
                accessory: .text("\(viewModel.streak())")
            )
            NoorListItem(
                title: .text(l("learning.dashboard.learned", table: .learning)),
                accessory: .text(lFormat("verses", table: .android, viewModel.learnedVerses))
            )
            NoorListItem(
                title: .text(l("learning.dashboard.reviews", table: .learning)),
                accessory: .text("\(viewModel.dueReviewCount())")
            )
        }
    }

    /// Le prochain passage à apprendre, ou l'annonce d'un programme terminé.
    private var nextSection: some View {
        NoorBasicSection(title: l("learning.dashboard.next", table: .learning)) {
            if let next = viewModel.nextToLearn, let label = viewModel.label(of: next) {
                NoorListItem(title: .text(label))
            } else {
                NoorListItem(title: .text(l("learning.dashboard.finished", table: .learning)))
            }
        }
    }

    /// Le pied de section des révisions : ce qu'il faut lire quand il n'y a rien à réviser.
    private var reviewFooter: String? {
        viewModel.dueReviewCount() == 0 ? l("learning.dashboard.none", table: .learning) : nil
    }

    private var progressText: String {
        let percent = Int((viewModel.progress * 100).rounded())
        return lFormat("learning.dashboard.progress.value", table: .learning, percent)
    }
}
