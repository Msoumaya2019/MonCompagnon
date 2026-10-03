//
//  HomeViewController.swift
//
//
//  Created by Mohamed Afifi on 2023-07-16.
//

import Localization
import ReadingSelectorFeature
import SwiftUI
import UIx

final class HomeViewController: UIHostingController<HomeView> {
    // MARK: Lifecycle

    init(
        viewModel: HomeViewModel,
        readingSelectorBuilder: ReadingSelectorBuilder,
        makeSearch: @escaping @MainActor () -> UIViewController?
    ) {
        self.viewModel = viewModel
        self.readingSelectorBuilder = readingSelectorBuilder
        self.makeSearch = makeSearch
        super.init(rootView: HomeView(viewModel: viewModel))

        initialize()
    }

    @available(*, unavailable)
    @MainActor
    dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.setListVisible(true)
        // L'apprentissage vit dans un autre onglet : revenir ici doit montrer ce qu'on y a appris,
        // sans avoir à relancer l'application.
        viewModel.refreshCoverage()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.setListVisible(false)
    }

    // MARK: Private

    private let viewModel: HomeViewModel
    private let readingSelectorBuilder: ReadingSelectorBuilder
    /// Construit l'écran de recherche. C'est une fabrique, et non l'écran : il ne doit être
    /// construit qu'au moment où on l'ouvre, et il a besoin du navigateur du Coran, que seul
    /// l'onglet détient.
    private let makeSearch: @MainActor () -> UIViewController?
    private lazy var segmentedControl = UISegmentedControl(frame: .zero)

    private func initialize() {
        configureSegmentedControl()
        configureNavigationBarButtons()
    }

    private func configureSegmentedControl() {
        segmentedControl.insertSegment(withTitle: lAndroid("quran_sura"), at: 0, animated: false)
        segmentedControl.insertSegment(withTitle: lAndroid("quran_juz2"), at: 1, animated: false)
        segmentedControl.insertSegment(withTitle: lAndroid("quran_hizb"), at: 2, animated: false)
        segmentedControl.selectedSegmentIndex = viewModel.type.rawValue
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        navigationItem.titleView = segmentedControl
        padSegments()
        segmentChanged()
    }

    /// Widens every segment beyond its fitted title so the titles don't hug the control's border.
    /// The padding is fixed because segment titles don't scale with Dynamic Type.
    private func padSegments() {
        let horizontalPadding: CGFloat = 12
        let segments = 0 ..< segmentedControl.numberOfSegments
        let fittedWidth = segmentedControl.sizeThatFits(UIView.layoutFittingCompressedSize).width
        let segmentWidth = fittedWidth / CGFloat(segments.count) + 2 * horizontalPadding
        for segment in segments {
            segmentedControl.setWidth(segmentWidth, forSegmentAt: segment)
        }
        segmentedControl.sizeToFit()
    }

    private func configureNavigationBarButtons() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage.symbol("books.vertical.fill"),
                style: .plain,
                target: self,
                action: #selector(openReadingSelectors)
            ),
            UIBarButtonItem(
                image: UIImage.symbol("magnifyingglass"),
                style: .plain,
                target: self,
                action: #selector(openSearch)
            ),
        ]

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage.symbol("arrow.up.arrow.down"),
            style: .plain,
            target: self,
            action: #selector(toggleSort)
        )
    }

    @objc
    private func toggleSort() {
        viewModel.toggleSurahSortOrder()
    }

    @objc
    private func openReadingSelectors() {
        let readingSelector = readingSelectorBuilder.build()
        navigationController?.pushViewController(readingSelector, animated: true)
    }

    /// Ouvre la recherche depuis l'en-tête.
    ///
    /// Elle n'a plus d'onglet — l'apprentissage a pris sa place dans la barre — mais garde son
    /// écran : c'est la loupe qui l'ouvre désormais, dans la pile de l'accueil.
    @objc
    private func openSearch() {
        guard let search = makeSearch() else {
            return
        }
        navigationController?.pushViewController(search, animated: true)
    }

    @objc
    private func segmentChanged() {
        let type = HomeViewType(rawValue: segmentedControl.selectedSegmentIndex) ?? .suras
        switch type {
        case .suras:
            navigationItem.title = lAndroid("quran_sura")
        case .juzs:
            navigationItem.title = lAndroid("quran_juz2")
        case .hizbs:
            navigationItem.title = lAndroid("quran_hizb")
        }
        viewModel.type = type
    }
}
