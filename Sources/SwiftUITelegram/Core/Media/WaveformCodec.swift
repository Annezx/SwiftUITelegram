import Foundation

/// Encodes and decodes Telegram's 5-bit packed voice-note waveform representation.
enum WaveformCodec {
    /// Decodes a 5-bit packed waveform byte stream into normalized `[0.0 ... 1.0]` bar heights,
    /// resampled to `targetBars` for clean UI rendering.
    static func decode(_ data: Data, targetBars: Int = 36) -> [Float] {
        guard targetBars > 0 else { return [] }
        let totalSamples = (data.count * 8) / 5
        guard totalSamples > 0 else {
            return defaultWaveform(barCount: targetBars)
        }

        let sampleCount = min(totalSamples, 128)
        var rawSamples = [Float]()
        rawSamples.reserveCapacity(sampleCount)

        data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            let byteCount = data.count

            for i in 0..<sampleCount {
                let bitOffset = i * 5
                let byteIndex = bitOffset / 8
                let bitShift = bitOffset % 8

                var value = UInt16(bytes[byteIndex])
                if byteIndex + 1 < byteCount {
                    value |= UInt16(bytes[byteIndex + 1]) << 8
                }
                let sample = (value >> bitShift) & 0x1F
                rawSamples.append(Float(sample) / 31.0)
            }
        }

        return resample(rawSamples, to: targetBars)
    }

    /// Encodes normalized `[0.0 ... 1.0]` amplitude samples into Telegram's 5-bit packed waveform `Data`.
    static func encode(levels: [Float], maxSamples: Int = 63) -> Data {
        guard !levels.isEmpty else { return Data() }
        let resampled = resample(levels, to: min(max(levels.count, 16), maxSamples))
        let totalBits = resampled.count * 5
        let byteCount = (totalBits + 7) / 8
        var output = [UInt8](repeating: 0, count: byteCount)

        for (index, level) in resampled.enumerated() {
            let clamped = max(0, min(1, level))
            let quantized = UInt16((clamped * 31.0).rounded()) & 0x1F
            let bitOffset = index * 5
            let byteIndex = bitOffset / 8
            let bitShift = bitOffset % 8

            output[byteIndex] |= UInt8((quantized << bitShift) & 0xFF)
            if bitShift > 3, byteIndex + 1 < byteCount {
                output[byteIndex + 1] |= UInt8((quantized >> (8 - bitShift)) & 0xFF)
            }
        }

        return Data(output)
    }

    static func resample(_ samples: [Float], to count: Int) -> [Float] {
        guard !samples.isEmpty, count > 0 else { return [] }
        if samples.count == count {
            return samples
        }
        var result = [Float](repeating: 0, count: count)
        let ratio = Float(samples.count) / Float(count)

        for i in 0..<count {
            let start = Int(Float(i) * ratio)
            let end = max(start + 1, min(samples.count, Int(Float(i + 1) * ratio)))
            var peak: Float = 0
            for j in start..<end {
                peak = max(peak, samples[j])
            }
            result[i] = peak
        }
        return result
    }

    private static func defaultWaveform(barCount: Int) -> [Float] {
        (0..<barCount).map { idx in
            let phase = Double(idx) / Double(max(barCount - 1, 1)) * .pi * 3.0
            return Float(0.22 + 0.35 * abs(sin(phase)))
        }
    }
}
