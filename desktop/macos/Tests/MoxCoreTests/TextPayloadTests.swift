import XCTest
@testable import MoxCore

final class TextPayloadTests: XCTestCase {
    func testTextSurvivesTheRoundTrip() throws {
        let text = "Hola, ¿qué tal? 👋\nSecond line"
        XCTAssertEqual(TextPayload.decode(try TextPayload.encode(text)), text)
    }

    func testBlankTextIsRefused() {
        XCTAssertThrowsError(try TextPayload.encode("  \n "))
    }

    func testTextOverOneMegabyteIsRefused() {
        XCTAssertThrowsError(try TextPayload.encode(String(repeating: "a", count: TextPayload.maxBytes + 1)))
    }

    func testThePreviewIsOneShortLine() {
        XCTAssertEqual(TextPayload.preview("  a\n b\t\tc "), "a b c")
        XCTAssertEqual(TextPayload.preview(String(repeating: "x", count: 50), max: 10).count, 10)
    }

    func testTheTextHotkeyDefaultsToControlShiftM() {
        XCTAssertEqual(Config.from([:]).textHotkey.human, "⌃⇧M")
        XCTAssertEqual(Config.from(["MOX_TEXT_HOTKEY": "ctrl+alt+t"]).textHotkey.human, "⌃⌥T")
    }
}
