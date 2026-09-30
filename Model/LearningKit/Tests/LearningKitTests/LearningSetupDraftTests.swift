//
//  LearningSetupDraftTests.swift
//  LearningKitTests
//
//  Éprouve le brouillon de la configuration guidée.
//
//  Le planificateur a déjà ses propres tests — couverture exacte, découpage en séances, acquis
//  solides et fragiles, date de fin. Ceux-ci portent sur ce que le brouillon décide **avant** de
//  les lui confier : les choix proposés, la validité de chaque étape, le rangement des
//  déclarations, et ce qu'on annonce à l'utilisateur avant qu'il commence.
//

import Foundation
import QuranKit
import XCTest
@testable import LearningKit

final class LearningSetupDraftTests: XCTestCase {
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
    /// Le nombre est **mesuré**, pas déduit : il vient de `ayahinfo_1920.db` du mushaf embarqué,
    /// où les sourates 78 à 114 comptent 564 couples (sourate, verset) distincts, et la table
    /// entière 6236.
    private var juz30: QuranRange {
        QuranRange(firstSura: 78, firstAyah: 1, lastSura: 114, lastAyah: 6)
    }

    private func makeDraft() -> LearningSetupDraft {
        LearningSetupDraft(quran: quran, calendar: calendar, createdAt: day0)
    }

    // MARK: - Les choix proposés

    /// Trente juz', dans l'ordre du mushaf, qui le couvrent exactement.
    func test_juzChoices_coverTheWholeMushafInOrder() {
        let choices = makeDraft().juzChoices()
        XCTAssertEqual(choices.count, 30)
        XCTAssertEqual(choices.map(\.juzNumber), Array(1 ... 30))

        let covered = choices.reduce(0) { $0 + $1.verseCount }
        XCTAssertEqual(covered, quran.verses.count, "les juz' couvrent le mushaf sans trou")
    }

    /// Le dernier choix est bien Juz 'Amma, avec sa taille et ses bornes.
    func test_theLastChoiceIsJuzAmma() {
        let choice = makeDraft().juzChoices().last
        XCTAssertEqual(choice?.juzNumber, 30)
        XCTAssertEqual(choice?.verseCount, 564)
        XCTAssertEqual(choice?.range, juz30)
    }

    /// Chaque choix porte l'état du brouillon : ni l'un ni l'autre ne ment.
    func test_juzChoices_reflectTheDraft() {
        var draft = makeDraft()
        draft.setSolidity(.solide, for: juz30)
        draft.toggleGoal(QuranRange(quran.juzs[0]))

        let choices = draft.juzChoices()
        XCTAssertEqual(choices.first?.juzNumber, 1)
        XCTAssertEqual(choices.first?.isGoal, true)
        XCTAssertEqual(choices.last?.solidity, .solide)
        XCTAssertEqual(choices.last?.isGoal, false)
    }

    // MARK: - La navigation

    /// Une étape incomplète ne se passe pas : le brouillon refuse d'avancer.
    ///
    /// L'interface désactive son bouton, mais une vue fautive ne doit pas pouvoir sauter un choix
    /// obligatoire — c'est le brouillon qui tient la règle.
    func test_advance_refusesWhenTheStepIsIncomplete() {
        var draft = makeDraft()
        XCTAssertTrue(draft.isFirstStep)
        XCTAssertTrue(draft.advance(), "l'étape « ce que je connais » se passe")
        XCTAssertEqual(draft.step, .goals)

        XCTAssertFalse(draft.canAdvance, "aucun objectif : l'étape n'est pas remplie")
        XCTAssertFalse(draft.advance(), "le brouillon refuse d'avancer")
        XCTAssertEqual(draft.step, .goals, "et l'étape n'a pas bougé")
    }

    func test_back_stopsAtTheFirstStep() {
        var draft = makeDraft()
        XCTAssertFalse(draft.back())
        XCTAssertTrue(draft.isFirstStep)
    }

