import AppKit
import AVFoundation
import AVKit
import SwiftUI

enum MediaLightboxKind: Equatable, Hashable {
    case photo(PhotoMedia)
    case video(VideoMedia)
    case animation(AnimationMedia)
}

struct MediaLightboxItem: Identifiable, Equatable, Hashable {
    let id: Int64
    let date: Date
    let kind: MediaLightboxKind

    var file: MediaFileDescriptor {
        switch kind {
        case .photo(let media): return media.file
        case .video(let media): return media.file
        case .animation(let media): return media.file
        }
    }

    var caption: String {
        switch kind {
        case .photo(let media): return media.caption
        case .video(let media): return media.caption
        case .animation(let media): return media.caption
        }
    }

    var suggestedFileName: String {
        switch kind {
        case .photo:
            return "photo_\(id).jpg"
        case .video(let media):
            return media.fileName.isEmpty ? "video_\(id).mp4" : media.fileName
        case .animation(let media):
            if !media.fileName.isEmpty { return media.fileName }
            return media.isGIFImage ? "animation_\(id).gif" : "animation_\(id).mp4"
        }
    }

    var mimeType: String? {
        switch kind {
        case .photo: return "image/jpeg"
        case .video(let media): return media.mimeType
        case .animation(let media): return media.mimeType
        }
    }

    static func extract(from messages: [MessageItem]) -> [MediaLightboxItem] {
        messages.compactMap { msg in
            switch msg.content {
            case .photo(let media):
                return MediaLightboxItem(id: msg.id, date: msg.date, kind: .photo(media))
            case .video(let media):
                return MediaLightboxItem(id: msg.id, date: msg.date, kind: .video(media))
            case .animation(let media):
                return MediaLightboxItem(id: msg.id, date: msg.date, kind: .animation(media))
            default:
                return nil
            }
        }
    }
}

struct MediaLightboxSession: Identifiable, Equatable {
    let id = UUID()
    let items: [MediaLightboxItem]
    let initialMessageId: Int64
}

