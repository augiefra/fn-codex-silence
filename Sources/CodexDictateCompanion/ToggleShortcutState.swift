import CoreGraphics

enum ShortcutAction: Equatable {
  case classicDictation
  case voiceConversation
}

struct ToggleShortcutState {
  static let fnKeyCode = CGKeyCode(63)
  static let rightOptionKeyCode = CGKeyCode(61)

  private(set) var fnIsDown = false
  private(set) var rightOptionIsDown = false

  mutating func handle(
    type: CGEventType,
    keyCode: CGKeyCode,
    flags: CGEventFlags
  ) -> ShortcutAction? {
    guard type == .flagsChanged else {
      return nil
    }

    let fnFlagIsDown = flags.contains(.maskSecondaryFn)
    let optionFlagIsDown = flags.contains(.maskAlternate)

    if !fnFlagIsDown {
      fnIsDown = false
    }
    if !optionFlagIsDown {
      rightOptionIsDown = false
    }

    switch keyCode {
    case Self.fnKeyCode:
      guard fnFlagIsDown, !fnIsDown else {
        return nil
      }

      fnIsDown = true
      return .classicDictation

    case Self.rightOptionKeyCode:
      if rightOptionIsDown {
        rightOptionIsDown = false
        return nil
      }

      guard optionFlagIsDown else {
        return nil
      }

      rightOptionIsDown = true
      return .voiceConversation

    default:
      return nil
    }
  }

  mutating func reset() {
    fnIsDown = false
    rightOptionIsDown = false
  }
}
