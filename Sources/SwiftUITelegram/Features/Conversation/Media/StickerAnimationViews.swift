import AppKit
import Lottie
import QuartzCore
import SwiftUI
import WebKit

// MARK: - TGS (Lottie Vector Animation) Renderer

/// Native macOS AppKit `LottieAnimationView` wrapper for Telegram `.tgs` animated stickers.
/// Uses Lottie's `.automatic` rendering engine (Core Animation GPU layers with automatic
/// main-thread fallback for advanced masks/mattes) and deterministic play/pause/replay control.
struct TGSStickerView: NSViewRepresentable {
    let animation: LottieAnimation
    var isPlaying: Bool = true
    var replayTrigger: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TGSContainerNSView {
        let container = TGSContainerNSView()
        context.coordinator.apply(
            animation: animation,
            isPlaying: isPlaying,
            replayTrigger: replayTrigger,
            to: container.animationView
        )
        return container
    }

    func updateNSView(_ nsView: TGSContainerNSView, context: Context) {
        context.coordinator.apply(
            animation: animation,
            isPlaying: isPlaying,
            replayTrigger: replayTrigger,
            to: nsView.animationView
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TGSContainerNSView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    static func dismantleNSView(_ nsView: TGSContainerNSView, coordinator: Coordinator) {
        nsView.animationView.stop()
        nsView.animationView.animation = nil
        coordinator.reset()
    }

    /// Pass-through container that isolates SwiftUI layout from `LottieAnimationView`'s
    /// 512×512 `intrinsicContentSize` and keeps hover/tap/context-menu gestures responsive.
    final class TGSContainerNSView: NSView {
        let animationView: LottieAnimationView

        override init(frame frameRect: NSRect) {
            self.animationView = LottieAnimationView(
                configuration: LottieConfiguration(renderingEngine: .automatic)
            )
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor

            animationView.contentMode = .scaleAspectFit
            animationView.loopMode = .loop
            animationView.backgroundBehavior = .pauseAndRestore
            animationView.respectAnimationFrameRate = true
            animationView.autoresizingMask = [.width, .height]
            animationView.frame = bounds
            addSubview(animationView)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        override func layout() {
            super.layout()
            animationView.frame = bounds
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    final class Coordinator {
        private var currentAnimationId: ObjectIdentifier?
        private var lastReplayTrigger: Int = 0
        private var lastIsPlaying: Bool = false

        func apply(
            animation: LottieAnimation,
            isPlaying: Bool,
            replayTrigger: Int,
            to view: LottieAnimationView
        ) {
            let nextId = ObjectIdentifier(animation)
            let animationChanged = currentAnimationId != nextId
            if animationChanged {
                currentAnimationId = nextId
                view.stop()
                view.animation = animation
                view.loopMode = .loop
                view.currentProgress = 0
                lastIsPlaying = false
            }

            let replayRequested = replayTrigger != lastReplayTrigger
            lastReplayTrigger = replayTrigger

            if replayRequested {
                view.stop()
                view.currentProgress = 0
                if isPlaying {
                    view.play()
                }
                lastIsPlaying = isPlaying
                return
            }

            if isPlaying {
                if !lastIsPlaying || !view.isAnimationPlaying {
                    view.play()
                }
            } else if lastIsPlaying || animationChanged {
                view.pause()
                view.currentProgress = 0
            }

            lastIsPlaying = isPlaying
        }

        func reset() {
            currentAnimationId = nil
            lastIsPlaying = false
        }
    }
}

// MARK: - WebM (VP9 + Alpha) Frame Sequence Player

/// Zero-overhead `CALayer`-backed looping player for decoded `WebMStickerSequence` frames.
/// Sets `layer.contents` directly inside disabled-action `CATransaction`s so playback never
/// triggers SwiftUI view diffing per frame, and pauses automatically when off-window.
struct WebMStickerPlayerView: NSViewRepresentable {
    let sequence: WebMStickerSequence
    var isPlaying: Bool = true
    var replayTrigger: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> FrameLayerNSView {
        let view = FrameLayerNSView()
        view.onWindowAttachmentChanged = { [weak coordinator = context.coordinator, weak view] attached in
            guard let coordinator, let view else { return }
            coordinator.setWindowAttached(attached, view: view)
        }
        context.coordinator.configure(
            view: view,
            sequence: sequence,
            isPlaying: isPlaying,
            replayTrigger: replayTrigger
        )
        return view
    }

    func updateNSView(_ nsView: FrameLayerNSView, context: Context) {
        context.coordinator.configure(
            view: nsView,
            sequence: sequence,
            isPlaying: isPlaying,
            replayTrigger: replayTrigger
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FrameLayerNSView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    static func dismantleNSView(_ nsView: FrameLayerNSView, coordinator: Coordinator) {
        coordinator.teardown(view: nsView)
    }

    final class FrameLayerNSView: NSView {
        var onWindowAttachmentChanged: ((Bool) -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.contentsGravity = .resizeAspect
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowAttachmentChanged?(window != nil)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        func display(frame: CGImage?) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contents = frame
            CATransaction.commit()
        }
    }

    final class Coordinator {
        private var currentSequenceId: ObjectIdentifier?
        private var sequence: WebMStickerSequence?
        private var frameIndex: Int = 0
        private var timer: Timer?
        private var wantsPlay: Bool = false
        private var isAttachedToWindow: Bool = true
        private var lastReplayTrigger: Int = 0
        private weak var targetView: FrameLayerNSView?

        func configure(
            view: FrameLayerNSView,
            sequence: WebMStickerSequence,
            isPlaying: Bool,
            replayTrigger: Int
        ) {
            targetView = view
            isAttachedToWindow = view.window != nil

            let nextId = ObjectIdentifier(sequence)
            let sequenceChanged = currentSequenceId != nextId
            if sequenceChanged {
                stopTimer()
                currentSequenceId = nextId
                self.sequence = sequence
                frameIndex = 0
                view.display(frame: sequence.frames.first?.image)
            }

            let replayRequested = replayTrigger != lastReplayTrigger
            lastReplayTrigger = replayTrigger
            wantsPlay = isPlaying

            if replayRequested {
                stopTimer()
                frameIndex = 0
                view.display(frame: sequence.frames.first?.image)
            }

            syncPlaybackState()
        }

        func setWindowAttached(_ attached: Bool, view: FrameLayerNSView) {
            targetView = view
            isAttachedToWindow = attached
            syncPlaybackState()
        }

        private func syncPlaybackState() {
            guard let sequence, sequence.frames.count > 1 else {
                stopTimer()
                return
            }

            if wantsPlay && isAttachedToWindow {
                if timer == nil {
                    scheduleNextTick()
                }
            } else {
                stopTimer()
                if !wantsPlay {
                    frameIndex = 0
                    targetView?.display(frame: sequence.frames.first?.image)
                }
            }
        }

        private func scheduleNextTick() {
            stopTimer()
            guard let sequence, !sequence.frames.isEmpty else { return }
            let delay = sequence.frames[frameIndex].duration

            let nextTimer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                guard let self, let sequence = self.sequence, !sequence.frames.isEmpty else { return }
                guard self.wantsPlay && self.isAttachedToWindow else {
                    self.stopTimer()
                    return
                }
                self.frameIndex = (self.frameIndex + 1) % sequence.frames.count
                self.targetView?.display(frame: sequence.frames[self.frameIndex].image)
                self.scheduleNextTick()
            }
            RunLoop.main.add(nextTimer, forMode: .common)
            timer = nextTimer
        }

        private func stopTimer() {
            timer?.invalidate()
            timer = nil
        }

        func teardown(view: FrameLayerNSView?) {
            stopTimer()
            view?.display(frame: nil)
            targetView = nil
            sequence = nil
            currentSequenceId = nil
        }

        deinit {
            stopTimer()
        }
    }
}

// MARK: - WebKit Fallback for Non-VP9 / Unsupported WebM Stickers

/// Lightweight transparent `WKWebView` fallback used only if native VideoToolbox decoding
/// declines a `.webm` sticker (e.g. legacy VP8 video stickers or virtualized GPUs).
struct WebMWebViewFallback: NSViewRepresentable {
    let localPath: String
    var isPlaying: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PassThroughWKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = PassThroughWKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        context.coordinator.loadIfNeeded(localPath: localPath, into: webView, isPlaying: isPlaying)
        return webView
    }

    func updateNSView(_ nsView: PassThroughWKWebView, context: Context) {
        context.coordinator.loadIfNeeded(localPath: localPath, into: nsView, isPlaying: isPlaying)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PassThroughWKWebView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    static func dismantleNSView(_ nsView: PassThroughWKWebView, coordinator: Coordinator) {
        nsView.stopLoading()
        nsView.loadHTMLString("", baseURL: nil)
        coordinator.reset()
    }

    final class PassThroughWKWebView: WKWebView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    final class Coordinator {
        private var loadedPath: String?
        private var lastPlaying: Bool = true

        func loadIfNeeded(localPath: String, into webView: WKWebView, isPlaying: Bool) {
            if loadedPath != localPath {
                loadedPath = localPath
                lastPlaying = isPlaying

                let videoURL = MediaFileActions.quickLookURL(
                    for: localPath,
                    preferredFileName: "sticker_\(abs(localPath.hashValue)).webm",
                    mimeType: "video/webm"
                )
                let htmlURL = videoURL.deletingLastPathComponent().appendingPathComponent("player.html")
                let encodedVideoName = videoURL.lastPathComponent
                    .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? videoURL.lastPathComponent
                let html = """
                <!doctype html>
                <html>
                <head>
                <meta charset="utf-8">
                <style>
                html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: transparent; }
                video { width: 100%; height: 100%; object-fit: contain; display: block; background: transparent; }
                </style>
                </head>
                <body>
                <video id="v" src="\(encodedVideoName)" autoplay loop muted playsinline></video>
                </body>
                </html>
                """
                try? html.write(to: htmlURL, atomically: true, encoding: .utf8)
                webView.loadFileURL(htmlURL, allowingReadAccessTo: videoURL.deletingLastPathComponent())
                return
            }

            if lastPlaying != isPlaying {
                lastPlaying = isPlaying
                let js = isPlaying ? "document.getElementById('v')?.play();" : "document.getElementById('v')?.pause();"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        func reset() {
            loadedPath = nil
        }
    }
}

// MARK: - Unified Sticker Surface (WebP + TGS Lottie + WebM VP9 Alpha)

/// Renders any Telegram sticker or animated sticker-pack thumbnail across all three formats
/// (`.webp`, `.tgs`, `.webm`) with automatic TDLib download, progressive thumbnail placeholder,
/// memory-bounded decoding cache, and configurable playback behavior.
struct AnimatedStickerSurfaceView: View {
    @Environment(AppStore.self) private var appStore

    let file: MediaFileDescriptor
    let format: StickerMediaFormat
    let thumbnail: ThumbnailInfo?
    let emoji: String
    let size: CGSize
    var isPlaying: Bool = true
    var firstFrameOnly: Bool = false
    var replayTrigger: Int = 0
    var maxPixelSize: Int = 256
    var downloadPriority: Int = 20
    var allowWebKitFallback: Bool = false
    var showDownloadSpinner: Bool = false

    @State private var lottieAnimation: LottieAnimation?
    @State private var webmSequence: WebMStickerSequence?
    @State private var webmFirstFrame: NSImage?
    @State private var webmDecodeFailed: Bool = false

    init(
        file: MediaFileDescriptor,
        format: StickerMediaFormat,
        thumbnail: ThumbnailInfo? = nil,
        emoji: String = "",
        size: CGSize,
        isPlaying: Bool = true,
        firstFrameOnly: Bool = false,
        replayTrigger: Int = 0,
        maxPixelSize: Int = 256,
        downloadPriority: Int = 20,
        allowWebKitFallback: Bool = false,
        showDownloadSpinner: Bool = false
    ) {
        self.file = file
        self.format = format
        self.thumbnail = thumbnail
        self.emoji = emoji
        self.size = size
        self.isPlaying = isPlaying
        self.firstFrameOnly = firstFrameOnly
        self.replayTrigger = replayTrigger
        self.maxPixelSize = maxPixelSize
        self.downloadPriority = downloadPriority
        self.allowWebKitFallback = allowWebKitFallback
        self.showDownloadSpinner = showDownloadSpinner
    }

    init(
        media: StickerMedia,
        size: CGSize,
        isPlaying: Bool = true,
        firstFrameOnly: Bool = false,
        replayTrigger: Int = 0,
        maxPixelSize: Int = 256,
        downloadPriority: Int = 20,
        allowWebKitFallback: Bool = true,
        showDownloadSpinner: Bool = true
    ) {
        self.init(
            file: media.file,
            format: media.format,
            thumbnail: media.thumbnail,
            emoji: media.emoji,
            size: size,
            isPlaying: isPlaying,
            firstFrameOnly: firstFrameOnly,
            replayTrigger: replayTrigger,
            maxPixelSize: maxPixelSize,
            downloadPriority: downloadPriority,
            allowWebKitFallback: allowWebKitFallback,
            showDownloadSpinner: showDownloadSpinner
        )
    }

    init(
        sticker: StickerItem,
        size: CGSize,
        isPlaying: Bool = false,
        firstFrameOnly: Bool = false,
        replayTrigger: Int = 0,
        maxPixelSize: Int = 128,
        downloadPriority: Int = 14,
        allowWebKitFallback: Bool = false,
        showDownloadSpinner: Bool = false
    ) {
        self.init(
            file: sticker.file,
            format: sticker.format,
            thumbnail: sticker.thumbnail,
            emoji: sticker.emoji,
            size: size,
            isPlaying: isPlaying,
            firstFrameOnly: firstFrameOnly,
            replayTrigger: replayTrigger,
            maxPixelSize: maxPixelSize,
            downloadPriority: downloadPriority,
            allowWebKitFallback: allowWebKitFallback,
            showDownloadSpinner: showDownloadSpinner
        )
    }

    init(
        thumbnailInfo: ThumbnailInfo,
        size: CGSize,
        isPlaying: Bool = false,
        maxPixelSize: Int = 96,
        downloadPriority: Int = 12
    ) {
        self.init(
            file: thumbnailInfo.file,
            format: thumbnailInfo.format.stickerFormat ?? .webp,
            thumbnail: nil,
            emoji: "",
            size: size,
            isPlaying: isPlaying,
            firstFrameOnly: !isPlaying,
            replayTrigger: 0,
            maxPixelSize: maxPixelSize,
            downloadPriority: downloadPriority,
            allowWebKitFallback: false,
            showDownloadSpinner: false
        )
    }

    private var transferState: FileTransferState {
        appStore.fileCache.state(for: file)
    }

    private var localPath: String? {
        guard transferState.isDownloaded,
              let path = transferState.localPath,
              !path.isEmpty
        else {
            return nil
        }
        return path
    }

    private var staticThumbnailImage: NSImage? {
        if let thumb = thumbnail, thumb.format.isStaticImage,
           let thumbImg = appStore.fileCache.image(for: thumb.file)
        {
            return thumbImg
        }
        return nil
    }

    private var webpImage: NSImage? {
        guard format == .webp else { return nil }
        return appStore.fileCache.image(for: file)
    }

    private var decodeTaskKey: String {
        "\(file.fileId)|\(localPath ?? "")|\(firstFrameOnly ? 0 : (isPlaying ? 2 : 1))|\(maxPixelSize)"
    }

    var body: some View {
        ZStack {
            renderedContent
        }
        .frame(width: size.width, height: size.height)
        .task(id: file.fileId) {
            if let thumb = thumbnail, thumb.format.isStaticImage {
                appStore.fileCache.ensureDownloaded(thumb.file, priority: downloadPriority + 2)
            }
            appStore.fileCache.ensureDownloaded(file, priority: downloadPriority)
        }
        .task(id: decodeTaskKey) {
            await decodeCurrentAssetIfNeeded()
        }
    }

    @ViewBuilder
    private var renderedContent: some View {
        switch format {
        case .webp:
            if let img = webpImage ?? staticThumbnailImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholderView
            }

        case .tgs:
            if let anim = lottieAnimation ?? localPath.flatMap({ TGSStickerCache.shared.cachedAnimation(for: $0) }) {
                TGSStickerView(
                    animation: anim,
                    isPlaying: isPlaying && !firstFrameOnly,
                    replayTrigger: replayTrigger
                )
            } else if let thumbImg = staticThumbnailImage {
                Image(nsImage: thumbImg)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholderView
            }

        case .webm:
            if !firstFrameOnly,
               let seq = webmSequence ?? localPath.flatMap({ WebMStickerCache.shared.cachedSequence(for: $0, maxPixelSize: maxPixelSize) })
            {
                WebMStickerPlayerView(
                    sequence: seq,
                    isPlaying: isPlaying,
                    replayTrigger: replayTrigger
                )
            } else if let frameImg = webmFirstFrame ?? localPath.flatMap({ WebMStickerCache.shared.cachedFirstFrame(for: $0, maxPixelSize: maxPixelSize) }) {
                Image(nsImage: frameImg)
                    .resizable()
                    .scaledToFit()
            } else if webmDecodeFailed, allowWebKitFallback, let path = localPath {
                WebMWebViewFallback(localPath: path, isPlaying: isPlaying && !firstFrameOnly)
            } else if let thumbImg = staticThumbnailImage {
                Image(nsImage: thumbImg)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholderView
            }
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        if showDownloadSpinner && transferState.isDownloading {
            ZStack {
                if !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: min(size.width, size.height) * 0.42))
                        .opacity(0.35)
                }
                ProgressView()
                    .controlSize(.small)
            }
        } else if !emoji.isEmpty {
            Text(emoji)
                .font(.system(size: min(size.width, size.height) * 0.5))
                .opacity(0.85)
        } else {
            RoundedRectangle(cornerRadius: min(size.width, size.height) * 0.2, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
                .padding(4)
        }
    }

    private func decodeCurrentAssetIfNeeded() async {
        guard let path = localPath else {
            lottieAnimation = nil
            webmSequence = nil
            webmFirstFrame = nil
            webmDecodeFailed = false
            return
        }

        switch format {
        case .webp:
            break

        case .tgs:
            if let cached = TGSStickerCache.shared.cachedAnimation(for: path) {
                lottieAnimation = cached
                return
            }
            let decoded = await TGSStickerCache.shared.loadAnimation(from: path)
            guard !Task.isCancelled else { return }
            lottieAnimation = decoded

        case .webm:
            if firstFrameOnly || !isPlaying {
                if let cached = WebMStickerCache.shared.cachedFirstFrame(for: path, maxPixelSize: maxPixelSize) {
                    webmFirstFrame = cached
                    webmDecodeFailed = false
                    return
                }
                let frame = await WebMStickerCache.shared.loadFirstFrame(from: path, maxPixelSize: maxPixelSize)
                guard !Task.isCancelled else { return }
                webmFirstFrame = frame
                webmDecodeFailed = (frame == nil)
            } else {
                if let cached = WebMStickerCache.shared.cachedSequence(for: path, maxPixelSize: maxPixelSize) {
                    webmSequence = cached
                    webmDecodeFailed = false
                    return
                }
                // Show first frame quickly while the full frame sequence decodes if no static thumb exists.
                if webmFirstFrame == nil && staticThumbnailImage == nil {
                    if let cachedFirst = WebMStickerCache.shared.cachedFirstFrame(for: path, maxPixelSize: maxPixelSize) {
                        webmFirstFrame = cachedFirst
                    }
                }
                let sequence = await WebMStickerCache.shared.loadSequence(from: path, maxPixelSize: maxPixelSize)
                guard !Task.isCancelled else { return }
                webmSequence = sequence
                if let firstCG = sequence?.frames.first?.image {
                    webmFirstFrame = NSImage(cgImage: firstCG, size: NSSize(width: firstCG.width, height: firstCG.height))
                }
                webmDecodeFailed = (sequence == nil)
            }
        }
    }
}
