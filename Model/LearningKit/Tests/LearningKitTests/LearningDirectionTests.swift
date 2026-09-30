//
//  LearningDirectionTests.swift
//  LearningKitTests
//
//  Le sens d'apprentissage, et la relecture des profils enregistrés avant lui.
//

import XCTest
@testable import LearningKit

final class LearningDirectionTests: XCTestCase {
    // MARK: Internal

    func test_theReverseSense_isTheOnlyDescendingOne() {
        XCTAssertFalse(LearningDirection.depuisLeDebut.isDescending)
        XCTAssertTrue(LearningDirection.depuisLaFin.isDescending)
    }

    func test_aFreshProfile_readsTheMushafOrder() {
        XCTAssertEqual(LearningProfile.empty.direction, .depuisLeDebut)
    }

    /// Le test qui protège les profils **déjà sur les appareils**.
    ///
    /// Le magasin range le profil entier dans une seule clé JSON, dont le contenu illisible rend la
    /// valeur par défaut au lieu de lever. Un décodage qui échouerait ne dirait donc rien : il
    /// rendrait un profil vierge, et l'utilisateur découvrirait que son programme a disparu.
    ///
    /// Le JSON relu ici est celui qu'écrivait la version d'avant le sens : toutes les clés du
    /// profil, **sans** `direction`.
    func test_aProfileSavedBeforeTheDirection_isReadBackIntact() throws {
        let profile = try decode(Self.profileSavedBeforeTheDirection)

        XCTAssertEqual(profile.direction, .depuisLeDebut, "Le repli décrit le seul comportement d'alors")
        XCTAssertEqual(profile.pace, .doux)
        XCTAssertEqual(profile.days, [.lundi, .mercredi])
        XCTAssertEqual(profile.sessionMinutes, 20)
        XCTAssertTrue(profile.isConfigured)
        XCTAssertEqual(profile.createdAt, Date(timeIntervalSinceReferenceDate: 0))
    }

    /// Et la clé, quand elle est là, est bien **lue**.
    ///
    /// Ce test est le seul qui épingle le **nom** de la clé sur le disque. Un aller-retour ne le
    /// ferait pas : si `CodingKeys` orthographiait `direction` autrement, l'écriture et la relecture
    /// s'accorderaient sur le mauvais nom, et le test passerait. Ici le JSON est écrit à la main.
    func test_aStoredDirection_isHonoured() throws {
        XCTAssertEqual(try decode(Self.profileWithTheReverseDirection).direction, .depuisLaFin)
    }

    /// Le sens survit à un aller-retour.
    ///
    /// C'est ce test qui rattrape un `CodingKeys` **amputé** du cas `direction` : un profil au sens
    /// par défaut se relirait correctement même si la clé n'était jamais écrite, puisque le repli
    /// rendrait la même valeur.
    func test_theDirectionSurvivesEncodingRoundTrip() throws {
        let profile = LearningProfile(
            pace: .doux,
            direction: .depuisLaFin,
            createdAt: Date(timeIntervalSince1970: 0),
            isConfigured: true
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(LearningProfile.self, from: data)

        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.direction, .depuisLaFin)
    }

    // MARK: Private

    /// Un profil tel qu'il était écrit **avant** que le sens existe.
    private static let profileSavedBeforeTheDirection = """
    {
      "knownRanges": [],
      "goals": [],
      "pace": "doux",
      "days": ["lundi", "mercredi"],
      "sessionMinutes": 20,
      "createdAt": 0,
      "isConfigured": true
    }
    """

    /// Le même, avec la clé du sens — pour que les deux ne diffèrent que par elle.
    private static let profileWithTheReverseDirection = """
    {
      "knownRanges": [],
      "goals": [],
      "pace": "doux",
      "days": ["lundi", "mercredi"],
      "sessionMinutes": 20,
      "direction": "depuisLaFin",
      "createdAt": 0,
      "isConfigured": true
    }
    """

    private func decode(_ json: String) throws -> LearningProfile {
        try JSONDecoder().decode(LearningProfile.self, from: Data(json.utf8))
    }
}
