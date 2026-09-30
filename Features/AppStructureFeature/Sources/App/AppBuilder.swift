//
//  AppBuilder.swift
//  Quran
//
//  Created by Afifi, Mohamed on 3/24/19.
//  Copyright © 2019 Quran.com. All rights reserved.
//

import AppDependencies
import AppMigrator
import UIKit
import WhatsNewFeature

@MainActor
struct AppBuilder {
    let container: AppDependencies

    /// - Parameter launchVersion: How this launch relates to the previous one,
    ///   captured before the launch commits the current app version.
    func build(launchVersion: LaunchVersionUpdate) -> AppViewController {
        let interactor = AppInteractor(
            supportsCloudKit: container.supportsCloudKit,
            analytics: container.analytics,
            lastPagePersistence: container.lastPagePersistence,
            // La recherche a quitté la barre : elle reste accessible par la loupe de l'écran
            // « Sourate / Juz' », qui l'ouvre dans sa propre pile. L'apprentissage prend sa place,
            // en seconde position — c'est devenu le geste principal de l'application.
            tabs: [
                HomeTabBuilder(container: container),
                LearningTabBuilder(container: container),
                NotesTabBuilder(container: container),
                BookmarksTabBuilder(container: container),
                SettingsTabBuilder(container: container),
            ]
        )
        return AppViewController(
            interactor: interactor,
            whatsNewController: AppWhatsNewController(
                analytics: container.analytics,
                launchVersion: launchVersion,
                appIconCatalog: container.appIconCatalog
            ),
            isAppIconAvailable: container.appIconService().isAvailable
        )
    }
}
