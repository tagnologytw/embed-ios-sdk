import XCTest
@testable import EmbedIOSSDK

final class EmbedTrackingURLTests: XCTestCase {
    private let page = "https://shop.91app.com/SalePage/Index/9323753"

    func testAddsWebUtmParametersToPageUrl() {
        let url = EmbedTrackingURL.make(
            pageUrl: page,
            folderId: "folder-1",
            folderName: "夏季 新品",
            embedLocation: "BELOW_BUY_BUTTON",
            mediaId: "media-9"
        )

        XCTAssertEqual(
            url,
            "https://shop.91app.com/SalePage/Index/9323753"
                + "?utm_source=embed_tagnology"
                + "&utm_id=folder-1"
                + "&utm_content=media-9"
                + "&utm_medium=BELOW_BUY_BUTTON"
                + "&utm_campaign=%E5%A4%8F%E5%AD%A3+%E6%96%B0%E5%93%81"
                + "&utm_term=https%3A%2F%2Fshop.91app.com%2FSalePage%2FIndex%2F9323753"
        )
    }

    func testFallsBackToCustomizedAndFolderIdAndLeavesMissingMediaIdEmpty() {
        let url = EmbedTrackingURL.make(
            pageUrl: page,
            folderId: "folder-1",
            folderName: nil,
            embedLocation: nil,
            mediaId: nil
        )

        XCTAssertEqual(
            url,
            "https://shop.91app.com/SalePage/Index/9323753"
                + "?utm_source=embed_tagnology&utm_id=folder-1&utm_content=&utm_medium=CUSTOMIZED&utm_campaign=folder-1"
                + "&utm_term=https%3A%2F%2Fshop.91app.com%2FSalePage%2FIndex%2F9323753"
        )
    }

    func testKeepsOtherQueryAndFragmentAndReplacesPreviousEmbedUtm() {
        let url = EmbedTrackingURL.make(
            pageUrl: page + "?shopId=1&utm_source=embed_tagnology&utm_content=old#reviews",
            folderId: "f",
            folderName: "wall",
            embedLocation: "ABOVE_FILTER",
            mediaId: nil
        )

        XCTAssertEqual(
            url,
            "https://shop.91app.com/SalePage/Index/9323753"
                + "?shopId=1&utm_source=embed_tagnology&utm_content=&utm_id=f&utm_medium=ABOVE_FILTER&utm_campaign=wall"
                + "&utm_term=https%3A%2F%2Fshop.91app.com%2FSalePage%2FIndex%2F9323753"
                + "#reviews"
        )
    }

    func testKeepsForeignUtmAndAppendsEmbedToUtmContent() {
        let url = EmbedTrackingURL.make(
            pageUrl: page + "?utm_source=facebook&utm_medium=cpc&utm_content=ad1",
            folderId: "f",
            folderName: "wall",
            embedLocation: "BELOW_BUY_BUTTON",
            mediaId: "m"
        )

        XCTAssertEqual(
            url,
            "https://shop.91app.com/SalePage/Index/9323753"
                + "?utm_source=facebook&utm_medium=cpc&utm_content=ad1%2Bembed_tagnology"
        )
    }

    func testForeignUtmWithoutContentGetsEmbedContent() {
        let url = EmbedTrackingURL.make(
            pageUrl: page + "?utm_source=line",
            folderId: "f",
            folderName: nil,
            embedLocation: nil,
            mediaId: nil
        )

        XCTAssertEqual(url, page + "?utm_source=line&utm_content=embed_tagnology")
    }

    func testReturnsNilForNonHttpPageUrl() {
        XCTAssertNil(EmbedTrackingURL.make(pageUrl: "", folderId: "f", folderName: nil, embedLocation: nil, mediaId: nil))
        XCTAssertNil(EmbedTrackingURL.make(pageUrl: "app://product/1", folderId: "f", folderName: nil, embedLocation: nil, mediaId: nil))
    }

    func testClickEventInitKeepsTrackingUrlOptional() {
        let event = EmbedWidgetClickEvent(folderId: "f", folderName: nil, position: nil, mediaId: nil, url: page)
        XCTAssertNil(event.trackingUrl)
    }

    // MARK: - Link click

    private let product = URL(string: "https://shop.91app.com/SalePage/Index/555")!

    func testLinkGetsFullEmbedUtmLikeWebAddUTMParams() {
        let url = EmbedTrackingURL.makeForLink(
            linkUrl: product,
            pageUrl: page + "?shopId=1",
            folderId: "f",
            folderName: "wall",
            mediaId: "m"
        )

        XCTAssertEqual(
            url,
            "https://shop.91app.com/SalePage/Index/555"
                + "?utm_source=embed_tagnology&utm_content=m&utm_medium=LINK&utm_id=f&utm_campaign=wall"
                + "&utm_term=https%3A%2F%2Fshop.91app.com%2FSalePage%2FIndex%2F9323753%3FshopId%3D1"
        )
    }

