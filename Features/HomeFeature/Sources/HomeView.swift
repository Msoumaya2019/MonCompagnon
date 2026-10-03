//
//  HomeView.swift
//
//
//  Created by Mohamed Afifi on 2023-07-16.
//

import FeaturesSupport
import LearningKit
import Localization
import NoorUI
import QuranAnnotations
import QuranKit
import QuranLocalization
import QuranText
import SwiftUI
import UIx

struct HomeView: View {
    @StateObject var viewModel: HomeViewModel

    var body: some View {
        #if QURAN_SYNC
        HomeViewUI(
            type: viewModel.type,
            readingBookmarks: viewModel.readingBookmarks,
            lastPages: viewModel.lastPages,
            suras: viewModel.suras,
            quarters: viewModel.quarters,
            hizbs: viewModel.hizbs,
            coverage: viewModel.coverage,
            quranFont: viewModel.reading.quranFont,
            start: { await viewModel.start() },
            selectReadingBookmark: { viewModel.navigateTo($0) },
            selectLastPage: { viewModel.navigateTo($0) },
            selectSura: { viewModel.navigateTo($0) },
            selectQuarter: { viewModel.navigateTo($0) },
            selectHizb: { viewModel.navigateTo($0) },
            markSuraAsKnown: { viewModel.markAsKnown($0, label: $0.localizedName()) },
            markQuarterAsKnown: { viewModel.markAsKnown($0.quarter, label: $0.quarter.localizedName) },
            markHizbAsKnown: { viewModel.markAsKnown($0.hizb, label: $0.hizb.localizedName) },
            surahSortOrder: viewModel.surahSortOrder,
            isJuzExpanded: { viewModel.isJuzExpanded($0) },
            setJuzExpanded: { viewModel.setJuz($0, expanded: $1) }
        )
        #else
        HomeViewUI(
            type: viewModel.type,
            lastPages: viewModel.lastPages,
            suras: viewModel.suras,
            quarters: viewModel.quarters,
            hizbs: viewModel.hizbs,
            coverage: viewModel.coverage,
            quranFont: viewModel.reading.quranFont,
            start: { await viewModel.start() },
            selectLastPage: { viewModel.navigateTo($0) },
            selectSura: { viewModel.navigateTo($0) },
            selectQuarter: { viewModel.navigateTo($0) },
            selectHizb: { viewModel.navigateTo($0) },
            markSuraAsKnown: { viewModel.markAsKnown($0, label: $0.localizedName()) },
            markQuarterAsKnown: { viewModel.markAsKnown($0.quarter, label: $0.quarter.localizedName) },
            markHizbAsKnown: { viewModel.markAsKnown($0.hizb, label: $0.hizb.localizedName) },
            surahSortOrder: viewModel.surahSortOrder,
            isJuzExpanded: { viewModel.isJuzExpanded($0) },
            setJuzExpanded: { viewModel.setJuz($0, expanded: $1) }
        )
        #endif
    }
}

private struct HomeViewUI: View {
    let type: HomeViewType
    #if QURAN_SYNC
    let readingBookmarks: [PlacedReadingBookmark]
    #endif
    let lastPages: [LastPage]
    let suras: [Sura]
    let quarters: [QuarterItem]
    let hizbs: [HizbItem]
    /// Ce qui est appris. `nil` tant que le relevé n'a pas été fait : une ligne ne doit alors rien
    /// affirmer sur l'avancement, plutôt que d'affirmer qu'il n'y en a aucun.
    let coverage: LearningCoverageReport?
    let quranFont: QuranFont

    let start: AsyncAction

    #if QURAN_SYNC
    let selectReadingBookmark: ItemAction<PlacedReadingBookmark>
    #endif
    let selectLastPage: ItemAction<LastPage>
    let selectSura: ItemAction<Sura>
    let selectQuarter: ItemAction<QuarterItem>
    let selectHizb: ItemAction<HizbItem>
    let markSuraAsKnown: ItemAction<Sura>
    let markQuarterAsKnown: ItemAction<QuarterItem>
    let markHizbAsKnown: ItemAction<HizbItem>
    let surahSortOrder: SurahSortOrder
    let isJuzExpanded: (Juz) -> Bool
    let setJuzExpanded: (Juz, Bool) -> Void

