import XCTest
@testable import EmbedIOSSDK

final class EmbedLinkOpenerTests: XCTestCase {
    func testProductLinksOnTheStoreOpenExternally() throws {
        let url = try XCTUnwrap(URL(string: "https://partnertest7.91app.com/SalePage/Index/9394400?utm_source=embed_tagnology"))
        XCTAssertTrue(EmbedLinkOpener.shouldOpenExternally(url))
    }

    func testEmbedPagesStayInTheWebView() throws {
        let lightbox = try XCTUnwrap(URL(string: "https://embed.tagnology.co/lightBox?page=https://example.com"))
        let display = try XCTUnwrap(URL(string: "https://www.embed.tagnology.co/display?folderId=1"))
        XCTAssertFalse(EmbedLinkOpener.shouldOpenExternally(lightbox))
        XCTAssertFalse(EmbedLinkOpener.shouldOpenExternally(display))
    }

    func testContactSchemesOpenExternally() throws {
        XCTAssertTrue(EmbedLinkOpener.shouldOpenExternally(try XCTUnwrap(URL(string: "tel:0212345678"))))
        XCTAssertTrue(EmbedLinkOpener.shouldOpenExternally(try XCTUnwrap(URL(string: "mailto:shop@example.com"))))
        XCTAssertTrue(EmbedLinkOpener.shouldOpenExternally(try XCTUnwrap(URL(string: "line://ti/p/@shop"))))
    }

    func testInternalSchemesStayInTheWebView() throws {
        XCTAssertFalse(EmbedLinkOpener.shouldOpenExternally(try XCTUnwrap(URL(string: "about:blank"))))
        XCTAssertFalse(EmbedLinkOpener.shouldOpenExternally(try XCTUnwrap(URL(string: "javascript:void(0)"))))
        XCTAssertFalse(EmbedLinkOpener.shouldOpenExternally(try XCTUnwrap(URL(string: "data:text/html,hi"))))
    }
}