    func testLinkLeavesMissingValuesEmpty() {
        let url = EmbedTrackingURL.makeForLink(
            linkUrl: product,
            pageUrl: nil,
            folderId: "f",
            folderName: nil,
            mediaId: nil
        )

        XCTAssertEqual(
            url,
            "https://shop.91app.com/SalePage/Index/555"
                + "?utm_source=embed_tagnology&utm_content=&utm_medium=LINK&utm_id=f&utm_campaign=&utm_term="
        )
    }

    func testLinkKeepsEmbedUtmTheWebPageAlreadyAdded() {
        // The Lightbox may show another post than the one first tapped; the page knows which.
        let link = URL(string: "https://shop.91app.com/SalePage/Index/555?utm_source=embed_tagnology&utm_content=shown-post&utm_medium=LINK&utm_id=f&utm_campaign=wall&utm_term=https%3A%2F%2Fshop.91app.com%2FSalePage%2FIndex%2F9323753")!
        let url = EmbedTrackingURL.makeForLink(
            linkUrl: link,
            pageUrl: page,
            folderId: "f",
            folderName: "wall",
            mediaId: "first-post"
        )

        XCTAssertEqual(url, link.absoluteString)
    }

    func testLinkReplacesOtherUtmSource() {
        let link = URL(string: "https://shop.91app.com/SalePage/Index/555?utm_source=facebook&utm_medium=cpc")!
        let url = EmbedTrackingURL.makeForLink(linkUrl: link, pageUrl: page, folderId: "f", folderName: "w", mediaId: "m")

        XCTAssertEqual(
            url,
            "https://shop.91app.com/SalePage/Index/555"
                + "?utm_source=embed_tagnology&utm_medium=LINK&utm_content=m&utm_id=f&utm_campaign=w"
                + "&utm_term=https%3A%2F%2Fshop.91app.com%2FSalePage%2FIndex%2F9323753"
        )
    }

    func testNonHttpLinkHasNoTrackingUrl() {
        let tel = URL(string: "tel:0212345678")!
        XCTAssertNil(EmbedTrackingURL.makeForLink(linkUrl: tel, pageUrl: page, folderId: "f", folderName: nil, mediaId: nil))
    }

    @MainActor
    func testLinkClickHandlerGetsTrackingUrlAndWidgetInfo() {
        defer { EmbedIOSSDK.setLinkClickHandler(nil) }
        var received: [EmbedLinkClickEvent] = []
        EmbedIOSSDK.setLinkClickHandler { event in
            received.append(event)
            return true
        }
        let context = EmbedLinkContext(pageUrl: page, folderId: "f", folderName: "wall", position: "BELOW_BUY_BUTTON", mediaId: "m")

        let outcome = EmbedLinkOpener.open(product, context: context, systemOpen: { _ in XCTFail("handled by app") })

        XCTAssertEqual(outcome, .handledByApp)
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.url, product)
        XCTAssertEqual(received.first?.folderId, "f")
        XCTAssertEqual(received.first?.position, "BELOW_BUY_BUTTON")
        XCTAssertEqual(received.first?.mediaId, "m")
        XCTAssertEqual(received.first?.pageUrl, page)
        XCTAssertTrue(received.first?.trackingUrl?.hasPrefix(product.absoluteString + "?utm_source=embed_tagnology") == true)
    }

    @MainActor
    func testLegacyLinkHandlerStillGetsTheUnchangedUrl() {
        defer { EmbedIOSSDK.setLinkHandler(nil) }
        var received: [URL] = []
        EmbedIOSSDK.setLinkHandler { url in
            received.append(url)
            return true
        }
        let context = EmbedLinkContext(pageUrl: page, folderId: "f", mediaId: "m")

        XCTAssertEqual(EmbedLinkOpener.open(product, context: context, systemOpen: { _ in }), .handledByApp)
        XCTAssertEqual(received, [product])
    }

    // MARK: - Click payload mediaId

    func testClickPayloadMediaIdPrefersMediaId() {
        XCTAssertEqual(EmbedClickPayload.mediaId(from: ["mediaId": "m", "mediaList": [["mediaId": "first"]]]), "m")
        XCTAssertEqual(EmbedClickPayload.mediaId(from: ["mediaId": NSNumber(value: 123)]), "123")
    }

    func testHighlightClickUsesFirstPrefetchedStory() {
        let item: [String: Any] = ["highlightId": "h", "mediaList": [["mediaId": "story-1"], ["mediaId": "story-2"]]]
        XCTAssertEqual(EmbedClickPayload.mediaId(from: item), "story-1")
    }

    func testHighlightClickWithoutPrefetchedListHasNoMediaId() {
        XCTAssertNil(EmbedClickPayload.mediaId(from: ["highlightId": "h"]))
        XCTAssertNil(EmbedClickPayload.mediaId(from: ["highlightId": "h", "mediaList": []]))
    }
}
