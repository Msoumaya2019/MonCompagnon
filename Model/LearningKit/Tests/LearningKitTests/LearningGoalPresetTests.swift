//
//  LearningGoalPresetTests.swift
//  LearningKitTests
//
//  Éprouve les cinq objectifs qu'on pose d'un geste.
//
//  Les bornes attendues sont **mesurées**, jamais déduites du mushaf : elles viennent de
//  `ayahinfo_1920.db`, la base que l'application embarque pour `hafs_1405`, croisée avec les débuts
//  de quartier de `Madani1405QuranReadingInfoRawData.swift`. Les lire sur `quran` ne prouverait
//  rien, puisque l'implémentation lit les mêmes tableaux.
//

import Foundation
import QuranKit
import XCTest
@testable import LearningKit

final class LearningGoalPresetTests: XCTestCase {
    private let quran = Quran.hafsMadani1405

    // MARK: - Les trois étendues

    /// « Tout le Coran » couvre le mushaf, de son premier verset à son dernier.
    ///
    /// 6236 versets : le compte du mushaf `hafs_1405`, mesuré dans `ayahinfo_1920.db`.
    func test_toutLeCoran_coversTheWholeMushaf() throws {
        let range = try XCTUnwrap(LearningGoalPreset.toutLeCoran.range(in: quran))

        XCTAssertEqual(range.firstSura, 1)
        XCTAssertEqual(range.firstAyah, 1)
        XCTAssertEqual(range.lastSura, 114)
        XCTAssertEqual(range.lastAyah, 6)
        XCTAssertEqual(range.verseCount(in: quran), 6236)
    }

    /// « Jusqu'à Yâsîn » part d'Al-Fâtiha et s'arrête au dernier verset de la sourate 36 — 36:83.
    func test_jusquAYasin_stopsAtTheLastVerseOfYasin() throws {
        let range = try XCTUnwrap(LearningGoalPreset.jusquAYasin.range(in: quran))

        XCTAssertEqual(range.firstSura, 1)
        XCTAssertEqual(range.firstAyah, 1)
        XCTAssertEqual(range.lastSura, 36)
        XCTAssertEqual(range.lastAyah, 83)
        XCTAssertEqual(range.verseCount(in: quran), 3788)
    }

    /// « La moitié du Coran » s'arrête à la fin du quinzième juz' — 18:74.
    ///
    /// Le seizième juz' commence à 18:75, mesuré dans les débuts de quartier de la source.
    ///
    /// - Important: la moitié se compte en **juz'**, et non en versets. Le mushaf en compte trente,
    ///   donc quinze en sont la moitié — mais ces quinze juz' ne couvrent que **2214** des 6236
    ///   versets, soit 35,5 % : les premières sourates sont longues en texte et courtes en versets.
    ///   Compter la moitié en versets tomberait à 26:186, au milieu d'une sourate, et un objectif qui
    ///   s'arrête au milieu d'une sourate ne se dit pas.
    func test_laMoitieDuCoran_stopsAtTheEndOfTheFifteenthJuz() throws {
        let range = try XCTUnwrap(LearningGoalPreset.laMoitieDuCoran.range(in: quran))

        XCTAssertEqual(range.firstSura, 1)
        XCTAssertEqual(range.firstAyah, 1)
        XCTAssertEqual(range.lastSura, 18)
        XCTAssertEqual(range.lastAyah, 74)
        XCTAssertEqual(range.verseCount(in: quran), 2214)
    }

    /// Les trois étendues sont **emboîtées**, et l'ordre surprend : Yâsîn va plus loin que la moitié.
    ///
    /// Toutes partent de 1:1, donc celle qui s'arrête le plus tard contient les autres. Que Yâsîn
    /// (3788 versets) dépasse la moitié (2214) n'est pas une anomalie : les quinze premiers juz'
    /// couvrent les longues sourates, qui pèsent peu en versets.
    func test_theThreeExtents_areNested() throws {
        let moitie = try XCTUnwrap(LearningGoalPreset.laMoitieDuCoran.range(in: quran)).verseCount(in: quran)
        let yasin = try XCTUnwrap(LearningGoalPreset.jusquAYasin.range(in: quran)).verseCount(in: quran)
        let tout = try XCTUnwrap(LearningGoalPreset.toutLeCoran.range(in: quran)).verseCount(in: quran)

        XCTAssertEqual(moitie, 2214)
        XCTAssertEqual(yasin, 3788)
        XCTAssertEqual(tout, 6236)
        XCTAssertLessThan(moitie, yasin, "« la moitié » s'arrête avant Yâsîn — contre l'intuition")
        XCTAssertLessThan(yasin, tout, "Yâsîn s'arrête avant la fin du mushaf")
    }

