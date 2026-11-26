import AppKit
import AVFoundation
import CoreMedia
import QuartzCore
import SwiftUI

/// Zero-chrome hardware-accelerated looping video player backed by `AVQueuePlayer` + `AVPlayerLooper`.
/// Used for inline GIF/MPEG4 animations and circular Telegram video notes.
struct LoopingVideoPlayerView: NSViewRepresentable {
    let url: URL
    var isMuted: Bool = true
    var isPlaying: Bool = true
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    var onProgress: ((Double) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PlayerLayerNSView {
        let view = PlayerLayerNSView()
        view.playerLayer.videoGravity = videoGravity
        context.coordinator.configure(
            view: view,
            url: url,
            isMuted: isMuted,
            isPlaying: isPlaying,
            onProgress: onProgress
        )
        return view
    }

    func updateNSView(_ nsView: PlayerLayerNSView, context: Context) {
        nsView.playerLayer.videoGravity = videoGravity
        context.coordinator.configure(
            view: nsView,
            url: url,
            isMuted: isMuted,
            isPlaying: isPlaying,
            onProgress: onProgress
        )
    }

    static func dismantleNSView(_ nsView: PlayerLayerNSView, coordinator: Coordinator) {
        coordinator.teardown()
        nsView.playerLayer.player = nil
    }

    final class PlayerLayerNSView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }

    final class Coordinator {
        private var queuePlayer: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var currentURL: URL?
        private var timeObserver: Any?
        private var progressCallback: ((Double) -> Void)?

        func configure(
            view: PlayerLayerNSView,
            url: URL,
            isMuted: Bool,
            isPlaying: Bool,
            onProgress: ((Double) -> Void)?
        ) {
            self.progressCallback = onProgress

            if currentURL != url {
                teardown()
                currentURL = url

                let asset = AVURLAsset(url: url)
                let templateItem = AVPlayerItem(asset: asset)
                let player = AVQueuePlayer()
                player.isMuted = isMuted
                player.actionAtItemEnd = .none

                let playerLooper = AVPlayerLooper(player: player, templateItem: templateItem)
                self.queuePlayer = player
                self.looper = playerLooper
                view.playerLayer.player = player

                if onProgress != nil {
                    let interval = CMTime(seconds: 0.08, preferredTimescale: 600)
                    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
                        guard let self, let player, let item = player.currentItem else { return }
                        let duration = CMTimeGetSeconds(item.duration)
                        let current = CMTimeGetSeconds(time)
                        if duration.isFinite && duration > 0 && current.isFinite {
                            let fraction = min(1.0, max(0.0, current / duration))
                            self.progressCallback?(fraction)
                        }
                    }
                }
            }

            if let player = queuePlayer {
                player.isMuted = isMuted
                if isPlaying {
                    if player.timeControlStatus != .playing {
                        player.play()
                    }
                } else {
                    player.pause()
                }
            }
        }

        func teardown() {
            if let observer = timeObserver, let player = queuePlayer {
                player.removeTimeObserver(observer)
            }
            timeObserver = nil
            queuePlayer?.pause()
            looper?.disableLooping()
            looper = nil
            queuePlayer?.removeAllItems()
            queuePlayer = nil
            currentURL = nil
        }

        deinit {
            teardown()
        }
    }
}

/// Native animated GIF renderer using `NSImageView.animates = true`.
struct AnimatedGIFImageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.image = NSImage(contentsOf: url)
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.animates = true
        if nsView.image == nil {
            nsView.image = NSImage(contentsOf: url)
        }
    }
}
