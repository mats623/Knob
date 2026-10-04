import AudioToolbox
import CoreAudio
import Foundation

enum SoftwareVolumeError: LocalizedError {
    case missingDeviceUID
    case coreAudio(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingDeviceUID: "Ausgabegerät nicht gefunden"
        case let .coreAudio(step, status): "\(step) fehlgeschlagen (\(status))"
        }
    }
}

private final class GainState {
    var target: Float = 1
    var current: Float = 1
}

/// Routes all system audio through a Core Audio process tap and plays it back
/// on the output device with our own gain applied. Works for outputs without
/// a hardware volume control (HDMI, DisplayPort).
final class SoftwareVolume {
    private(set) var device = AudioDeviceID(kAudioObjectUnknown)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "knob.software-volume", qos: .userInteractive)
    private let state = GainState()

    var isRunning: Bool { procID != nil }

    var gain: Float {
        get { state.target }
        set { state.target = max(0, min(1, newValue)) }
    }

    func start(outputDevice: AudioDeviceID) throws {
        stop()
        do {
            try setUp(outputDevice: outputDevice)
            device = outputDevice
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            self.procID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        device = AudioDeviceID(kAudioObjectUnknown)
    }

    private func setUp(outputDevice: AudioDeviceID) throws {
        guard let outputUID = AudioDevices.uid(outputDevice) else { throw SoftwareVolumeError.missingDeviceUID }

        // Never tap our own playback, otherwise we'd feed ourselves.
        let ownProcess = AudioDevices.processObject(for: getpid()).map { [$0] } ?? []
        let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: ownProcess)
        tap.uuid = UUID()
        tap.name = "Knob"
        tap.isPrivate = true
        tap.muteBehavior = .mutedWhenTapped

        var status = AudioHardwareCreateProcessTap(tap, &tapID)
        guard status == noErr else { throw SoftwareVolumeError.coreAudio("Audio-Tap", status) }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Knob Output",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tap.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr else { throw SoftwareVolumeError.coreAudio("Aggregate-Gerät", status) }

        let state = self.state
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, output, _ in
            Self.render(input: input, output: output, state: state)
        }
        guard status == noErr, let procID else { throw SoftwareVolumeError.coreAudio("Audio-Callback", status) }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw SoftwareVolumeError.coreAudio("Audio-Start", status) }
    }

    /// Copies tapped samples to the output, ramping the gain across the buffer to avoid clicks.
    private static func render(input: UnsafePointer<AudioBufferList>,
                               output: UnsafeMutablePointer<AudioBufferList>,
                               state: GainState) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let startGain = state.current
        let targetGain = state.target

        var inputChannels = 0
        for buffer in inputs { inputChannels += Int(buffer.mNumberChannels) }

        var channelBase = 0
        for buffer in outputs {
            guard let data = buffer.mData, buffer.mNumberChannels > 0 else { continue }
            let channels = Int(buffer.mNumberChannels)
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            let destination = data.assumingMemoryBound(to: Float.self)
            memset(data, 0, Int(buffer.mDataByteSize))

            for channel in 0..<channels where channelBase + channel < inputChannels {
                // Find the matching tapped channel (interleaved or not).
                var index = channelBase + channel
                var source: UnsafeMutablePointer<Float>?
                var stride = 1
                var sourceFrames = 0
                for inBuffer in inputs {
                    let count = Int(inBuffer.mNumberChannels)
                    if index < count {
                        if let inData = inBuffer.mData, count > 0 {
                            source = inData.assumingMemoryBound(to: Float.self) + index
                            stride = count
                            sourceFrames = Int(inBuffer.mDataByteSize) / (MemoryLayout<Float>.size * count)
                        }
                        break
                    }
                    index -= count
                }
                guard let source else { continue }

                let n = min(frames, sourceFrames)
                guard n > 0 else { continue }
                let step = (targetGain - startGain) / Float(n)
                var gain = startGain
                for frame in 0..<n {
                    gain += step
                    destination[frame * channels + channel] = source[frame * stride] * gain
                }
            }
            channelBase += channels
        }
        state.current = targetGain
    }
}
