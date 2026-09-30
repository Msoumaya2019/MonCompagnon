//
//  LearningHomeViewController.swift
//  LearningFeature
//

import LearningPersistence
import Localization
import SwiftUI

/// L'écran d'apprentissage : la configuration guidée tant qu'elle n'est pas terminée, le
/// récapitulatif du programme ensuite.
final class LearningHomeViewController: UIHostingController<LearningHomeView> {
    // MARK: Lifecycle

    init(viewModel: LearningHomeViewModel, persistence: LearningPersistence) {
        self.viewModel = viewModel
        self.persistence = persistence
        super.init(rootView: LearningHomeView(viewModel: viewModel))

        navigationItem.title = l("learning.title", table: .learning)

        // `self` n'existe qu'après `super.init`, et la vue est construite avant : on lui donne
        // son action ici. La capturer dans l'initialiseur serait refusé par Swift.
        rootView.editProgram = { [weak self] in self?.openProgramSetup() }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // La configuration a pu être terminée pendant l'absence : on relit le magasin.
        viewModel.reload()
    }

    // MARK: Private

    private let viewModel: LearningHomeViewModel
    private let persistence: LearningPersistence

    private func openProgramSetup() {
        let setup = LearningSetupViewController(persistence: persistence)
        navigationController?.pushViewController(setup, animated: true)
    }
}
