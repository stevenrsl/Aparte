import AVFoundation
import AudioToolbox
import Foundation

/// How a meeting's sound is kept on disk: as it is heard, and once it is over.
///
/// An MPEG-4 file (`.m4a`) can be read only once its index is written, when it
/// is closed. A meeting killed on the way (a crash, `kill -9`, a phone out of
/// battery or out of memory) left a file nothing could open, and the whole
/// recording was lost (reproduced on 2026-09-24). So while listening, each side
/// is written as ADTS AAC (`.aac`): the same AAC at 64 kbit/s, but a stream of
/// frames that each carry their own header, readable up to the last frame
/// written. Killed after 20 s of real-time writing, the `.aac` read back 20.3 s;
/// the `.m4a` did not open ('dta?'). A CAF holding AAC was no better: its
/// packet sizes are written at the close too, and it read 0 s.
///
/// When listening stops, and when an interrupted listening is found at the next
/// launch, the `.aac` is put into an `.m4a` without being encoded again (the
/// same packets, 0.14 s for 26 minutes) and moves to `.trash/`. Everything that
/// reads a recording (playback, transcription, voices) reads that `.m4a`, as
/// it always has. Should the move fail, the `.aac` stays listed on the page:
/// AVAudioFile reads it too.
public enum Recording {
    static let growingExtension = "aac"
    static let finishedExtension = "m4a"

    /// The file a side is written to while listening: its final path, in ADTS.
    static func growingPath(for path: String) -> String {
        (path as NSString).deletingPathExtension + "." + growingExtension
    }

    static func isGrowing(_ path: String) -> Bool {
        (path as NSString).pathExtension.lowercased() == growingExtension
    }

    /// Opens the file a side is written to. AAC, mono, 64 kbit/s: about 30 MB
    /// for an hour of one side, and plenty for speech. The `.aac` extension is
    /// what makes AVAudioFile write ADTS.
    public static func open(_ url: URL, sampleRate: Double) throws -> AVAudioFile {
        try AVAudioFile(forWriting: url,
                        settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                   AVSampleRateKey: sampleRate,
                                   AVNumberOfChannelsKey: 1,
                                   AVEncoderBitRateKey: 64_000],
                        commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    /// Seconds of sound a file holds, or nil when it cannot be read.
    public static func seconds(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    enum Failure: Error {
        case audioFile(String, OSStatus)
        case unreadable
    }

    /// Puts an ADTS file's packets into an MPEG-4 file, without encoding them
    /// again. The `.m4a` is written beside it under a temporary name and
    /// takes its place only once it reads back as long as the `.aac`.
    public static func remux(_ source: URL, to target: URL) throws {
        func check(_ status: OSStatus, _ step: String) throws {
            if status != noErr { throw Failure.audioFile(step, status) }
        }
        var inputID: AudioFileID?
        try check(AudioFileOpenURL(source as CFURL, .readPermission, kAudioFileAAC_ADTSType, &inputID), "open")
        guard let input = inputID else { throw Failure.unreadable }
        defer { AudioFileClose(input) }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioFileGetProperty(input, kAudioFilePropertyDataFormat, &size, &format), "format")

        let temporary = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(8)).m4a")
        var outputID: AudioFileID?
        try check(AudioFileCreateWithURL(temporary as CFURL, kAudioFileM4AType, &format, .eraseFile, &outputID), "create")
        guard let output = outputID else { throw Failure.unreadable }
        var closed = false
        defer {
            if !closed { AudioFileClose(output) }
            try? FileManager.default.removeItem(at: temporary)
        }

        var cookieSize: UInt32 = 0
        if AudioFileGetPropertyInfo(input, kAudioFilePropertyMagicCookieData, &cookieSize, nil) == noErr, cookieSize > 0 {
            var cookie = [UInt8](repeating: 0, count: Int(cookieSize))
            try check(AudioFileGetProperty(input, kAudioFilePropertyMagicCookieData, &cookieSize, &cookie), "cookie")
            try check(AudioFileSetProperty(output, kAudioFilePropertyMagicCookieData, cookieSize, cookie), "cookie")
        }

        var largest: UInt32 = 0
        size = 4
        try check(AudioFileGetProperty(input, kAudioFilePropertyMaximumPacketSize, &size, &largest), "packet size")
        let perRead: UInt32 = 512
        var data = [UInt8](repeating: 0, count: Int(max(largest, 2048) * perRead))
        var descriptions = [AudioStreamPacketDescription](repeating: .init(), count: Int(perRead))
        var read: Int64 = 0
        var written: Int64 = 0
        while true {
            var bytes = UInt32(data.count)
            var count = perRead
            let status = AudioFileReadPacketData(input, false, &bytes, &descriptions, read, &count, &data)
            if count == 0 { break }
            // The last frame of a file cut short can be incomplete: what came before is kept.
            if status != noErr, status != kAudioFileEndOfFileError { break }
            var toWrite = count
            try check(AudioFileWritePackets(output, false, bytes, descriptions, written, &toWrite, data), "write")
            read += Int64(count)
            written += Int64(toWrite)
        }
        guard written > 0 else { throw Failure.unreadable }
        try check(AudioFileClose(output), "close")
        closed = true

        // The M4A leaves out the encoder's priming (2,112 frames, 44 ms at
        // 48 kHz), which ADTS cannot say, so it reads that much shorter.
        guard let heard = seconds(of: temporary), let before = seconds(of: source), heard >= before - 0.5
        else { throw Failure.unreadable }
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: temporary, to: target)
    }
}
