import XCTest
@testable import EmbedIOSSDK

private actor ControlledPageBundleFetcher {
    typealias Response = EmbedAPI.PageBundleResponse

    private var continuations: [String: CheckedContinuation<Response, Error>] = [:]

    func fetch(pageUrl: String) async throws -> Response {
        try await withCheckedThrowingContinuation { continuation in
            continuations[pageUrl] = continuation
        }
    }

    func waitUntilRequested(_ pageUrl: String) async {
        while continuations[pageUrl] == nil {
            await Task.yield()
        }
    }

    func succeed(pageUrl: String, response: Response) {
        continuations.removeValue(forKey: pageUrl)?.resume(returning: response)
    }

    func fail(pageUrl: String, error: Error) {
        continuations.removeValue(forKey: pageUrl)?.resume(throwing: error)
    }
}

@MainActor
final class EmbedWidgetDataManagerTests: XCTestCase {
    func testFixedPositionsUseEightPointSpacing() {
        let fixedPositions: [EmbedPosition] = [
            .FIXED_BOTTOM_LEFT,
            .FIXED_BOTTOM_RIGHT,
            .FIXED_TOP_LEFT,
            .FIXED_TOP_RIGHT,
            .FIXED_CENTER_LEFT,
            .FIXED_CENTER_RIGHT
        ]
        let standardPositions: [EmbedPosition] = [
            .BELOW_BUY_BUTTON,
            .BELOW_MAIN_PRODUCT_INFO,
            .ABOVE_RECOMMENDATION,
            .ABOVE_FILTER
        ]

        XCTAssertTrue(fixedPositions.allSatisfy { $0.widgetStackSpacing == 8 })
        XCTAssertTrue(standardPositions.allSatisfy { $0.widgetStackSpacing == 0 })
    }

    func testFixedPositionReturnsAllMatchingWidgetsInTimestampOrder() async {
        let pageUrl = "https://example.com/SalePage/Index/500"
        let response = EmbedAPI.PageBundleResponse(
            message: "ok",
            pageBundle: [
                EmbedFolderInfo(
                    folderId: "older-left",
                    timestamp: 100,
                    layout: "FloatingMedia",
                    setting: ["floatingMediaPosition": .string("BottomLeft")]
                ),
                EmbedFolderInfo(
                    folderId: "newer-left",
                    timestamp: 200,
                    layout: "floatingmedia",
                    floatingMediaPosition: "BottomLeft"
                ),
                EmbedFolderInfo(
                    folderId: "other-position",
                    timestamp: 300,
                    layout: "FloatingMedia",
                    floatingMediaPosition: "BottomRight"
                ),
                EmbedFolderInfo(
                    folderId: "not-floating-media",
                    embedLocation: EmbedPosition.FIXED_BOTTOM_LEFT.rawValue,
                    timestamp: 400,
                    layout: "Carousel"
                )
            ]
        )
        let manager = EmbedWidgetDataManager._makeForTests { _, _, _, _ in
            response
        }

        let initError = await manager.initialize(
            pageUrl: pageUrl,
            mid: "1",
            payloadSecret: "secret"
        )
        XCTAssertNil(initError)

        let result = await manager.getWidgetsForPositionResult(
            position: .FIXED_BOTTOM_LEFT,
            expectedPageUrl: pageUrl
        )

        XCTAssertNil(result.error)
        XCTAssertEqual(
            result.widgets.map(\.folderId),
            ["newer-left", "older-left"]
        )
    }

