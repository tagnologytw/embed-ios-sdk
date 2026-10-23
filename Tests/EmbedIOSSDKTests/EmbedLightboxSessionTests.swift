import XCTest
import WebKit
@testable import EmbedIOSSDK

@MainActor
final class EmbedLightboxSessionTests: XCTestCase {
    func testWidgetsOnTheSamePageShareOnePreloadedLightbox() {
        let pageUrl = "https://lightbox-share-\(UUID().uuidString).invalid/page"

        let first = EmbedLightboxStore.session(for: pageUrl)
        let second = EmbedLightboxStore.session(for: pageUrl)

        XCTAssertTrue(first === second)
        XCTAssertTrue(first.webView === second.webView)
    }

    func testAnotherPageGetsItsOwnLightbox() {
        let first = EmbedLightboxStore.session(for: "https://lightbox-a-\(UUID().uuidString).invalid/page")
        let second = EmbedLightboxStore.session(for: "https://lightbox-b-\(UUID().uuidString).invalid/page")

        XCTAssertFalse(first === second)
        XCTAssertFalse(first.webView === second.webView)
    }

    func testLightboxIsLoadedBeforeItIsShown() {
        let pageUrl = "https://lightbox-preload-\(UUID().uuidString).invalid/page"

        let session = EmbedLightboxStore.session(for: pageUrl)

        XCTAssertNil(session.webView.superview)
        XCTAssertTrue(session.webView.isLoading)
        XCTAssertFalse(session.webView.configuration.websiteDataStore.isPersistent)
    }
}
