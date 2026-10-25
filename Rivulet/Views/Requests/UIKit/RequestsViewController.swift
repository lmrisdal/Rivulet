// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  RequestsViewController.swift
//  Rivulet
//
//  The Requests tab: a list of what is downloading now, then a grid of Seerr
//  requests still waiting, then a grid of requests now available (History).
//  Refreshes while it is on screen. Select opens the title's detail page.
//

import UIKit

@MainActor
final class RequestsViewController: UIViewController {
    private nonisolated enum Section: Hashable, Sendable { case downloading, requests, history

        var title: String {
            switch self {
            case .downloading: return "Downloading"
            case .requests: return "Requests"
            case .history: return "History"
            }
        }

        var isList: Bool { self == .downloading }
    }

    private nonisolated struct Item: Hashable, Sendable {
        let section: Section
        let id: String
    }

    private static let headerKind = "RequestsHeader"
    private static let columns = MediaRowMetrics.posterFullCount
    private static let downloadsInterval: Duration = .seconds(5)
    private static let requestsInterval: TimeInterval = 30

    private let feed = RequestsFeed()
    private var tiles: [Item: RequestTile] = [:]
    private var sectionOrder: [Section] = []
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var dataSource = makeDataSource()
    private let stateView = HomeStateView()
    /// Holds focus while the first load runs, so Menu still reaches this tab.
    private let loadingAnchor = PreviewFocusAnchorView()
    private var pollTask: Task<Void, Never>?
    private var lastRequestsLoad: Date?
    private var focusTarget: IndexPath?
    private var postedBelowTop = false

    // MARK: - View

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset.bottom = MediaRowMetrics.rowLeading
        collectionView.delegate = self
        collectionView.register(RequestTileCell.self, forCellWithReuseIdentifier: RequestTileCell.reuseID)
        collectionView.register(RequestDownloadRowCell.self,
                                forCellWithReuseIdentifier: RequestDownloadRowCell.reuseID)
        collectionView.register(RequestsHeaderView.self, forSupplementaryViewOfKind: Self.headerKind,
                                withReuseIdentifier: Self.headerKind)
        collectionView.dataSource = dataSource
        view.addSubview(collectionView)

