//
//  LearningTab.swift
//  Quran
//
//

import AppDependencies
import LearningFeature
import Localization
import QuranViewFeature
import UIKit

struct LearningTabBuilder: TabBuildable {
    let container: AppDependencies

    func build() -> UIViewController {
        let interactor = LearningTabInteractor(
            quranBuilder: QuranBuilder(container: container),
            learningBuilder: LearningBuilder(container: container)
        )
        let viewController = LearningTabViewController(interactor: interactor)
        viewController.navigationBar.prefersLargeTitles = true
        return viewController
    }
}

/// L'onglet d'apprentissage.
///
/// Il hérite de `TabInteractor` comme les autres onglets : il **est** donc un `QuranNavigator`, et
/// se passe à lui-même comme navigateur de l'écran. C'est ce qui lui permet d'ouvrir le Coran sur
/// la portion du jour sans repasser par l'accueil.
private final class LearningTabInteractor: TabInteractor {
    // MARK: Lifecycle

    init(quranBuilder: QuranBuilder, learningBuilder: LearningBuilder) {
        self.learningBuilder = learningBuilder
        super.init(quranBuilder: quranBuilder)
    }

    // MARK: Internal

    override func start() {
        guard let presenter else {
            return
        }
        presenter.setViewControllers([learningBuilder.build(withListener: self)], animated: false)
    }

    // MARK: Private

    private let learningBuilder: LearningBuilder
}

private class LearningTabViewController: TabViewController {
    override func getTabBarItem() -> UITabBarItem {
        UITabBarItem(
            title: l("learning.title", table: .learning),
            image: .symbol("graduationcap"),
            selectedImage: .symbol("graduationcap.fill")
        )
    }
}
