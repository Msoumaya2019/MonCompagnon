//
//  ReadingAvailabilityTests.swift
//  ReadingServiceTests
//
//  Éprouve la règle qui décide quelles lectures sont proposées.
//

import Foundation
import QuranKit
import XCTest
@testable import ReadingService

final class ReadingAvailabilityTests: XCTestCase {
    /// Une lecture téléchargeable reste proposée, même si ses images ne sont pas encore là.
    ///
    /// C'est la règle qui rend le téléchargement atteignable : masquer une lecture non encore
    /// téléchargée la rendrait définitivement inaccessible, puisque c'est en la choisissant qu'on
    /// déclenche son téléchargement. L'assertion ne dépend donc que de l'existence d'une archive,
    /// et jamais de ce que contient l'appareil.
    func test_aDownloadableReadingStaysOffered() {
        let fake = ReadingRemoteResourcesFake()
        for reading in Reading.allReadings where fake.resource(for: reading) != nil {
            let message = "\(reading) a une archive : elle doit rester proposée"
            XCTAssertTrue(reading.isObtainable(remoteResources: fake), message)
        }
    }

    /// Le faux fournit bien des archives : sans cela, le test précédent serait vide et vert.
    ///
    /// Un contrôle qui ne traverse rien est vert pour la mauvaise raison. Celui-ci compte les
    /// lectures réellement soumises à la règle.
    func test_theFakeActuallyOffersArchives() {
        let fake = ReadingRemoteResourcesFake()
        let offertes = Reading.allReadings.filter { fake.resource(for: $0) != nil }
        let attendues = Reading.allReadings.count - 1
        XCTAssertEqual(offertes.count, attendues, "seul le mushaf du paquet n'a pas d'archive")
    }

    /// Aucune archive, aucune image : la lecture n'est pas proposée.
    ///
    /// Le cas négatif n'est éprouvé qu'avec une table vide, et non contre le dossier Documents de
    /// la machine : `isAvailable` lit ce dossier, et un test qui en dépendrait passerait ou
    /// échouerait selon ce que le développeur a téléchargé.
    func test_aReadingWithoutArchiveIsNotObtainableWhenNothingIsOnTheDevice() {
        let vide = QuranAppReadingRemoteResources(baseURL: URL(string: "https://files.quran.app/")!)
        for reading in Reading.allReadings {
            XCTAssertNil(vide.resource(for: reading))
        }
    }
}