        stateView.frame = view.bounds
        stateView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        stateView.onAction = { [weak self] in self?.reload(includeRequests: true) }
        view.addSubview(stateView)
        view.addSubview(loadingAnchor)
        updateState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startPolling()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pollTask?.cancel()
        pollTask = nil
    }

    private func makeLayout() -> UICollectionViewLayout {
        let tile = MediaRowMetrics.poster
        let size = RequestTileCell.size
        return UICollectionViewCompositionalLayout { [weak self] index, _ in
            let isList = self?.sectionOrder[safe: index]?.isList ?? false
            let section: NSCollectionLayoutSection
            if isList {
                let height = RequestDownloadRowCell.height
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1), heightDimension: .absolute(height)))
                let group = NSCollectionLayoutGroup.vertical(
                    layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                                       heightDimension: .absolute(height)),
                    subitems: [item])
                section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(
                    top: 0, leading: MediaRowMetrics.rowLeading, bottom: 40, trailing: MediaRowMetrics.rowLeading)
            } else {
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                    widthDimension: .absolute(size.width), heightDimension: .absolute(size.height)))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                                       heightDimension: .absolute(size.height)),
                    subitems: [item])
                group.interItemSpacing = .fixed(tile.gap)
                section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = tile.gap
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: tile.leading, bottom: 40,
                                                                trailing: tile.leading)
            }
            section.contentInsetsReference = .none
            section.supplementariesFollowContentInsets = false
            let height = index == 0 ? RequestsHeaderView.firstHeight : RequestsHeaderView.height
            section.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                                   heightDimension: .absolute(height)),
                elementKind: Self.headerKind, alignment: .top)]
            return section
        }
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Item> {
        let dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            let tile = self?.tiles[item]
            if item.section.isList {
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: RequestDownloadRowCell.reuseID, for: indexPath) as! RequestDownloadRowCell
                if let tile { cell.configure(tile) }
                return cell
            }
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RequestTileCell.reuseID,
                                                          for: indexPath) as! RequestTileCell
            if let tile { cell.configure(tile) }
            return cell
        }
        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind, withReuseIdentifier: Self.headerKind, for: indexPath) as! RequestsHeaderView
            let section = self?.sectionOrder[safe: indexPath.section]
            header.configure(title: section?.title)
            return header
        }
        return dataSource
    }

    // MARK: - Data

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let requestsDue = self.lastRequestsLoad.map {
                    Date().timeIntervalSince($0) >= Self.requestsInterval
                } ?? true
                await self.load(includeRequests: requestsDue)
                try? await Task.sleep(for: Self.downloadsInterval)
            }
        }
    }

    private func reload(includeRequests: Bool) {
        Task { await load(includeRequests: includeRequests) }
    }

    private func load(includeRequests: Bool) async {
        if includeRequests { lastRequestsLoad = Date() }
        await feed.load(includeRequests: includeRequests)
        guard !Task.isCancelled else { return }
        apply()
    }

    private func apply() {
        let wasEmpty = tiles.isEmpty
        var next: [Item: RequestTile] = [:]
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        var order: [Section] = []
        for (section, sectionTiles) in [(Section.downloading, feed.downloads), (.requests, feed.requests),
                                         (.history, feed.history)]
        where !sectionTiles.isEmpty {
            order.append(section)
            snapshot.appendSections([section])
            let items = sectionTiles.map { Item(section: section, id: $0.id) }
            snapshot.appendItems(items, toSection: section)
            for (item, tile) in zip(items, sectionTiles) { next[item] = tile }
        }
        let changed = next.compactMap { item, tile in tiles[item].map { $0 == tile ? nil : item } ?? nil }
        snapshot.reconfigureItems(changed)
        let sectionsChanged = order != sectionOrder
        tiles = next
        sectionOrder = order
        // The layout picks list or grid by `sectionOrder`, so it must be rebuilt before the diff lands.
        if sectionsChanged { collectionView.collectionViewLayout.invalidateLayout() }
        dataSource.apply(snapshot, animatingDifferences: !wasEmpty)
        // Headers read `sectionOrder`, which the diff does not see.
        if sectionsChanged, !wasEmpty { refreshHeaders() }
        updateState()
        if wasEmpty, !tiles.isEmpty {
            setNeedsFocusUpdate()
            NotificationCenter.default.post(name: .contentBecameFocusable, object: nil)
        }
    }

    private func refreshHeaders() {
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: Self.headerKind) {
            guard let header = collectionView.supplementaryView(forElementKind: Self.headerKind, at: indexPath)
                    as? RequestsHeaderView else { continue }
            header.configure(title: sectionOrder[safe: indexPath.section]?.title)
        }
        collectionView.collectionViewLayout.invalidateLayout()
    }

    private func updateState() {
        let kind: HomeStateView.Kind?
        if !tiles.isEmpty {
            kind = nil
        } else if !feed.hasLoaded {
            kind = .loading
        } else if let failure = feed.failure {
            kind = .error(message: failure)
        } else {
            kind = .empty(message: "Nothing is requested or downloading.")
        }
        if let kind { stateView.configure(kind: kind) }
        stateView.isHidden = kind == nil
        collectionView.isHidden = kind != nil
        loadingAnchor.isHidden = feed.hasLoaded || !tiles.isEmpty
    }

    // MARK: - Focus

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if !loadingAnchor.isHidden { return [loadingAnchor] }
        return [stateView.isHidden ? collectionView : stateView]
    }

    // MARK: - Detail

    private func openDetail(_ tile: RequestTile) {
        guard let tmdbID = tile.tmdbID else { return }
        let listItem = TMDBListItem(
            id: tmdbID, title: tile.title, overview: tile.overview, posterPath: tile.posterPath,
            backdropPath: tile.backdropPath, releaseDate: tile.releaseDate, voteAverage: tile.voteAverage,
            mediaType: tile.type == .movie ? .movie : .tv)
        let tmdbItem = TMDBMediaMapper.item(listItem)
        Task { @MainActor [weak self] in
            var item = await LibraryItemResolver.libraryItem(for: tmdbItem)
            // A title that just arrived may not be in the library index yet,
            // and Jellyfin copies never are: ask the servers directly.
            if item == nil, tile.isAvailable {
                item = await LibraryArrivalFinder.find(
                    tmdbID: tmdbID, type: tile.type, title: tile.title, year: tmdbItem.year,
                    plexRatingKey: tile.plexRatingKey, jellyfinItemID: tile.jellyfinItemID)
            }
            self?.presentDetail(item ?? tmdbItem)
        }
    }

    private func presentDetail(_ item: MediaItem) {
        let detail = PreviewCarouselViewController(
            items: [item],
            selectedIndex: 0,
            sourceFrame: .zero,
            sourceTarget: nil,
            standaloneDetail: true,
            onDismiss: { [weak self] _ in self?.reload(includeRequests: true) })
        var top: UIViewController = self
        while let presented = top.presentedViewController { top = presented }
        top.present(detail, animated: true)
    }
}

// MARK: - UICollectionViewDelegate

extension RequestsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath), let tile = tiles[item] else { return }
        openDetail(tile)
    }

    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        // Only a path whose cell exists right now can take focus.
        focusTarget.flatMap { collectionView.cellForItem(at: $0) == nil ? nil : $0 }
    }

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                        with coordinator: UIFocusAnimationCoordinator) {
        let next = context.nextFocusedIndexPath
        if let next { focusTarget = next }
        if next == nil {
            for case let cell as RequestTileCell in collectionView.visibleCells { cell.resetStaleFocusAppearance() }
        }
        // Below the top row the shell hides its pill; off the page it shows again.
        let belowTop = next.map { path in
            let firstRow = sectionOrder[safe: path.section]?.isList == true ? 1 : Self.columns
            return path.section != 0 || path.item >= firstRow
        } ?? false
        if belowTop != postedBelowTop {
            postedBelowTop = belowTop
            NotificationCenter.default.post(name: .contentFocusBelowTopChanged, object: belowTop)
        }
    }
}

// MARK: - Header

/// A section title on the content margin. The first one clears the shell's pill.
private final class RequestsHeaderView: UICollectionReusableView {
    static let height: CGFloat = 80
    static let firstHeight = ShellPillMetrics.contentClearance + height
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 38, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MediaRowMetrics.rowLeading),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -MediaRowMetrics.rowTrailing),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String?) {
        label.text = title
    }
}
