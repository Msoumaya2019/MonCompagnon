//
//  LearningRhythmTests.swift
//  LearningKitTests
//
//  Éprouve les allures, le rythme personnalisé et le calcul inverse de la date de fin.
//
//  Ces trois choses tiennent ensemble : une allure est un rythme, une allure personnalisée est un
//  rythme que l'utilisateur pose, et le calcul inverse est le rythme qu'une échéance impose. Les
//  éprouver séparément laisserait passer l'écart entre ce qu'on annonce et ce qui est appliqué —
//  c'est précisément ce que le planificateur lit sur le profil, et non sur l'allure.
//

import Foundation
import QuranKit
import XCTest
@testable import LearningKit

final class LearningRhythmTests: XCTestCase {
    private let quran = Quran.hafsMadani1405

    /// Calendrier figé pour des tests déterministes, quelle que soit la machine.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Un jour de référence stable : mercredi 30 septembre 2026, midi UTC.
    private var day0: Date {
        DateComponents(calendar: calendar, year: 2026, month: 9, day: 30, hour: 12).date!
    }

    /// Le juz' 30, « Juz 'Amma » : sourates 78 à 114, soit 564 versets.
    ///
    /// Le nombre est **mesuré** : il vient de `ayahinfo_1920.db` du mushaf embarqué, où les
    /// sourates 78 à 114 comptent 564 couples (sourate, verset) distincts.
    private var juz30: QuranRange {
        QuranRange(firstSura: 78, firstAyah: 1, lastSura: 114, lastAyah: 6)
    }

