import XCTest
@testable import EmbedIOSSDK

/// 91APP 回報（2026-10-29）：Lightbox 頁面沒回 toggleLB 時只有轉圈、沒有任何關閉方式。
final class EmbedLightboxLoadingTests: XCTestCase {
    func testLoadingShowsSpinnerAndCloseButton() {
        XCTAssertTrue(EmbedLightboxLoading.showsSpinner(contentShown: false, loadFailed: false))
        XCTAssertTrue(EmbedLightboxLoading.showsCloseButton(contentShown: false, loadFailed: false))
    }

    func testShownContentUsesThePageCloseButton() {
        XCTAssertFalse(EmbedLightboxLoading.showsSpinner(contentShown: true, loadFailed: false))
        XCTAssertFalse(EmbedLightboxLoading.showsCloseButton(contentShown: true, loadFailed: false))
    }

    func testFailedOrTimedOutLoadShowsOnlyTheCloseButton() {
        XCTAssertFalse(EmbedLightboxLoading.showsSpinner(contentShown: false, loadFailed: true))
        XCTAssertTrue(EmbedLightboxLoading.showsCloseButton(contentShown: false, loadFailed: true))
    }

    func testTimeoutAppliesOnlyWhileStillLoading() {
        XCTAssertTrue(EmbedLightboxLoading.hasTimedOut(isPresented: true, contentShown: false, loadFailed: false))
        // Content arrived, the cover was closed, or loading already failed: nothing to do.
        XCTAssertFalse(EmbedLightboxLoading.hasTimedOut(isPresented: true, contentShown: true, loadFailed: false))
        XCTAssertFalse(EmbedLightboxLoading.hasTimedOut(isPresented: false, contentShown: false, loadFailed: false))
        XCTAssertFalse(EmbedLightboxLoading.hasTimedOut(isPresented: true, contentShown: false, loadFailed: true))
    }

    func testTimeoutIsTenSeconds() {
        XCTAssertEqual(EmbedLightboxLoading.timeout, 10)
    }
}
