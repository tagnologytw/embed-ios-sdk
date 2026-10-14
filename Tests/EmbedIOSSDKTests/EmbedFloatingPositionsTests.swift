import XCTest
@testable import EmbedIOSSDK

final class EmbedFloatingPositionsTests: XCTestCase {
    func testRequestPostsMidPageUrlAndSecret() throws {
        let request = try EmbedAPI.makeFloatingPositionsRequest(
            pageUrl: "https://partnertest4.91app.com/SalePage/Index/8778040",
            mid: "41458",
            secret: "test-secret"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://embed.tagnology.co/api/widget/floatingPositions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["mid"] as? Int, 41458)
        XCTAssertEqual(json["pageUrl"] as? String, "https://partnertest4.91app.com/SalePage/Index/8778040")
        XCTAssertEqual(json["secret"] as? String, "test-secret")
    }

    func testRequestKeepsNonNumericMidAsString() throws {
        let request = try EmbedAPI.makeFloatingPositionsRequest(
            pageUrl: "https://example.com/SalePage/Index/1",
            mid: "shop-a",
            secret: "s"
        )
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["mid"] as? String, "shop-a")
    }

    func testRequestRejectsEmptyPageUrl() {
        XCTAssertThrowsError(
            try EmbedAPI.makeFloatingPositionsRequest(pageUrl: "", mid: "1", secret: "s")
        )
    }

    func testParseKeepsOnlyFloatingPositionsInOrderWithoutDuplicates() {
        let positions = EmbedAPI.parseFloatingPositions([
            "FIXED_BOTTOM_RIGHT",
            "fixed_top_left",
            "BELOW_BUY_BUTTON",
            "UNKNOWN",
            "FIXED_BOTTOM_RIGHT"
        ])

        XCTAssertEqual(positions, [.FIXED_BOTTOM_RIGHT, .FIXED_TOP_LEFT])
    }

    func testParseEmptyArrayReturnsNoPositions() {
        XCTAssertEqual(EmbedAPI.parseFloatingPositions([]), [])
    }

    func testDecodeResponse() throws {
        let data = Data(#"{"message":"success","positions":["FIXED_TOP_LEFT"]}"#.utf8)
        let response = try JSONDecoder().decode(EmbedAPI.FloatingPositionsResponse.self, from: data)
        XCTAssertEqual(EmbedAPI.parseFloatingPositions(response.positions), [.FIXED_TOP_LEFT])
    }
}

@MainActor
final class EmbedFloatingPositionsDataManagerTests: XCTestCase {
    private let pageUrl = "https://example.com/SalePage/Index/500"

    private func makeManager(
        floating: @escaping EmbedWidgetDataManager.FloatingPositionsFetcher
    ) -> EmbedWidgetDataManager {
        EmbedWidgetDataManager._makeForTests(floatingPositionsFetcher: floating) { _, _, _, _ in
            EmbedAPI.PageBundleResponse(message: "ok", pageBundle: [])
        }
    }

    func testReturnsNotInitializedBeforeInitialize() async {
        let manager = makeManager { _, _, _, _ in [.FIXED_TOP_LEFT] }

        let result = await manager.floatingPositionsResult()

        XCTAssertEqual(result.positions, [])
        XCTAssertEqual(result.error?.statusCode, EmbedWidgetLoadError.StatusCode.notInitialized.rawValue)
    }

    func testInitializeFetchesFloatingPositionsWithInitParameters() async {
        var received: [String] = []
        let manager = makeManager { pageUrl, mid, secret, baseURL in
            received = [pageUrl, mid, secret, baseURL]
            return [.FIXED_TOP_LEFT, .FIXED_BOTTOM_RIGHT]
        }

        let initError = await manager.initialize(
            pageUrl: pageUrl,
            mid: "41458",
            payloadSecret: "secret",
            baseURL: "https://api.example.com"
        )
        let result = await manager.floatingPositionsResult()

        XCTAssertNil(initError)
        XCTAssertEqual(received, [pageUrl, "41458", "secret", "https://api.example.com"])
        XCTAssertEqual(result.positions, [.FIXED_TOP_LEFT, .FIXED_BOTTOM_RIGHT])
        XCTAssertNil(result.error)
    }

    func testFloatingFailureDoesNotFailInitialize() async {
        let manager = makeManager { _, _, _, _ in throw URLError(.badServerResponse) }

        let initError = await manager.initialize(pageUrl: pageUrl, mid: "1", payloadSecret: "s")
        let result = await manager.floatingPositionsResult()

        XCTAssertNil(initError)
        XCTAssertEqual(result.positions, [])
        XCTAssertEqual(result.error?.statusCode, EmbedWidgetLoadError.StatusCode.systemError.rawValue)
    }

    func testWaitsForInitializationInProgress() async {
        let manager = makeManager { _, _, _, _ in
            try await Task.sleep(nanoseconds: 50_000_000)
            return [.FIXED_CENTER_LEFT]
        }

        let initTask = Task { await manager.initialize(pageUrl: pageUrl, mid: "1", payloadSecret: "s") }
        await Task.yield()
        let result = await manager.floatingPositionsResult()
        _ = await initTask.value

        XCTAssertEqual(result.positions, [.FIXED_CENTER_LEFT])
        XCTAssertNil(result.error)
    }
}
