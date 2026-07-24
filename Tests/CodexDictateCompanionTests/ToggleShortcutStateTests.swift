import CoreGraphics
import XCTest
@testable import CodexDictateCompanion

final class ToggleShortcutStateTests: XCTestCase {
  func testFnTogglesOnlyOnPress() {
    var state = ToggleShortcutState()

    XCTAssertEqual(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.fnKeyCode, flags: [.maskSecondaryFn]),
      .classicDictation
    )
    XCTAssertNil(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.fnKeyCode, flags: [])
    )
    XCTAssertEqual(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.fnKeyCode, flags: [.maskSecondaryFn]),
      .classicDictation
    )
  }

  func testRightOptionTogglesOnlyOnPress() {
    var state = ToggleShortcutState()

    XCTAssertEqual(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.rightOptionKeyCode, flags: [.maskAlternate]),
      .voiceConversation
    )
    XCTAssertNil(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.rightOptionKeyCode, flags: [])
    )
    XCTAssertEqual(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.rightOptionKeyCode, flags: [.maskAlternate]),
      .voiceConversation
    )
  }

  func testLeftOptionNeverToggles() {
    var state = ToggleShortcutState()

    XCTAssertNil(state.handle(type: .flagsChanged, keyCode: 58, flags: [.maskAlternate]))
    XCTAssertNil(state.handle(type: .flagsChanged, keyCode: 58, flags: []))
  }

  func testArrowKeysAndOrdinaryEventsNeverToggle() {
    var state = ToggleShortcutState()

    for keyCode: CGKeyCode in [123, 124, 125, 126] {
      XCTAssertNil(state.handle(type: .keyDown, keyCode: keyCode, flags: []))
      XCTAssertNil(state.handle(type: .keyUp, keyCode: keyCode, flags: []))
    }
    XCTAssertNil(state.handle(type: .flagsChanged, keyCode: 56, flags: [.maskShift]))
  }

  func testHeldModifierDoesNotToggleTwice() {
    var state = ToggleShortcutState()

    XCTAssertEqual(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.fnKeyCode, flags: [.maskSecondaryFn]),
      .classicDictation
    )
    XCTAssertNil(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.fnKeyCode, flags: [.maskSecondaryFn])
    )
  }

  func testRightOptionReleaseIsIgnoredWhileLeftOptionStaysDown() {
    var state = ToggleShortcutState()

    XCTAssertEqual(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.rightOptionKeyCode, flags: [.maskAlternate]),
      .voiceConversation
    )
    XCTAssertNil(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.rightOptionKeyCode, flags: [.maskAlternate])
    )
    XCTAssertEqual(
      state.handle(type: .flagsChanged, keyCode: ToggleShortcutState.rightOptionKeyCode, flags: [.maskAlternate]),
      .voiceConversation
    )
  }
}
