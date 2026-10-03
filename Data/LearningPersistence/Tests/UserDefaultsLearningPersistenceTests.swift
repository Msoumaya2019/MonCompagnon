//
//  UserDefaultsLearningPersistenceTests.swift
//  LearningPersistenceTests
//
//  Éprouve la conservation du profil et du programme d'apprentissage.
//

import Foundation
import LearningKit
import QuranKit
import XCTest
@testable import LearningPersistence

final class UserDefaultsLearningPersistenceTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        for key in keys {
            originalValues[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys {
            if let value = originalValues[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    // MARK: - Valeurs par défaut

    func testMissingProfileIsAnEmptyProfile() {
        let profile = persistence.loadProfile()
        XCTAssertFalse(profile.isConfigured)
        XCTAssertTrue(profile.goals.isEmpty)
        XCTAssertTrue(profile.knownRanges.isEmpty)
    }

    func testMissingProgramIsEmpty() {
        let program = persistence.loadProgram()
        XCTAssertTrue(program.isEmpty)
        XCTAssertNil(program.generatedAt)
    }

    func testMissingProgressIsEmpty() {
        XCTAssertTrue(persistence.loadProgress().isEmpty)
    }

    // MARK: - Aller-retour

    func testProfileSurvivesARoundTrip() {
        let profile = learningProfile(
            pace: .soutenu,
            knownRanges: [
                KnownRange(range: baqara, label: "Al-Baqara", solidity: .fragile),
                KnownRange(range: goal, label: "An-Naba", solidity: .solide),
            ]
        )
        persistence.saveProfile(profile)
        XCTAssertEqual(persistence.loadProfile(), profile)
    }

    func testProgramSurvivesARoundTrip() {
        let program = learnedProgram()
        persistence.saveProgram(program)
        XCTAssertEqual(persistence.loadProgram(), program)
    }

    func testTheStoredProfileSurvivesANewInstance() {
        let profile = learningProfile(pace: .doux)
        persistence.saveProfile(profile)
        // Une autre instance, comme après un redémarrage de l'application.
        XCTAssertEqual(UserDefaultsLearningPersistence(quran: quran, calendar: calendar).loadProfile(), profile)
    }

    func testTheStoredKeysAreStable() {
        persistence.saveProfile(learningProfile(pace: .doux))
        persistence.saveProgram(LearningProgram(items: [], generatedAt: day(0)))
        for key in keys {
            XCTAssertNotNil(UserDefaults.standard.object(forKey: key) as? Data, "clé \(key) absente")
        }
    }

    // MARK: - Contenu illisible

    func testCorruptedProfileFallsBackToEmpty() {
        for corrupted in [Data("pas du json".utf8), Data("{}".utf8), Data()] {
            UserDefaults.standard.set(corrupted, forKey: "learningProfile")
            XCTAssertFalse(persistence.loadProfile().isConfigured)
        }
    }

    func testCorruptedProgramFallsBackToEmpty() {
        for corrupted in [Data("pas du json".utf8), Data("{}".utf8), Data()] {
            UserDefaults.standard.set(corrupted, forKey: "learningProgram")
            XCTAssertTrue(persistence.loadProgram().isEmpty)
        }
    }

    // MARK: - Effacement

    func testResetClearsProfileProgramAndProgress() {
        persistence.saveProfile(learningProfile(pace: .doux))
        persistence.saveProgram(learnedProgram())
        persistence.reset()
        XCTAssertFalse(persistence.loadProfile().isConfigured)
        XCTAssertTrue(persistence.loadProgram().isEmpty)
        XCTAssertTrue(persistence.loadProgress().isEmpty)
    }

    // MARK: - Progression

    func testSavingAProgramRecordsTheProgress() {
        var program = persistence.regenerateProgram(for: learningProfile(pace: .doux), from: day(0))
        let id = program.items[0].id
        program.markLearned(id: id, at: day(0), calendar: calendar)
        persistence.saveProgram(program)

        let progress = persistence.loadProgress()
        XCTAssertEqual(progress, LearningProgress(of: program, in: quran))
        XCTAssertGreaterThan(progress.lastMemorizedVerse(inSurah: 78), 0)
    }

    func testProgressSurvivesARoundTrip() {
        let progress = LearningProgress(surahs: [
            SurahLearningProgress(
                surahId: 78,
                lastMemorizedVerse: 40,
                targetVerse: 40,
                startedAt: day(0),
                updatedAt: day(1)
            ),
            SurahLearningProgress(
                surahId: 2,
                lastMemorizedVerse: 12,
                targetVerse: 286,
                startedAt: day(0),
                updatedAt: day(2)
            ),
        ])
        persistence.saveProgress(progress)

        XCTAssertEqual(persistence.loadProgress(), progress)
        XCTAssertEqual(persistence.loadProgress().surahs.map(\.surahId), [2, 78])
    }

    /// La seule perte silencieuse que ce module puisse causer, et celle que le relevé empêche.
    ///
    /// Un objectif retiré quitte le programme : déduit du seul programme courant, son avancement
    /// disparaîtrait avec lui. Conservé à part et fusionné, il attend qu'on le rajoute.
    func testProgressSurvivesAProgramThatNoLongerCoversTheSurah() {
        var program = persistence.regenerateProgram(for: learningProfile(pace: .doux), from: day(0))
        for item in program.items.prefix(2) {
            program.markLearned(id: item.id, at: day(0), calendar: calendar)
        }
        persistence.saveProgram(program)
        let acquired = persistence.loadProgress().lastMemorizedVerse(inSurah: 78)
        XCTAssertGreaterThan(acquired, 0)

        // Le programme ne porte plus la sourate — comme après le retrait de l'objectif.
        persistence.saveProgram(LearningProgram(items: [], generatedAt: day(1)))

        XCTAssertEqual(persistence.loadProgress().lastMemorizedVerse(inSurah: 78), acquired)
    }

    func testAGoalAddedBackResumesWhereItStopped() {
        var program = persistence.regenerateProgram(for: learningProfile(pace: .doux), from: day(0))
        for item in program.items.prefix(2) {
            program.markLearned(id: item.id, at: day(0), calendar: calendar)
        }
        persistence.saveProgram(program)
        let acquired = persistence.loadProgress().lastMemorizedVerse(inSurah: 78)

        persistence.saveProgram(LearningProgram(items: [], generatedAt: day(1)))
        let regenerated = persistence.regenerateProgram(for: learningProfile(pace: .doux), from: day(2))

        XCTAssertEqual(persistence.loadProgress().lastMemorizedVerse(inSurah: 78), acquired)
        XCTAssertEqual(
            regenerated.nextToLearn()?.range.firstAyah,
            acquired + 1,
            "Le programme reprend au verset qui suit le repère, sans rien recompter"
        )
        XCTAssertEqual(regenerated.items.prefix(2).map(\.storedStatus), [.learned, .learned])
    }

    // MARK: - Régénération

    func testRegenerateSavesWhatItReturns() {
        let program = persistence.regenerateProgram(for: learningProfile(pace: .doux), from: day(0))
        XCTAssertEqual(persistence.loadProgram(), program)
        XCTAssertFalse(program.isEmpty)
    }

    func testRegenerateOmitsWhatIsDeclaredSolid() {
        let profile = learningProfile(
            pace: .doux,
            knownRanges: [KnownRange(range: goal, label: "An-Naba", solidity: .solide)]
        )
        XCTAssertTrue(persistence.regenerateProgram(for: profile, from: day(0)).isEmpty)
    }

    /// Déclarer connue une sourate qu'on a déjà commencé à apprendre.
    ///
    /// C'est le geste de la liste des sourates, et le seul endroit où la déclaration et l'acquis se
    /// rencontrent sur la même sourate : l'objectif est retranché du programme, qui devient vide,
    /// alors qu'un travail a déjà été fait. Deux choses doivent y survivre — l'avancement, et ce que
    /// la liste en lit.
    func testDeclaringAPartiallyLearnedSurahKnownKeepsWhatWasLearned() {
        var profile = learningProfile(pace: .doux)
        var program = persistence.regenerateProgram(for: profile, from: day(0))
        for item in program.items.prefix(2) {
            program.markLearned(id: item.id, at: day(0), calendar: calendar)
        }
        persistence.saveProgram(program)
        let acquired = persistence.loadProgress().lastMemorizedVerse(inSurah: 78)
        XCTAssertGreaterThan(acquired, 0)

        // Le geste : la sourate entière rejoint ce qui est connu, en solide.
        profile.knownRanges.append(KnownRange(range: goal, label: "An-Naba", solidity: .solide))
        persistence.saveProfile(profile)

        let regenerated = persistence.regenerateProgram(for: profile, from: day(2))

        // Plus rien à programmer : tout l'objectif est déclaré connu.
        XCTAssertTrue(regenerated.isEmpty)
        XCTAssertTrue(persistence.loadProgram().isEmpty)
        // Et rien de perdu : l'avancement reste dans le relevé, prêt à resservir si l'objectif
        // revenait un jour.
        XCTAssertEqual(persistence.loadProgress().lastMemorizedVerse(inSurah: 78), acquired)
        // La liste doit lire la sourate comme sue — du profil **et** du programme réunis, puisque le
        // programme, lui, ne dit plus rien d'elle.
        let coverage = LearningCoverageReport(
            profile: persistence.loadProfile(),
            program: persistence.loadProgram(),
            quran: quran
        )
        XCTAssertEqual(coverage.coverage(of: quran.suras[77]), .complete)
    }

    func testRegeneratePreservesAcquiredProgressAcrossAPaceChange() {
        var profile = learningProfile(pace: .doux)
        var program = persistence.regenerateProgram(for: profile, from: day(0))

        // L'allure « doux » vise 3 versets par séance : les cinq premières séances font 15 versets.
        for item in program.items.prefix(5) {
            program.markLearned(id: item.id, at: day(0), calendar: calendar)
        }
        persistence.saveProgram(program)
        let acquired = program.learnedVerses(in: quran)
        XCTAssertEqual(acquired, 15)

        // À l'allure « soutenu », la sourate tient en deux séances — 78:1 à 78:30, puis 78:31 à
        // 78:40 — et l'acquis de 15 versets tombe au milieu de la première. Sans reprise, le
        // programme régénéré effacerait ces 15 versets ; avec elle, il en faut trois passages.
        profile.pace = .soutenu
        let regenerated = persistence.regenerateProgram(for: profile, from: day(0))

        XCTAssertEqual(regenerated.items.count, 3)
        XCTAssertEqual(regenerated.learnedVerses(in: quran), acquired)
        XCTAssertEqual(regenerated.totalVerses(in: quran), 40)
        XCTAssertEqual(persistence.loadProgram(), regenerated)
    }

    // MARK: Private

    /// Les trois clés du module, écrites en dur : une clé renommée doit faire échouer ce test, sans
    /// quoi l'application perdrait silencieusement les données des utilisateurs déjà installés.
    private let keys = ["learningProfile", "learningProgram", "learningProgress"]

    private let quran = Quran.hafsMadani1405

    /// Calendrier figé pour des tests déterministes, quelle que soit la machine.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var originalValues: [String: Any] = [:]

    /// Une instance neuve à chaque appel : l'état vit dans les préférences, pas dans l'objet.
    private var persistence: UserDefaultsLearningPersistence {
        UserDefaultsLearningPersistence(quran: quran, calendar: calendar)
    }

    /// L'objectif de tous les profils de ce fichier : la sourate An-Naba entière, 78:1 à 78:40.
    private var goal: QuranRange {
        QuranRange(firstSura: 78, firstAyah: 1, lastSura: 78, lastAyah: 40)
    }

    /// La sourate Al-Baqara entière — de quoi éprouver un intervalle connu, sans qu'il soit un
    /// objectif.
    private var baqara: QuranRange {
        QuranRange(firstSura: 2, firstAyah: 1, lastSura: 2, lastAyah: 286)
    }

    /// Le jour `offset` après le mercredi 30 septembre 2026, midi UTC.
    private func day(_ offset: Int) -> Date {
        let reference = DateComponents(calendar: calendar, year: 2026, month: 9, day: 30, hour: 12).date!
        return calendar.date(byAdding: .day, value: offset, to: reference)!
    }

    private func learningProfile(
        pace: LearningPace,
        knownRanges: [KnownRange] = [],
        goals: [LearningGoal]? = nil
    ) -> LearningProfile {
        let resolvedGoals = goals ?? [
            LearningGoal(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                range: goal,
                label: "An-Naba",
                targetDate: day(30)
            ),
        ]
        return LearningProfile(
            knownRanges: knownRanges,
            goals: resolvedGoals,
            pace: pace,
            days: [.lundi, .mercredi, .vendredi],
            sessionMinutes: 25,
            createdAt: day(0),
            isConfigured: true
        )
    }

    /// Un programme dont le premier passage est appris et dû en révision.
    private func learnedProgram() -> LearningProgram {
        var program = LearningProgram(items: [
            LearningItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                range: QuranRange(firstSura: 78, firstAyah: 1, lastSura: 78, lastAyah: 3),
                label: "78:1-78:3",
                position: 0
            ),
        ], generatedAt: day(0))
        program.markLearned(id: program.items[0].id, at: day(0), calendar: calendar)
        return program
    }
}
