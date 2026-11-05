import Foundation
import XCTest
import WebKit
@testable import EmbedIOSSDK

@MainActor
final class EmbedWebViewConfigurationTests: XCTestCase {
    func testSDKConfigurationsShareAnIsolatedDataStore() {
        let firstConfiguration = EmbedWebViewConfigurationFactory.make()
        let secondConfiguration = EmbedWebViewConfigurationFactory.make()
        let defaultDataStore = WKWebsiteDataStore.default()

        XCTAssertFalse(firstConfiguration.websiteDataStore === defaultDataStore)
        XCTAssertTrue(firstConfiguration.websiteDataStore === secondConfiguration.websiteDataStore)
    }

    /// The HTTP cache must survive app launches (iOS 17+), so the widget page's JS is not
    /// downloaded again on every launch. iOS 16 has no identifier stores.
    func testSDKDataStoreIsPersistentOnIOS17() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("identifier stores need iOS 17") }
        let store = EmbedWebViewConfigurationFactory.websiteDataStore

        XCTAssertTrue(store.isPersistent)
        XCTAssertEqual(store.identifier, EmbedWebViewConfigurationFactory.persistentStoreIdentifier)
    }

    /// Only the disk cache is kept across launches: cookies left by an earlier launch are
    /// removed before initialize returns, as with the earlier in-memory store.
    func testPreparingWebsiteDataRemovesEarlierCookiesButKeepsTheDiskCache() async throws {
        XCTAssertEqual(EmbedWebViewConfigurationFactory.dataTypesKeptAcrossLaunches, [WKWebsiteDataTypeDiskCache])

        let cookieName = "earlier-launch-\(UUID().uuidString)"
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "sdk-cookie-cleanup.invalid",
            .path: "/",
            .name: cookieName,
            .value: "stale",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(3600)
        ]))
        let store = EmbedWebViewConfigurationFactory.websiteDataStore
        await store.httpCookieStore.setCookie(cookie)
        // Cleanup runs once per launch; reset it to simulate the next launch.
        EmbedWebViewConfigurationFactory.resetPreparationForTests()

        await EmbedWebViewConfigurationFactory.prepareWebsiteData()

        let cookies = await store.httpCookieStore.allCookies()
        if store.isPersistent {
            XCTAssertFalse(cookies.contains { $0.name == cookieName })
        }
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
