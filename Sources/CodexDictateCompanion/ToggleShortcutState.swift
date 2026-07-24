import CoreGraphics

struct ToggleShortcutState {
  static let fnKeyCode = CGKeyCode(63)
  static let rightOptionKeyCode = CGKeyCode(61)

  private(set) var fnIsDown = false
  private(set) var rightOptionIsDown = false

  mutating func handle(
    type: CGEventType,
    keyCode: CGKeyCode,
    flags: CGEventFlags
  ) -> Bool {
    guard type == .flagsChanged else {
      return false
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
        return false
      }

      fnIsDown = true
      return true

    case Self.rightOptionKeyCode:
      if rightOptionIsDown {
        rightOptionIsDown = false
        return false
      }

      guard optionFlagIsDown else {
        return false
      }

      rightOptionIsDown = true
      return true

    default:
      return false
    }
  }

  mutating func reset() {
    fnIsDown = false
    rightOptionIsDown = false
  }
}
