import AppKit
import AudioToolbox
import CoreAudio
import Foundation

private enum AppConstants {
  static let appName = "Codex Dictate Companion"
  static let bundleID = "com.augiefra.codex-dictate-companion"
  static let logDirectoryName = "codex-dictate-companion"
}

private enum Logger {
  private static var logURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/\(AppConstants.logDirectoryName)", isDirectory: true)
      .appendingPathComponent("out.log")
  }

  static func info(_ message: String) {
    print(message)
    fflush(stdout)
    append(message)
  }

  static func error(_ message: String) {
    fputs("\(message)\n", stderr)
    fflush(stderr)
    append(message)
  }

  private static func append(_ message: String) {
    do {
      try FileManager.default.createDirectory(
        at: logURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )

      let line = "\(Date()) \(message)\n"
      let data = Data(line.utf8)

      if FileManager.default.fileExists(atPath: logURL.path) {
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
      } else {
        try data.write(to: logURL)
      }
    } catch {
      // Logging must never break keyboard monitoring.
    }
  }
}

private enum AppError: Error, CustomStringConvertible {
  case eventTapUnavailable
  case invalidArgument(String)
  case audioDeviceUnavailable(OSStatus)
  case audioMuteReadFailed(OSStatus)
  case audioMuteWriteFailed(OSStatus)
  case audioVolumeReadFailed(OSStatus)
  case audioVolumeWriteFailed(OSStatus)
  case audioInputDeviceUnavailable(OSStatus)
  case audioInputDeviceWriteFailed(OSStatus)

  var description: String {
    switch self {
    case .eventTapUnavailable:
      return "Unable to create the keyboard event tap. Grant Input Monitoring permission, then restart \(AppConstants.appName)."
    case .invalidArgument(let value):
      return "Invalid argument: \(value)"
    case .audioDeviceUnavailable(let status):
      return "Unable to find the default output audio device. OSStatus: \(status)"
    case .audioMuteReadFailed(let status):
      return "Unable to read the output mute state. OSStatus: \(status)"
    case .audioMuteWriteFailed(let status):
      return "Unable to update the output mute state. OSStatus: \(status)"
    case .audioVolumeReadFailed(let status):
      return "Unable to read the output volume. OSStatus: \(status)"
    case .audioVolumeWriteFailed(let status):
      return "Unable to update the output volume. OSStatus: \(status)"
    case .audioInputDeviceUnavailable(let status):
      return "Unable to find a usable input audio device. OSStatus: \(status)"
    case .audioInputDeviceWriteFailed(let status):
      return "Unable to update the default input audio device. OSStatus: \(status)"
    }
  }
}

private struct Options {
  var showEvents = false
  var testMute = false
  var checkPermissions = false
  var requestPermissions = false
}

private enum MenuBarIcon: String, CaseIterable {
  case microphone
  case waveform
  case command

  var title: String {
    switch self {
    case .microphone: return "Micro"
    case .waveform: return "Wave"
    case .command: return "Command"
    }
  }

  var symbolName: String {
    switch self {
    case .microphone: return "mic.fill"
    case .waveform: return "waveform"
    case .command: return "command"
    }
  }
}

private final class Preferences {
  private enum Keys {
    static let icon = "menuBarIcon"
    static let monitorEnabled = "monitorEnabled"
    static let airPodsStereoGuardEnabled = "airPodsStereoGuardEnabled"
  }

  private let defaults = UserDefaults.standard

  var icon: MenuBarIcon {
    get {
      if let rawValue = defaults.string(forKey: Keys.icon),
         let icon = MenuBarIcon(rawValue: rawValue) {
        return icon
      }
      return .microphone
    }
    set {
      defaults.set(newValue.rawValue, forKey: Keys.icon)
    }
  }

  var monitorEnabled: Bool {
    get {
      if defaults.object(forKey: Keys.monitorEnabled) == nil {
        return true
      }
      return defaults.bool(forKey: Keys.monitorEnabled)
    }
    set {
      defaults.set(newValue, forKey: Keys.monitorEnabled)
    }
  }

  var airPodsStereoGuardEnabled: Bool {
    get {
      if defaults.object(forKey: Keys.airPodsStereoGuardEnabled) == nil {
        return true
      }
      return defaults.bool(forKey: Keys.airPodsStereoGuardEnabled)
    }
    set {
      defaults.set(newValue, forKey: Keys.airPodsStereoGuardEnabled)
    }
  }
}

private final class AudioMuteController {
  private enum SilenceState {
    case mute(previousMuted: Bool)
    case volume(controls: [VolumeControl])
  }

  private enum VolumeAPI {
    case audioHardwareService
    case audioObject
  }

  private struct VolumeControl {
    let api: VolumeAPI
    let address: AudioObjectPropertyAddress
    let previousVolume: Float32
  }

