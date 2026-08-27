#if os(macOS)
import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

public enum CoreAudioProcessTapError: LocalizedError, Sendable {
    case createTap(OSStatus)
    case missingTapFormat
    case defaultOutput(OSStatus)
    case outputUID(OSStatus)
    case createAggregate(OSStatus)
    case createIOProc(OSStatus)
    case startDevice(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .createTap(let status): "Unable to create Core Audio process tap (\(status))."
        case .missingTapFormat: "The process tap did not expose an audio format."
        case .defaultOutput(let status): "Unable to resolve the default system output (\(status))."
        case .outputUID(let status): "Unable to resolve the default system output UID (\(status))."
        case .createAggregate(let status): "Unable to create the private process-tap device (\(status))."
        case .createIOProc(let status): "Unable to create the process-tap I/O callback (\(status))."
        case .startDevice(let status): "Unable to start process audio capture (\(status))."
        }
    }
}

public final class CoreAudioProcessTapCapture: @unchecked Sendable {
    private let source: AudioProcessSource
    private let queue = DispatchQueue(label: "SFCall.CoreAudioProcessTap", qos: .userInitiated)
    private let stateLock = NSLock()

    private var processTapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var delivery: PCMDeliveryBox?

    public init(source: AudioProcessSource) {
        self.source = source
    }

    public func start(
        onAudio: @escaping (AVAudioPCMBuffer) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        stop(completion: nil)

        do {
            let tapDescription = CATapDescription(stereoMixdownOfProcesses: [source.id])
            tapDescription.uuid = UUID()
            tapDescription.muteBehavior = .unmuted

            var tapID = AudioObjectID(kAudioObjectUnknown)
            let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &tapID)
            guard tapStatus == noErr else {
                throw CoreAudioProcessTapError.createTap(tapStatus)
            }
            processTapID = tapID

            var streamDescription = try Self.readTapFormat(tapID)
            guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
                throw CoreAudioProcessTapError.missingTapFormat
            }

            let outputID = try Self.defaultSystemOutput()
            let outputUID = try Self.deviceUID(outputID)

            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "SFCall Process Tap \(source.pid)",
                kAudioAggregateDeviceUIDKey: "com.sfcall.tap.\(UUID().uuidString)",
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [kAudioSubDeviceUIDKey: outputUID]
                ],
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                        kAudioSubTapDriftCompensationKey: true
                    ]
                ]
            ]

            var aggregateID = AudioObjectID(kAudioObjectUnknown)
            let aggregateStatus = AudioHardwareCreateAggregateDevice(
                aggregateDescription as CFDictionary,
                &aggregateID
            )
            guard aggregateStatus == noErr else {
                throw CoreAudioProcessTapError.createAggregate(aggregateStatus)
            }
            aggregateDeviceID = aggregateID

            let delivery = PCMDeliveryBox(onAudio)
            self.delivery = delivery

            var procID: AudioDeviceIOProcID?
            let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
                &procID,
                aggregateID,
                queue
            ) { _, inputData, _, _, _ in
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    bufferListNoCopy: inputData,
                    deallocator: nil
                ) else { return }
                delivery.deliver(buffer)
            }
            guard ioStatus == noErr else {
                throw CoreAudioProcessTapError.createIOProc(ioStatus)
            }
            deviceProcID = procID

            let startStatus = AudioDeviceStart(aggregateID, procID)
            guard startStatus == noErr else {
                throw CoreAudioProcessTapError.startDevice(startStatus)
            }

            completion(nil)
        } catch {
            cleanup()
            completion(error)
        }
    }

    public func stop(completion: (@Sendable () -> Void)? = nil) {
        cleanup()
        completion?()
    }

    deinit {
        cleanup()
    }

    private func cleanup() {
        stateLock.lock()
        let aggregateID = aggregateDeviceID
        let tapID = processTapID
        let procID = deviceProcID
        aggregateDeviceID = kAudioObjectUnknown
        processTapID = kAudioObjectUnknown
        deviceProcID = nil
        delivery = nil
        stateLock.unlock()

        if aggregateID != kAudioObjectUnknown {
            if let procID {
                _ = AudioDeviceStop(aggregateID, procID)
                _ = AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            _ = AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyProcessTap(tapID)
        }
    }

    private static func defaultSystemOutput() throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr else { throw CoreAudioProcessTapError.defaultOutput(status) }
        return value
    }

    private static func deviceUID(_ deviceID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { throw CoreAudioProcessTapError.outputUID(status) }
        return value as String
    }

    private static func readTapFormat(_ tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &value)
        guard status == noErr else { throw CoreAudioProcessTapError.missingTapFormat }
        return value
    }
}

private final class PCMDeliveryBox: @unchecked Sendable {
    private let handler: (AVAudioPCMBuffer) -> Void

    init(_ handler: @escaping (AVAudioPCMBuffer) -> Void) {
        self.handler = handler
    }

    func deliver(_ buffer: AVAudioPCMBuffer) {
        handler(buffer)
    }
}
#endif