    /// On peut aller directement à une étape, dans les deux sens.
    func test_go_reachesAnyStepAndTheLastOneIsFinal() {
        var draft = makeDraft()
        draft.go(to: .summary)
        XCTAssertEqual(draft.step, .summary)
        XCTAssertTrue(draft.isLastStep)
        XCTAssertFalse(draft.advance(), "il n'y a pas d'étape après la dernière")

        draft.go(to: .known)
        XCTAssertTrue(draft.isFirstStep)
    }

    /// Sans jour de travail, l'étape des jours bloque — et aucune fin n'est estimable.
    func test_noWorkingDay_blocksTheDaysStepAndTheEstimate() {
        var draft = makeDraft()
        // Un objectif est nécessaire : sans lui le programme est vide, et une estimation de fin
        // « déjà terminé » court-circuite la question des jours. C'est bien « aucun jour » que ce
        // test interroge, pas « rien à apprendre ».
        draft.toggleGoal(juz30)
        draft.go(to: .days)
        draft.days = []

        XCTAssertFalse(draft.canAdvance, "sans jour de travail, l'étape ne se franchit pas")
        XCTAssertNil(draft.summary(from: day0).estimatedEndDate, "et il n'y a alors pas de fin")
    }

    // MARK: - Ce que je connais

    /// L'état tourne : rien → solide → fragile → rien.
    func test_cycleSolidity_turnsThroughTheThreeStates() {
        var draft = makeDraft()
        XCTAssertNil(draft.solidity(of: juz30))

        draft.cycleSolidity(for: juz30)
        XCTAssertEqual(draft.solidity(of: juz30), .solide)

        draft.cycleSolidity(for: juz30)
        XCTAssertEqual(draft.solidity(of: juz30), .fragile)

        draft.cycleSolidity(for: juz30)
        XCTAssertNil(draft.solidity(of: juz30), "le troisième tour revient au point de départ")
        XCTAssertTrue(draft.known.isEmpty, "aucune déclaration ne doit rester")
    }

    /// Corriger une déclaration conserve son identifiant et son libellé.
    ///
    /// Passer de « solide » à « fragile » corrige la **même** déclaration : un identifiant neuf la
    /// ferait passer pour une autre.
    func test_setSolidity_keepsTheIdentityWhenTheSolidityChanges() {
        var draft = makeDraft()
        draft.setSolidity(.solide, for: juz30, label: "Juz 'Amma")
        let identity = draft.known.first?.id

        draft.setSolidity(.fragile, for: juz30)
        XCTAssertEqual(draft.known.count, 1)
        XCTAssertEqual(draft.known.first?.id, identity)
        XCTAssertEqual(draft.known.first?.label, "Juz 'Amma", "le libellé est conservé")
        XCTAssertEqual(draft.known.first?.solidity, .fragile)
    }

    /// Déclarer puis effacer laisse le brouillon exactement tel qu'il était.
    func test_declaringThenClearing_restoresTheDraft() {
        let initial = makeDraft()
        var draft = makeDraft()
        draft.setSolidity(.solide, for: juz30)
        draft.setSolidity(nil, for: juz30)
        XCTAssertEqual(draft, initial)
    }

    // MARK: - Ce que je veux apprendre

    func test_toggleGoal_addsThenRemoves() {
        var draft = makeDraft()
        XCTAssertFalse(draft.isGoal(juz30))

        draft.toggleGoal(juz30, label: "Juz 'Amma")
        XCTAssertTrue(draft.isGoal(juz30))

        draft.toggleGoal(juz30)
        XCTAssertFalse(draft.isGoal(juz30))
        XCTAssertTrue(draft.goals.isEmpty)
    }