    /// Un jour décalé de `offset` jours par rapport à `day0`.
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: day0)!
    }

    private func makeDraft() -> LearningSetupDraft {
        LearningSetupDraft(quran: quran, calendar: calendar, createdAt: day0)
    }

    private func planner() -> LearningPlanner {
        LearningPlanner(quran: quran, calendar: calendar)
    }

    /// Construit un profil d'essai.
    ///
    /// Le nom porte `make` : nommer la variable locale comme la méthode la masquerait dans son
    /// propre initialiseur, ce que Swift refuse.
    private func makeProfile(
        goals: [QuranRange],
        pace: LearningPace = .regulier,
        customVerses: Int? = nil
    ) -> LearningProfile {
        LearningProfile(
            goals: goals.map { LearningGoal(range: $0, label: nil, targetDate: nil) },
            pace: pace,
            customVersesPerSession: customVerses,
            createdAt: day0,
            isConfigured: true
        )
    }

    /// Le rythme d'une allure **fixe**.
    ///
    /// `0` si l'allure n'en porte pas — ce que ces tests ne demandent jamais : ils n'appellent ce
    /// raccourci que sur les quatre allures fixes, et `.personnalise` est éprouvée à part.
    private func fixedVerses(of pace: LearningPace) -> Int {
        pace.versesPerSession ?? 0
    }

    // MARK: - Les cinq allures

    /// Quatre allures portent leur nombre, la cinquième n'en porte aucun.
    func test_theFivePaces_fourCarryANumberAndOneDoesNot() {
        XCTAssertEqual(LearningPace.allCases.count, 5)

        let fixed = LearningPace.allCases.compactMap(\.versesPerSession)
        XCTAssertEqual(fixed.count, 4, "quatre allures fixes")
        XCTAssertNil(LearningPace.personnalise.versesPerSession, "« personnalisé » ne dit aucun nombre")
        XCTAssertEqual(fixed, fixed.sorted(), "les rythmes croissent : la liste se lit comme une progression")
        XCTAssertEqual(Set(fixed).count, 4, "aucun rythme en double")
    }

    /// Le profil applique l'allure quand elle porte un nombre, et le nombre de l'utilisateur sinon.
    func test_theProfile_usesThePaceNumberOrTheCustomOne() {
        for pace in LearningPace.allCases where pace != .personnalise {
            XCTAssertEqual(
                makeProfile(goals: [], pace: pace).versesPerSession,
                fixedVerses(of: pace),
                "Allure \(pace) : c'est l'allure qui décide"
            )
        }

        XCTAssertEqual(
            makeProfile(goals: [], pace: .personnalise, customVerses: 12).versesPerSession,
            12,
            "« personnalisé » applique le nombre du profil"
        )
    }

    /// Une allure personnalisée sans nombre ne fait pas tomber le programme à un verset.
    func test_aCustomPaceWithoutANumber_fallsBackWithoutPretending() {
        let bare = makeProfile(goals: [], pace: .personnalise)
        XCTAssertEqual(bare.versesPerSession, LearningProfile.fallbackVersesPerSession)
        XCTAssertEqual(
            bare.versesPerSession,
            fixedVerses(of: .regulier),
            "le repli est le rythme de l'allure régulière"
        )

        let zero = makeProfile(goals: [], pace: .personnalise, customVerses: 0)
        XCTAssertEqual(zero.versesPerSession, LearningProfile.fallbackVersesPerSession, "zéro n'est pas un rythme")
    }

    /// Un nombre personnalisé ne s'applique pas à une allure fixe — mais il n'est pas perdu.
    func test_aCustomNumber_doesNotOverrideAFixedPace() {
        var tuned = makeProfile(goals: [], pace: .personnalise, customVerses: 12)

        tuned.pace = .soutenu
        XCTAssertEqual(tuned.versesPerSession, fixedVerses(of: .soutenu), "l'allure fixe décide")

        tuned.pace = .personnalise
        XCTAssertEqual(tuned.versesPerSession, 12, "et le nombre est retrouvé au retour")
    }

    /// Une allure personnalisée découpe réellement au nombre du profil.
    ///
    /// La comparaison porte sur le **nombre de séances** : c'est ce qui distingue un rythme large
    /// d'un rythme serré sur le même objectif, et aucune valeur de repli ne produit cet écart.
    func test_aCustomPace_shapesTheProgramWithItsOwnNumber() {
        let wide = planner().makeProgram(
            for: makeProfile(goals: [juz30], pace: .personnalise, customVerses: 40),
            from: day0
        )
        let narrow = planner().makeProgram(
            for: makeProfile(goals: [juz30], pace: .personnalise, customVerses: 8),
            from: day0
        )

        XCTAssertGreaterThan(wide.items.count, 0)
        XCTAssertLessThan(wide.items.count, narrow.items.count, "un rythme plus large fait moins de séances")
        for item in wide.items {
            XCTAssertLessThanOrEqual(item.verseCount(in: quran), 80, "jamais plus du double de la cible")
        }
    }

    // MARK: - Le choix de l'allure

    /// Choisir « personnalisé » pose un nombre : une allure sans nombre serait découpée au repli.
    func test_selectingTheCustomPace_posesANumber() {
        var draft = makeDraft()
        XCTAssertNil(draft.customVersesPerSession)
        XCTAssertEqual(draft.pace, .regulier)

        draft.select(pace: .personnalise)
        XCTAssertEqual(draft.customVersesPerSession, fixedVerses(of: .regulier))
        XCTAssertEqual(draft.versesPerSession, fixedVerses(of: .regulier))
    }

    /// Le nombre choisi survit à un détour par une autre allure.
    func test_theCustomNumber_survivesATourThroughAnotherPace() {
        var draft = makeDraft()
        draft.select(pace: .personnalise)
        draft.setVersesPerSession(12)

        draft.select(pace: .doux)
        XCTAssertEqual(draft.versesPerSession, fixedVerses(of: .doux), "l'allure fixe décide")

        draft.select(pace: .personnalise)
        XCTAssertEqual(draft.customVersesPerSession, 12, "et le nombre est retrouvé")
        XCTAssertEqual(draft.versesPerSession, 12)
    }

    /// Un nombre ne se pose que sur une allure personnalisée.
    func test_settingANumber_isRefusedOnAFixedPace() {
        var draft = makeDraft()
        draft.select(pace: .doux)
        draft.setVersesPerSession(12)

        XCTAssertNil(draft.customVersesPerSession)
        XCTAssertEqual(draft.versesPerSession, fixedVerses(of: .doux), "rien n'a été écrasé")
    }

    /// Le nombre est borné à un verset : à zéro, le découpage n'avancerait pas.
    func test_theCustomNumber_neverFallsBelowOne() {
        var draft = makeDraft()
        draft.select(pace: .personnalise)
        draft.setVersesPerSession(0)
        XCTAssertEqual(draft.customVersesPerSession, 1)
    }

    /// Le profil engendré porte le nombre, et le brouillon le retrouve en modification.
    func test_theProfile_carriesTheCustomNumberBackIntoTheDraft() {
        var draft = makeDraft()
        draft.toggleGoal(juz30)
        draft.select(pace: .personnalise)
        draft.setVersesPerSession(12)

        let profile = draft.makeProfile()
        XCTAssertEqual(profile.customVersesPerSession, 12)

        let edition = LearningSetupDraft(editing: profile, quran: quran, calendar: calendar)
        XCTAssertEqual(edition.pace, .personnalise)
        XCTAssertEqual(edition.customVersesPerSession, 12)
        XCTAssertEqual(edition.versesPerSession, 12)
    }

    // MARK: - Le calcul inverse

    /// Une échéance de quatre semaines pour Juz 'Amma demande 21 versets par séance.
    ///
    /// 564 versets sur 28 jours : 28 × 20 = 560 ne suffit pas, donc 21.
    func test_requiredVersesPerSession_dividesTheRemainingVersesOverTheWorkingDays() {
        var draft = makeDraft()
        draft.toggleGoal(juz30)

        // Du 30 septembre au 27 octobre 2026, bornes incluses : 28 jours, tous travaillés.
        XCTAssertEqual(draft.requiredVersesPerSession(by: day(27), from: day0), 21)
    }

    /// Un seul jour de travail par semaine demande bien plus par séance.
    func test_requiredVersesPerSession_countsOnlyTheWorkingDays() {
        var draft = makeDraft()
        draft.toggleGoal(juz30)
        draft.days = [.lundi]

        // Quatre lundis dans l'intervalle : 564 / 4 = 141.
        XCTAssertEqual(draft.requiredVersesPerSession(by: day(27), from: day0), 141)
    }

    /// Une échéance le jour même demande tout d'un coup.
    func test_requiredVersesPerSession_onTheSameDay_asksForEverything() {
        var draft = makeDraft()
        draft.toggleGoal(juz30)
        XCTAssertEqual(draft.requiredVersesPerSession(by: day0, from: day0), 564)
    }

    /// Sans objectif, sans jour de travail, ou avec une échéance dépassée, il n'y a pas de cible.
    ///
    /// Les trois cas rendent `nil` pour des raisons différentes : ne pas les séparer laisserait
    /// croire qu'un seul suffit, alors que chacun protège d'une division par zéro ou par l'infini.
    func test_requiredVersesPerSession_isNilWhenThereIsNothingToPlan() {
        let noGoal = makeDraft()
        XCTAssertNil(noGoal.requiredVersesPerSession(by: day(27), from: day0), "rien à apprendre")

        var noDay = makeDraft()
        noDay.toggleGoal(juz30)
        noDay.days = []
        XCTAssertNil(noDay.requiredVersesPerSession(by: day(27), from: day0), "aucun jour de travail")

        var late = makeDraft()
        late.toggleGoal(juz30)
        XCTAssertNil(late.requiredVersesPerSession(by: day(-1), from: day0), "échéance dépassée")
    }

    /// Une échéance déjà couverte par ce qui est déclaré solide ne demande plus rien.
    func test_requiredVersesPerSession_isNilWhenEverythingIsAlreadyKnown() {
        var draft = makeDraft()
        draft.toggleGoal(juz30)
        draft.setSolidity(.solide, for: juz30)
        XCTAssertNil(draft.requiredVersesPerSession(by: day(27), from: day0), "tout est déjà su")
    }

    // MARK: - Les jours de travail

    /// Le compte des jours de travail ne retient que les jours choisis, bornes incluses.
    func test_workingDays_countsOnlyTheChosenDays() {
        let all = planner().workingDays(from: day0, through: day(27), days: Set(LearningDay.allCases))
        XCTAssertEqual(all, 28, "28 jours consécutifs, bornes incluses")

        XCTAssertEqual(planner().workingDays(from: day0, through: day(27), days: [.lundi]), 4)
        XCTAssertEqual(planner().workingDays(from: day0, through: day0, days: [.mercredi]), 1)
        XCTAssertEqual(planner().workingDays(from: day0, through: day0, days: [.jeudi]), 0, "ce jour-là n'est pas travaillé")

        XCTAssertEqual(planner().workingDays(from: day0, through: day(27), days: []), 0, "aucun jour")
        XCTAssertEqual(planner().workingDays(from: day0, through: day(-1), days: Set(LearningDay.allCases)), 0, "échéance dépassée")
    }

    /// Plus l'échéance est proche, plus la cible est exigeante — et jamais l'inverse.
    ///
    /// C'est la seule relation qui doive tenir dans tous les cas. L'égalité avec l'estimation de
    /// fin, elle, ne tiendrait pas : le découpage arrondit chaque séance à une fin de page et peut
    /// donc faire plus de séances que la cible ne le prévoit, jamais moins.
    func test_requiredVersesPerSession_growsAsTheDeadlineComesCloser() {
        var draft = makeDraft()
        draft.toggleGoal(juz30)

        let far = draft.requiredVersesPerSession(by: day(27), from: day0) ?? 0
        let near = draft.requiredVersesPerSession(by: day(6), from: day0) ?? 0
        XCTAssertGreaterThan(near, far, "une semaine demande plus que quatre")

        // Travailler un seul jour par semaine demande plus que travailler tous les jours.
        draft.days = [.lundi]
        let weekly = draft.requiredVersesPerSession(by: day(27), from: day0) ?? 0
        XCTAssertGreaterThan(weekly, far, "un seul jour par semaine demande plus")
    }
}
