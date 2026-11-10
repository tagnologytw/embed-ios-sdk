import XCTest
@testable import EmbedIOSSDK

/// 91APP 回報（2026-11-09）：分類頁進商品頁再返回，版位重新載入、高度從頭變化，頁面跟著跳動。
final class EmbedWidgetReloadTests: XCTestCase {
    func testReturningToTheSamePageKeepsLoadedWidgets() {
        XCTAssertTrue(EmbedWidgetReload.keepsLoadedWidgets(sameIdentity: true, isLoading: false, hasError: false, widgetCount: 2))
    }

    func testAnotherPageOrPositionLoadsAgain() {
        XCTAssertFalse(EmbedWidgetReload.keepsLoadedWidgets(sameIdentity: false, isLoading: false, hasError: false, widgetCount: 2))
    }

    func testLoadCancelledBeforeFinishingLoadsAgain() {
        // Leaving the page while loading cancels the task with isLoading still true.
        XCTAssertFalse(EmbedWidgetReload.keepsLoadedWidgets(sameIdentity: true, isLoading: true, hasError: false, widgetCount: 0))
    }

    func testFailedOrEmptyLoadRunsAgain() {
        XCTAssertFalse(EmbedWidgetReload.keepsLoadedWidgets(sameIdentity: true, isLoading: false, hasError: true, widgetCount: 0))
        XCTAssertFalse(EmbedWidgetReload.keepsLoadedWidgets(sameIdentity: true, isLoading: false, hasError: false, widgetCount: 0))
    }
}
