//
//  LearningSetupViewController.swift
//  LearningFeature
//

import LearningPersistence
import Localization
import SwiftUI

/// La configuration guidée d'un programme d'apprentissage.
final class LearningSetupViewController: UIHostingController<LearningSetupView> {
    // MARK: Lifecycle

    init(persistence: LearningPersistence) {
        let viewModel = LearningSetupViewModel(persistence: persistence)
        self.viewModel = viewModel
        super.init(rootView: LearningSetupView(viewModel: viewModel))

        navigationItem.title = l("learning.setup.title", table: .learning)

        rootView.finish = { [weak self] in self?.finish() }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Private

    private let viewModel: LearningSetupViewModel

    /// Enregistre la configuration, puis revient à l'écran qui l'a ouverte.
    ///
    /// L'écran d'accueil relit le magasin à son retour : c'est le magasin qui porte l'état, et non
    /// cet écran, ce qui évite d'avoir à le prévenir du changement.
    private func finish() {
        viewModel.start()
        navigationController?.popViewController(animated: true)
    }
}
