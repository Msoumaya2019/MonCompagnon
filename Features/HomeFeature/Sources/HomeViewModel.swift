//
//  HomeViewModel.swift
//
//
//  Created by Mohamed Afifi on 2023-07-16.
//

import AnnotationsService
import Combine
import Crashing
import Foundation
import LearningKit
import LearningPersistence
import NoorUI
import Preferences
import QuranAnnotations
import QuranKit
import QuranText
import QuranTextKit
import ReadingService
import VLogging

enum SurahSortOrder: Int, Codable {
    case ascending = 1
    case descending = -1
}

enum HomeViewType: Int {
    case suras
    case juzs
    /// Le hizb, soixantième partie du Coran.
    ///
    /// Il a son propre segment plutôt que d'être un sous-niveau du juz' : c'est ainsi que
    /// l'utilisateur en parle (« j'ai appris ce hizb »), et le hizb est déjà une unité de la
    /// configuration de l'apprentissage. Le montrer sous le juz' aurait densifié la liste des
    /// rubu' sans rien éclairer.
    case hizbs
}

@MainActor
final class HomeViewModel: ObservableObject {
    // MARK: Lifecycle

    #if QURAN_SYNC
    init(
        lastPageService: any LastPageService,
        textRetriever: QuranTextDataService,
        readingBookmarkService: MobileSyncReadingBookmarkService,
        learningPersistence: LearningPersistence,
        navigateToPage: @escaping (Page, LastPage?) -> Void,
        navigateToAyah: @escaping (AyahNumber) -> Void
    ) {
        self.lastPageService = lastPageService
        self.textRetriever = textRetriever
        self.readingBookmarkService = readingBookmarkService
        self.learningPersistence = learningPersistence
        reading = ReadingPreferences.shared.reading
        self.navigateToPage = navigateToPage
        self.navigateToAyah = navigateToAyah

        HomePreferences.shared.$surahSortOrder
            .assign(to: &$surahSortOrder)
        readingPreferences.$reading
            .assign(to: &$reading)
    }
    #else
    init(
        lastPageService: any LastPageService,
        textRetriever: QuranTextDataService,
        learningPersistence: LearningPersistence,
        navigateToPage: @escaping (Page, LastPage?) -> Void,
        navigateToAyah: @escaping (AyahNumber) -> Void
    ) {
        self.lastPageService = lastPageService
        self.textRetriever = textRetriever
        self.learningPersistence = learningPersistence
        reading = ReadingPreferences.shared.reading
        self.navigateToPage = navigateToPage
        self.navigateToAyah = navigateToAyah

        HomePreferences.shared.$surahSortOrder
            .assign(to: &$surahSortOrder)
        readingPreferences.$reading
            .assign(to: &$reading)
    }
    #endif

    // MARK: Internal

    @Published var suras: [Sura] = [] {
        didSet { recordListUpdate(reason: "suras_loaded") }
    }

    @Published var quarters: [QuarterItem] = [] {
        didSet { recordListUpdate(reason: "quarters_loaded") }
    }

    @Published var hizbs: [HizbItem] = [] {
        didSet { recordListUpdate(reason: "hizbs_loaded") }
    }

    /// Ce qui est appris, pour marquer chaque ligne d'une liste.
    ///
    /// **Dérivé, et non stocké** : le relevé se recalcule à partir du profil et du programme
    /// enregistrés, et rien n'est écrit. Il n'y a donc rien à migrer, et aucune seconde vérité à
    /// tenir à jour.
    @Published private(set) var coverage: LearningCoverageReport?

    @Published var lastPages: [LastPage] = [] {
        didSet { recordListUpdate(reason: "last_pages_changed") }
    }

    #if QURAN_SYNC
    @Published var readingBookmarks: [PlacedReadingBookmark] = [] {
        didSet { recordListUpdate(reason: "reading_bookmarks_changed") }
    }
    #endif

    @Published var surahSortOrder: SurahSortOrder = HomePreferences.shared.surahSortOrder {
        didSet { recordListUpdate(reason: "sort_order_changed") }
    }

    @Published var collapsedJuzs: Set<Juz> = []

    @Published var type = HomeViewType.suras {
        didSet {
            logger.info("Home: \(type) selected")
            recordListUpdate(reason: "mode_changed")
        }
    }

    @Published var reading: Reading