    /// La déclaration en attente de confirmation, ou `nil`.
    ///
    /// L'état vit ici, et non dans le modèle de vue : c'est une affaire d'écran, et le magasin ne
    /// doit rien savoir d'une intention qu'on peut encore annuler.
    @State private var pendingKnown: PendingKnown? = nil

    var body: some View {
        ZStack {
            NoorList {
                #if QURAN_SYNC
                ContinueReadingSection(
                    title: l("home.continue-reading.title"),
                    readingBookmarks: readingBookmarks,
                    lastPages: lastPages,
                    selectReadingBookmark: selectReadingBookmark,
                    selectLastPage: selectLastPage
                )
                #else
                ContinueReadingSection(title: l("home.continue-reading.title"), lastPages: lastPages, selectLastPage: selectLastPage)
                #endif

                switch type {
                case .suras:
                    sectionsView(items: suras, groupBy: \.page.startJuz) { sura in
                        suraView(sura)
                    }
                case .juzs:
                    sectionsView(items: quarters, groupBy: \.quarter.juz) { quarter in
                        quarterView(quarter)
                    }
                case .hizbs:
                    sectionsView(items: hizbs, groupBy: \.hizb.juz) { hizb in
                        hizbView(hizb)
                    }
                }
            }
            // iOS 15's SwiftUI List produces invalid UITableView batch updates when
            // every section and row moves at once. Replace the list snapshot instead.
            .id(surahSortOrder.rawValue)
        }
        .task { await start() }
        .alert(
            l("learning.known.mark.title", table: .learning),
            isPresented: isConfirmingKnown,
            presenting: pendingKnown
        ) { pending in
            Button(l("learning.known.mark.confirm", table: .learning)) {
                pending.confirm()
                pendingKnown = nil
            }
            Button(lAndroid("cancel"), role: .cancel) {
                pendingKnown = nil
            }
        } message: { pending in
            Text(lFormat("learning.known.mark.message", table: .learning, pending.groupName, pending.verseCount))
        }
    }

    /// La confirmation ouverte, vue comme un booléen.
    ///
    /// C'est la forme qu'attend `alert(isPresented:)`, et le seul endroit où l'on remet l'intention
    /// à zéro : fermer l'alerte — par un bouton ou autrement — annule la déclaration.
    private var isConfirmingKnown: Binding<Bool> {
        Binding(
            get: { pendingKnown != nil },
            set: { if !$0 { pendingKnown = nil } }
        )
    }

    func suraView(_ sura: Sura) -> some View {
        let ayahsString = lFormat("verses", table: .android, sura.verses.count)
        let suraType = sura.isMakki ? lAndroid("makki") : lAndroid("madani")
        var subtitleComponents = [suraType, ayahsString]
        if !Locale.preferredLanguageLocale.isArabicLanguage {
            subtitleComponents.insert(sura.localizedTranslatedName(), at: 0)
        }
        let style = LearningCoverageStyle(report: coverage, group: sura)
        if let label = style?.label {
            subtitleComponents.append(label)
        }
        let subtitle = subtitleComponents.joined(separator: " · ")

        return markable(
            NoorListItem(
                leadingEdgeLineColor: style?.edgeColor,
                title: "\(sura.localizedSuraNumber). \(sura: sura)",
                subtitle: .init(text: .text(subtitle), location: .bottom),
                accessory: .text(sura.page.localizedNumber, accessibilityLabel: sura.page.localizedName),
                action: .sync { selectSura(sura) }
            ),
            group: sura,
            name: sura.localizedName(),
            apply: { markSuraAsKnown(sura) }
        )
    }