struct MediaLightboxView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss

    let session: MediaLightboxSession
    let onQuickLook: (URL) -> Void

    @State private var selectedIndex: Int = 0
    @State private var zoomScale: CGFloat = 1.0
    @State private var videoPlayer: AVPlayer?
    @State private var loadedVideoPath: String?
    @FocusState private var isViewerFocused: Bool

    private var currentItem: MediaLightboxItem? {
        guard session.items.indices.contains(selectedIndex) else { return nil }
        return session.items[selectedIndex]
    }

    private var canGoPrevious: Bool {
        selectedIndex > 0
    }

    private var canGoNext: Bool {
        selectedIndex + 1 < session.items.count
    }

    var body: some View {
        VStack(spacing: 0) {
            topToolbar

            Divider()

            ZStack {
                Color.black.opacity(0.92)

                if let item = currentItem {
                    mediaStage(for: item)
                }

                navigationArrows
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let item = currentItem, !item.caption.isEmpty {
                Divider()
                ScrollView {
                    Text(item.caption)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .frame(maxHeight: 110)
                .background(.bar)
            }
        }
        .frame(minWidth: 780, idealWidth: 960, minHeight: 560, idealHeight: 680)
        .focusable()
        .focused($isViewerFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            goPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            goNext()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onAppear {
            if let idx = session.items.firstIndex(where: { $0.id == session.initialMessageId }) {
                selectedIndex = idx
            }
            isViewerFocused = true
            prepareCurrentItem()
        }
        .onChange(of: selectedIndex) { _, _ in
            zoomScale = 1.0
            releaseVideoPlayer()
            prepareCurrentItem()
        }
        .onDisappear {
            releaseVideoPlayer()
        }
    }

    private var topToolbar: some View {
        let state = currentItem.map { appStore.fileCache.state(for: $0.file) }

        return HStack(spacing: 12) {
            if let item = currentItem {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(for: item))
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text("\(selectedIndex + 1) / \(session.items.count)")
                            .monospacedDigit()
                        Text("·")
                        Text(Self.dateFormatter.string(from: item.date))
                            .monospacedDigit()
                        if let state, state.expectedSize > 0 {
                            Text("·")
                            Text(MediaFormatters.formatFileSize(state.expectedSize))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if case .photo = currentItem?.kind {
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.snappy(duration: 0.16)) {
                            zoomScale = max(0.5, zoomScale - 0.5)
                        }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .help("缩小")

                    Button {
                        withAnimation(.snappy(duration: 0.16)) {
                            zoomScale = 1.0
                        }
                    } label: {
                        Text("\(Int((zoomScale * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .frame(minWidth: 42)
                    }
                    .help("重置缩放")

                    Button {
                        withAnimation(.snappy(duration: 0.16)) {
                            zoomScale = min(4.0, zoomScale + 0.5)
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .help("放大")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let item = currentItem, let localPath = state?.localPath, state?.isDownloaded == true {
                if case .photo = item.kind {
                    Button {
                        MediaFileActions.copyImageToPasteboard(from: localPath)
                    } label: {
                        Label("复制图片", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                }

                Button {
                    let qlURL = MediaFileActions.quickLookURL(
                        for: localPath,
                        preferredFileName: item.suggestedFileName,
                        mimeType: item.mimeType
                    )
                    onQuickLook(qlURL)
                } label: {
                    Label("Quick Look", systemImage: "eye")
                }
                .controlSize(.small)

                Button {
                    MediaFileActions.saveFile(
                        from: localPath,
                        suggestedFileName: item.suggestedFileName,
                        mimeType: item.mimeType
                    )
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)

                Button {
                    MediaFileActions.revealInFinder(localPath: localPath)
                } label: {
                    Image(systemName: "folder")
                }
                .controlSize(.small)
                .help("在 Finder 中显示")
            }

            Button("关闭") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func mediaStage(for item: MediaLightboxItem) -> some View {
        let state = appStore.fileCache.state(for: item.file)

        switch item.kind {
        case .photo(let photo):
            photoStage(photo: photo, state: state)

        case .video(let video):
            videoStage(video: video, state: state)

        case .animation(let animation):
            animationStage(animation: animation, state: state)
        }
    }

    @ViewBuilder
    private func photoStage(photo: PhotoMedia, state: FileTransferState) -> some View {
        if let nsImage = appStore.fileCache.image(for: photo.file)
            ?? photo.previewFile.flatMap({ appStore.fileCache.image(for: $0) })
        {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: proxy.size.width * zoomScale,
                            height: proxy.size.height * zoomScale
                        )
                        .frame(
                            minWidth: proxy.size.width,
                            minHeight: proxy.size.height
                        )
                }
                .onTapGesture(count: 2) {
                    withAnimation(.snappy(duration: 0.2)) {
                        zoomScale = zoomScale > 1.05 ? 1.0 : 2.0
                    }
                }
            }
        } else {
            VStack(spacing: 12) {
                MediaTransferButton(
                    state: state,
                    size: 54,
                    onStartDownload: {
                        appStore.fileCache.startDownload(fileId: photo.file.fileId, priority: 30)
                    },
                    onCancelDownload: {
                        appStore.fileCache.cancelDownload(fileId: photo.file.fileId)
                    }
                )
                Text(state.isDownloading ? "正在下载高清原图…" : "点击下载原图")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    @ViewBuilder
    private func videoStage(video: VideoMedia, state: FileTransferState) -> some View {
        if state.isDownloaded, let localPath = state.localPath {
            VideoPlayer(player: videoPlayer)
                .onAppear {
                    loadVideoIfNeeded(path: localPath)
                }
                .onChange(of: localPath) { _, newPath in
                    loadVideoIfNeeded(path: newPath)
                }
        } else {
            VStack(spacing: 14) {
                MediaTransferButton(
                    state: state,
                    size: 58,
                    onStartDownload: {
                        appStore.fileCache.startDownload(fileId: video.file.fileId, priority: 30)
                    },
                    onCancelDownload: {
                        appStore.fileCache.cancelDownload(fileId: video.file.fileId)
                    }
                )
                if state.isDownloading && state.expectedSize > 0 {
                    Text("正在下载视频 \(MediaFormatters.formatFileSize(state.downloadedSize)) / \(MediaFormatters.formatFileSize(state.expectedSize))")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                } else {
                    Text("点击下载并播放视频")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    @ViewBuilder
    private func animationStage(animation: AnimationMedia, state: FileTransferState) -> some View {
        if state.isDownloaded, let localPath = state.localPath {
            if animation.isGIFImage {
                AnimatedGIFImageView(url: URL(fileURLWithPath: localPath))
                    .padding(24)
            } else {
                LoopingVideoPlayerView(
                    url: URL(fileURLWithPath: localPath),
                    isMuted: true,
                    isPlaying: true,
                    videoGravity: .resizeAspect
                )
                .padding(24)
            }
        } else {
            MediaTransferButton(
                state: state,
                size: 56,
                onStartDownload: {
                    appStore.fileCache.startDownload(fileId: animation.file.fileId, priority: 30)
                },
                onCancelDownload: {
                    appStore.fileCache.cancelDownload(fileId: animation.file.fileId)
                }
            )
        }
    }

    private var navigationArrows: some View {
        HStack {
            if canGoPrevious {
                Button(action: goPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 14)
                .help("上一项 (←)")
            }

            Spacer()

            if canGoNext {
                Button(action: goNext) {
                    Image(systemName: "chevron.right")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 14)
                .help("下一项 (→)")
            }
        }
    }

    private func goPrevious() {
        guard canGoPrevious else { return }
        selectedIndex -= 1
    }

    private func goNext() {
        guard canGoNext else { return }
        selectedIndex += 1
    }

    private func prepareCurrentItem() {
        guard let item = currentItem else { return }
        switch item.kind {
        case .photo(let photo):
            appStore.fileCache.ensureDownloaded(photo.file, priority: 30)
        case .animation(let animation):
            appStore.fileCache.ensureDownloaded(animation.file, priority: 30)
        case .video(let video):
            let state = appStore.fileCache.state(for: video.file)
            if state.isDownloaded, let path = state.localPath {
                loadVideoIfNeeded(path: path)
            }
        }
    }

    private func loadVideoIfNeeded(path: String) {
        guard loadedVideoPath != path else { return }
        releaseVideoPlayer()
        appStore.audioPlayer.stop()
        loadedVideoPath = path
        let player = AVPlayer(url: URL(fileURLWithPath: path))
        videoPlayer = player
        player.play()
    }

    private func releaseVideoPlayer() {
        videoPlayer?.pause()
        videoPlayer = nil
        loadedVideoPath = nil
    }

    private func title(for item: MediaLightboxItem) -> String {
        switch item.kind {
        case .photo(let photo):
            return "图片 (\(photo.width)×\(photo.height))"
        case .video(let video):
            let name = video.fileName.isEmpty ? "视频" : video.fileName
            return "\(name) · \(MediaFormatters.formatDuration(video.duration))"
        case .animation:
            return "GIF 动图"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
