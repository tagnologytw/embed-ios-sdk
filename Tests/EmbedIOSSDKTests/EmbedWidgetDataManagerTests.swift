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
