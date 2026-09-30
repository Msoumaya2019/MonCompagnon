//
//  QuranAppReadingRemoteResourcesTests.swift
//  ReadingServiceTests
//
//  Éprouve la table des mushafs téléchargeables.
//

import Foundation
import QuranKit
import XCTest
@testable import ReadingService

final class QuranAppReadingRemoteResourcesTests: XCTestCase {
    private let baseURL = URL(string: "https://files.quran.app/")!

    private var resources: QuranAppReadingRemoteResources {
        QuranAppReadingRemoteResources(baseURL: baseURL)
    }

    /// Aucune lecture n'est téléchargeable : les deux mushafs proposés sont dans le paquet.
    ///
    /// Le test porte sur les **sept** lectures, et non sur les cinq écartées : rétablir une ligne
    /// dans la table sans embarquer les images correspondantes le fera échouer, ce qui est
    /// exactement ce qu'on veut savoir — une lecture téléchargeable qui n'est pas embarquée doit
    /// être un choix conscient, pas un oubli.
    func test_noReadingIsDownloadable() {
        for reading in Reading.allReadings {
            let message = "\(reading) ne doit pas être téléchargeable : son mushaf est embarqué"
            XCTAssertNil(resources.resource(for: reading), message)
        }
    }

    /// L'adresse de base ne fait naître aucune ressource tant que la table est vide.
    ///
    /// Vérifie au passage que la construction d'une ressource dépend bien de l'hôte reçu : le jour
    /// où la table sera rétablie, l'adresse ne devra pas être figée sur `files.quran.app`.
    func test_theBaseURLIsTheOnlySourceOfAnAddress() {
        let racine = URL(string: "https://exemple.test/racine/")!
        let autre = QuranAppReadingRemoteResources(baseURL: racine)
        for reading in Reading.allReadings {
            XCTAssertNil(autre.resource(for: reading))
        }
    }
}
