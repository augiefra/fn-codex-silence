import CoreGraphics
import XCTest
@testable import CodexDictateCompanion

final class ToggleShortcutStateTests: XCTestCase {
  func testFnTogglesOnlyOnPress() {
    var state = ToggleShortcutState()

    XCTAssertTrue(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.fnKeyCode, flags: [.maskSecondaryFn])
    )
    XCTAssertFalse(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.fnKeyCode, flags: [])
    )
    XCTAssertTrue(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.fnKeyCode, flags: [.maskSecondaryFn])
    )
  }

  func testRightOptionTogglesOnlyOnPress() {
    var state = ToggleShortcutState()

    XCTAssertTrue(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.rightOptionKeyCode, flags: [.maskAlternate])
    )
    XCTAssertFalse(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.rightOptionKeyCode, flags: [])
    )
    XCTAssertTrue(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.rightOptionKeyCode, flags: [.maskAlternate])
    )
  }

  func testLeftOptionNeverToggles() {
    var state = ToggleShortcutState()

    XCTAssertFalse(state.handle(type: .flagsChanged, keyCode: 58, flags: [.maskAlternate]))
    XCTAssertFalse(state.handle(type: .flagsChanged, keyCode: 58, flags: []))
  }

  func testArrowKeysAndOrdinaryEventsNeverToggle() {
    var state = ToggleShortcutState()

    for keyCode: CGKeyCode in [123, 124, 125, 126] {
      XCTAssertFalse(state.handle(type: .keyDown, keyCode: keyCode, flags: []))
      XCTAssertFalse(state.handle(type: .keyUp, keyCode: keyCode, flags: []))
    }
    XCTAssertFalse(state.handle(type: .flagsChanged, keyCode: 56, flags: [.maskShift]))
  }

  func testHeldModifierDoesNotToggleTwice() {
    var state = ToggleShortcutState()

    XCTAssertTrue(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.fnKeyCode, flags: [.maskSecondaryFn])
    )
    XCTAssertFalse(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.fnKeyCode, flags: [.maskSecondaryFn])
    )
  }

  func testRightOptionReleaseIsIgnoredWhileLeftOptionStaysDown() {
    var state = ToggleShortcutState()

    XCTAssertTrue(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.rightOptionKeyCode, flags: [.maskAlternate])
    )
    XCTAssertFalse(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.rightOptionKeyCode, flags: [.maskAlternate])
    )
    XCTAssertTrue(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.rightOptionKeyCode, flags: [.maskAlternate])
    )
  }
}
