//
//  LearningBuilder.swift
//  LearningFeature
//
//  Ouvre l'espace d'apprentissage.
//

import AppDependencies
import UIKit

/// Ouvre l'espace d'apprentissage.
///
/// Le profil et le programme viennent de `AppDependencies` : c'est le même magasin pour toute
/// l'application, comme il n'y a qu'une préférence de lecture. Le constructeur ne fait que le
/// câblage — ce qui décide vit dans `LearningKit`, éprouvé sans interface.
@MainActor
public struct LearningBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    /// L'écran d'apprentissage : la configuration guidée si rien n'a encore été configuré, le
    /// récapitulatif du programme sinon.
    public func build() -> UIViewController {
        let persistence = container.learningPersistence
        let viewModel = LearningHomeViewModel(persistence: persistence)
        return LearningHomeViewController(viewModel: viewModel, persistence: persistence)
    }

    // MARK: Private

    private let container: AppDependencies
}