    func setListVisible(_ visible: Bool) {
        isListVisible = visible
        if visible {
            crashContext.setScreen("home")
            updateActiveListContext()
        } else {
            crashContext.clearActiveList(owner: "home")
        }
        logger.info("Crash context: home list visible=\(visible)")
    }

    func isJuzExpanded(_ juz: Juz) -> Bool {
        !collapsedJuzs.contains(juz)
    }

    func setJuz(_ juz: Juz, expanded: Bool) {
        if expanded {
            collapsedJuzs.remove(juz)
        } else {
            collapsedJuzs.insert(juz)
        }
        recordListUpdate(reason: "section_expansion_changed")
    }

    /// Relit l'avancement de l'apprentissage.
    ///
    /// Appelé à chaque apparition de l'écran, et non une seule fois au lancement : l'apprentissage
    /// vit dans un autre onglet, et y apprendre une sourate doit se voir sur ces listes **sans
    /// relancer l'application**. Le relevé est bon marché — il rassemble une fois les versets
    /// appris — mais il n'a pas à être refait à chaque rendu de ligne : c'est pourquoi il est lu
    /// ici et rangé, plutôt que calculé dans le corps de la vue.
    func refreshCoverage() {
        coverage = LearningCoverageReport(
            profile: learningPersistence.loadProfile(),
            program: learningPersistence.loadProgram(),
            quran: reading.quran
        )
    }

    func start() async {
        refreshCoverage()
        async let lastPages: () = loadLastPages()
        async let suras: () = loadSuras()
        async let quarters: () = loadQuarters()
        async let hizbs: () = loadHizbs()
        #if QURAN_SYNC
        async let readingBookmarks: () = loadReadingBookmarks()
        _ = await [lastPages, suras, quarters, hizbs, readingBookmarks]
        #else
        _ = await [lastPages, suras, quarters, hizbs]
        #endif
    }

    func navigateTo(_ lastPage: LastPage) {
        navigateToPage(lastPage.page, lastPage)
    }

    #if QURAN_SYNC
    func navigateTo(_ readingBookmark: PlacedReadingBookmark) {
        switch readingBookmark.placement {
        case .ayah(let ayahNumber):
            navigateToAyah(ayahNumber)
        case .page(let page):
            navigateToPage(page, nil)
        }
    }
    #endif

    func navigateTo(_ sura: Sura) {
        navigateToAyah(sura.firstVerse)
    }

    func navigateTo(_ item: QuarterItem) {
        navigateToAyah(item.quarter.firstVerse)
    }

    func navigateTo(_ item: HizbItem) {
        navigateToAyah(item.hizb.firstVerse)
    }

    func toggleSurahSortOrder() {
        HomePreferences.shared.surahSortOrder = surahSortOrder == .ascending ? .descending : .ascending
    }

    // MARK: Private

    private let lastPageService: any LastPageService
    private let textRetriever: QuranTextDataService
    private let learningPersistence: LearningPersistence
    #if QURAN_SYNC
    private let readingBookmarkService: MobileSyncReadingBookmarkService
    #endif
    private let navigateToPage: (Page, LastPage?) -> Void
    private let navigateToAyah: (AyahNumber) -> Void
    private let readingPreferences = ReadingPreferences.shared