    func quarterView(_ item: QuarterItem) -> some View {
        let quarter = item.quarter
        let ayah = quarter.firstVerse
        let page = ayah.page
        let style = LearningCoverageStyle(report: coverage, group: quarter)

        return markable(
            NoorListItem(
                leadingEdgeLineColor: style?.edgeColor,
                subheading: .text(quarter.localizedName),
                title: "\(ayah: ayah)",
                rightSubtitle: "\(quran: item.ayahText, font: quranFont, lineLimit: 1)",
                subtitle: style.map { NoorListItem.Subtitle(text: .text($0.label), location: .bottom) },
                accessory: .text(page.localizedNumber, accessibilityLabel: page.localizedName),
                action: .sync { selectQuarter(item) }
            ),
            group: quarter,
            name: quarter.localizedName,
            apply: { markQuarterAsKnown(item) }
        )
    }

    /// La ligne d'un hizb : même forme que celle d'un rubu'.
    ///
    /// Les deux groupes sont des plages de versets du même genre, et les montrer différemment
    /// n'apprendrait rien à l'utilisateur. Seul le sous-titre change — « Hizb 12 » au lieu de
    /// « Hizb 12 نصف » — parce que c'est le nom du groupe lui-même.
    func hizbView(_ item: HizbItem) -> some View {
        let hizb = item.hizb
        let ayah = hizb.firstVerse
        let page = ayah.page
        let style = LearningCoverageStyle(report: coverage, group: hizb)

        return markable(
            NoorListItem(
                leadingEdgeLineColor: style?.edgeColor,
                subheading: .text(hizb.localizedName),
                title: "\(ayah: ayah)",
                rightSubtitle: "\(quran: item.ayahText, font: quranFont, lineLimit: 1)",
                subtitle: style.map { NoorListItem.Subtitle(text: .text($0.label), location: .bottom) },
                accessory: .text(page.localizedNumber, accessibilityLabel: page.localizedName),
                action: .sync { selectHizb(item) }
            ),
            group: hizb,
            name: hizb.localizedName,
            apply: { markHizbAsKnown(item) }
        )
    }

    /// La ligne, augmentée du geste qui déclare son groupe connu.
    ///
    /// Le menu contextuel est ce qui rend le geste **découvrable** : rien, sur la ligne, ne dirait
    /// autrement qu'on peut la cocher. C'est aussi le seul appui long que SwiftUI gère sans entrer
    /// en conflit avec le défilement de la liste — un `onLongPressGesture` posé sur une ligne le
    /// fait. **Premier emploi dans l'application** : le dépôt n'avait jusqu'ici aucun menu
    /// contextuel.
    ///
    /// Le geste n'est posé que s'il a quelque chose à faire. Un groupe déjà su en entier n'a rien à
    /// rejoindre : proposer « marquer comme connue » pour ne rien faire ensuite serait un mensonge,
    /// et coûterait une confirmation pour rien.
    ///
    /// **Limite assumée.** Un groupe su en entier par le programme, mais encore en révision, porte
    /// l'état `.complete` : le geste ne lui est donc pas offert. C'est voulu — le geste dit « je la
    /// connais », pas « cessez de me la faire réviser », qui est une autre décision et se prend dans
    /// les réglages de l'apprentissage. L'état, lui, ignore délibérément les échéances : il dit ce
    /// qu'on sait, jamais ce qu'on doit.
    @ViewBuilder
    func markable<Row: View>(
        _ row: Row,
        group: some QuranGroup,
        name: String,
        apply: @escaping Action
    ) -> some View {
        if let report = coverage, report.coverage(of: group) == .complete {
            row
        } else {
            row.contextMenu {
                Button {
                    pendingKnown = PendingKnown(
                        groupName: name,
                        verseCount: group.verses.count,
                        confirm: apply
                    )
                } label: {
                    Label(l("learning.known.mark", table: .learning), systemImage: "checkmark.circle")
                }
            }
        }
    }