    func testNewPageRemainsActiveWhenPreviousInitializationFinishesLast() async {
        let fetcher = ControlledPageBundleFetcher()
        let manager = EmbedWidgetDataManager._makeForTests { pageUrl, _, _, _ in
            try await fetcher.fetch(pageUrl: pageUrl)
        }

        let firstPageUrl = "https://example.com/SalePage/Index/100"
        let secondPageUrl = "https://example.com/SalePage/Index/200"

        let firstTask = Task { @MainActor in
            await manager.initialize(
                pageUrl: firstPageUrl,
                mid: "1",
                payloadSecret: "secret"
            )
        }
        await fetcher.waitUntilRequested(firstPageUrl)

        let secondTask = Task { @MainActor in
            await manager.initialize(
                pageUrl: secondPageUrl,
                mid: "1",
                payloadSecret: "secret"
            )
        }
        await fetcher.waitUntilRequested(secondPageUrl)

        await fetcher.succeed(
            pageUrl: secondPageUrl,
            response: makeResponse(folderId: "second", pageUrl: secondPageUrl)
        )
        let secondError = await secondTask.value
        XCTAssertNil(secondError)

        var result = await manager.getWidgetsForPositionResult(
            position: .BELOW_BUY_BUTTON,
            expectedPageUrl: secondPageUrl
        )
        XCTAssertNil(result.error)
        XCTAssertEqual(result.pageUrl, secondPageUrl)
        XCTAssertEqual(result.widgets.map(\.folderId), ["second"])

        // The cancelled fetch deliberately ignores cancellation and completes
        // after the current page. Its result must not overwrite shared state.
        await fetcher.succeed(
            pageUrl: firstPageUrl,
            response: makeResponse(folderId: "first", pageUrl: firstPageUrl)
        )
        let firstError = await firstTask.value
        XCTAssertEqual(
            firstError?.statusCode,
            EmbedWidgetLoadError.StatusCode.pageMismatch.rawValue
        )

        result = await manager.getWidgetsForPositionResult(
            position: .BELOW_BUY_BUTTON,
            expectedPageUrl: secondPageUrl
        )
        XCTAssertNil(result.error)
        XCTAssertEqual(result.pageUrl, secondPageUrl)
        XCTAssertEqual(result.widgets.map(\.folderId), ["second"])
    }

    func testStaleFailureCannotReplaceSuccessfulCurrentPageState() async {
        let fetcher = ControlledPageBundleFetcher()
        let manager = EmbedWidgetDataManager._makeForTests { pageUrl, _, _, _ in
            try await fetcher.fetch(pageUrl: pageUrl)
        }

        let firstPageUrl = "https://example.com/SalePage/Index/300"
        let secondPageUrl = "https://example.com/SalePage/Index/400"

        let firstTask = Task { @MainActor in
            await manager.initialize(
                pageUrl: firstPageUrl,
                mid: "1",
                payloadSecret: "secret"
            )
        }
        await fetcher.waitUntilRequested(firstPageUrl)

        let secondTask = Task { @MainActor in
            await manager.initialize(
                pageUrl: secondPageUrl,
                mid: "1",
                payloadSecret: "secret"
            )
        }
        await fetcher.waitUntilRequested(secondPageUrl)

        await fetcher.succeed(
            pageUrl: secondPageUrl,
            response: makeResponse(folderId: "current", pageUrl: secondPageUrl)
        )
        let secondError = await secondTask.value
        XCTAssertNil(secondError)

        await fetcher.fail(pageUrl: firstPageUrl, error: URLError(.timedOut))
        let firstError = await firstTask.value
        XCTAssertEqual(
            firstError?.statusCode,
            EmbedWidgetLoadError.StatusCode.pageMismatch.rawValue
        )

        let result = await manager.getWidgetsForPositionResult(
            position: .BELOW_BUY_BUTTON,
            expectedPageUrl: secondPageUrl
        )
        XCTAssertNil(result.error)
        XCTAssertEqual(result.pageUrl, secondPageUrl)
        XCTAssertEqual(result.widgets.map(\.folderId), ["current"])
    }

    private func makeResponse(
        folderId: String,
        pageUrl: String
    ) -> EmbedAPI.PageBundleResponse {
        EmbedAPI.PageBundleResponse(
            message: "ok",
            pageBundle: [
                EmbedFolderInfo(
                    folderId: folderId,
                    productUrl: pageUrl,
                    embedLocation: EmbedPosition.BELOW_BUY_BUTTON.rawValue
                )
            ]
        )
    }
}
