// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  RequestDownloadRowCell.swift
//  Rivulet
//
//  One row of the Requests page's download list: a small poster, the title,
//  what is downloading and its state, the percentage and time left, and a
//  progress bar across the text column. The focused row sits on the Music
//  pages' glass platter.
//

import UIKit

@MainActor
final class RequestDownloadRowCell: UICollectionViewCell {
    static let reuseID = "RequestDownloadRowCell"
    static let height: CGFloat = 160
    /// How far the focus platter reaches past the column on each side.
    static let platterOutset: CGFloat = 28

    private static let thumbSize = CGSize(width: 80, height: 120)

    private let platter = MusicFocusPlatterView()
    private let thumb = UIImageView()
    private let title = MusicChrome.label(size: 31, weight: .semibold)
    private let detail = MusicChrome.label(size: 27, weight: .regular)
    private let percent = MusicChrome.label(size: 31, weight: .semibold)
    private let timeLeft = MusicChrome.label(size: 27, weight: .regular)
    private let progressBar = RequestProgressBar()

    private var showsFocus = false
    private var imageTask: Task<Void, Never>?
    private var imageURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        contentView.clipsToBounds = false
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.layer.cornerRadius = 10
        thumb.layer.cornerCurve = .continuous
        thumb.backgroundColor = UIColor(white: 1, alpha: 0.08)
        percent.textAlignment = .right
        timeLeft.textAlignment = .right
        [platter, thumb, title, detail, percent, timeLeft, progressBar].forEach(contentView.addSubview)
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ tile: RequestTile) {
        title.text = tile.title
        detail.text = [tile.detail, tile.status, tile.sizeText].compactMap { $0 }.joined(separator: " · ")
        percent.text = tile.progress.map { "\(Int(($0 * 100).rounded(.down)))%" }
        timeLeft.text = tile.secondsLeft.map(RequestTiles.timeLeftText)
        progressBar.isHidden = tile.progress == nil
        progressBar.progress = tile.progress ?? 0
        loadImage(tile)
        setNeedsLayout()
    }

    private func loadImage(_ tile: RequestTile) {
        guard tile.posterURL != imageURL || thumb.image == nil else { return }
        imageURL = tile.posterURL
        imageTask?.cancel()
        guard let url = tile.posterURL else {
            thumb.image = MusicChrome.placeholder(tile.type == .movie ? "film" : "tv", side: Self.thumbSize.width)
            return
        }
        if let cached = ImageCacheManager.shared.cachedImage(for: url) {
            thumb.image = cached
            return
        }
        thumb.image = nil
        imageTask = Task { [weak self] in
            let image = await ImageCacheManager.shared.image(for: url)
            guard let self, self.imageURL == url, let image else { return }
            self.thumb.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        imageURL = nil
        thumb.image = nil
        showsFocus = false
        platter.alpha = 0
        applyColors()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let outset = Self.platterOutset
        platter.frame = bounds.insetBy(dx: -outset, dy: 8)

        let thumbSize = Self.thumbSize
        thumb.frame = CGRect(x: 0, y: (bounds.height - thumbSize.height) / 2,
                             width: thumbSize.width, height: thumbSize.height)
        let textX = thumb.frame.maxX + 32
        let textWidth = bounds.width - textX

        let titleHeight = ceil(title.font.lineHeight)
        let detailHeight = ceil(detail.font.lineHeight)
        let barGap: CGFloat = 16
        let barHeight: CGFloat = 8
        let blockHeight = titleHeight + detailHeight + (progressBar.isHidden ? 0 : barGap + barHeight)
        let top = (bounds.height - blockHeight) / 2

        percent.sizeToFit()
        timeLeft.sizeToFit()
        let rightWidth = min(max(percent.bounds.width, timeLeft.bounds.width), textWidth / 3)
        let leftWidth = textWidth - (rightWidth > 0 ? rightWidth + 24 : 0)
        title.frame = CGRect(x: textX, y: top, width: leftWidth, height: titleHeight)
        detail.frame = CGRect(x: textX, y: title.frame.maxY, width: leftWidth, height: detailHeight)
        percent.frame = CGRect(x: bounds.width - rightWidth, y: top, width: rightWidth, height: titleHeight)
        timeLeft.frame = CGRect(x: bounds.width - rightWidth, y: detail.frame.minY,
                                width: rightWidth, height: detailHeight)
        progressBar.frame = CGRect(x: textX, y: detail.frame.maxY + barGap, width: textWidth, height: barHeight)
    }

    // MARK: - Focus

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let focused = context.nextFocusedView === self
        coordinator.animateFocusChange(gained: focused) {
            self.showsFocus = focused
            self.platter.alpha = focused ? 1 : 0
            self.applyColors()
        }
    }

    private func applyColors() {
        title.textColor = .white
        percent.textColor = .white
        detail.textColor = showsFocus ? .white : MusicMetrics.secondary
        timeLeft.textColor = showsFocus ? .white : MusicMetrics.secondary
    }
}