    @ViewBuilder
    func sectionsView<Item: Identifiable>(
        items: [Item],
        groupBy: (Item) -> Juz,
        @ViewBuilder listItem: @escaping (Item) -> some View
    ) -> some View {
        let itemsByJuz = Dictionary(grouping: items, by: groupBy)
        let juzs = itemsByJuz.keys.sorted {
            surahSortOrder.rawValue * ($0.juzNumber - $1.juzNumber) < 0
        }

        ForEach(juzs) { juz in
            let items = (itemsByJuz[juz] ?? []).sorted {
                switch ($0, $1) {
                case let (thisSura as Sura, thatSura as Sura):
                    surahSortOrder.rawValue * (thisSura.suraNumber - thatSura.suraNumber) < 0
                case let (thisQuarter as QuarterItem, thatQuarter as QuarterItem):
                    surahSortOrder.rawValue * (thisQuarter.quarter.quarterNumber - thatQuarter.quarter.quarterNumber) < 0
                case let (thisHizb as HizbItem, thatHizb as HizbItem):
                    surahSortOrder.rawValue * (thisHizb.hizb.hizbNumber - thatHizb.hizb.hizbNumber) < 0
                default:
                    false
                }
            }
            let isExpanded = Binding(
                get: { isJuzExpanded(juz) },
                set: { setJuzExpanded(juz, $0) }
            )
            NoorSection(title: juz.localizedName, isExpanded: isExpanded, items) { item in
                listItem(item)
            }
        }
    }
}

/// Une déclaration de groupe connu, en attente de confirmation.
///
/// La confirmation n'est pas une politesse. Déclarer un groupe connu ajoute un acquis au profil
/// puis refait **tous** les passages : c'est l'opération la plus lourde du module, et la seule qui
/// retire des passages du programme. L'intention est donc rangée ici, avec de quoi l'annoncer, tant
/// que l'utilisateur n'a pas tranché.
///
/// Elle vit dans la vue, et non dans le modèle de vue : le magasin ne doit rien savoir d'une
/// intention qu'on peut encore annuler.
private struct PendingKnown {
    let groupName: String
    let verseCount: Int
    let confirm: Action
}

@MainActor
private struct HomePreview: View {
    static let ayahText: QuranText = "وَإِذۡ قَالَ مُوسَىٰ لِقَوۡمِهِۦ يَٰقَوۡمِ إِنَّكُمۡ ظَلَمۡتُمۡ أَنفُسَكُم بِٱتِّخَاذِكُمُ ٱلۡعِجۡلَ فَتُوبُوٓاْ إِلَىٰ بَارِئِكُمۡ فَٱقۡتُلُوٓاْ أَنفُسَكُمۡ ذَٰلِكُمۡ خَيۡرٞ لَّكُمۡ عِندَ بَارِئِكُمۡ فَتَابَ عَلَيۡكُمۡۚ إِنَّهُۥ هُوَ ٱلتَّوَّابُ ٱلرَّحِيمُ"

    /// Un relevé de démonstration, pour que la maquette montre les **trois** états : Al-Fâtiha sue
    /// en entier, le début d'Al-Baqarah sue à moitié, tout le reste inconnu.
    static var previewCoverage: LearningCoverageReport {
        LearningCoverageReport(
            profile: LearningProfile(knownRanges: [
                KnownRange(
                    range: QuranRange(firstSura: 1, firstAyah: 1, lastSura: 1, lastAyah: 7),
                    label: nil,
                    solidity: .solide
                ),
                KnownRange(
                    range: QuranRange(firstSura: 2, firstAyah: 1, lastSura: 2, lastAyah: 100),
                    label: nil,
                    solidity: .fragile
                ),
            ]),
            program: LearningProgram()
        )
    }

    static var staticLastPages: [LastPage] {
        let pages = [0, 4, 49, 76, 105, 127, 150, 176, 200, 221].map { Quran.hafsMadani1405.pages[$0] }
        return (0 ..< pages.count).map { i -> LastPage in
            let timestamp = Date(timeIntervalSinceNow: -Double(i * 31 + 1) * 60)
            #if QURAN_SYNC
            return LastPage(
                id: "preview-\(i)",
                page: pages[i],
                modifiedOn: timestamp
            )
            #else
            return LastPage(
                page: pages[i],
                createdOn: timestamp,
                modifiedOn: timestamp
            )
            #endif
        }
    }

