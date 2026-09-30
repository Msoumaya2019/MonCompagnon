//
//  LearningPlanningViewController.swift
//  LearningFeature
//
//  L'écran du planning.
//

import FeaturesSupport
import LearningKit
import Localization
import SwiftUI

/// Le planning de l'apprentissage.
///
/// Le contrôleur ne fait que trois choses : poser le titre, donner ses gestes à la vue une fois
/// qu'elle existe, et ouvrir le Coran. Ce qui décide vit dans `LearningKit`, éprouvé sans interface.
final class LearningPlanningViewController: UIHostingController<LearningPlanningView> {
    // MARK: Lifecycle

    /// - Parameter listener: le navigateur du Coran, qui appartient à l'onglet. L'écran ne sait pas
    ///   naviguer : il demande, et l'onglet ouvre.
    init(viewModel: LearningPlanningViewModel, listener: QuranNavigator?) {
        self.viewModel = viewModel
        self.listener = listener
        super.init(rootView: LearningPlanningView(viewModel: viewModel))

        navigationItem.title = l("learning.planning.title", table: .learning)

        // `self` n'existe qu'après `super.init`, et la vue est construite avant : on lui donne son
        // geste ici. Le capturer dans l'initialiseur serait refusé par Swift.
        rootView.open = { [weak self] item in self?.openLearning(item) }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Le programme a pu changer pendant l'absence, et le jour a pu tourner : les deux sont
        // repris ensemble, sans quoi la grille et les listes ne parleraient plus du même instant.
        viewModel.reload()
    }

    // MARK: Private

    private let viewModel: LearningPlanningViewModel
    private let listener: QuranNavigator?

    /// Ouvre le Coran sur un passage.
    ///
    /// On passe par le **verset** et non par la page : c'est ce que fait déjà le tableau de bord, et
    /// c'est plus précis — le mushaf se place sur le verset, pas seulement sur la page qui le
    /// contient.
    private func openLearning(_ item: LearningItem) {
        guard let verse = viewModel.firstVerse(of: item) else {
            return
        }
        listener?.navigateTo(ayah: verse, lastPage: nil)
    }
}