    /// Deux brouillons qui portent les mêmes déclarations sont égaux, quel que soit l'ordre de
    /// saisie.
    ///
    /// C'est ce que garantit le rangement à la saisie : sans lui, cocher les juz' dans un ordre
    /// puis dans l'autre donnerait deux états différents pour une même configuration.
    func test_theOrderOfEntry_doesNotChangeTheDraft() {
        var ascending = makeDraft()
        ascending.toggleGoal(QuranRange(quran.juzs[0]))
        ascending.toggleGoal(juz30)
        ascending.setSolidity(.solide, for: QuranRange(quran.juzs[1]))
        ascending.setSolidity(.fragile, for: juz30)

        var descending = makeDraft()
        descending.setSolidity(.fragile, for: juz30)
        descending.setSolidity(.solide, for: QuranRange(quran.juzs[1]))
        descending.toggleGoal(juz30)
        descending.toggleGoal(QuranRange(quran.juzs[0]))

        // Comparer les deux brouillons entiers serait trop fort : chaque déclaration porte un
        // identifiant neuf, et deux saisies dans un ordre différent en engendrent de différents.
        // Ce qui doit être identique, c'est ce qui décide — intervalles, solidité, objectifs,
        // allure, jours — et leur ordre.
        XCTAssertEqual(ascending.known.map(\.range), descending.known.map(\.range))
        XCTAssertEqual(ascending.known.map(\.solidity), descending.known.map(\.solidity))
        XCTAssertEqual(ascending.goals.map(\.range), descending.goals.map(\.range))
        XCTAssertEqual(ascending.days, descending.days)
        XCTAssertEqual(ascending.pace, descending.pace)
        XCTAssertEqual(ascending.sessionMinutes, descending.sessionMinutes)
        XCTAssertEqual(ascending.goals.map(\.range.firstSura), [1, 78], "les objectifs sont rangés")
        XCTAssertEqual(ascending.known.map(\.range.firstSura), [2, 78], "les acquis sont rangés")
    }

    /// Une échéance ne s'accroche qu'à un objectif, et le laisse intact.
    func test_setDeadline_onlyAppliesToAGoalAndKeepsIt() {
        var draft = makeDraft()
        draft.setDeadline(day0, for: juz30)
        XCTAssertNil(draft.deadline(for: juz30), "sans objectif, pas d'échéance")
        XCTAssertTrue(draft.goals.isEmpty)

        draft.toggleGoal(juz30)
        let identity = draft.goals.first?.id
        draft.setDeadline(day0, for: juz30)
        XCTAssertEqual(draft.deadline(for: juz30), day0)
        XCTAssertEqual(draft.goals.first?.id, identity, "l'objectif reste le même")

        draft.setDeadline(nil, for: juz30)
        XCTAssertNil(draft.deadline(for: juz30), "l'échéance s'efface")
        XCTAssertTrue(draft.isGoal(juz30), "l'effacer ne retire pas l'objectif")
    }

    // MARK: - Le profil

    func test_makeProfile_carriesTheDraftAndMarksItConfigured() {
        var draft = makeDraft()
        draft.toggleGoal(juz30, label: "Juz 'Amma")
        draft.setSolidity(.fragile, for: QuranRange(quran.juzs[0]))
        draft.pace = .doux
        draft.days = [.lundi, .mercredi]
        draft.sessionMinutes = 25

        let profile = draft.makeProfile()
        XCTAssertTrue(profile.isConfigured, "une configuration terminée se dit terminée")
        XCTAssertEqual(profile.createdAt, day0, "la date de création est celle du brouillon")
        XCTAssertEqual(profile.goals, draft.goals)
        XCTAssertEqual(profile.knownRanges, draft.known)
        XCTAssertEqual(profile.pace, .doux)
        XCTAssertEqual(profile.days, [.lundi, .mercredi])
        XCTAssertEqual(profile.sessionMinutes, 25)
    }

    /// Modifier un programme existant n'est pas recommencer son apprentissage.
    func test_editingAProfile_keepsItsCreationDateAndDoesNotTouchIt() {
        var configured = makeDraft()
        configured.toggleGoal(juz30)
        configured.setSolidity(.solide, for: QuranRange(quran.juzs[0]))
        configured.pace = .soutenu
        configured.days = [.samedi]
        configured.sessionMinutes = 30
        let profile = configured.makeProfile()

        var edition = LearningSetupDraft(editing: profile, quran: quran, calendar: calendar)
        XCTAssertEqual(edition.createdAt, day0)
        XCTAssertEqual(edition.goals, profile.goals)
        XCTAssertEqual(edition.known, profile.knownRanges)
        XCTAssertEqual(edition.pace, .soutenu)
        XCTAssertEqual(edition.days, [.samedi])
        XCTAssertEqual(edition.sessionMinutes, 30)
        XCTAssertEqual(edition.step, .known, "une modification repart de la première étape")

        edition.toggleGoal(juz30)
        XCTAssertEqual(profile.goals.count, 1, "le profil d'origine n'est pas modifié")
        XCTAssertEqual(edition.makeProfile().createdAt, day0)
    }