  private var silenceStates: [AudioDeviceID: SilenceState] = [:]
  private var skippedOutputLogDates: [AudioDeviceID: Date] = [:]
  private var silenceTimer: Timer?

  func mute() {
    applySilenceToAllOutputs()

    if silenceTimer == nil {
      let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
        self?.applySilenceToAllOutputs()
      }
      RunLoop.main.add(timer, forMode: .common)
      silenceTimer = timer
    }
  }

  func restore() {
    silenceTimer?.invalidate()
    silenceTimer = nil

    guard !silenceStates.isEmpty else {
      return
    }

    var failedStates: [AudioDeviceID: SilenceState] = [:]

    for (deviceID, state) in silenceStates {
      do {
        switch state {
        case .mute(let previousMuted):
          try setMuted(previousMuted, deviceID: deviceID)
          Logger.info("codex-dictate-companion: restored \(deviceName(deviceID: deviceID)) to muted=\(previousMuted)")
        case .volume(let controls):
          try restoreVolume(controls, deviceID: deviceID)
          let previousVolume = controls.first?.previousVolume ?? 0
          Logger.info("codex-dictate-companion: restored \(deviceName(deviceID: deviceID)) to volume=\(String(format: "%.2f", previousVolume))")
        }
      } catch {
        Logger.error("codex-dictate-companion: \(error)")
        failedStates[deviceID] = state
      }
    }

    silenceStates = failedStates
    skippedOutputLogDates.removeAll()
  }

  func testMuteCycle() throws {
    let deviceID = try defaultOutputDeviceID()
    let name = deviceName(deviceID: deviceID)
    let originalDescription: String

    do {
      originalDescription = "muted=\(try isMuted(deviceID: deviceID))"
    } catch {
      let controls = try readVolumeControls(deviceID: deviceID)
      originalDescription = "volume=\(String(format: "%.2f", controls.first?.previousVolume ?? 0))"
    }

    Logger.info("codex-dictate-companion: current \(name) state: \(originalDescription)")
    Logger.info("codex-dictate-companion: muting for 0.5s")
    mute()
    Thread.sleep(forTimeInterval: 0.5)
    restore()
    Logger.info("codex-dictate-companion: restored test state")
  }

  func defaultOutputName() -> String {
    do {
      return deviceName(deviceID: try defaultOutputDeviceID())
    } catch {
      return "Default output"
    }
  }

  private func defaultOutputDeviceID() throws -> AudioDeviceID {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )

    guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else {
      throw AppError.audioDeviceUnavailable(status)
    }

    return deviceID
  }

  private func isMuted(deviceID: AudioDeviceID) throws -> Bool {
    var muted = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = mutePropertyAddress()

    let status = AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &size,
      &muted
    )

    guard status == noErr else {
      throw AppError.audioMuteReadFailed(status)
    }

    return muted != 0
  }

  private func setMuted(_ muted: Bool, deviceID: AudioDeviceID) throws {
    var value = UInt32(muted ? 1 : 0)
    var address = mutePropertyAddress()

    guard AudioObjectHasProperty(deviceID, &address) else {
      throw AppError.audioMuteWriteFailed(kAudioHardwareUnknownPropertyError)
    }

    let status = AudioObjectSetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      UInt32(MemoryLayout<UInt32>.size),
      &value
    )

    guard status == noErr else {
      throw AppError.audioMuteWriteFailed(status)
    }
  }

  private func volume(deviceID: AudioDeviceID) throws -> Float32 {
    var volume = Float32(0)
    var size = UInt32(MemoryLayout<Float32>.size)
    var address = volumePropertyAddress()

    let status = AudioHardwareServiceGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &size,
      &volume
    )

    guard status == noErr else {
      throw AppError.audioVolumeReadFailed(status)
    }

    return volume
  }

  private func setVolume(_ volume: Float32, controls: [VolumeControl], deviceID: AudioDeviceID) throws {
    for control in controls {
      try setVolume(volume, control: control, deviceID: deviceID)
    }
  }

  private func restoreVolume(_ controls: [VolumeControl], deviceID: AudioDeviceID) throws {
    if let currentControls = try? readVolumeControls(deviceID: deviceID),
       let previousVolume = controls.first?.previousVolume {
      do {
        try setVolume(previousVolume, controls: currentControls, deviceID: deviceID)
        return
      } catch {
        // Fall back to the controls captured before the route/profile changed.
      }
    }

    for control in controls {
      try setVolume(control.previousVolume, control: control, deviceID: deviceID)
    }
  }

  private func setVolume(_ volume: Float32, control: VolumeControl, deviceID: AudioDeviceID) throws {
    var value = min(max(volume, 0), 1)
    var address = control.address
    let size = UInt32(MemoryLayout<Float32>.size)
    let status: OSStatus

    switch control.api {
    case .audioHardwareService:
      status = AudioHardwareServiceSetPropertyData(deviceID, &address, 0, nil, size, &value)
    case .audioObject:
      status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
    }

    guard status == noErr else {
      throw AppError.audioVolumeWriteFailed(status)
    }
  }

  private func applySilenceToAllOutputs() {
    let devices = allOutputDeviceIDs()

    guard !devices.isEmpty else {
      do {
        try applySilence(to: defaultOutputDeviceID())
      } catch {
        Logger.error("codex-dictate-companion: \(error)")
      }
      return
    }

    for deviceID in devices {
      do {
        try applySilence(to: deviceID)
      } catch {
        let name = deviceName(deviceID: deviceID)
        if isNoSoftwareOutputControl(error) {
          logSkippedOutput(deviceID: deviceID, name: name)
        } else {
          Logger.error("codex-dictate-companion: \(error)")
        }
      }
    }
  }

  private func applySilence(to deviceID: AudioDeviceID) throws {
    let name = deviceName(deviceID: deviceID)

    if let existing = silenceStates[deviceID] {
      try enforceSilence(existing, deviceID: deviceID)
      return
    }

    if shouldUseVolumeFallback(deviceID: deviceID, deviceName: name) {
      try muteUsingVolumeFallback(deviceID: deviceID, deviceName: name)
      return
    }

    do {
      let previousMuted = try isMuted(deviceID: deviceID)
      try setMuted(true, deviceID: deviceID)
      silenceStates[deviceID] = .mute(previousMuted: previousMuted)
      Logger.info("codex-dictate-companion: muted \(name)")
    } catch {
      try muteUsingVolumeFallback(deviceID: deviceID, deviceName: name)
    }
  }

  private func enforceSilence(_ state: SilenceState, deviceID: AudioDeviceID) throws {
    switch state {
    case .mute:
      try setMuted(true, deviceID: deviceID)
    case .volume(let controls):
      do {
        let currentControls = try readVolumeControls(deviceID: deviceID)
        try setVolume(0, controls: currentControls, deviceID: deviceID)
      } catch {
        try setVolume(0, controls: controls, deviceID: deviceID)
      }
    }
  }

  private func logSkippedOutput(deviceID: AudioDeviceID, name: String) {
    let now = Date()
    if let previous = skippedOutputLogDates[deviceID], now.timeIntervalSince(previous) < 2 {
      return
    }

    skippedOutputLogDates[deviceID] = now
    Logger.info("codex-dictate-companion: skipped \(name), no software output mute/volume control")
  }

  private func muteUsingVolumeFallback(deviceID: AudioDeviceID, deviceName: String) throws {
    let controls = try readVolumeControls(deviceID: deviceID)
    let previousVolume = controls.first?.previousVolume ?? 0
    try setVolume(0, controls: controls, deviceID: deviceID)
    silenceStates[deviceID] = .volume(controls: controls)
    Logger.info("codex-dictate-companion: muted \(deviceName) using volume fallback, previousVolume=\(String(format: "%.2f", previousVolume))")
  }

  private func isNoSoftwareOutputControl(_ error: Error) -> Bool {
    switch error {
    case AppError.audioMuteWriteFailed(let status),
         AppError.audioVolumeReadFailed(let status),
         AppError.audioVolumeWriteFailed(let status):
      return status == kAudioHardwareUnknownPropertyError
    default:
      return false
    }
  }

  private func readVolumeControls(deviceID: AudioDeviceID) throws -> [VolumeControl] {
    if let control = try? readVolumeControl(deviceID: deviceID, api: .audioHardwareService, address: volumePropertyAddress()) {
      return [control]
    }

    if let control = try? readVolumeControl(deviceID: deviceID, api: .audioObject, address: scalarVolumePropertyAddress(element: kAudioObjectPropertyElementMain)) {
      return [control]
    }

    let channelControls = [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)].compactMap { element in
      try? readVolumeControl(deviceID: deviceID, api: .audioObject, address: scalarVolumePropertyAddress(element: element))
    }

    if !channelControls.isEmpty {
      return channelControls
    }

    throw AppError.audioVolumeReadFailed(kAudioHardwareUnknownPropertyError)
  }

  private func readVolumeControl(deviceID: AudioDeviceID, api: VolumeAPI, address: AudioObjectPropertyAddress) throws -> VolumeControl {
    var volume = Float32(0)
    var mutableAddress = address
    var size = UInt32(MemoryLayout<Float32>.size)
    let status: OSStatus

    switch api {
    case .audioHardwareService:
      status = AudioHardwareServiceGetPropertyData(deviceID, &mutableAddress, 0, nil, &size, &volume)
    case .audioObject:
      guard AudioObjectHasProperty(deviceID, &mutableAddress) else {
        throw AppError.audioVolumeReadFailed(kAudioHardwareUnknownPropertyError)
      }
      status = AudioObjectGetPropertyData(deviceID, &mutableAddress, 0, nil, &size, &volume)
    }

    guard status == noErr else {
      throw AppError.audioVolumeReadFailed(status)
    }

    return VolumeControl(api: api, address: address, previousVolume: volume)
  }

  private func shouldUseVolumeFallback(deviceID: AudioDeviceID, deviceName: String) -> Bool {
    if let transportType = transportType(deviceID: deviceID) {
      switch transportType {
      case kAudioDeviceTransportTypeBluetooth,
           kAudioDeviceTransportTypeBluetoothLE,
           kAudioDeviceTransportTypeAirPlay:
        return true
      default:
        break
      }
    }

    let lowercasedName = deviceName.lowercased()
    return lowercasedName.contains("airpods") || lowercasedName.contains("bluetooth")
  }

  private func allOutputDeviceIDs() -> [AudioDeviceID] {
    allDeviceIDs().filter { hasOutputStreams(deviceID: $0) }
  }

  private func allDeviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var size = UInt32(0)

    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
      return []
    }

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = Array(repeating: AudioDeviceID(0), count: count)

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &devices
    )

    guard status == noErr else {
      return []
    }

    return devices
  }

  private func hasOutputStreams(deviceID: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size = UInt32(0)

    return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
  }

  private func transportType(deviceID: AudioDeviceID) -> UInt32? {
    var transportType = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &size,
      &transportType
    )

    guard status == noErr else {
      return nil
    }

    return transportType
  }

  private func mutePropertyAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyMute,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  private func volumePropertyAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  private func scalarVolumePropertyAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyVolumeScalar,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: element
    )
  }

  private func deviceName(deviceID: AudioDeviceID) -> String {
    var name: CFString = "default output" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = withUnsafeMutablePointer(to: &name) { pointer in
      AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
    }

    guard status == noErr else {
      return "default output"
    }

    return name as String
  }

}

