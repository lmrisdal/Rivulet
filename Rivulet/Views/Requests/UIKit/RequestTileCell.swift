// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  RequestTileCell.swift
//  Rivulet
//
//  A Requests page tile: the system poster lockup with the title and its
//  status under the art, and a progress bar over the art while Seerr reports
//  a download.
//

import UIKit
import TVUIKit

@MainActor
final class RequestTileCell: UICollectionViewCell {
    static let reuseID = "RequestTileCell"
    private static let tile = MediaRowMetrics.poster

    /// The lockup frame plus the two-line footer under the art.
    static let size: CGSize = {
        var size = tile.frame
        size.height += MusicMetrics.lockupFooter - (tile.frame.height - tile.art.height) / 2
        return size
    }()

    private let poster = TVPosterView()
    private let progressBar = RequestProgressBar()
    private var imageTask: Task<Void, Never>?
    private var imageURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        contentView.clipsToBounds = false

        poster.contentSize = Self.tile.art
        poster.imageView.contentMode = .scaleAspectFill
        poster.image = PosterCell.blankArtwork
        poster.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(poster)

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        poster.imageView.addSubview(progressBar)

        NSLayoutConstraint.activate([
            poster.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            poster.topAnchor.constraint(equalTo: contentView.topAnchor),
            progressBar.leadingAnchor.constraint(equalTo: poster.imageView.leadingAnchor, constant: 16),
            progressBar.trailingAnchor.constraint(equalTo: poster.imageView.trailingAnchor, constant: -16),
            progressBar.bottomAnchor.constraint(equalTo: poster.imageView.bottomAnchor, constant: -16),
            progressBar.heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ tile: RequestTile) {
        poster.title = tile.title
        poster.subtitle = tile.status
        progressBar.isHidden = tile.progress == nil
        progressBar.progress = tile.progress ?? 0
        applyFocusAppearance(isFocused)
        guard tile.posterURL != imageURL else { return }
        imageURL = tile.posterURL
        imageTask?.cancel()
        guard let url = tile.posterURL else {
            poster.image = MusicChrome.placeholder(tile.type == .movie ? "film" : "tv",
                                                   side: Self.tile.art.width)
            return
        }
        if let cached = ImageCacheManager.shared.cachedImage(for: url) {
            poster.image = cached
            return
        }
        poster.image = PosterCell.blankArtwork
        imageTask = Task { [weak self] in
            let image = await ImageCacheManager.shared.image(for: url)
            guard let self, self.imageURL == url, let image else { return }
            self.poster.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        imageURL = nil
        poster.image = PosterCell.blankArtwork
        resetStaleFocusAppearance()
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let focused = context.nextFocusedView === self
        coordinator.addCoordinatedAnimations({
            self.applyFocusAppearance(focused)
        }, completion: { [weak self] in
            if !focused { self?.resetStaleFocusAppearance() }
        })
    }

    private func applyFocusAppearance(_ focused: Bool) {
        let footer = poster.footerView as? TVLockupHeaderFooterView
        footer?.titleLabel?.textColor = .white
        footer?.subtitleLabel?.textColor = focused ? .white : MusicMetrics.secondary
    }

    /// The poster can strand its enlarged look when focus leaves the whole
    /// collection: clear it directly (same reset as `PhotoCell`).
    func resetStaleFocusAppearance() {
        guard !isFocused else { return }
        func clear(_ view: UIView) {
            if !view.transform.isIdentity { view.transform = .identity }
            if !CATransform3DIsIdentity(view.layer.transform) { view.layer.transform = CATransform3DIdentity }
            view.motionEffects.forEach { view.removeMotionEffect($0) }
            view.subviews.forEach(clear)
        }
        clear(poster)
        applyFocusAppearance(false)
    }
}

/// A white capsule filling a translucent track.
final class RequestProgressBar: UIView {
    private let fill = UIView()

    var progress: Double = 0 {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor(white: 0, alpha: 0.45)
        fill.backgroundColor = .white
        addSubview(fill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        fill.layer.cornerRadius = bounds.height / 2
        let clamped = CGFloat(min(max(progress, 0), 1))
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * clamped, height: bounds.height)
    }
}
