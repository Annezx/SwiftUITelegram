import AVFoundation
import Foundation
import Observation

/// Manages single-stream playback of voice notes (including OGG/Opus via CAF remuxing)
/// and audio messages across the entire application.
@MainActor
@Observable
final class AudioPlaybackManager: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    private(set) var activeMessageId: Int64?
    private(set) var isPlaying: Bool = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var playbackRate: Float = 1.0
    var errorMessage: String?

    /// Message ID waiting for its audio file download to finish before auto-starting playback.
    var pendingAutoPlayMessageId: Int64?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1.0, max(0.0, currentTime / duration))
    }

    func isPlaying(messageId: Int64) -> Bool {
        activeMessageId == messageId && isPlaying
    }

    func isActive(messageId: Int64) -> Bool {
        activeMessageId == messageId
    }

    func progress(for messageId: Int64) -> Double {
        activeMessageId == messageId ? progress : 0
    }

    func currentTime(for messageId: Int64) -> TimeInterval {
        activeMessageId == messageId ? currentTime : 0
    }

    func togglePlayback(
        messageId: Int64,
        filePath: String,
        fallbackDuration: Int,
        onStarted: (() -> Void)? = nil
    ) {
        errorMessage = nil
        pendingAutoPlayMessageId = nil

        if activeMessageId == messageId, let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
                stopTimer()
            } else {
                player.enableRate = true
                player.rate = playbackRate
                if player.play() {
                    isPlaying = true
                    startTimer()
                }
            }
            return
        }

        startPlaying(
            messageId: messageId,
            filePath: filePath,
            fallbackDuration: fallbackDuration,
            onStarted: onStarted
        )
    }

    func seek(toFraction fraction: Double, for messageId: Int64) {
        guard activeMessageId == messageId, let player, duration > 0 else { return }
        let clamped = min(1.0, max(0.0, fraction))
        let target = duration * clamped
        player.currentTime = target
        currentTime = target
    }

    func cyclePlaybackRate() {
        if playbackRate < 1.25 {
            playbackRate = 1.5
        } else if playbackRate < 1.75 {
            playbackRate = 2.0
        } else {
            playbackRate = 1.0
        }

        if let player {
            player.enableRate = true
            player.rate = playbackRate
        }
    }

    func stop() {
        stopTimer()
        player?.stop()
        player = nil
        activeMessageId = nil
        pendingAutoPlayMessageId = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        errorMessage = nil
    }

    // MARK: - Private

    private func startPlaying(
        messageId: Int64,
        filePath: String,
        fallbackDuration: Int,
        onStarted: (() -> Void)?
    ) {
        stopTimer()
        player?.stop()
        player = nil

        let sourceURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            errorMessage = "本地音频文件不存在，请重新下载。"
            return
        }

        let playableURL: URL
        do {
            let ext = sourceURL.pathExtension.lowercased()
            if ext == "oga" || ext == "ogg" || OggOpusToCAFConverter.isOggContainer(at: sourceURL) {
                playableURL = try OggOpusToCAFConverter.playableCAFURL(for: sourceURL)
            } else {
                playableURL = sourceURL
            }
        } catch {
            errorMessage = "语音解码失败：\(error.localizedDescription)"
            return
        }

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: playableURL)
            newPlayer.delegate = self
            newPlayer.enableRate = true
            newPlayer.rate = playbackRate
            newPlayer.prepareToPlay()

            guard newPlayer.play() else {
                errorMessage = "无法开始播放该音频文件。"
                return
            }

            player = newPlayer
            activeMessageId = messageId
            duration = newPlayer.duration > 0 ? newPlayer.duration : TimeInterval(max(fallbackDuration, 1))
            currentTime = 0
            isPlaying = true
            startTimer()
            onStarted?()
        } catch {
            errorMessage = "不支持播放此音频格式：\(error.localizedDescription)"
        }
    }

    private func startTimer() {
        stopTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedURL = player.url
        Task { @MainActor [weak self] in
            guard let self, self.player?.url == finishedURL else { return }
            self.stopTimer()
            self.isPlaying = false
            self.currentTime = 0
            self.activeMessageId = nil
            self.player = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Swift.Error)?) {
        let failedURL = player.url
        let description = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, self.player?.url == failedURL else { return }
            self.stop()
            if let description {
                self.errorMessage = "音频播放出错：\(description)"
            }
        }
    }
}