    private func loadLastPages() async {
        let readings = readingPreferences.$reading
            .prepend(readingPreferences.reading)
            .values()
        var observationTask: Task<Void, Never>?
        defer { observationTask?.cancel() }

        for await reading in readings {
            observationTask?.cancel()
            let sequence = lastPageService.lastPages(quran: reading.quran)
            observationTask = Task { [weak self] in
                do {
                    for try await lastPages in sequence {
                        guard !Task.isCancelled else { return }
                        self?.lastPages = lastPages
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    crasher.recordError(error, reason: "Failed to load last pages")
                }
            }
        }
    }

    #if QURAN_SYNC
    private func loadReadingBookmarks() async {
        let readings = readingPreferences.$reading
            .prepend(readingPreferences.reading)
            .values()
        var observationTask: Task<Void, Never>?
        defer { observationTask?.cancel() }

        for await reading in readings {
            observationTask?.cancel()
            let sequence = readingBookmarkService.placedReadingBookmarksSequence(quran: reading.quran)
            observationTask = Task { [weak self] in
                do {
                    for try await bookmarks in sequence {
                        guard !Task.isCancelled else { return }
                        self?.readingBookmarks = PlacedReadingBookmark.sortedByDate(bookmarks)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    crasher.recordError(error, reason: "Failed to load reading bookmark")
                }
            }
        }
    }
    #endif

    private func loadSuras() async {
        let readings = readingPreferences.$reading
            .prepend(readingPreferences.reading)
            .values()

        for await reading in readings {
            crashContext.setReading(id: String(describing: reading))
            suras = reading.quran.suras
        }
    }

    private func loadQuarters() async {
        let readings = readingPreferences.$reading
            .prepend(readingPreferences.reading)
            .values()

        for await reading in readings {
            crashContext.setReading(id: String(describing: reading))
            let quarters = reading.quran.quarters
            let text = await textForFirstVerses(quarters.map(\.firstVerse))
            self.quarters = quarters.map { QuarterItem(quarter: $0, ayahText: text[$0.firstVerse] ?? "") }
        }
    }

    private func loadHizbs() async {
        let readings = readingPreferences.$reading
            .prepend(readingPreferences.reading)
            .values()

        for await reading in readings {
            crashContext.setReading(id: String(describing: reading))
            let hizbs = reading.quran.hizbs
            let text = await textForFirstVerses(hizbs.map(\.firstVerse))
            self.hizbs = hizbs.map { HizbItem(hizb: $0, ayahText: text[$0.firstVerse] ?? "") }
        }
    }

    /// Le texte du premier verset de chaque groupe, pour la ligne de liste.
    ///
    /// Les deux sortes de groupes partagent le même besoin — un repère de texte sous leur nom — et
    /// le même nettoyage : le premier verset d'un hizb comme d'un rubu' porte le signe ۞, qui n'a
    /// pas sa place dans une liste. Une seule requête, donc, et un seul nettoyage.
    private func textForFirstVerses(_ verses: [AyahNumber]) async -> [AyahNumber: QuranText] {
        do {
            let verseTexts = try await textRetriever.textForVerses(verses, translations: [])
            return cleanUpText(verseTexts)
        } catch {
            crasher.recordError(error, reason: "Failed to retrieve groups text")
            return [:]
        }
    }

    private func cleanUpText(_ verseTexts: [AyahNumber: VerseText]) -> [AyahNumber: QuranText] {
        let quarterStart = "۞" // Hizb marker
        return verseTexts.mapValues {
            QuranText($0.arabicText.text.replacingOccurrences(of: quarterStart, with: ""))
        }
    }

    private var isListVisible = false
    private var listGeneration = 0
    private var recordedRowCount = 0

    private var listMode: String {
        switch type {
        case .suras: "suras"
        case .juzs: "juzs"
        case .hizbs: "hizbs"
        }
    }

    private var hasContinueReadingSection: Bool {
        #if QURAN_SYNC
        !lastPages.isEmpty || !readingBookmarks.isEmpty
        #else
        !lastPages.isEmpty
        #endif
    }

    private var listRowCount: Int {
        var count = lastPages.isEmpty ? 0 : 1
        #if QURAN_SYNC
        count += readingBookmarks.count + (readingBookmarks.count > 1 ? 1 : 0)
        #endif
        switch type {
        case .suras:
            count += suras.count
        case .juzs:
            count += quarters.count
        case .hizbs:
            count += hizbs.count
        }
        return count
    }

    private var listSectionCount: Int {
        var count = hasContinueReadingSection ? 1 : 0
        switch type {
        case .suras:
            count += Set(suras.map(\.page.startJuz)).count
        case .juzs:
            count += Set(quarters.map(\.quarter.juz)).count
        case .hizbs:
            count += Set(hizbs.map(\.hizb.juz)).count
        }
        return count
    }

    private func recordListUpdate(reason: String) {
        let rowsBefore = recordedRowCount
        let rowsAfter = listRowCount
        listGeneration += 1
        recordedRowCount = rowsAfter
        crashContext.recordListUpdate(
            owner: "home",
            reason: reason,
            rowsBefore: rowsBefore,
            rowsAfter: rowsAfter,
            generation: listGeneration
        )
        if isListVisible {
            updateActiveListContext()
        }
        logger.info(
            "Crash context: list update owner=home reason=\(reason) mode=\(listMode) generation=\(listGeneration) rows=\(rowsBefore)->\(rowsAfter) sections=\(listSectionCount)"
        )
    }

    private func updateActiveListContext() {
        crashContext.setActiveList(
            owner: "home",
            mode: listMode,
            generation: listGeneration,
            sectionCount: listSectionCount,
            rowCount: listRowCount
        )
    }
}
