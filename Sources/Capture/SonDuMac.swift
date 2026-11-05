import AVFoundation
import CoreAudio
import os

// MARK: - The Mac's sound


/// Everything the Mac plays, through a Core Audio process tap (macOS 14.2 and
/// later). This is how a Teams, Meet or Zoom call is heard without joining it
/// as a bot and without the screen recording permission ScreenCaptureKit would
/// need: the tap asks only for "system audio recording", and it hears the call
/// whichever app or browser tab is playing it.
///
/// The tap is global, minus this app, so playing back a meeting's audio inside
/// Aparté is never transcribed into the next one. It is wrapped in a
/// private aggregate device, which is what gives it a clock and an IO callback.
public final class SystemAudioSource: AudioSource {
    public var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "eu.stevenrsl.aparte.system-audio", qos: .userInitiated)
    private var mesure = FrequenceMesuree(annoncee: 48000)
    private var enAttente: [AVAudioPCMBuffer] = []
    private var formats: [Double: AVAudioFormat] = [:]

    public init() {}

    public func start() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: Self.ownProcessObject().map { [$0] } ?? [])
        description.uuid = UUID()
        description.name = "Aparté"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { throw ErreurCapture.sonDuMac("création du tap", status) }
        tapID = tap

        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &streamDescription)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &streamDescription) else {
            stop()
            throw ErreurCapture.sonDuMac("format du tap", status)
        }
        mesure = FrequenceMesuree(annoncee: format.sampleRate)
        enAttente = []
        formats = [format.sampleRate: format]
        let formatDuTap = streamDescription

        let outputUID = try Self.defaultOutputDeviceUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Aparté",
            kAudioAggregateDeviceUIDKey: "eu.stevenrsl.aparte.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var aggregateDevice = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateDevice)
        guard status == noErr else {
            stop()
            throw ErreurCapture.sonDuMac("périphérique agrégé", status)
        }
        aggregateID = aggregateDevice

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, inputTime, _, _ in
            guard let self,
                  let brut = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil)
            else { return }
            let horloge = inputTime.pointee.mFlags.contains(.hostTimeValid) ? inputTime.pointee.mHostTime : AudioGetCurrentHostTime()
            let temps = Double(AudioConvertHostTimeToNanos(horloge)) / 1_000_000_000
            self.remettre(brut, input: input, a: temps, description: formatDuTap)
        }
        guard status == noErr else {
            stop()
            throw ErreurCapture.sonDuMac("rappel audio", status)
        }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            stop()
            throw ErreurCapture.sonDuMac("démarrage", status)
        }
    }

    /// Le tap annonce son format une fois pour toutes : chaque tampon repart sous la fréquence mesurée.
    /// Le temps de la première mesure, le son attend : mal étiqueté, il serait déjà écrit trop vite.
    private func remettre(_ brut: AVAudioPCMBuffer, input: UnsafePointer<AudioBufferList>, a temps: Double,
                          description: AudioStreamBasicDescription) {
        guard let frequence = mesure.observer(images: Int(brut.frameLength), a: temps) else {
            if let copie = AudioBuffers.mono(brut) { enAttente.append(copie) }
            return
        }
        if frequence != mesure.annoncee, formats[frequence] == nil {
            Logger(subsystem: "eu.stevenrsl.aparte", category: "capture")
                .notice("Son du Mac annoncé à \(self.mesure.annoncee, privacy: .public) Hz, mesuré à \(frequence, privacy: .public) Hz")
        }
        for copie in enAttente {
            if let reetiquete = Self.reetiqueter(copie, a: frequence) { onBuffer?(reetiquete) }
        }
        enAttente = []
        if formats[frequence] == nil {
            var corrigee = description
            corrigee.mSampleRate = frequence
            formats[frequence] = AVAudioFormat(streamDescription: &corrigee)
        }
        guard let juste = formats[frequence] else { return }
        if juste == brut.format {
            onBuffer?(brut)
        } else if let tampon = AVAudioPCMBuffer(pcmFormat: juste, bufferListNoCopy: input, deallocator: nil) {
            onBuffer?(tampon)
        }
    }

    static func reetiqueter(_ mono: AVAudioPCMBuffer, a frequence: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: frequence, channels: 1, interleaved: false),
              let sortie = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: mono.frameLength),
              let source = mono.floatChannelData?[0], let cible = sortie.floatChannelData?[0] else { return nil }
        sortie.frameLength = mono.frameLength
        cible.update(from: source, count: Int(mono.frameLength))
        return sortie
    }

    public func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private static func ownProcessObject() -> AudioObjectID? {
        var pid = ProcessInfo.processInfo.processIdentifier
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    private static func defaultOutputDeviceUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw ErreurCapture.sonDuMac("sortie par défaut", status) }

        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        guard status == noErr, let value = uid?.takeRetainedValue() else {
            throw ErreurCapture.sonDuMac("identifiant de la sortie", status)
        }
        return value as String
    }
}
