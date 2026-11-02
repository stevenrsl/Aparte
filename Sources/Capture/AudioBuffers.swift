import AVFoundation
import Accelerate

public enum AudioBuffers {
    /// A mono Float32 copy of any PCM buffer, channels averaged.
    ///
    /// Both sides of a call arrive in different shapes: the microphone as
    /// planar floats, the Mac's sound as interleaved stereo from the tap. Speech
    /// needs one channel, and a file per side needs only one, so everything is
    /// brought to the same shape at the door. It is also a copy, which matters
    /// for the tap, whose buffers belong to Core Audio and are gone when the
    /// callback returns.
    public static func mono(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: buffer.format.sampleRate,
                                         channels: 1, interleaved: false),
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let dst = out.floatChannelData?[0]
        else { return nil }
        out.frameLength = AVAudioFrameCount(frames)

        let scale = 1 / Float(channels)
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let src = buffer.floatChannelData else { return nil }
            if buffer.format.isInterleaved {
                let p = src[0]
                for i in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<channels { sum += p[i * channels + c] }
                    dst[i] = sum * scale
                }
            } else if channels == 1 {
                dst.update(from: src[0], count: frames)
            } else {
                for i in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<channels { sum += src[c][i] }
                    dst[i] = sum * scale
                }
            }
        case .pcmFormatInt16:
            guard let src = buffer.int16ChannelData else { return nil }
            let interleaved = buffer.format.isInterleaved
            for i in 0..<frames {
                var sum: Float = 0
                for c in 0..<channels {
                    let sample = interleaved ? src[0][i * channels + c] : src[c][i]
                    sum += Float(sample) / 32768
                }
                dst[i] = sum * scale
            }
        case .pcmFormatInt32:
            guard let src = buffer.int32ChannelData else { return nil }
            let interleaved = buffer.format.isInterleaved
            for i in 0..<frames {
                var sum: Float = 0
                for c in 0..<channels {
                    let sample = interleaved ? src[0][i * channels + c] : src[c][i]
                    sum += Float(sample) / 2_147_483_648
                }
                dst[i] = sum * scale
            }
        default:
            return nil
        }
        return out
    }

    /// Loudness of a mono buffer on a 0...1 scale that suits the eye: RMS in
    /// decibels, with -55 dB as silence and -10 dB as full.
    public static func level(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(data, 1, &rms, vDSP_Length(buffer.frameLength))
        let db = 20 * log10(max(rms, 1e-7))
        return min(1, max(0, (db + 55) / 45))
    }
}

/// Converts a stream of mono buffers to the format the speech analyzer wants,
/// keeping the resampler's state between buffers so there is no click at every
/// seam.
final class StreamConverter {
    let source: AVAudioFormat
    private let converter: AVAudioConverter?
    private let target: AVAudioFormat

    init(from source: AVAudioFormat, to target: AVAudioFormat) {
        self.source = source
        self.target = target
        converter = source == target ? nil : AVAudioConverter(from: source, to: target)
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var handed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if handed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            handed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, out.frameLength > 0 else { return nil }
        return out
    }
}
