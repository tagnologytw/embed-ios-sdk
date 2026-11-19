import XCTest
@testable import EmbedIOSSDK

final class EmbedLinkOpenerTests: XCTestCase {
    private let productURL = URL(string: "https://partnertest7.91app.com/SalePage/Index/9394400?utm_source=embed_tagnology")!

    @MainActor
    override func tearDown() {
        EmbedIOSSDK.setLinkHandler(nil)
        super.tearDown()
    }

    @MainActor
    func testWithoutHandlerLinksOpenWithTheSystem() {
        var opened: [URL] = []
        let outcome = EmbedLinkOpener.open(productURL, systemOpen: { opened.append($0) })
        XCTAssertEqual(outcome, .openedBySystem)
        XCTAssertEqual(opened, [productURL])
    }

    @MainActor
    func testHandlerReturningTrueKeepsTheLinkOutOfTheBrowser() {
        var handled: [URL] = []
        var opened: [URL] = []
        EmbedIOSSDK.setLinkHandler { url in
            handled.append(url)
            return true
        }
        let outcome = EmbedLinkOpener.open(productURL, systemOpen: { opened.append($0) })
        XCTAssertEqual(outcome, .handledByApp)
        XCTAssertEqual(handled, [productURL], "the App gets the full URL, query included")
        XCTAssertTrue(opened.isEmpty)
    }

    @MainActor
    func testHandlerReturningFalseFallsBackToTheSystem() {
        var opened: [URL] = []
        EmbedIOSSDK.setLinkHandler { _ in false }
        let outcome = EmbedLinkOpener.open(productURL, systemOpen: { opened.append($0) })
        XCTAssertEqual(outcome, .openedBySystem)
        XCTAssertEqual(opened, [productURL])
    }

    @MainActor
    func testEmbedPagesNeverReachTheHandler() throws {
        var handled = 0
        EmbedIOSSDK.setLinkHandler { _ in
            handled += 1
            return true
        }
        let lightbox = try XCTUnwrap(URL(string: "https://embed.tagnology.co/lightBox?page=https://example.com"))
        XCTAssertEqual(EmbedLinkOpener.open(lightbox, systemOpen: { _ in XCTFail("must stay in the web view") }), .notExternal)
        XCTAssertEqual(EmbedLinkOpener.open(nil, systemOpen: { _ in XCTFail("no URL") }), .notExternal)
        XCTAssertEqual(handled, 0)
    }

    @MainActor
    func testSettingNilRemovesTheHandler() {
        var opened = 0
        EmbedIOSSDK.setLinkHandler { _ in true }
        EmbedIOSSDK.setLinkHandler(nil)
        XCTAssertEqual(EmbedLinkOpener.open(productURL, systemOpen: { _ in opened += 1 }), .openedBySystem)
        XCTAssertEqual(opened, 1)
    }

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
