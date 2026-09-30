//
//  LearningSetupDraftTests.swift
//  LearningKitTests
//
//  Éprouve le brouillon de la configuration guidée.
//
//  Le planificateur a déjà ses propres tests — couverture exacte, découpage en séances, acquis
//  solides et fragiles, date de fin. Ceux-ci portent sur ce que le brouillon décide **avant** de
//  les lui confier : les choix proposés et leurs trois unités, ce qui autorise à créer le programme,
//  le rangement des déclarations, la reprise du Coran entier, et ce qu'on annonce à l'utilisateur
//  avant qu'il commence.
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

    /// Le nombre de morceaux d'une unité, écrit en clair.
    ///
    /// Les valeurs sont des **oracles indépendants** : les lire sur `quran` ne prouverait rien,
    /// puisque l'implémentation lit les mêmes tableaux. Elles viennent du mushaf embarqué —
    /// 114 sourates, 60 hizb, 30 juz'.
    private func pieceCount(of unit: LearningUnit) -> Int {
        switch unit {
        case .sourate: return 114
        case .hizb: return 60
        case .juz: return 30
        }
    }

    // MARK: - Les choix proposés

    /// Trente juz', dans l'ordre du mushaf, qui le couvrent exactement.
    func test_theJuzChoices_coverTheWholeMushafInOrder() {
        let choices = makeDraft().choices(for: .juz)
        XCTAssertEqual(choices.count, 30)
        XCTAssertEqual(choices.map(\.number), Array(1 ... 30))

        let covered = choices.reduce(0) { $0 + $1.verseCount }
        XCTAssertEqual(covered, quran.verses.count, "les juz' couvrent le mushaf sans trou")
    }

    /// Le dernier choix est bien Juz 'Amma, avec sa taille et ses bornes.
    func test_theLastChoiceIsJuzAmma() {
        let choice = makeDraft().choices(for: .juz).last
        XCTAssertEqual(choice?.number, 30)
        XCTAssertEqual(choice?.unit, .juz)
        XCTAssertEqual(choice?.verseCount, 564)
        XCTAssertEqual(choice?.range, juz30)
    }

    /// Chaque choix porte l'état du brouillon : ni l'un ni l'autre ne ment.
    func test_theJuzChoices_reflectTheDraft() {
        var draft = makeDraft()
        draft.setSolidity(.solide, for: juz30)
        draft.toggleGoal(QuranRange(quran.juzs[0]))

        let choices = draft.choices(for: .juz)
        XCTAssertEqual(choices.first?.number, 1)
        XCTAssertEqual(choices.first?.isGoal, true)
        XCTAssertEqual(choices.last?.solidity, .solide)
        XCTAssertEqual(choices.last?.isGoal, false)
    }

    // MARK: - Ce qui autorise à créer le programme

    /// Sans jour de travail, il n'y a pas de programme à créer — et aucune fin n'est estimable.
    ///
    /// La configuration est une page unique : il n'y a plus d'étape à franchir, donc plus rien à
    /// refuser en chemin. Ce qui reste à tenir, c'est la condition du bouton — et elle est
    /// **nécessaire mais pas suffisante**, d'où les deux assertions.
    func test_noWorkingDay_blocksTheStartAndTheEstimate() {
        var draft = makeDraft()
        // Un objectif est nécessaire : sans lui le programme est vide, et une estimation de fin
        // « déjà terminé » court-circuite la question des jours. C'est bien « aucun jour » que ce
        // test interroge, pas « rien à apprendre ».
        draft.toggleGoal(juz30)
        draft.days = []

        XCTAssertFalse(draft.canStart(from: day0), "sans jour de travail, rien ne se crée")
        XCTAssertNil(draft.summary(from: day0).estimatedEndDate, "et il n'y a alors pas de fin")
    }

    /// Un objectif sans jour de travail n'est pas non plus un programme à créer, et l'inverse non plus.
    ///
    /// Les deux conditions sont indépendantes : les éprouver séparément est ce qui garantit qu'aucune
    /// des deux ne se fait passer pour l'autre.
    func test_canStart_requiresBothAGoalAndAWorkingDay() {
        let noGoal = makeDraft()
        XCTAssertFalse(noGoal.canStart(from: day0), "des jours, mais rien à apprendre")

        var noDay = makeDraft()
        noDay.toggleGoal(juz30)
        noDay.days = []
        XCTAssertFalse(noDay.canStart(from: day0), "quelque chose à apprendre, mais aucun jour")

        var complete = makeDraft()
        complete.toggleGoal(juz30)
        XCTAssertTrue(complete.canStart(from: day0), "les deux ensemble : le programme se crée")
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

    /// Une échéance vaut pour le programme entier, et se pose sur chaque objectif du profil.
    ///
    /// Le brouillon n'en porte qu'une : l'utilisateur n'a qu'une date en tête. C'est
    /// `makeProfile()` qui la répartit, parce que `LearningGoal` est le seul type qui sait la porter
    /// jusqu'au disque.
    func test_theDeadline_landsOnEveryGoalOfTheProfile() {
        var draft = makeDraft()
        draft.toggleGoal(juz30)
        draft.toggleGoal(QuranRange(quran.suras[0]))

        XCTAssertNil(draft.deadline, "aucune échéance au départ")
        XCTAssertTrue(
            draft.makeProfile().goals.allSatisfy { $0.targetDate == nil },
            "sans échéance, aucun objectif n'en porte"
        )

        draft.deadline = day0
        let profile = draft.makeProfile()
        XCTAssertEqual(profile.goals.count, 2)
        XCTAssertTrue(
            profile.goals.allSatisfy { $0.targetDate == day0 },
            "l'échéance est celle du programme, pas d'un objectif"
        )

        // Et le brouillon la retrouve tel quel quand on rouvre la configuration.
        let edition = LearningSetupDraft(editing: profile, quran: quran, calendar: calendar)
        XCTAssertEqual(edition.deadline, day0)

        draft.deadline = nil
        XCTAssertTrue(draft.makeProfile().goals.allSatisfy { $0.targetDate == nil }, "et elle s'efface")
        XCTAssertTrue(draft.isGoal(juz30), "l'effacer ne retire aucun objectif")
    }

    // MARK: - Le profil

    func test_makeProfile_carriesTheDraftAndMarksItConfigured() {
        var draft = makeDraft()
        draft.toggleGoal(juz30, label: "Juz 'Amma")
        draft.setSolidity(.fragile, for: QuranRange(quran.juzs[0]))
        draft.select(pace: .doux)
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
        configured.select(pace: .soutenu)
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

        edition.toggleGoal(juz30)
        XCTAssertEqual(profile.goals.count, 1, "le profil d'origine n'est pas modifié")
        XCTAssertEqual(edition.makeProfile().createdAt, day0)
    }

    // MARK: - Le sens d'apprentissage

    /// Le sens traverse le brouillon : c'est par lui qu'il atteint le profil, donc le planificateur.
    func test_theDraftCarriesTheDirection() {
        var draft = makeDraft()
        XCTAssertEqual(draft.direction, .depuisLeDebut, "l'ordre du mushaf est le défaut")
        XCTAssertEqual(draft.makeProfile().direction, .depuisLeDebut)

        draft.direction = .depuisLaFin
        XCTAssertEqual(draft.makeProfile().direction, .depuisLaFin, "le choix doit atteindre le profil")
    }

    /// Modifier un programme à rebours le rouvre à rebours, et non dans l'ordre du mushaf.
    func test_editingAProfile_restoresTheDirection() {
        var configured = makeDraft()
        configured.toggleGoal(juz30)
        configured.direction = .depuisLaFin
        let profile = configured.makeProfile()

        let edition = LearningSetupDraft(editing: profile, quran: quran, calendar: calendar)
        XCTAssertEqual(edition.direction, .depuisLaFin, "un programme à rebours se rouvre à rebours")
        XCTAssertEqual(edition.makeProfile().direction, .depuisLaFin)
    }

    /// Le sens change **par quel bout** on commence, pas **combien** il reste à faire : ni le nombre
    /// de séances, ni l'échéance annoncée ne bougent.
    ///
    /// C'est ce que le commentaire de `direction` affirme. Une affirmation non éprouvée dérive —
    /// surtout ici, où le récapitulatif engendre réellement le programme pour l'annoncer.
    func test_theDirection_doesNotChangeWhatTheSummaryAnnounces() {
        var forward = makeDraft()
        forward.toggleGoal(juz30)
        var backward = forward
        backward.direction = .depuisLaFin

        XCTAssertEqual(backward.summary(from: day0), forward.summary(from: day0))
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
        gentle.select(pace: .doux)

        var sustained = makeDraft()
        sustained.toggleGoal(juz30)
        sustained.select(pace: .soutenu)

        let doux = gentle.summary(from: day0)
        let soutenu = sustained.summary(from: day0)

        XCTAssertGreaterThan(doux.sessionCount, soutenu.sessionCount, "doux : plus de séances")
        let finDoux = doux.estimatedEndDate ?? day0
        let finSoutenu = soutenu.estimatedEndDate ?? day0
        XCTAssertGreaterThan(finDoux, finSoutenu, "et finit plus tard")
    }

    // MARK: - Les trois unités de choix

    /// Chaque unité propose ses morceaux, numérotés dans l'ordre, et ils couvrent le mushaf.
    func test_eachUnit_coversTheWholeMushaf() {
        let draft = makeDraft()
        for unit in LearningUnit.allCases {
            let choices = draft.choices(for: unit)
            XCTAssertEqual(choices.count, pieceCount(of: unit), "Unit \(unit) : nombre de morceaux")
            XCTAssertEqual(choices.map(\.number), Array(1 ... choices.count), "Unit \(unit) : numérotés à partir de 1")
            XCTAssertTrue(choices.allSatisfy { $0.unit == unit }, "Unit \(unit) : chaque choix dit son unité")
            XCTAssertEqual(
                choices.reduce(0) { $0 + $1.verseCount },
                quran.verses.count,
                "Unit \(unit) : les morceaux couvrent le mushaf sans trou"
            )
        }
    }

    /// Le premier morceau de chaque unité a les bornes du mushaf, et la première sourate ses versets.
    func test_theFirstChoiceOfEachUnit_hasTheExpectedBounds() {
        let draft = makeDraft()
        XCTAssertEqual(draft.choices(for: .sourate).first?.range, QuranRange(firstSura: 1, firstAyah: 1, lastSura: 1, lastAyah: 7))
        XCTAssertEqual(draft.choices(for: .sourate).first?.verseCount, 7, "Al-Fatiha compte sept versets")
        XCTAssertEqual(draft.choices(for: .hizb).first?.range, QuranRange(quran.hizbs[0]))
        XCTAssertEqual(draft.choices(for: .juz).first?.range, QuranRange(quran.juzs[0]))
    }

    /// Les deux sections ont chacune la leur, et elles ne se commandent pas l'une l'autre.
    ///
    /// Celle dont on dit « je connais cette sourate » n'est pas forcément celle dont on dit « je
    /// veux apprendre ce juz' » : les partager obligerait à revenir en arrière entre les sections.
    func test_eachSectionHasItsOwnUnit() {
        var draft = makeDraft()
        XCTAssertEqual(draft.knownUnit, .juz, "le juz' est l'unité par défaut des deux sections")
        XCTAssertEqual(draft.goalUnit, .juz)

        draft.knownUnit = .hizb
        XCTAssertEqual(draft.knownChoices().count, 60)
        XCTAssertEqual(draft.goalChoices().count, 30, "changer une unité ne change pas l'autre")

        draft.goalUnit = .sourate
        XCTAssertEqual(draft.knownChoices().count, 60)
        XCTAssertEqual(draft.goalChoices().count, 114)
    }

    /// Chaque choix a une identité qui distingue les unités.
    ///
    /// Le rang seul ne suffirait pas : la sourate 3, le hizb 3 et le juz' 3 sont trois morceaux
    /// différents, et une identité partagée les ferait passer l'un pour l'autre dans une liste.
    func test_choicesOfDifferentUnits_doNotShareAnIdentity() {
        let draft = makeDraft()
        let sura = draft.choices(for: .sourate)[2]
        let hizb = draft.choices(for: .hizb)[2]
        let juz = draft.choices(for: .juz)[2]

        XCTAssertEqual(sura.number, 3)
        XCTAssertEqual(Set([sura.id, hizb.id, juz.id]).count, 3, "trois morceaux, trois identités")
    }

    /// Changer d'unité ne défait rien, et deux unités peuvent coexister comme objectifs.
    func test_changingTheUnit_keepsWhatIsDeclared() {
        var draft = makeDraft()
        draft.toggleGoal(QuranRange(quran.suras[0]), label: "Al-Fatiha")
        draft.setSolidity(.solide, for: juz30)

        draft.goalUnit = .sourate
        XCTAssertTrue(draft.isGoal(QuranRange(quran.suras[0])))
        XCTAssertEqual(draft.choices(for: .sourate).first?.isGoal, true, "l'objectif se voit dans l'unité sourate")
        XCTAssertEqual(draft.choices(for: .juz).last?.solidity, .solide, "et l'acquis dans l'unité juz'")

        draft.toggleGoal(juz30)
        XCTAssertEqual(draft.goals.count, 2, "une sourate et un juz' coexistent")
        XCTAssertEqual(draft.goals.map(\.range.firstSura), [1, 78], "et restent rangés dans l'ordre du mushaf")
    }

    // MARK: - Repartir de zéro, continuer le Coran

    /// « Je commence de zéro » efface les déclarations, et rien d'autre.
    func test_startFromScratch_clearsTheDeclarationsOnly() {
        var draft = makeDraft()
        draft.toggleGoal(juz30)
        draft.setSolidity(.solide, for: QuranRange(quran.juzs[0]))
        draft.select(pace: .doux)
        draft.days = [.lundi]
        draft.sessionMinutes = 30

        draft.startFromScratch()
        XCTAssertTrue(draft.known.isEmpty, "plus aucun acquis")
        XCTAssertTrue(draft.goals.isEmpty, "plus aucun objectif")
        XCTAssertEqual(draft.pace, .doux, "le rythme n'est pas remis en question")
        XCTAssertEqual(draft.days, [.lundi])
        XCTAssertEqual(draft.sessionMinutes, 30)
    }

    /// « Continuer le Coran » prend le mushaf entier comme objectif, et remplace les autres.
    func test_continueThroughTheQuran_takesTheWholeMushafAndReplacesTheGoals() {
        var draft = makeDraft()
        draft.toggleGoal(juz30)

        draft.continueThroughTheQuran()
        XCTAssertEqual(draft.goals.count, 1, "un seul objectif : le Coran entier")
        XCTAssertEqual(
            draft.goals.first?.range,
            QuranRange(firstSura: 1, firstAyah: 1, lastSura: 114, lastAyah: 6)
        )
        XCTAssertEqual(draft.goals.first?.range.verseCount(in: quran), quran.verses.count)
        XCTAssertFalse(draft.isGoal(juz30), "l'objectif précédent est remplacé, non doublé")
    }

    /// Le Coran entier laisse réellement quelque chose à apprendre, et la reprise le couvre en entier.
    ///
    /// C'est la promesse de « continuer progressivement » : un programme qui part du début du
    /// mushaf et va jusqu'à la fin, sans trou. Le relevé de progression, lui, décide où il reprend —
    /// c'est le lot de `LearningProgress`, et non du brouillon.
    func test_continuingThroughTheQuran_producesAContiguousProgram() {
        var draft = makeDraft()
        draft.continueThroughTheQuran()
        draft.select(pace: .soutenu)

        let summary = draft.summary(from: day0)
        XCTAssertFalse(summary.isEmpty)
        XCTAssertEqual(summary.remainingVerses, quran.verses.count, "tout le Coran reste à apprendre")
        XCTAssertGreaterThan(summary.sessionCount, 0)
    }
}
