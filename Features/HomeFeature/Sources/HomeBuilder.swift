//
//  HomeBuilder.swift
//  Quran
//
//  Created by Afifi, Mohamed on 11/14/20.
//  Copyright © 2020 Quran.com. All rights reserved.
//

import AnnotationsService
import AppDependencies
import FeaturesSupport
import QuranTextKit
import ReadingSelectorFeature
import SearchFeature
import UIKit

@MainActor
public struct HomeBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    public func build(withListener listener: QuranNavigator) -> UIViewController {
        let textRetriever = QuranTextDataService(
            databasesURL: container.databasesURL,
            quranFileURL: container.quranUthmaniV2Database
        )
        #if QURAN_SYNC
        let viewModel = HomeViewModel(
            lastPageService: container.lastPageService(),
            textRetriever: textRetriever,
            readingBookmarkService: container.readingBookmarkService(),
            learningPersistence: container.learningPersistence,
            navigateToPage: { [weak listener] page, lastPage in
                listener?.navigateTo(page: page, lastPage: lastPage)
            },
            navigateToAyah: { [weak listener] ayah in
                listener?.navigateTo(ayah: ayah, lastPage: nil)
            }
        )
        #else
        let viewModel = HomeViewModel(
            lastPageService: container.lastPageService(),
            textRetriever: textRetriever,
            learningPersistence: container.learningPersistence,
            navigateToPage: { [weak listener] page, lastPage in
                listener?.navigateTo(page: page, lastPage: lastPage)
            },
            navigateToAyah: { [weak listener] ayah in
                listener?.navigateTo(ayah: ayah, lastPage: nil)
            }
        )
        #endif
        let viewController = HomeViewController(
            viewModel: viewModel,
            readingSelectorBuilder: ReadingSelectorBuilder(container: container),
            // La recherche n'a plus d'onglet : c'est l'accueil qui l'ouvre. La fabrique est
            // construite ici parce que le navigateur du Coran ne vit que dans l'onglet, et la
            // recherche en a besoin pour ouvrir le verset qu'on choisit.
            makeSearch: { [weak listener] in
                guard let listener else {
                    return nil
                }
                return SearchBuilder(container: container).build(withListener: listener)
            }
        )
        return viewController
    }

    // MARK: Internal

    let container: AppDependencies
}
