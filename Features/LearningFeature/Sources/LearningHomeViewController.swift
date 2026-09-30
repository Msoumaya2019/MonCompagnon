//
//  LearningHomeViewController.swift
//  LearningFeature
//

import FeaturesSupport
import LearningKit
import LearningPersistence
import Localization
import SwiftUI

/// L'écran d'apprentissage : la configuration guidée tant qu'elle n'est pas terminée, le
/// récapitulatif du programme ensuite.
final class LearningHomeViewController: UIHostingController<LearningHomeView> {
    // MARK: Lifecycle

    /// - Parameter listener: le navigateur du Coran, qui appartient à l'onglet. L'écran ne sait pas
    ///   naviguer : il demande, et l'onglet ouvre.
    init(viewModel: LearningHomeViewModel, persistence: LearningPersistence, listener: QuranNavigator?) {
        self.viewModel = viewModel
        self.persistence = persistence
        self.listener = listener
        super.init(rootView: LearningHomeView(viewModel: viewModel))

        navigationItem.title = l("learning.title", table: .learning)

        // `self` n'existe qu'après `super.init`, et la vue est construite avant : on lui donne ses
        // actions ici. Les capturer dans l'initialiseur serait refusé par Swift.
        rootView.editProgram = { [weak self] in self?.openProgramSetup() }
        rootView.openPlanning = { [weak self] in self?.openPlanning() }
        rootView.open = { [weak self] item in self?.openLearning(item) }
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
    private let listener: QuranNavigator?

    private func openProgramSetup() {
        let setup = LearningSetupViewController(persistence: persistence)
        navigationController?.pushViewController(setup, animated: true)
    }

    /// Ouvre le planning.
    ///
    /// Le modèle de vue du planning est construit ici, et non par le constructeur : il a besoin du
    /// magasin et du navigateur, que le tableau de bord tient déjà. Le faire remonter jusqu'à
    /// `LearningBuilder` obligerait celui-ci à connaître un écran de plus, sans rien apporter.
    private func openPlanning() {
        let planning = LearningPlanningViewController(
            viewModel: LearningPlanningViewModel(persistence: persistence),
            listener: listener
        )
        navigationController?.pushViewController(planning, animated: true)
    }

    /// Ouvre le Coran sur un passage.
    ///
    /// On passe par le **verset** et non par la page : c'est ce que fait déjà l'accueil, et c'est
    /// plus précis — le mushaf se place sur le verset, pas seulement sur la page qui le contient.
    private func openLearning(_ item: LearningItem) {
        guard let verse = viewModel.firstVerse(of: item) else {
            return
        }
        listener?.navigateTo(ayah: verse, lastPage: nil)
    }
}
