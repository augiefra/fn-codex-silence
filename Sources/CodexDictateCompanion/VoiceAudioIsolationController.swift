import CoreAudio
import Foundation

private let discardAudioIOProc: AudioDeviceIOProc = { _, _, _, _, _, _, _ in
  noErr
}

enum VoiceAudioIsolationError: Error, CustomStringConvertible {
  case createTap(OSStatus)
  case createAggregateDevice(OSStatus)
  case createIOProc(OSStatus)
  case startIO(OSStatus)

  var description: String {
    switch self {
    case .createTap(let status):
      return "Unable to create Voice audio isolation. OSStatus: \(status)"
    case .createAggregateDevice(let status):
      return "Unable to create the Voice isolation audio device. OSStatus: \(status)"
    case .createIOProc(let status):
      return "Unable to prepare Voice audio isolation. OSStatus: \(status)"
    case .startIO(let status):
      return "Unable to start Voice audio isolation. OSStatus: \(status)"
    }
  }
}

final class VoiceAudioIsolationController {
  private let allowedBundleIDs = [
    "com.openai.codex",
    "com.openai.codex.helper"
  ]

  private var tapID = AudioObjectID(kAudioObjectUnknown)
  private var aggregateDeviceID = AudioDeviceID(kAudioObjectUnknown)
  private var ioProcID: AudioDeviceIOProcID?

  var isActive: Bool {
    ioProcID != nil
  }

  func start() throws {
    guard !isActive else {
      return
    }

    let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
    tapDescription.name = "Codex Voice Isolation"
    tapDescription.uuid = UUID()
    tapDescription.isPrivate = true
    tapDescription.muteBehavior = .mutedWhenTapped
    tapDescription.bundleIDs = allowedBundleIDs
    tapDescription.isProcessRestoreEnabled = true

    var newTapID = AudioObjectID(kAudioObjectUnknown)
    var status = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
    guard status == noErr else {
      throw VoiceAudioIsolationError.createTap(status)
    }
    tapID = newTapID

    do {
      let aggregateDescription: [String: Any] = [
        kAudioAggregateDeviceNameKey: "Codex Voice Isolation",
        kAudioAggregateDeviceUIDKey: "com.augiefra.codex-dictate-companion.voice-isolation.\(UUID().uuidString)",
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceTapListKey: [[
          kAudioSubTapUIDKey: tapDescription.uuid.uuidString
        ]]
      ]

      var newAggregateDeviceID = AudioDeviceID(kAudioObjectUnknown)
      status = AudioHardwareCreateAggregateDevice(
        aggregateDescription as CFDictionary,
        &newAggregateDeviceID
      )
      guard status == noErr else {
        throw VoiceAudioIsolationError.createAggregateDevice(status)
      }
      aggregateDeviceID = newAggregateDeviceID

      var newIOProcID: AudioDeviceIOProcID?
      status = AudioDeviceCreateIOProcID(
        aggregateDeviceID,
        discardAudioIOProc,
        nil,
        &newIOProcID
      )
      guard status == noErr, let newIOProcID else {
        throw VoiceAudioIsolationError.createIOProc(status)
      }
      ioProcID = newIOProcID

      status = AudioDeviceStart(aggregateDeviceID, newIOProcID)
      guard status == noErr else {
        throw VoiceAudioIsolationError.startIO(status)
      }
    } catch {
      stop()
      throw error
    }
  }

  func stop() {
    if let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
      let stopStatus = AudioDeviceStop(aggregateDeviceID, ioProcID)
      if stopStatus != noErr {
        Logger.error("codex-dictate-companion: Voice isolation stop failed. OSStatus: \(stopStatus)")
      }

      let destroyStatus = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
      if destroyStatus != noErr {
        Logger.error("codex-dictate-companion: Voice isolation IO cleanup failed. OSStatus: \(destroyStatus)")
      }
    }
    ioProcID = nil

    if aggregateDeviceID != kAudioObjectUnknown {
      let status = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
      if status != noErr {
        Logger.error("codex-dictate-companion: Voice isolation device cleanup failed. OSStatus: \(status)")
      }
      aggregateDeviceID = AudioDeviceID(kAudioObjectUnknown)
    }

    if tapID != kAudioObjectUnknown {
      let status = AudioHardwareDestroyProcessTap(tapID)
      if status != noErr {
        Logger.error("codex-dictate-companion: Voice isolation tap cleanup failed. OSStatus: \(status)")
      }
      tapID = AudioObjectID(kAudioObjectUnknown)
    }
  }

  deinit {
    stop()
  }
}