private final class AudioInputRouteController {
  private var previousInputDeviceID: AudioDeviceID?
  private var protectionTimer: Timer?

  func startAirPodsStereoGuard(enabled: Bool) {
    guard enabled else {
      return
    }

    protectAirPodsStereoIfNeeded(enabled: true)

    guard protectionTimer == nil else {
      return
    }

    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      self?.protectAirPodsStereoIfNeeded(enabled: true)
    }
    RunLoop.main.add(timer, forMode: .common)
    protectionTimer = timer
  }

  func stopAirPodsStereoGuard(restorePreviousInput: Bool) {
    protectionTimer?.invalidate()
    protectionTimer = nil

    if restorePreviousInput {
      restoreNow()
    }
  }

  func protectAirPodsStereoIfNeeded(enabled: Bool) {
    guard enabled else {
      return
    }

    do {
      let currentInputID = try defaultInputDeviceID()
      let currentName = deviceName(deviceID: currentInputID)

      guard shouldAvoidAsDictationInput(deviceID: currentInputID, deviceName: currentName) else {
        return
      }

      guard let fallbackID = bestFallbackInputDeviceID(excluding: currentInputID) else {
        Logger.info("codex-dictate-companion: AirPods stereo guard found no non-Bluetooth input fallback; keeping \(currentName)")
        return
      }

      let fallbackName = deviceName(deviceID: fallbackID)
      try setDefaultInputDeviceID(fallbackID)

      if previousInputDeviceID == nil {
        previousInputDeviceID = currentInputID
      }

      Logger.info("codex-dictate-companion: AirPods stereo guard switched input from \(currentName) to \(fallbackName)")
    } catch {
      Logger.error("codex-dictate-companion: \(error)")
    }
  }

  func restoreNow() {
    guard let previousInputDeviceID else {
      return
    }

    do {
      try setDefaultInputDeviceID(previousInputDeviceID)
      Logger.info("codex-dictate-companion: AirPods stereo guard restored input to \(deviceName(deviceID: previousInputDeviceID))")
    } catch {
      Logger.error("codex-dictate-companion: \(error)")
    }

    self.previousInputDeviceID = nil
  }

  func defaultInputName() -> String {
    do {
      return deviceName(deviceID: try defaultInputDeviceID())
    } catch {
      return "Default input"
    }
  }

  private func defaultInputDeviceID() throws -> AudioDeviceID {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )

    guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else {
      throw AppError.audioInputDeviceUnavailable(status)
    }

    return deviceID
  }

  private func setDefaultInputDeviceID(_ deviceID: AudioDeviceID) throws {
    var mutableDeviceID = deviceID
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      UInt32(MemoryLayout<AudioDeviceID>.size),
      &mutableDeviceID
    )

    guard status == noErr else {
      throw AppError.audioInputDeviceWriteFailed(status)
    }
  }

  private func bestFallbackInputDeviceID(excluding excludedID: AudioDeviceID) -> AudioDeviceID? {
    allDeviceIDs()
      .filter { $0 != excludedID }
      .filter { hasInputStreams(deviceID: $0) }
      .filter {
        let name = deviceName(deviceID: $0)
        return !shouldAvoidAsDictationInput(deviceID: $0, deviceName: name)
      }
      .compactMap { deviceID -> (AudioDeviceID, Int)? in
        let score = fallbackScore(deviceID: deviceID, deviceName: deviceName(deviceID: deviceID))
        return score >= 0 ? (deviceID, score) : nil
      }
      .sorted { lhs, rhs in
        if lhs.1 == rhs.1 {
          return deviceName(deviceID: lhs.0) < deviceName(deviceID: rhs.0)
        }
        return lhs.1 > rhs.1
      }
      .first?
      .0
  }

  private func fallbackScore(deviceID: AudioDeviceID, deviceName: String) -> Int {
    let lowercasedName = deviceName.lowercased()

    if lowercasedName.contains("blackhole") ||
       lowercasedName.contains("soundflower") ||
       lowercasedName.contains("loopback") ||
       lowercasedName.contains("aggregate") ||
       lowercasedName.contains("multi-output") {
      return -1
    }

    var score = 10

    if let transportType = transportType(deviceID: deviceID) {
      switch transportType {
      case kAudioDeviceTransportTypeBuiltIn:
        score += 100
      case kAudioDeviceTransportTypeUSB:
        score += 60
      case kAudioDeviceTransportTypePCI:
        score += 40
      default:
        break
      }
    }

    if lowercasedName.contains("macbook") {
      score += 40
    }
    if lowercasedName.contains("built-in") || lowercasedName.contains("internal") {
      score += 30
    }
    if lowercasedName.contains("microphone") || lowercasedName.contains("micro") {
      score += 20
    }
    if lowercasedName.contains("display") {
      score += 5
    }

    return score
  }

  private func shouldAvoidAsDictationInput(deviceID: AudioDeviceID, deviceName: String) -> Bool {
    if let transportType = transportType(deviceID: deviceID) {
      switch transportType {
      case kAudioDeviceTransportTypeBluetooth,
           kAudioDeviceTransportTypeBluetoothLE:
        return true
      default:
        break
      }
    }

    let lowercasedName = deviceName.lowercased()
    return lowercasedName.contains("airpods") || lowercasedName.contains("bluetooth")
  }

  private func allDeviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var size = UInt32(0)

    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
      return []
    }

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = Array(repeating: AudioDeviceID(0), count: count)

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &devices
    )

    guard status == noErr else {
      return []
    }

    return devices
  }

  private func hasInputStreams(deviceID: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size = UInt32(0)

    return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
  }

  private func transportType(deviceID: AudioDeviceID) -> UInt32? {
    var transportType = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &size,
      &transportType
    )

    guard status == noErr else {
      return nil
    }

    return transportType
  }

  private func deviceName(deviceID: AudioDeviceID) -> String {
    var name: CFString = "default input" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = withUnsafeMutablePointer(to: &name) { pointer in
      AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
    }

    guard status == noErr else {
      return "default input"
    }

    return name as String
  }
}