    // MARK: - Le récapitulatif

    /// Sans objectif, il n'y a rien à programmer.
    ///
    /// La date de fin vaut **aujourd'hui** — c'est la règle du planificateur pour un programme
    /// terminé — et non `nil`. L'interface ne peut donc pas s'en servir pour savoir s'il reste
    /// quelque chose à faire : c'est `isEmpty` qui répond à cette question.
    func test_summary_withoutGoal_isEmptyButEndsToday() {
        let summary = makeDraft().summary(from: day0)
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.sessionCount, 0)
        XCTAssertEqual(summary.reviewCount, 0)
        XCTAssertEqual(summary.remainingVerses, 0)
        XCTAssertEqual(summary.estimatedEndDate, calendar.startOfDay(for: day0))
    }

    /// Un objectif déjà su par cœur ne laisse rien à programmer.
    func test_summary_ofAGoalEntirelyKnownSolid_isEmpty() {
        var draft = makeDraft()
        draft.toggleGoal(juz30)
        draft.setSolidity(.solide, for: juz30)

        XCTAssertTrue(draft.summary(from: day0).isEmpty)
        XCTAssertFalse(draft.canStart(from: day0), "il n'y a rien à commencer")
    }

    /// Un objectif déclaré fragile reste un programme : il est à revoir.
    ///
    /// C'est le cas qui distingue « rien à apprendre » de « rien à faire ». Ne compter que les
    /// séances d'apprentissage ferait passer ce programme pour vide.
    func test_summary_ofAGoalEntirelyKnownFragile_staysAProgram() {
        var draft = makeDraft()
        draft.toggleGoal(juz30)
        draft.setSolidity(.fragile, for: juz30)

        let summary = draft.summary(from: day0)
        XCTAssertEqual(summary.sessionCount, 0, "il n'y a plus rien à apprendre")
        XCTAssertEqual(summary.reviewCount, 1, "mais il y a à revoir")
        XCTAssertFalse(summary.isEmpty, "un programme de révision n'est pas un programme vide")
        XCTAssertTrue(draft.canStart(from: day0))
    }

    /// Un objectif à apprendre est annoncé avec sa taille exacte, et rien à revoir.
    func test_summary_ofAJuzToLearn_announcesItsExactSize() {
        var draft = makeDraft()
        draft.toggleGoal(juz30)

        let summary = draft.summary(from: day0)
        XCTAssertFalse(summary.isEmpty)
        XCTAssertEqual(summary.reviewCount, 0, "aucun acquis fragile : aucune révision")
        XCTAssertEqual(summary.remainingVerses, 564, "tout le juz' 30 reste à apprendre")
        XCTAssertGreaterThan(summary.sessionCount, 0)
        XCTAssertNotNil(summary.estimatedEndDate, "des jours choisis : une fin est estimable")
        XCTAssertTrue(draft.canStart(from: day0))
    }

    /// L'allure change réellement le programme, et l'annonce suit.
    func test_thePace_changesTheProgramAndTheAnnouncedEnd() {
        var gentle = makeDraft()
        gentle.toggleGoal(juz30)
        gentle.pace = .doux

        var sustained = makeDraft()
        sustained.toggleGoal(juz30)
        sustained.pace = .soutenu

        let doux = gentle.summary(from: day0)
        let soutenu = sustained.summary(from: day0)

        XCTAssertGreaterThan(doux.sessionCount, soutenu.sessionCount, "doux : plus de séances")
        let finDoux = doux.estimatedEndDate ?? day0
        let finSoutenu = soutenu.estimatedEndDate ?? day0
        XCTAssertGreaterThan(finDoux, finSoutenu, "et finit plus tard")
    }
}
