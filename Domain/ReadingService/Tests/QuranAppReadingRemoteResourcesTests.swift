import Foundation
import QuranKit
import XCTest
@testable import ReadingService

/// L'adresse et la version sont celles qui ont été mesurées sur le serveur : l'archive du
/// Tajweed répond, pèse 143 688 256 octets, contient les 604 pages en largeur 1280 et la base
/// `ayahinfo_1280.db`, et porte les marqueurs `.v2` à `.v7`. Ces tests figent ce qui a été
/// vérifié, pour qu'une faute de frappe ne puisse pas passer inaperçue.
final class QuranAppReadingRemoteResourcesTests: XCTestCase {
    private let baseURL = URL(string: "https://files.quran.app/")!

    private var resources: QuranAppReadingRemoteResources {
        QuranAppReadingRemoteResources(baseURL: baseURL)
    }

    func test_tajweedIsDownloadableFromTheAddressVerifiedAgainstTheServer() throws {
        let resource = try XCTUnwrap(resources.resource(for: .tajweed))

        XCTAssertEqual(
            resource.url.absoluteString,
            "https://files.quran.app/hafs/tajweed/zips/images_1280.zip"
        )
        XCTAssertEqual(resource.url.scheme, "https")
        XCTAssertEqual(resource.url.host, "files.quran.app")
        XCTAssertEqual(resource.version, 7)
    }

    func test_theBundledMushafHasNothingToDownload() {
        XCTAssertNil(resources.resource(for: .hafs_1405))
    }

    func test_theOtherMushafsAreNotOffered() {
        let others: [Reading] = [.hafs_1421, .hafs_1439, .hafs_1440, .hafs_1441, .indoPak]
        for reading in others {
            let message = "\(reading) ne doit pas être téléchargeable"
            XCTAssertNil(resources.resource(for: reading), message)
        }
    }

    /// Le dossier de destination doit être celui que l'application ira lire : c'est `localPath`
    /// qui décide, et le décompresser ailleurs rendrait le mushaf introuvable.
    func test_theArchiveIsDownloadedUnderTheReadingFolder() throws {
        let resource = try XCTUnwrap(resources.resource(for: .tajweed))

        XCTAssertEqual(resource.downloadDestination.path, "readings/tajweed")
        XCTAssertEqual(resource.zipFile.path, "readings/tajweed/images_1280.zip")
        XCTAssertEqual(resource.reading, .tajweed)
    }

    /// L'hôte appartient à l'application : il ne doit pas être figé ici.
    func test_theAddressFollowsTheBaseURLItIsGiven() throws {
        let racine = URL(string: "https://exemple.test/racine/")!
        let other = QuranAppReadingRemoteResources(baseURL: racine)
        let resource = try XCTUnwrap(other.resource(for: .tajweed))

        XCTAssertEqual(
            resource.url.absoluteString,
            "https://exemple.test/racine/hafs/tajweed/zips/images_1280.zip"
        )
    }
}
