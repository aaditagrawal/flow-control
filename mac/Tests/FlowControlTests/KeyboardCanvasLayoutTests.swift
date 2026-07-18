import CoreGraphics
import XCTest
@testable import FlowControl

final class KeyboardCanvasLayoutTests: XCTestCase {
    func testNaturalKeyboardSizeMatchesAllPhysicalRows() {
        XCTAssertEqual(KeyboardCanvasLayout.keyboardSize.width, 858, accuracy: 0.001)
        XCTAssertEqual(KeyboardCanvasLayout.keyboardSize.height, 298, accuracy: 0.001)
        XCTAssertEqual(KeyboardCanvasLayout.chassisSize.width, 898, accuracy: 0.001)
        XCTAssertEqual(KeyboardCanvasLayout.chassisSize.height, 338, accuracy: 0.001)
        XCTAssertEqual(KeyboardCanvasLayout.paddedKeyboardSize.width, 946, accuracy: 0.001)
        XCTAssertEqual(KeyboardCanvasLayout.paddedKeyboardSize.height, 386, accuracy: 0.001)
    }

    func testFitScaleUsesBothWindowDimensionsAndCapsLargeWindows() {
        XCTAssertEqual(
            KeyboardCanvasLayout.fittingScale(in: KeyboardCanvasLayout.paddedKeyboardSize),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            KeyboardCanvasLayout.fittingScale(
                in: CGSize(
                    width: KeyboardCanvasLayout.paddedKeyboardSize.width * 0.5,
                    height: 1_000
                )
            ),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            KeyboardCanvasLayout.fittingScale(
                in: CGSize(
                    width: 2_000,
                    height: KeyboardCanvasLayout.paddedKeyboardSize.height * 0.5
                )
            ),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            KeyboardCanvasLayout.fittingScale(in: CGSize(width: 4_000, height: 4_000)),
            KeyboardCanvasLayout.maximumFitScale,
            accuracy: 0.001
        )
    }

    func testCompactFitKeepsTheWholeKeyboardInsideTheViewport() {
        let viewport = CGSize(width: 610, height: 320)
        let scale = KeyboardCanvasLayout.fittingScale(in: viewport)

        XCTAssertGreaterThan(scale, 0.6)
        XCTAssertLessThanOrEqual(KeyboardCanvasLayout.paddedKeyboardSize.width * scale, viewport.width + 0.001)
        XCTAssertLessThanOrEqual(KeyboardCanvasLayout.paddedKeyboardSize.height * scale, viewport.height + 0.001)
    }

    func testReferenceLayoutUsesOnlyUniformInterKeySpacing() {
        let keysByID = Dictionary(
            uniqueKeysWithValues: KeyboardLayout.rows
                .flatMap { $0 }
                .map { ($0.id, $0) }
        )

        for keyID in ["f1", "print-screen", "home", "end", "page-up", "page-down", "arrow-left"] {
            XCTAssertEqual(keysByID[keyID]?.spacerBefore, 0)
        }
    }

    func testManualZoomPreferenceIsClampedToUsableLimits() {
        XCTAssertEqual(InterfacePreferences.clampedKeyboardZoom(0.1), 0.6)
        XCTAssertEqual(InterfacePreferences.clampedKeyboardZoom(1.2), 1.2)
        XCTAssertEqual(InterfacePreferences.clampedKeyboardZoom(3), 1.5)
    }
}