private protocol ShortcutMonitorDelegate: AnyObject {
  func shortcutMonitorDidMute()
  func shortcutMonitorDidRestore()
}

private final class ShortcutMonitor {
  weak var delegate: ShortcutMonitorDelegate?

  var enabled: Bool {
    didSet {
      guard enabled != oldValue else {
        return
      }

      if enabled {
        inputRoute.startAirPodsStereoGuard(enabled: airPodsStereoGuardEnabled)
      } else {
        resetShortcut(reason: "companion disabled")
        inputRoute.stopAirPodsStereoGuard(restorePreviousInput: true)
      }
    }
  }

  private let showEvents: Bool
  var airPodsStereoGuardEnabled: Bool
  private let audio = AudioMuteController()
  private let inputRoute = AudioInputRouteController()
  private var shortcutState = ToggleShortcutState()
  private var isOutputMuted = false
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  var isRunning: Bool {
    eventTap != nil
  }

  init(options: Options, enabled: Bool, airPodsStereoGuardEnabled: Bool) {
    showEvents = options.showEvents
    self.airPodsStereoGuardEnabled = airPodsStereoGuardEnabled
    self.enabled = enabled
  }

  func start() throws {
    logPermissions()

    let eventMask = 1 << CGEventType.flagsChanged.rawValue

    eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .listenOnly,
      eventsOfInterest: CGEventMask(eventMask),
      callback: eventCallback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    )

