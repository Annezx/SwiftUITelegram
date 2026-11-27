import AVFoundation
import Foundation
import Observation

struct RecordedVoiceNote: Sendable {
    let fileURL: URL
    let duration: Int
    let waveform: Data
}

/// Records macOS microphone audio directly into AAC (`.m4a`), which TDLib accepts natively
/// in `InputVoiceNote`, while capturing live amplitude samples for waveform visualization.
@MainActor
@Observable
final class VoiceRecorderManager: NSObject {
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var recordingURL: URL?
    private var recordedSamples: [Float] = []

    private(set) var isRecording: Bool = false
    private(set) var elapsedDuration: TimeInterval = 0
    private(set) var liveLevels: [Float] = []
    var errorMessage: String?

    func startRecording() async {
        guard !isRecording else { return }
        errorMessage = nil

        let authorized = await ensureMicrophonePermission()
        guard authorized else {
            errorMessage = "未获得麦克风权限，请在「系统设置 → 隐私与安全性 → 麦克风」中允许 SwiftUITelegram。"
            return
        }

        let dir = AppConfiguration.outgoingStagingDirectory
            .appendingPathComponent("voice-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let outputURL = dir.appendingPathComponent("voice_note.m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64_000,
        ]

        do {
            let newRecorder = try AVAudioRecorder(url: outputURL, settings: settings)
            newRecorder.isMeteringEnabled = true
            guard newRecorder.prepareToRecord(), newRecorder.record() else {
                errorMessage = "无法启动麦克风录音，请检查系统音频输入设备。"
                try? FileManager.default.removeItem(at: dir)
                return
            }

            recorder = newRecorder
            recordingURL = outputURL
            recordedSamples = []
            liveLevels = []
            elapsedDuration = 0
            isRecording = true
            startMeterTimer()
        } catch {
            errorMessage = "录音初始化失败：\(error.localizedDescription)"
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func finishRecording() -> RecordedVoiceNote? {
        guard isRecording, let recorder, let url = recordingURL else {
            return nil
        }

        let finalDuration = max(recorder.currentTime, elapsedDuration)
        stopMeterTimer()
        recorder.stop()

        let samples = recordedSamples
        self.recorder = nil
        self.recordingURL = nil
        self.recordedSamples = []
        self.liveLevels = []
        self.isRecording = false
        self.elapsedDuration = 0

        guard finalDuration >= 0.4 else {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            errorMessage = "录音时间太短。"
            return nil
        }

        let waveform = WaveformCodec.encode(levels: samples, maxSamples: 63)
        return RecordedVoiceNote(
            fileURL: url,
            duration: max(1, Int(finalDuration.rounded())),
            waveform: waveform
        )
    }

    func cancelRecording() {
        stopMeterTimer()
        recorder?.stop()
        recorder = nil

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        recordingURL = nil
        recordedSamples = []
        liveLevels = []
        elapsedDuration = 0
        isRecording = false
    }

    // MARK: - Private

    private func ensureMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func startMeterTimer() {
        stopMeterTimer()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let recorder = self.recorder, recorder.isRecording else { return }
                recorder.updateMeters()
                self.elapsedDuration = recorder.currentTime

                let decibels = recorder.averagePower(forChannel: 0)
                let normalized = Self.normalizedPower(fromDecibels: decibels)
                self.recordedSamples.append(normalized)

                var recent = self.liveLevels
                recent.append(normalized)
                if recent.count > 36 {
                    recent.removeFirst(recent.count - 36)
                }
                self.liveLevels = recent
            }
        }
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private static func normalizedPower(fromDecibels dB: Float) -> Float {
        if dB <= -55 { return 0.05 }
        if dB >= -2 { return 1.0 }
        let linear = (dB + 55.0) / 53.0
        return max(0.05, min(1.0, pow(linear, Float(1.35))))
    }
}
