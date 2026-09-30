//
//  AppDelegate.swift
//  QuranEngineApp
//
//  Created by Mohamed Afifi on 2023-06-24.
//

import AppStructureFeature
import Foundation
import Logging
import NoorFont
import NoorUI
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    // MARK: Internal

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Self.startLogging()

        print("Documents directory: ", FileManager.documentsURL)

        FontName.registerFonts()
        LoggingSystem.bootstrap(StreamLogHandler.standardError)

        Task {
            // Eagerly load download manager to handle any background downloads.
            await container.downloadManager.start()

            // Begin fetching resources immediately after download manager is initialized.
            await container.readingResources.startLoadingResources()
        }

        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        let downloadManager = container.downloadManager
        downloadManager.setBackgroundSessionCompletion(completionHandler)
    }

    // MARK: Private

    /// La clé du réglage « Activer la journalisation de débogage » de l'écran de diagnostic.
    ///
    /// Recopiée ici, et c'est le seul endroit où elle l'est : `SettingsFeature`, qui la déclare,
    /// n'est lié à la cible de l'application que par `AppStructureFeature`, et l'importer depuis
    /// ici ne serait pas garanti. La changer d'un côté sans l'autre rendrait de nouveau le
    /// réglage muet — ce qu'il était, justement : rien ne le lisait.
    private static let debugLoggingKey = "enableDebugLogging"

    /// Le plafond du fichier de journal, au-delà duquel il est repris de zéro au lancement.
    private static let logSizeLimit = 4 * 1024 * 1024

    private let container = Container.shared

    /// Redirige la sortie d'erreur vers un fichier du dossier des journaux.
    ///
    /// Tout ce que l'application raconte — chaque `logger`, chaque `print` — part sur la sortie
    /// d'erreur, que personne ne peut lire sur un appareil. L'écran de diagnostic emporte
    /// pourtant le dossier `Documents/logs` : d'où deux archives successives sans un seul fichier
    /// de journal, donc sans rien à lire. On y redirige la sortie, et le réglage prend son sens.
    ///
    /// Un journal ne doit pas remplir l'appareil : au-delà du plafond, le fichier est supprimé au
    /// lancement. Seule la session en cours nous intéresse de toute façon.
    private static func startLogging() {
        guard UserDefaults.standard.bool(forKey: debugLoggingKey) else {
            return
        }

        let directory = Container.shared.logsDirectory
        let fileURL = directory.appendingPathComponent("moncompagnon.log", isDirectory: false)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attributes[.size] as? NSNumber,
           size.intValue > logSizeLimit
        {
            try? FileManager.default.removeItem(at: fileURL)
        }

        _ = freopen(fileURL.path, "a", stderr)
    }
}
