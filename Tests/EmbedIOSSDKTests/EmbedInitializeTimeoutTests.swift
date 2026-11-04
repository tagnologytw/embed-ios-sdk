import XCTest
@testable import EmbedIOSSDK

/// A pageBundle request that never answers and ignores cancellation, like a stalled connection.
private actor StalledFetcher {
    private var continuations: [CheckedContinuation<EmbedAPI.PageBundleResponse, Error>] = []

    func fetch() async throws -> EmbedAPI.PageBundleResponse {
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }

    func release() {
        continuations.forEach { $0.resume(throwing: URLError(.cancelled)) }
        continuations = []
    }
}

@MainActor
final class EmbedInitializeTimeoutTests: XCTestCase {
    private let pageUrl = "https://example.com/SalePage/Index/700"

    private func makeResponse() -> EmbedAPI.PageBundleResponse {
        EmbedAPI.PageBundleResponse(
            message: "ok",
            pageBundle: [
                EmbedFolderInfo(
                    folderId: "folder-1",
                    embedLocation: EmbedPosition.BELOW_BUY_BUTTON.rawValue
                )
            ]
        )
    }

    func testDefaultTimeoutIsThreeSeconds() {
        XCTAssertEqual(EmbedIOSSDK.defaultInitializeTimeout, 3)
    }

    func testSlowPageBundleReturnsTimeoutAtTheDeadline() async {
        let fetcher = StalledFetcher()
        let manager = EmbedWidgetDataManager._makeForTests { _, _, _, _ in
            try await fetcher.fetch()
        }

        let started = Date()
        let error = await manager.initialize(
            pageUrl: pageUrl,
            mid: "1",
            payloadSecret: "secret",
            timeout: 0.2
        )
        let elapsed = Date().timeIntervalSince(started)
        await fetcher.release()

        XCTAssertEqual(error?.statusCode, EmbedWidgetLoadError.StatusCode.timeout.rawValue)
        XCTAssertLessThan(elapsed, 1.0, "initialize must return at the deadline even if the request never answers")

        let result = await manager.getWidgetsForPositionResult(
            position: .BELOW_BUY_BUTTON,
            expectedPageUrl: pageUrl
        )
        XCTAssertTrue(result.widgets.isEmpty)
        XCTAssertEqual(result.error?.statusCode, EmbedWidgetLoadError.StatusCode.timeout.rawValue)
    }

    func testTimeoutCanBeRetriedAndSucceed() async {
        var attempts = 0
        let response = makeResponse()
        let manager = EmbedWidgetDataManager._makeForTests { _, _, _, _ in
            attempts += 1
            if attempts == 1 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
            return response
        }

        let first = await manager.initialize(pageUrl: pageUrl, mid: "1", payloadSecret: "secret", timeout: 0.2)
        XCTAssertEqual(first?.statusCode, EmbedWidgetLoadError.StatusCode.timeout.rawValue)

        let second = await manager.initialize(pageUrl: pageUrl, mid: "1", payloadSecret: "secret", timeout: 0.2)
        XCTAssertNil(second)
        let result = await manager.getWidgetsForPositionResult(
            position: .BELOW_BUY_BUTTON,
            expectedPageUrl: pageUrl
        )
        XCTAssertEqual(result.widgets.map(\.folderId), ["folder-1"])
    }

    func testSlowFloatingPositionsDoNotDelayInitialize() async {
        let response = makeResponse()
        let manager = EmbedWidgetDataManager._makeForTests(
            floatingPositionsFetcher: { _, _, _, _ in
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return [.FIXED_BOTTOM_RIGHT]
            },
            pageBundleFetcher: { _, _, _, _ in response }
        )

        let started = Date()
        let error = await manager.initialize(
            pageUrl: pageUrl,
            mid: "1",
            payloadSecret: "secret",
            timeout: 0.2
        )

        XCTAssertNil(error)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
        let floating = await manager.floatingPositionsResult()
        XCTAssertEqual(floating.positions, [])
        XCTAssertEqual(floating.error?.statusCode, EmbedWidgetLoadError.StatusCode.timeout.rawValue)
    }

    func testZeroTimeoutWaitsForTheResponse() async {
        let response = makeResponse()
        let manager = EmbedWidgetDataManager._makeForTests { _, _, _, _ in
            try await Task.sleep(nanoseconds: 300_000_000)
            return response
        }

        let error = await manager.initialize(
            pageUrl: pageUrl,
            mid: "1",
            payloadSecret: "secret",
            timeout: 0
        )

        XCTAssertNil(error)
    }

    func testUnboundedTimeoutsRunWithoutALimitInsteadOfCrashing() async throws {
        for seconds in [TimeInterval.infinity, .nan, 1e12, -1] {
            let value = try await EmbedDeadline.run(seconds: seconds) { 7 }
            XCTAssertEqual(value, 7, "seconds=\(seconds)")
        }
    }

    func testDeadlineReturnsTheResultWhenItArrivesInTime() async throws {
        let value = try await EmbedDeadline.run(seconds: 1) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testDeadlinePassesThroughTheRequestError() async {
        do {
            _ = try await EmbedDeadline.run(seconds: 1) { () async throws -> Int in
                throw URLError(.badServerResponse)
            }
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
        }
    }
}