    let quran = Quran.hafsMadani1405

    @State var lastPages: [LastPage] = staticLastPages
    #if QURAN_SYNC
    @State var readingBookmarks: [PlacedReadingBookmark] = [
        PlacedReadingBookmark(
            id: "preview-orange", slot: .orange,
            placement: .ayah(Quran.hafsMadani1405.suras[0].verses[5]),
            modifiedOn: Date(timeIntervalSinceNow: -36000)
        ),
        PlacedReadingBookmark(
            id: "preview-teal", slot: .teal,
            placement: .page(Quran.hafsMadani1405.pages[22]),
            modifiedOn: Date(timeIntervalSinceNow: -86400)
        ),
        PlacedReadingBookmark(
            id: "preview-red", slot: .red,
            placement: .ayah(Quran.hafsMadani1405.suras[35].verses[57]),
            modifiedOn: Date(timeIntervalSinceNow: -259_200)
        ),
    ]
    #endif
    @State var type: HomeViewType = .suras
    @State var collapsedJuzs: Set<Juz> = []

    var body: some View {
        NavigationView {
            Group {
                #if QURAN_SYNC
                HomeViewUI(
                    type: type,
                    readingBookmarks: readingBookmarks,
                    lastPages: lastPages,
                    suras: quran.suras,
                    quarters: quran.quarters.map { QuarterItem(quarter: $0, ayahText: Self.ayahText) },
                    hizbs: quran.hizbs.map { HizbItem(hizb: $0, ayahText: Self.ayahText) },
                    coverage: Self.previewCoverage,
                    quranFont: .uthmanicHafs,
                    start: {},
                    selectReadingBookmark: { _ in },
                    selectLastPage: { _ in },
                    selectSura: { _ in },
                    selectQuarter: { _ in },
                    selectHizb: { _ in },
                    markSuraAsKnown: { _ in },
                    markQuarterAsKnown: { _ in },
                    markHizbAsKnown: { _ in },
                    surahSortOrder: .ascending,
                    isJuzExpanded: { !collapsedJuzs.contains($0) },
                    setJuzExpanded: { juz, expanded in
                        if expanded { collapsedJuzs.remove(juz) } else { collapsedJuzs.insert(juz) }
                    }
                )
                #else
                HomeViewUI(
                    type: type,
                    lastPages: lastPages,
                    suras: quran.suras,
                    quarters: quran.quarters.map { QuarterItem(quarter: $0, ayahText: Self.ayahText) },
                    hizbs: quran.hizbs.map { HizbItem(hizb: $0, ayahText: Self.ayahText) },
                    coverage: Self.previewCoverage,
                    quranFont: .uthmanicHafs,
                    start: {},
                    selectLastPage: { _ in },
                    selectSura: { _ in },
                    selectQuarter: { _ in },
                    selectHizb: { _ in },
                    markSuraAsKnown: { _ in },
                    markQuarterAsKnown: { _ in },
                    markHizbAsKnown: { _ in },
                    surahSortOrder: .ascending,
                    isJuzExpanded: { !collapsedJuzs.contains($0) },
                    setJuzExpanded: { juz, expanded in
                        if expanded { collapsedJuzs.remove(juz) } else { collapsedJuzs.insert(juz) }
                    }
                )
                #endif
            }
            .navigationTitle("Home")
            .toolbar {
                if type == .suras {
                    Button("Juzs") { type = .juzs }
                } else {
                    Button("Suras") { type = .suras }
                }

                if lastPages.isEmpty {
                    Button("Populate Last Pages") { lastPages = Self.staticLastPages }
                } else {
                    Button("Empty") { lastPages = [] }
                }
            }
        }
    }
}

#Preview {
    HomePreview()
}
