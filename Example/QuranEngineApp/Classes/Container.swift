//
//  Container.swift
//  QuranEngineApp
//
//  Created by Mohamed Afifi on 2023-06-24.
//

import Analytics
import AppDependencies
import BatchDownloader
import CoreDataModel
import CoreDataPersistence
import Foundation
import LastPagePersistence
import LearningPersistence
#if QURAN_SYNC
import AuthenticationClient
import LegacyDataMigration
import LegacyDataPersistence
import MobileSync
#endif
import NoorUI
import NotePersistence
import PageBookmarkPersistence
import ReadingService
import UIKit
import VLogging

/// Hosts singleton dependencies
class Container: AppDependencies {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = Container()

    /// Les mushafs que l'application n'embarque pas, servis par l'hôte qu'elle utilise déjà pour
    /// l'audio des récitateurs. La table est vide : les deux mushafs proposés — le Madani 1405 et
    /// le Tajweed — sont dans le paquet. Elle reste le seul endroit où déclarer une lecture
    /// téléchargeable, et c'est elle qui décide de ce que le sélecteur propose.
    let remoteResources: ReadingRemoteResources? = QuranAppReadingRemoteResources(
        baseURL: Constant.filesAppHost
    )

    private(set) lazy var readingResources = ReadingResourcesService(
        downloader: downloadManager,
        remoteResources: remoteResources
    )

    let analytics: AnalyticsLibrary = LoggingAnalyticsLibrary()

    private(set) lazy var lastPagePersistence: LastPagePersistence = CoreDataLastPagePersistence(stack: coreDataStack)
    private(set) lazy var pageBookmarkPersistence: PageBookmarkPersistence = CoreDataPageBookmarkPersistence(stack: coreDataStack)

    private(set) lazy var notePersistence: NotePersistence = CoreDataNotePersistence(stack: coreDataStack)

    /// Le profil et le programme d'apprentissage, rangés dans les préférences de l'appareil.
    ///
    /// Le mushaf de référence est celui par défaut : les passages sont désignés par leurs
    /// coordonnées — sourate et verset — qui ne dépendent pas du mushaf. Seul le découpage des
    /// séances suit les fins de page, et changer de mushaf le recalcule sans perdre la progression.
    let learningPersistence: LearningPersistence = UserDefaultsLearningPersistence()

    let appIconCatalog = AppIconCatalog.example

    #if QURAN_SYNC
    private(set) lazy var quranDataService: QuranDataService = syncAppGraph.quranDataService

    private(set) lazy var authenticationClient: any AuthenticationClient = {
        let authService = syncAppGraph.authService
        return AuthenticationClientMobileSyncImpl(authService: authService)
    }()

    private(set) lazy var legacyDataImportCoordinator = LegacyDataImportCoordinator(
        reader: CoreDataLegacyDataReader(stack: coreDataStack),
        quranDataService: quranDataService
    )
    #endif

    private(set) lazy var downloadManager: DownloadManager = {
        // Le transfert se fait dans l'application, et non dans le démon d'arrière-plan.
        //
        // Le terrain a montré que **tout** téléchargement échoue — les trois hôtes, tous les lots —
        // avec `NSURLErrorCannotCreateFile` (`-3000`), et toujours **à la fin** du transfert : le
        // journal d'une version antérieure montre la progression atteindre 1,0, puis l'échec, sans
        // que `didFinishDownloadingTo` soit jamais appelé. Les octets arrivent donc, et c'est le
        // démon qui n'arrive pas à créer son fichier. Ni le disque — 24,44 Go libres — ni le
        // conteneur — où l'application écrit son archive de diagnostics sans peine — ne sont en
        // cause. La session d'arrière-plan est le seul suspect qui reste.
        //
        // Ce que cela coûte : un téléchargement s'interrompt quand l'application est suspendue. Rien
        // n'est perdu pour autant : le gestionnaire reprend les lots en attente depuis sa base à
        // chaque lancement (`startPendingTasksIfNeeded`). Il faut donc laisser l'application
        // ouverte, ce qui reste préférable à des téléchargements qui n'aboutissent jamais.
        //
        // Pour revenir en arrière : `URLSessionConfiguration.background(withIdentifier:
        // "DownloadsBackgroundIdentifier")`. L'identifiant reste celui qu'attend
        // `AppDelegate.handleEventsForBackgroundURLSession`.
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60 * 5 // 5 minutes
        return DownloadManager(
            // Un récitateur continu demande 115 fichiers, un récitateur verset par verset en
            // demande plus de six mille. La limite était de 600 : tous ces fichiers étaient donc
            // remis au système d'un seul coup, ce qui revient à saturer le démon de
            // téléchargement d'arrière-plan — celui-là même qui doit créer chaque fichier. On
            // revient à la valeur par défaut d'Apple pour un hôte, largement suffisante puisque le
            // débit, et non le nombre de connexions, est le facteur limitant.
            maxSimultaneousDownloads: 6,
            configuration: configuration,
            downloadsURL: Constant.databasesURL.appendingPathComponent("downloads.db", isDirectory: false)
        )
    }()

