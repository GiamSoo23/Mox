import XCTest
@testable import MoxCore

final class HotKeyComboTests: XCTestCase {
    func testParsesTheDefaultHotkey() throws {
        let combo = try XCTUnwrap(HotKeyCombo.parse("cmd+shift+m"))
        XCTAssertEqual(combo.key, .m)
        XCTAssertEqual(combo.modifiers, [.command, .shift])
    }

    func testAcceptsAliasesCaseAndSpaces() throws {
        let combo = try XCTUnwrap(HotKeyCombo.parse("Command + Option + U"))
        XCTAssertEqual(combo.key, .u)
        XCTAssertEqual(combo.modifiers, [.command, .option])

        let other = try XCTUnwrap(HotKeyCombo.parse("ctrl+alt+k"))
        XCTAssertEqual(other.modifiers, [.control, .option])
    }

    func testRejectsWhatItCantRegister() {
        XCTAssertNil(HotKeyCombo.parse(""), "empty")
        XCTAssertNil(HotKeyCombo.parse("cmd+shift"), "no key")
        XCTAssertNil(HotKeyCombo.parse("cmd+shift+1"), "digits aren't supported")
        XCTAssertNil(HotKeyCombo.parse("cmd+shift+mm"), "a key is one letter")
    }

    func testHumanReadableSymbolsFollowTheMacOrder() {
        let all = HotKeyCombo(key: .m, modifiers: [.command, .shift, .option, .control])
        XCTAssertEqual(all.human, "⌃⌥⇧⌘M")
        XCTAssertEqual(HotKeyCombo.parse("cmd+shift+m")?.human, "⇧⌘M")
    }
}