    guard let eventTap else {
      throw AppError.eventTapUnavailable
    }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    runLoopSource = source
    CGEvent.tapEnable(tap: eventTap, enable: true)

    Logger.info("codex-dictate-companion: running. Shortcuts: Fn/Globe and right Option")
    if enabled {
      inputRoute.startAirPodsStereoGuard(enabled: airPodsStereoGuardEnabled)
    }
  }

  fileprivate func handle(
    type: CGEventType,
    keyCode: CGKeyCode,
    flags: CGEventFlags
  ) {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      resetShortcut(reason: "keyboard event tap disabled")
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      return
    }

    let shouldToggle = enabled
      && shortcutState.handle(type: type, keyCode: keyCode, flags: flags)

    if showEvents {
      Logger.info("event=\(type.rawValue) keyCode=\(keyCode) flags=\(flags.rawValue) fn=\(flags.contains(.maskSecondaryFn)) option=\(flags.contains(.maskAlternate)) toggle=\(shouldToggle)")
    }

    guard shouldToggle else {
      return
    }

    if isOutputMuted {
      Logger.info("codex-dictate-companion: output restored by shortcut")
      audio.restore()
      isOutputMuted = false
      delegate?.shortcutMonitorDidRestore()
    } else {
      inputRoute.protectAirPodsStereoIfNeeded(enabled: airPodsStereoGuardEnabled)
      Logger.info("codex-dictate-companion: output muted by shortcut")
      audio.mute()
      isOutputMuted = true
      delegate?.shortcutMonitorDidMute()
    }
  }

  func stop(reason: String) {
    resetShortcut(reason: reason)
    inputRoute.stopAirPodsStereoGuard(restorePreviousInput: true)

    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
      CFRunLoopSourceInvalidate(runLoopSource)
    }
    runLoopSource = nil
    eventTap = nil
  }

  func setAirPodsStereoGuardEnabled(_ enabled: Bool) {
    airPodsStereoGuardEnabled = enabled

    if enabled && self.enabled {
      inputRoute.startAirPodsStereoGuard(enabled: true)
    } else {
      inputRoute.stopAirPodsStereoGuard(restorePreviousInput: true)
    }
  }

  private func resetShortcut(reason: String) {
    shortcutState.reset()
    let wasMuted = isOutputMuted
    audio.restore()
    isOutputMuted = false

    if wasMuted {
      Logger.info("codex-dictate-companion: restored audio because \(reason)")
      delegate?.shortcutMonitorDidRestore()
    }
  }

  private func logPermissions() {
    Logger.info("codex-dictate-companion: \(permissionSummary())")
  }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, ShortcutMonitorDelegate {
  private let options: Options
  private let preferences = Preferences()
  private let audio = AudioMuteController()
  private let inputRoute = AudioInputRouteController()
  private var statusItem: NSStatusItem?
  private var monitor: ShortcutMonitor?
  private var isMutedByShortcut = false
  private var permissionRetryTimer: Timer?
  private var isShuttingDown = false

  init(options: Options) {
    self.options = options
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    installSafetyObservers()
    installStatusItem()
    requestKeyboardPermissionsIfNeeded()
    startMonitor()
  }

  func applicationWillTerminate(_ notification: Notification) {
    shutdown(reason: "application terminating")
  }

  func shortcutMonitorDidMute() {
    isMutedByShortcut = true
    updateStatusIcon()
  }

  func shortcutMonitorDidRestore() {
    isMutedByShortcut = false
    updateStatusIcon()
  }

  @objc private func toggleMonitoring(_ sender: NSMenuItem) {
    preferences.monitorEnabled.toggle()

    if preferences.monitorEnabled, monitor == nil {
      startMonitor()
    }
    monitor?.enabled = preferences.monitorEnabled
    rebuildMenu()
    updateStatusIcon()
  }

  @objc private func toggleAirPodsStereoGuard(_ sender: NSMenuItem) {
    preferences.airPodsStereoGuardEnabled.toggle()
    monitor?.setAirPodsStereoGuardEnabled(preferences.airPodsStereoGuardEnabled)
    rebuildMenu()
  }

  @objc private func selectIcon(_ sender: NSMenuItem) {
    guard let rawValue = sender.representedObject as? String,
          let icon = MenuBarIcon(rawValue: rawValue) else {
      return
    }

    preferences.icon = icon
    rebuildMenu()
    updateStatusIcon()
  }

  @objc private func testMute(_ sender: NSMenuItem) {
    do {
      try audio.testMuteCycle()
    } catch {
      Logger.error("codex-dictate-companion: \(error)")
    }
  }

  @objc private func requestPermissions(_ sender: NSMenuItem) {
    requestKeyboardPermissionsIfNeeded(promptEvenIfPreflightPasses: true)
    schedulePermissionRetry()
    rebuildMenu()
  }

  private func requestKeyboardPermissionsIfNeeded(promptEvenIfPreflightPasses: Bool = false) {
    guard promptEvenIfPreflightPasses || !CGPreflightListenEventAccess() else {
      return
    }

    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    Logger.info("codex-dictate-companion: requesting Input Monitoring permission")
    _ = CGRequestListenEventAccess()
    Logger.info("codex-dictate-companion: \(permissionSummary())")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      NSApp.setActivationPolicy(.accessory)
    }
  }

  @objc private func openInputMonitoring(_ sender: NSMenuItem) {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
  }

  @objc private func openLogs(_ sender: NSMenuItem) {
    let url = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/\(AppConstants.logDirectoryName)", isDirectory: true)
    NSWorkspace.shared.open(url)
  }

  @objc private func quit(_ sender: NSMenuItem) {
    shutdown(reason: "user quit")
    NSApp.terminate(nil)
  }

  private func installStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.toolTip = AppConstants.appName
    statusItem = item
    rebuildMenu()
    updateStatusIcon()
  }

  private func rebuildMenu() {
    let menu = NSMenu()

    let title = NSMenuItem(title: AppConstants.appName, action: nil, keyEquivalent: "")
    title.isEnabled = false
    menu.addItem(title)

    let output = NSMenuItem(title: "Output: \(audio.defaultOutputName())", action: nil, keyEquivalent: "")
    output.isEnabled = false
    menu.addItem(output)

    let input = NSMenuItem(title: "Input: \(inputRoute.defaultInputName())", action: nil, keyEquivalent: "")
    input.isEnabled = false
    menu.addItem(input)

    let shortcut = NSMenuItem(title: "Shortcuts: Fn/Globe or Right Option", action: nil, keyEquivalent: "")
    shortcut.isEnabled = false
    menu.addItem(shortcut)

    let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
    status.isEnabled = false
    menu.addItem(status)

    menu.addItem(.separator())

    let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleMonitoring(_:)), keyEquivalent: "")
    toggle.target = self
    toggle.state = preferences.monitorEnabled ? .on : .off
    menu.addItem(toggle)

    let airPodsGuard = NSMenuItem(title: "AirPods Stereo Guard", action: #selector(toggleAirPodsStereoGuard(_:)), keyEquivalent: "")
    airPodsGuard.target = self
    airPodsGuard.state = preferences.airPodsStereoGuardEnabled ? .on : .off
    menu.addItem(airPodsGuard)

    let test = NSMenuItem(title: "Test Mute", action: #selector(testMute(_:)), keyEquivalent: "")
    test.target = self
    test.isEnabled = !isMutedByShortcut
    menu.addItem(test)

    menu.addItem(iconSubmenu())
    menu.addItem(permissionSubmenu())

    menu.addItem(.separator())

    let logs = NSMenuItem(title: "Open Logs", action: #selector(openLogs(_:)), keyEquivalent: "")
    logs.target = self
    menu.addItem(logs)

    menu.addItem(.separator())

    let quit = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)

    statusItem?.menu = menu
  }

  private func iconSubmenu() -> NSMenuItem {
    let item = NSMenuItem(title: "Menu Bar Icon", action: nil, keyEquivalent: "")
    let submenu = NSMenu()

    for icon in MenuBarIcon.allCases {
      let menuItem = NSMenuItem(title: icon.title, action: #selector(selectIcon(_:)), keyEquivalent: "")
      menuItem.target = self
      menuItem.representedObject = icon.rawValue
      menuItem.state = preferences.icon == icon ? .on : .off
      submenu.addItem(menuItem)
    }

    item.submenu = submenu
    return item
  }

  private func permissionSubmenu() -> NSMenuItem {
    let item = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
    let submenu = NSMenu()

    let inputGranted = CGPreflightListenEventAccess()
    let inputTitle = "Input Monitoring: \(inputGranted ? "OK" : "Missing")"
    let input = NSMenuItem(title: inputTitle, action: #selector(openInputMonitoring(_:)), keyEquivalent: "")
    input.target = self
    submenu.addItem(input)

    submenu.addItem(.separator())

    let request = NSMenuItem(title: "Request Input Monitoring", action: #selector(requestPermissions(_:)), keyEquivalent: "")
    request.target = self
    submenu.addItem(request)

    item.submenu = submenu
    return item
  }

  private func updateStatusIcon() {
    guard let button = statusItem?.button else {
      return
    }

    let icon = preferences.icon
    let image = NSImage(systemSymbolName: icon.symbolName, accessibilityDescription: AppConstants.appName)
    image?.isTemplate = true
    button.image = image
    button.title = image == nil ? "CD" : ""
    button.contentTintColor = isMutedByShortcut ? .systemBlue : nil
  }

  private func startMonitor() {
    guard monitor == nil else {
      return
    }

    do {
      let shortcutMonitor = ShortcutMonitor(
        options: options,
        enabled: preferences.monitorEnabled,
        airPodsStereoGuardEnabled: preferences.airPodsStereoGuardEnabled
      )
      shortcutMonitor.delegate = self
      try shortcutMonitor.start()
      monitor = shortcutMonitor
      permissionRetryTimer?.invalidate()
      permissionRetryTimer = nil
      rebuildMenu()
    } catch {
      Logger.error("codex-dictate-companion: \(error)")
      schedulePermissionRetry()
    }
  }

  private var statusTitle: String {
    if isMutedByShortcut {
      return "Status: Muting Output"
    }
    if !CGPreflightListenEventAccess() || monitor == nil {
      return CGPreflightListenEventAccess()
        ? "Status: Paused"
        : "Status: Input Monitoring Required"
    }
    return preferences.monitorEnabled ? "Status: Ready" : "Status: Disabled"
  }

  private func schedulePermissionRetry() {
    guard permissionRetryTimer == nil else {
      return
    }

    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
      guard let self else {
        timer.invalidate()
        return
      }

      guard CGPreflightListenEventAccess() else {
        return
      }

      self.startMonitor()
    }
    RunLoop.main.add(timer, forMode: .common)
    permissionRetryTimer = timer
  }

  private func installSafetyObservers() {
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    workspaceCenter.addObserver(
      self,
      selector: #selector(systemSessionWillChange(_:)),
      name: NSWorkspace.willSleepNotification,
      object: nil
    )
    workspaceCenter.addObserver(
      self,
      selector: #selector(systemSessionWillChange(_:)),
      name: NSWorkspace.sessionDidResignActiveNotification,
      object: nil
    )
    workspaceCenter.addObserver(
      self,
      selector: #selector(systemSessionDidBecomeActive(_:)),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )
    workspaceCenter.addObserver(
      self,
      selector: #selector(systemSessionDidBecomeActive(_:)),
      name: NSWorkspace.sessionDidBecomeActiveNotification,
      object: nil
    )

  }

  @objc private func systemSessionWillChange(_ notification: Notification) {
    monitor?.stop(reason: notification.name.rawValue)
    monitor = nil
    isMutedByShortcut = false
    updateStatusIcon()
  }

  @objc private func systemSessionDidBecomeActive(_ notification: Notification) {
    guard !isShuttingDown else {
      return
    }
    startMonitor()
  }

  private func shutdown(reason: String) {
    guard !isShuttingDown else {
      return
    }

    isShuttingDown = true
    permissionRetryTimer?.invalidate()
    permissionRetryTimer = nil
    monitor?.stop(reason: reason)
    monitor = nil
    audio.restore()
  }
}

private let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
  if let userInfo {
    let monitor = Unmanaged<ShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags

    DispatchQueue.main.async { [weak monitor] in
      monitor?.handle(type: type, keyCode: keyCode, flags: flags)
    }
  }

  return Unmanaged.passUnretained(event)
}

private func parseOptions() throws -> Options {
  var options = Options()
  var args = Array(CommandLine.arguments.dropFirst())

  while !args.isEmpty {
    let arg = args.removeFirst()

    switch arg {
    case "--help", "-h":
      printHelp()
      exit(0)
    case "--show-events":
      options.showEvents = true
    case "--test-mute":
      options.testMute = true
    case "--check-permissions":
      options.checkPermissions = true
    case "--request-permissions":
      options.requestPermissions = true
    default:
      throw AppError.invalidArgument(arg)
    }
  }

  return options
}

private func printHelp() {
  print("""
  Usage: codex-dictate-companion [--show-events] [--test-mute] [--check-permissions] [--request-permissions]

  Press Fn/Globe or right Option once to mute macOS output audio.
  Press either shortcut again to restore the previous audio state.
  """)
}

private func preparePermissionRequestIfNeeded() {
  NSApplication.shared.setActivationPolicy(.regular)
  NSApplication.shared.activate(ignoringOtherApps: true)
}

private func permissionSummary() -> String {
  "permissions inputMonitoring=\(CGPreflightListenEventAccess())"
}

do {
  let options = try parseOptions()

  if options.checkPermissions {
    Logger.info("codex-dictate-companion: \(permissionSummary())")
    exit(0)
  }

  if options.requestPermissions {
    preparePermissionRequestIfNeeded()
    Logger.info("codex-dictate-companion: requesting Input Monitoring permission")
    _ = CGRequestListenEventAccess()
    Logger.info("codex-dictate-companion: \(permissionSummary())")
    exit(0)
  }

  if options.testMute {
    try AudioMuteController().testMuteCycle()
    exit(0)
  }

  let delegate = AppDelegate(options: options)
  NSApplication.shared.delegate = delegate
  withExtendedLifetime(delegate) {
    NSApplication.shared.run()
  }
} catch {
  Logger.error("codex-dictate-companion: \(error)")
  exit(1)
}