    var databasesURL: URL { Constant.databasesURL }
    var wordsDatabase: URL { Constant.wordsDatabase }
    var filesAppHost: URL { Constant.filesAppHost }
    var quranProfileURL: URL { Self.quranProfileURL() }
    var appHost: URL { Constant.appHost }
    var databasesDirectory: URL { Constant.databasesURL }
    var logsDirectory: URL { FileManager.documentsURL.appendingPathComponent("logs") }

    var supportsCloudKit: Bool { false }

    // MARK: Private

    #if QURAN_SYNC
    private static let mobileSyncRedirectURI = "com.quran.oauth://callback"
    private static let mobileSyncScopes = [
        "openid",
        "offline_access",
        "content",
        "user",
        "bookmark",
        "sync",
        "collection",
        "reading_session",
        "preference",
        "note",
    ]

    private lazy var syncAppGraph: AppGraph = {
        let authConfig = Self.mobileSyncAuthConfiguration()
        let synchronizationEnvironment = Self.makeSynchronizationEnvironment(usePreProduction: Self.usePreProductionSyncEnvironment())

        AuthFlowFactoryProvider.shared.doInitialize()

        let driverFactory = DriverFactory()
        let storage = AppleMobileSyncStorageFactory.shared.create()
        let graph = SharedDependencyGraph.shared.doInit(
            driverFactory: driverFactory,
            storage: storage,
            environment: synchronizationEnvironment,
            authConfig: authConfig
        )

        return graph
    }()

    private static func mobileSyncAuthConfiguration() -> AuthConfig {
        let clientID = nonEmptyEnvironmentValue("QURAN_OAUTH_CLIENT_ID") ?? "stub-value"
        if clientID == "stub-value" {
            logger.info("Using stubbed client ID for sync")
        }

        let usePreProduction = usePreProductionSyncEnvironment()
        let authEnvironment: AuthEnvironment = usePreProduction ? .prelive : .production

        return AuthConfig(
            environment: authEnvironment,
            clientId: clientID,
            clientSecret: nonEmptyEnvironmentValue("QURAN_OAUTH_CLIENT_SECRET"),
            redirectUri: mobileSyncRedirectURI,
            postLogoutRedirectUri: mobileSyncRedirectURI,
            scopes: mobileSyncScopes
        )
    }

    private static func makeSynchronizationEnvironment(usePreProduction: Bool) -> SynchronizationEnvironment {
        let endpoint = usePreProduction
            ? "https://apis-prelive.quran.foundation/auth"
            : "https://apis.quran.foundation/auth"
        return SynchronizationEnvironment(endPointURL: endpoint)
    }
    #endif

    private lazy var coreDataStack: CoreDataStack = {
        let stack = CoreDataStack(name: "Quran", modelUrl: CoreDataModelResources.quranModel) {
            let lastPage = CoreDataLastPageUniquifier()
            let pageBookmark = CoreDataPageBookmarkUniquifier()
            return [lastPage, pageBookmark]
        }
        return stack
    }()

    private static func nonEmptyEnvironmentValue(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func quranProfileURL() -> URL {
        let url = usePreProductionSyncEnvironment()
            ? "https://prelive.quran.com/profile"
            : "https://quran.com/profile"
        return URL(validURL: url)
    }

    private static func usePreProductionSyncEnvironment() -> Bool {
        guard let environment = nonEmptyEnvironmentValue("QURAN_OAUTH_ENVIRONMENT") else {
            return true
        }
        return environment.lowercased() != "production"
    }
}

private enum Constant {
    static let wordsDatabase = Bundle.main
        .url(forResource: "words", withExtension: "db")!

    static let appHost: URL = .init(validURL: "https://quran.app/")

    static let filesAppHost: URL = .init(validURL: "https://files.quran.app/")

    static let databasesURL = FileManager.documentsURL
        .appendingPathComponent("databases", isDirectory: true)
}
