import XCTest
@testable import EmbedIOSSDK

final class EmbedFolderInfoPositionTests: XCTestCase {
    func testFloatingMediaReportsItsFixedPositionInsteadOfEmbedLocation() {
        // pageBundle gives FloatingMedia folders a default embedLocation they are not shown at.
        let folderInfo = EmbedFolderInfo(
            folderId: "floating",
            embedLocation: EmbedPosition.BELOW_BUY_BUTTON.rawValue,
            layout: "FloatingMedia",
            floatingMediaPosition: "BottomRight"
        )

        XCTAssertEqual(folderInfo.displayPosition, EmbedPosition.FIXED_BOTTOM_RIGHT.rawValue)
    }

    func testFloatingMediaPositionFromSettingIsUsed() {
        let folderInfo = EmbedFolderInfo(
            folderId: "floating",
            layout: "floatingmedia",
            setting: ["floatingMediaPosition": .string("TopLeft")]
        )

        XCTAssertEqual(folderInfo.displayPosition, EmbedPosition.FIXED_TOP_LEFT.rawValue)
    }

    func testInlineWidgetReportsItsEmbedLocation() {
        let folderInfo = EmbedFolderInfo(
            folderId: "inline",
            embedLocation: EmbedPosition.ABOVE_RECOMMENDATION.rawValue,
            layout: "Highlight"
        )

        XCTAssertEqual(folderInfo.displayPosition, EmbedPosition.ABOVE_RECOMMENDATION.rawValue)
    }

    func testEveryFloatingMediaPositionMapsToAFixedPosition() {
        let mapping: [String: EmbedPosition] = [
            "BottomLeft": .FIXED_BOTTOM_LEFT,
            "BottomRight": .FIXED_BOTTOM_RIGHT,
            "TopLeft": .FIXED_TOP_LEFT,
            "TopRight": .FIXED_TOP_RIGHT,
            "CenterLeft": .FIXED_CENTER_LEFT,
            "CenterRight": .FIXED_CENTER_RIGHT
        ]
        for (floatingMediaPosition, position) in mapping {
            XCTAssertEqual(EmbedPosition(floatingMediaPosition: floatingMediaPosition), position)
        }
        XCTAssertNil(EmbedPosition(floatingMediaPosition: "Middle"))
        XCTAssertNil(EmbedPosition(floatingMediaPosition: nil))
    }
}
