import Foundation
import XCTest
import WebKit
@testable import EmbedIOSSDK

@MainActor
final class EmbedWebViewConfigurationTests: XCTestCase {
    func testSDKConfigurationsShareAnIsolatedNonPersistentDataStore() {
        let firstConfiguration = EmbedWebViewConfigurationFactory.make()
        let secondConfiguration = EmbedWebViewConfigurationFactory.make()
        let defaultDataStore = WKWebsiteDataStore.default()

        XCTAssertFalse(firstConfiguration.websiteDataStore.isPersistent)
        XCTAssertFalse(firstConfiguration.websiteDataStore === defaultDataStore)
        XCTAssertTrue(firstConfiguration.websiteDataStore === secondConfiguration.websiteDataStore)
    }

    func testHostDefaultStoreCookieIsNotVisibleToSDKWebViews() async throws {
        let cookieName = "host-session-\(UUID().uuidString)"
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "host-cookie-isolation.invalid",
            .path: "/",
            .name: cookieName,
            .value: "private-host-value",
            .secure: "TRUE"
        ]))
        let defaultCookieStore = WKWebsiteDataStore.default().httpCookieStore
        let sdkCookieStore = EmbedWebViewConfigurationFactory.make().websiteDataStore.httpCookieStore

        await defaultCookieStore.setCookie(cookie)
        let hostCookies = await defaultCookieStore.allCookies()
        let sdkCookies = await sdkCookieStore.allCookies()
        await defaultCookieStore.deleteCookie(cookie)

        XCTAssertTrue(hostCookies.contains { $0.name == cookieName })
        XCTAssertFalse(sdkCookies.contains { $0.name == cookieName })
    }

    func testSDKConfigurationKeepsRequiredWidgetPlaybackSettings() {
        let configuration = EmbedWebViewConfigurationFactory.make()

        XCTAssertTrue(configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertTrue(configuration.allowsInlineMediaPlayback)
        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, [])
    }
}
