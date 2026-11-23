import XCTest
@testable import EmbedIOSSDK

/// Server answers 403 + errorCode APP_SDK_DISABLED when the merchant's App SDK access is off.
@MainActor
final class EmbedAppSdkDisabledTests: XCTestCase {
    private let pageUrl = "https://example.com/SalePage/Index/800"

    private func httpResponse(_ statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://embed.tagnology.co/api/widget/pageBundle")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    func testValidateThrowsAppSdkDisabledFor403WithErrorCode() {
        let body = #"{"success":false,"code":403,"errorCode":"APP_SDK_DISABLED","message":"app sdk disabled"}"#
        XCTAssertThrowsError(
            try EmbedAPI.validateHTTPResponse(httpResponse(403), data: Data(body.utf8))
        ) { error in
            XCTAssertTrue(error is EmbedAPI.AppSdkDisabledError)
        }
    }

    func testValidateKeepsBadServerResponseForOther403() {
        let body = #"{"message":"forbidden"}"#
        XCTAssertThrowsError(
            try EmbedAPI.validateHTTPResponse(httpResponse(403), data: Data(body.utf8))
        ) { error in
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
        }
    }

    func testValidatePassesFor2xx() {
        XCTAssertNoThrow(try EmbedAPI.validateHTTPResponse(httpResponse(200), data: Data()))
    }

    func testInitializeReturns403WithErrorCodeAndWidgetsGetTheSameError() async {
        let manager = EmbedWidgetDataManager._makeForTests(
            floatingPositionsFetcher: { _, _, _, _ in throw EmbedAPI.AppSdkDisabledError() },
            pageBundleFetcher: { _, _, _, _ in throw EmbedAPI.AppSdkDisabledError() }
        )

        let error = await manager.initialize(pageUrl: pageUrl, mid: "1", payloadSecret: "secret")

        XCTAssertEqual(error?.statusCode, 403)
        XCTAssertEqual(error?.statusCode, EmbedWidgetLoadError.StatusCode.appSdkDisabled.rawValue)
        XCTAssertEqual(error?.errorCode, EmbedAPI.appSdkDisabledErrorCode)

        let widgets = await manager.getWidgetsForPositionResult(
            position: .BELOW_BUY_BUTTON,
            expectedPageUrl: pageUrl
        )
        XCTAssertTrue(widgets.widgets.isEmpty)
        XCTAssertEqual(widgets.error?.statusCode, 403)
        XCTAssertEqual(widgets.error?.errorCode, "APP_SDK_DISABLED")

        let floating = await manager.floatingPositionsResult()
        XCTAssertTrue(floating.positions.isEmpty)
        XCTAssertEqual(floating.error?.errorCode, "APP_SDK_DISABLED")
    }
}