    // MARK: - Les deux désignations

    /// Un juz' et un hizb ne portent **aucun** intervalle : ils amènent à la liste.
    func test_theTwoDesignations_carryNoRange() {
        XCTAssertNil(LearningGoalPreset.unJuz.range(in: quran))
        XCTAssertNil(LearningGoalPreset.unHizb.range(in: quran))
    }

    /// Et ils portent l'unité qui répond à leur nom.
    func test_theTwoDesignations_carryTheirUnit() {
        XCTAssertEqual(LearningGoalPreset.unJuz.unit, .juz)
        XCTAssertEqual(LearningGoalPreset.unHizb.unit, .hizb)
    }

    /// Les trois étendues, elles, ne touchent pas au sélecteur d'unité : elles posent un objectif,
    /// pas une façon de le désigner.
    func test_theThreeExtents_doNotTouchTheUnit() {
        let etendues: [LearningGoalPreset] = [.toutLeCoran, .laMoitieDuCoran, .jusquAYasin]
        for preset in etendues {
            XCTAssertNil(preset.unit, "« \(preset.rawValue) » ne devait pas poser d'unité")
        }
    }

    /// Chaque choix est **soit** une étendue, **soit** une désignation — jamais les deux, jamais ni
    /// l'une ni l'autre.
    ///
    /// C'est ce qui garantit qu'aucun preset ne se perd en route : un choix sans intervalle et sans
    /// unité ne ferait rien du tout quand on le touche, et l'utilisateur croirait l'avoir choisi.
    func test_everyPreset_carriesEitherARangeOrAUnit() {
        for preset in LearningGoalPreset.allCases {
            let aUnIntervalle = preset.range(in: quran) != nil
            let aUneUnite = preset.unit != nil
            XCTAssertTrue(aUnIntervalle || aUneUnite, "« \(preset.rawValue) » ne pose rien")
            XCTAssertFalse(aUnIntervalle && aUneUnite, "« \(preset.rawValue) » pose deux choses à la fois")
        }
    }

    // MARK: - Ce que le geste pose

    /// Toucher une étendue pose un objectif, et **remplace** ceux qui étaient là.
    ///
    /// Une étendue qui part de 1:1 contient tout ce qui la précède : garder les anciens objectifs à
    /// côté ferait compter deux fois les mêmes versets. C'est la raison déjà écrite pour
    /// `continueThroughTheQuran()`.
    func test_applyingAnExtent_replacesTheGoals() throws {
        var draft = LearningSetupDraft(quran: quran)
        draft.toggleGoal(QuranRange(firstSura: 78, firstAyah: 1, lastSura: 114, lastAyah: 6))

        draft.apply(.jusquAYasin)

        XCTAssertEqual(draft.goals.map(\.range), [try XCTUnwrap(LearningGoalPreset.jusquAYasin.range(in: quran))])
    }

    /// « Tout le Coran » pose exactement ce que pose « continuer à travers le Coran ».
    ///
    /// Les deux gestes existent pour deux raisons différentes — l'un est un choix de l'étape des
    /// objectifs, l'autre une reprise —, mais ils doivent désigner la même étendue. Sans ce
    /// contrôle, les deux pourraient diverger sans que rien ne le dise.
    func test_toutLeCoran_posesExactlyWhatContinuingPoses() {
        var parLePreset = LearningSetupDraft(quran: quran)
        var parLaReprise = LearningSetupDraft(quran: quran)

        parLePreset.apply(.toutLeCoran)
        parLaReprise.continueThroughTheQuran()

        XCTAssertEqual(parLePreset.goals.map(\.range), parLaReprise.goals.map(\.range))
    }

    /// Toucher une désignation ne pose **aucun** objectif : elle déplace le sélecteur, c'est tout.
    func test_applyingADesignation_onlyMovesTheUnit() {
        var draft = LearningSetupDraft(quran: quran)
        draft.toggleGoal(QuranRange(firstSura: 78, firstAyah: 1, lastSura: 114, lastAyah: 6))
        let avant = draft.goals.map(\.range)

        draft.apply(.unHizb)

        XCTAssertEqual(draft.goalUnit, .hizb)
        XCTAssertEqual(draft.goals.map(\.range), avant, "une désignation ne touche pas aux objectifs")
    }

    /// Toucher deux fois la même étendue ne l'accumule pas : elle est posée, puis reposée.
    func test_applyingTheSameExtentTwice_leavesASingleGoal() {
        var draft = LearningSetupDraft(quran: quran)

        draft.apply(.laMoitieDuCoran)
        draft.apply(.laMoitieDuCoran)

        XCTAssertEqual(draft.goals.count, 1)
    }
}
