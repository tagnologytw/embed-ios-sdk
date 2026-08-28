// EmbedViews.swift
import SwiftUI
import WebKit
import CryptoKit

// MARK: - View Modifiers
@available(iOS 16.0, *)
extension View {
    fileprivate func interactiveDismissDisabledCompat(_ disabled: Bool) -> some View {
        // iOS 16+ 直接支援 interactiveDismissDisabled (iOS 15.0+)
        self.interactiveDismissDisabled(disabled)
    }
}

// MARK: - Bridge constants
enum EmbedBridge {
    static let resizeHandlerName = "tagnologyResize"
    static let eventHandlerName = "tagnologyEvent"
    static let eventTypeKey = "eventType"
    static let bridgeInjectionFlag = "__tagnologyNativeBridgeInjected"
}

enum EmbedLogger {
    // Turn on only when debugging.
    static let isEnabled = false

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print(message())
    }
}

// MARK: - Analytics
enum EmbedAction: String {
    case pageView = "PAGE_VIEW"
    case embedView = "EMBED_VIEW"
    case dwellTime = "DWELL_TIME"
}

struct EmbedLogEntry {
    let action: EmbedAction
    let info: [String: Any]
}

final class EmbedAnalyticsManager {
    static let shared = EmbedAnalyticsManager()

    private var currentPageUrl: String?
    private var currentHost: String?
    private var currentBaseURL: String?
    private var folderInfosById: [String: EmbedFolderInfo] = [:]
    private var folderIds: [String] = []
    private var loggedEmbedFolderIds = Set<String>()
    private var hasLoggedPageView = false
    private var startTimeMs: Int64?
    private var startWidgetTimeMs: Int64?
    private var dwellTimeSent = false

    private var nowProvider: () -> Date = Date.init
    private var requestSender: (URLRequest) -> Void = { request in
        URLSession.shared.dataTask(with: request).resume()
    }

    private init() {}

    private func nowMs() -> Int64 {
        Int64(nowProvider().timeIntervalSince1970 * 1000)
    }

    private func buildWidgetLogURL(baseURL: String) -> URL? {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return URL(string: "\(trimmed)/widget/log")
    }

    private func sendLog(_ entry: EmbedLogEntry, baseURL: String) {
        guard let host = currentHost,
              let page = currentPageUrl,
              let url = buildWidgetLogURL(baseURL: baseURL) else {
            return
        }

        let payload: [String: Any] = [
            "host": host,
            "action": entry.action.rawValue,
            "info": entry.info.merging([
                "page": page,
                "isMobile": true
            ]) { current, _ in current }
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        if let payloadString = String(data: bodyData, encoding: .utf8) {
            print("[EmbedAnalytics] POST \(url.absoluteString) action=\(entry.action.rawValue) payload=\(payloadString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        requestSender(request)
    }

    func beginPageIfNeeded(pageUrl: String, folderInfos: [EmbedFolderInfo], baseURL: String, forceNewSession: Bool = false) {
        let isNewPage = currentPageUrl != pageUrl
        if isNewPage || forceNewSession {
            currentPageUrl = pageUrl
            currentHost = URL(string: pageUrl)?.host
            currentBaseURL = baseURL
            folderInfosById.removeAll()
            folderIds = []
            loggedEmbedFolderIds.removeAll()
            hasLoggedPageView = false
            startTimeMs = nowMs()
            startWidgetTimeMs = nil
            dwellTimeSent = false
            print("[EmbedAnalytics] session started page=\(pageUrl) forceNewSession=\(forceNewSession)")
        }

        var uniqueFolderIds = [String]()
        var seenFolderIds = Set<String>()
        for info in folderInfos {
            folderInfosById[info.folderId] = info
            if seenFolderIds.insert(info.folderId).inserted {
                uniqueFolderIds.append(info.folderId)
            }
        }
        folderIds = uniqueFolderIds

        if !hasLoggedPageView, !folderIds.isEmpty {
            hasLoggedPageView = true
            sendLog(
                EmbedLogEntry(
                    action: .pageView,
                    info: ["folderIds": folderIds]
                ),
                baseURL: baseURL
            )
        } else if folderIds.isEmpty {
            print("[EmbedAnalytics] skip PAGE_VIEW because /widget/pageBundle returned empty pageBundle")
        }
    }

    @discardableResult
    func markWidgetVisible(folderId: String, baseURL: String) -> Bool {
        guard !folderId.isEmpty else { return false }
        let activeBaseURL = currentBaseURL ?? baseURL
        guard let folderInfo = folderInfosById[folderId] else {
            // Session is not ready yet (or no pageBundle data), wait for the next visibility check.
            return false
        }
        if startWidgetTimeMs == nil {
            startWidgetTimeMs = nowMs()
        }
        if loggedEmbedFolderIds.contains(folderId) {
            return false
        }
        loggedEmbedFolderIds.insert(folderId)

        if folderInfo.layout?.lowercased() == "floatingmedia" {
            return true
        }

        sendLog(
            EmbedLogEntry(
                action: .embedView,
                info: [
                    "folderId": folderId,
                    "embedLocation": folderInfo.embedLocation ?? "CUSTOMIZED"
                ]
            ),
            baseURL: activeBaseURL
        )
        return true
    }

    func endPageIfNeeded(baseURL: String, minDurationMs: Int64 = 5000) {
        guard let startTimeMs, !dwellTimeSent else { return }
        let activeBaseURL = currentBaseURL ?? baseURL
        let currentMs = nowMs()
        let dwellTime = currentMs - startTimeMs
        guard dwellTime > minDurationMs else {
            print("[EmbedAnalytics] skip DWELL_TIME because dwellTime=\(dwellTime) <= \(minDurationMs)")
            return
        }
        guard !folderIds.isEmpty else {
            print("[EmbedAnalytics] skip DWELL_TIME because pageBundle is empty (no folderIds)")
            return
        }

        let widgetDwellTime: Int64 = {
            guard let startWidgetTimeMs else { return 0 }
            return max(currentMs - startWidgetTimeMs, 0)
        }()

        for folderId in folderIds {
            sendLog(
                EmbedLogEntry(
                    action: .dwellTime,
                    info: [
                        "folderId": folderId,
                        "dwellTime": dwellTime,
                        "widgetDwellTime": widgetDwellTime
                    ]
                ),
                baseURL: activeBaseURL
            )
        }

        dwellTimeSent = true
        print("[EmbedAnalytics] DWELL_TIME sent for \(folderIds.count) folderIds")
    }

#if DEBUG
    func _resetForTests() {
        currentPageUrl = nil
        currentHost = nil
        currentBaseURL = nil
        folderInfosById.removeAll()
        folderIds = []
        loggedEmbedFolderIds.removeAll()
        hasLoggedPageView = false
        startTimeMs = nil
        startWidgetTimeMs = nil
        dwellTimeSent = false
        nowProvider = Date.init
        requestSender = { _ in }
    }

    func _setNowProviderForTests(_ provider: @escaping () -> Date) {
        nowProvider = provider
    }

    func _setRequestSenderForTests(_ sender: @escaping (URLRequest) -> Void) {
        requestSender = sender
    }
#endif
}

#if DEBUG
public enum EmbedAnalyticsTestingHook {
    public static func reset() {
        EmbedAnalyticsManager.shared._resetForTests()
    }

    public static func setNowProvider(_ provider: @escaping () -> Date) {
        EmbedAnalyticsManager.shared._setNowProviderForTests(provider)
    }

    public static func setRequestSender(_ sender: @escaping (URLRequest) -> Void) {
        EmbedAnalyticsManager.shared._setRequestSenderForTests(sender)
    }

    public static func beginPage(pageUrl: String, folderInfos: [EmbedFolderInfo], baseURL: String = EmbedAPI.defaultBaseURL) {
        EmbedAnalyticsManager.shared.beginPageIfNeeded(pageUrl: pageUrl, folderInfos: folderInfos, baseURL: baseURL)
    }

    public static func markWidgetVisible(folderId: String, baseURL: String = EmbedAPI.defaultBaseURL) {
        EmbedAnalyticsManager.shared.markWidgetVisible(folderId: folderId, baseURL: baseURL)
    }

    public static func endPage(baseURL: String = EmbedAPI.defaultBaseURL, minDurationMs: Int64 = 5000) {
        EmbedAnalyticsManager.shared.endPageIfNeeded(baseURL: baseURL, minDurationMs: minDurationMs)
    }
}
#endif

// MARK: - Position Enum
/**
 * @enum EmbedPosition
 * @description Defines the position where the embed widget should be displayed on the page.
 */
public enum EmbedPosition: String, Codable {
    case BELOW_BUY_BUTTON = "BELOW_BUY_BUTTON"
    case BELOW_MAIN_PRODUCT_INFO = "BELOW_MAIN_PRODUCT_INFO"
    case ABOVE_RECOMMENDATION = "ABOVE_RECOMMENDATION"
    case ABOVE_FILTER = "ABOVE_FILTER"
	case FIXED_BOTTOM_LEFT = "FIXED_BOTTOM_LEFT"
	case FIXED_BOTTOM_RIGHT = "FIXED_BOTTOM_RIGHT"
	case FIXED_TOP_LEFT = "FIXED_TOP_LEFT"
	case FIXED_TOP_RIGHT = "FIXED_TOP_RIGHT"
	case FIXED_CENTER_LEFT = "FIXED_CENTER_LEFT"
	case FIXED_CENTER_RIGHT = "FIXED_CENTER_RIGHT"
}

// MARK: - SDK Namespace
/**
 * @enum EmbedIOSSDK
 * @description Main namespace for EmbedIOSSDK, providing convenient access to SDK types and constants.
 */
public enum EmbedIOSSDK {
    /// Position enum for embed widget placement
    public typealias Position = EmbedPosition
    
    /// Convenience access to position values
    public static let BELOW_BUY_BUTTON = EmbedPosition.BELOW_BUY_BUTTON
    public static let BELOW_MAIN_PRODUCT_INFO = EmbedPosition.BELOW_MAIN_PRODUCT_INFO
    public static let ABOVE_RECOMMENDATION = EmbedPosition.ABOVE_RECOMMENDATION
    public static let ABOVE_FILTER = EmbedPosition.ABOVE_FILTER
	public static let FIXED_BOTTOM_LEFT = EmbedPosition.FIXED_BOTTOM_LEFT
	public static let FIXED_BOTTOM_RIGHT = EmbedPosition.FIXED_BOTTOM_RIGHT
	public static let FIXED_TOP_LEFT = EmbedPosition.FIXED_TOP_LEFT
	public static let FIXED_TOP_RIGHT = EmbedPosition.FIXED_TOP_RIGHT
	public static let FIXED_CENTER_LEFT = EmbedPosition.FIXED_CENTER_LEFT
	public static let FIXED_CENTER_RIGHT = EmbedPosition.FIXED_CENTER_RIGHT

    /**
     * @function initialize
     * @description Initializes embed data for the current page. This must be called once
     *              before rendering EmbedWidgetView(position:).
     *
     * @param {String} pageUrl - Current page URL.
     * @param {String} mid - Merchant ID.
     * @param {String} secret - payloadSecret used to encrypt request body.
     * @param {String} baseURL - API base URL. Defaults to SDK endpoint.
     *
     * @returns {EmbedWidgetLoadError?} nil if success; error when initialization fails.
     */
    @available(iOS 16.0, *)
    public static func initialize(
        pageUrl: String,
        mid: String,
        secret: String,
        baseURL: String = EmbedAPI.defaultBaseURL,
        forceRefresh: Bool = false
    ) async -> EmbedWidgetLoadError? {
        await EmbedWidgetDataManager.shared.initialize(
            pageUrl: pageUrl,
            mid: mid,
            payloadSecret: secret,
            baseURL: baseURL,
            forceRefresh: forceRefresh
        )
    }

    public static func notifyPageDidLeave(baseURL: String = EmbedAPI.defaultBaseURL) {
        print("[EmbedAnalytics] notifyPageDidLeave called")
        EmbedAnalyticsManager.shared.endPageIfNeeded(baseURL: baseURL)
    }
}

// MARK: - API
/**
 * @class EmbedAPI
 * @description Handles API calls to fetch embed widget information from the server.
 */
public enum EmbedAPI {
    public static let defaultBaseURL = "https://embed.tagnology.co/api"

    public enum EmbedAPIError: LocalizedError {
        case invalidPageURL
        case invalidPageID
        case invalidPayloadSecret
        case encryptionFailed

        public var errorDescription: String? {
            switch self {
            case .invalidPageURL:
                return "Invalid page URL."
            case .invalidPageID:
                return "Failed to extract page ID from page URL."
            case .invalidPayloadSecret:
                return "payloadSecret must be base64-encoded 32 bytes."
            case .encryptionFailed:
                return "Failed to encrypt request payload."
            }
        }
    }

    public struct PageBundleRequestBody: Codable {
        public let mid: Int
        public let iv: String
        public let payload: String
        public let tag: String
    }
    
    /**
     * @function extractPageIdFromPageUrl
     * @description Extracts page ID from page URL using 91APP rules:
     *              - /SalePage/Index/{id}        -> "{id}"
     *              - /SalePageCategory/{id}      -> "category_{id}"
     *
     * @param {String} pageUrl - The page URL to extract product ID from.
     *
     * @returns {String?} The extracted page ID, or nil if not found.
     */
    public static func extractPageIdFromPageUrl(_ pageUrl: String) -> String? {
        guard let url = URL(string: pageUrl) else {
            return nil
        }

        let pathComponents = url.path.components(separatedBy: "/").filter { !$0.isEmpty }
        let lowercasedComponents = pathComponents.map { $0.lowercased() }

        if let indexPosition = lowercasedComponents.firstIndex(of: "index"),
           indexPosition + 1 < pathComponents.count {
            return pathComponents[indexPosition + 1]
        }

        if let categoryPosition = lowercasedComponents.firstIndex(of: "salepagecategory"),
           categoryPosition + 1 < pathComponents.count {
            // Category pages must carry the "category_" prefix to match the web
            // side's getPageInfo lookup key; a bare id returns an empty pageBundle.
            return "category_" + pathComponents[categoryPosition + 1]
        }

        return nil
    }

    // backward compatible alias
    public static func extractProductIdFromPageUrl(_ pageUrl: String) -> String? {
        extractPageIdFromPageUrl(pageUrl)
    }

    private static func getAESKey(mid: String, payloadSecret: String) -> SymmetricKey {
        let digest = SHA256.hash(data: Data((mid + payloadSecret).utf8))
        return SymmetricKey(data: Data(digest))
    }

    private static func validatePayloadSecret(_ payloadSecret: String) throws {
        guard let secretData = Data(base64Encoded: payloadSecret), secretData.count == 32 else {
            throw EmbedAPIError.invalidPayloadSecret
        }
    }

    public static func encryptPayload(mid: String, id: String, url: String, payloadSecret: String) throws -> PageBundleRequestBody {
        try validatePayloadSecret(payloadSecret)

        guard let midNumber = Int(mid) else {
            throw EmbedAPIError.encryptionFailed
        }

        let aesKey = getAESKey(mid: mid, payloadSecret: payloadSecret)
        let nonceData = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        let nonce = try AES.GCM.Nonce(data: nonceData)

        let payloadObject: [String: Any] = [
            "mid": midNumber,
            "id": id,
            "url": url
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadObject, options: [])
        let sealedBox = try AES.GCM.seal(payloadData, using: aesKey, nonce: nonce)

        return PageBundleRequestBody(
            mid: midNumber,
            iv: nonceData.base64EncodedString(),
            payload: sealedBox.ciphertext.base64EncodedString(),
            tag: sealedBox.tag.base64EncodedString()
        )
    }

    /**
     * @struct PageBundleResponse
     * @description Response structure from /widget/pageBundle.
     */
    public struct PageBundleResponse: Codable {
        public let message: String
        public let pageBundle: [EmbedFolderInfo]

        public init(message: String, pageBundle: [EmbedFolderInfo]) {
            self.message = message
            self.pageBundle = pageBundle
        }
    }

    /**
     * @function fetchPageBundle
     * @description Calls /widget/pageBundle with encrypted payload.
     */
    public static func fetchPageBundle(
        pageUrl: String,
        mid: String,
        payloadSecret: String,
        baseURL: String = defaultBaseURL
    ) async throws -> PageBundleResponse {
        guard let pageID = extractPageIdFromPageUrl(pageUrl) else {
            throw EmbedAPIError.invalidPageID
        }

        let requestBody = try encryptPayload(
            mid: mid,
            id: pageID,
            url: pageUrl,
            payloadSecret: payloadSecret
        )

        guard let requestURL = URL(string: "\(baseURL)/widget/pageBundle") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(PageBundleResponse.self, from: data)
    }
}

public enum EmbedJSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: EmbedJSONValue])
    case array([EmbedJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .number(Double(intValue))
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let objectValue = try? container.decode([String: EmbedJSONValue].self) {
            self = .object(objectValue)
        } else if let arrayValue = try? container.decode([EmbedJSONValue].self) {
            self = .array(arrayValue)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}

// MARK: - Models
/**
 * @struct EmbedFolderInfo
 * @description Information about an embed widget folder.
 */
public struct EmbedFolderInfo: Identifiable, Codable, Hashable {
    public let folderId: String
    public let productId: String?
    public let platform: String?
    public let productName: String?
    public let productUrl: String?
    public let productImage: String?
    public let embedLocation: String?
    public let timestamp: Int?
    public let folderName: String?
    public let layout: String?
    public let setting: [String: EmbedJSONValue]?
    public let floatingMediaPosition: String?

    public var id: String { folderId }

    public var resolvedFloatingMediaPosition: String? {
        if let floatingMediaPosition, !floatingMediaPosition.isEmpty {
            return floatingMediaPosition
        }
        return setting?["floatingMediaPosition"]?.stringValue
    }

    enum CodingKeys: String, CodingKey {
        case folderId
        case productId
        case platform
        case productName
        case productUrl
        case productImage
        case embedLocation
        case timestamp
        case folderName
        case layout
        case setting
        case floatingMediaPosition
    }

    public init(folderId: String, productId: String? = nil, platform: String? = nil, productName: String? = nil, productUrl: String? = nil, productImage: String? = nil, embedLocation: String? = nil, timestamp: Int? = nil, folderName: String? = nil, layout: String? = nil, setting: [String: EmbedJSONValue]? = nil, floatingMediaPosition: String? = nil) {
        self.folderId = folderId
        self.productId = productId
        self.platform = platform
        self.productName = productName
        self.productUrl = productUrl
        self.productImage = productImage
        self.embedLocation = embedLocation
        self.timestamp = timestamp
        self.folderName = folderName
        self.layout = layout
        self.setting = setting
        self.floatingMediaPosition = floatingMediaPosition
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folderId = try container.decode(String.self, forKey: .folderId)
        productId = try container.decodeIfPresent(String.self, forKey: .productId)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
        productUrl = try container.decodeIfPresent(String.self, forKey: .productUrl)
        productImage = try container.decodeIfPresent(String.self, forKey: .productImage)
        embedLocation = try container.decodeIfPresent(String.self, forKey: .embedLocation)
        timestamp = try container.decodeIfPresent(Int.self, forKey: .timestamp)
        folderName = try container.decodeIfPresent(String.self, forKey: .folderName)
        layout = try container.decodeIfPresent(String.self, forKey: .layout)
        setting = try? container.decode([String: EmbedJSONValue].self, forKey: .setting)
        floatingMediaPosition = try container.decodeIfPresent(String.self, forKey: .floatingMediaPosition)
    }
}

// MARK: - Load Error
/**
 * @struct EmbedWidgetLoadError
 * @description Callback payload for EmbedWidgetView non-normal states.
 */
public struct EmbedWidgetLoadError: Error {
    public enum StatusCode: Int {
        case ok = 200
        case noData = 204
        case invalidInitPayload = 422
        case initializing = 425
        case notInitialized = 428
        case timeout = 408
        case systemError = 500
        case otherError = 520
    }

    public let statusCode: Int
    public let message: String
    public let pageUrl: String
    public let position: EmbedPosition

    public init(statusCode: StatusCode, message: String, pageUrl: String, position: EmbedPosition) {
        self.statusCode = statusCode.rawValue
        self.message = message
        self.pageUrl = pageUrl
        self.position = position
    }

    func withPosition(_ newPosition: EmbedPosition) -> EmbedWidgetLoadError {
        EmbedWidgetLoadError(
            statusCode: StatusCode(rawValue: statusCode) ?? .otherError,
            message: message,
            pageUrl: pageUrl,
            position: newPosition
        )
    }
}

public struct EmbedWidgetClickEvent {
    public let folderId: String
    public let folderName: String?
    public let position: String?
    public let mediaId: String?
    public let url: String?

    public init(folderId: String, folderName: String?, position: String?, mediaId: String?, url: String?) {
        self.folderId = folderId
        self.folderName = folderName
        self.position = position
        self.mediaId = mediaId
        self.url = url
    }
}

// MARK: - EmbedWidgetDataManager (Shared Data Manager)
@available(iOS 16.0, *)
@MainActor
public class EmbedWidgetDataManager: ObservableObject {
    public static let shared = EmbedWidgetDataManager()

    private var cache: [String: CacheEntry] = [:]
    private var currentContext: InitContext?
    private var initTask: Task<Void, Never>?
    private var initState: InitState = .idle
    private var initError: EmbedWidgetLoadError?

    private enum InitState {
        case idle
        case loading
        case ready
        case failed
    }

    private struct InitContext: Equatable {
        let pageUrl: String
        let mid: String
        let payloadSecret: String
        let baseURL: String
    }

    private struct CacheEntry {
        let pageInfo: [EmbedFolderInfo]
    }

    struct WidgetLoadResult {
        let widgets: [EmbedFolderInfo]
        let pageUrl: String
        let error: EmbedWidgetLoadError?
    }

    private init() {}

    private func noDataResult(statusCode: EmbedWidgetLoadError.StatusCode, message: String, pageUrl: String, position: EmbedPosition) -> WidgetLoadResult {
        WidgetLoadResult(
            widgets: [],
            pageUrl: pageUrl,
            error: EmbedWidgetLoadError(
                statusCode: statusCode,
                message: message,
                pageUrl: pageUrl,
                position: position
            )
        )
    }

    private func classifyError(_ error: Error, pageUrl: String, position: EmbedPosition) -> EmbedWidgetLoadError {
        if let apiError = error as? EmbedAPI.EmbedAPIError {
            switch apiError {
            case .invalidPageID, .invalidPayloadSecret, .invalidPageURL, .encryptionFailed:
                return EmbedWidgetLoadError(
                    statusCode: .invalidInitPayload,
                    message: "Initialization payload error: \(apiError.localizedDescription)",
                    pageUrl: pageUrl,
                    position: position
                )
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return EmbedWidgetLoadError(
                    statusCode: .timeout,
                    message: "Request timeout: \(urlError.localizedDescription)",
                    pageUrl: pageUrl,
                    position: position
                )
            case .badServerResponse:
                return EmbedWidgetLoadError(
                    statusCode: .systemError,
                    message: "System error: \(urlError.localizedDescription)",
                    pageUrl: pageUrl,
                    position: position
                )
            default:
                return EmbedWidgetLoadError(
                    statusCode: .otherError,
                    message: "Other error: \(urlError.localizedDescription)",
                    pageUrl: pageUrl,
                    position: position
                )
            }
        }

        if error is DecodingError {
            return EmbedWidgetLoadError(
                statusCode: .systemError,
                message: "System error: Failed to decode API response.",
                pageUrl: pageUrl,
                position: position
            )
        }

        return EmbedWidgetLoadError(
            statusCode: .otherError,
            message: "Other error: \(error.localizedDescription)",
            pageUrl: pageUrl,
            position: position
        )
    }

    @discardableResult
    public func initialize(
        pageUrl: String,
        mid: String,
        payloadSecret: String,
        baseURL: String = EmbedAPI.defaultBaseURL,
        forceRefresh: Bool = false
    ) async -> EmbedWidgetLoadError? {
        let context = InitContext(
            pageUrl: pageUrl,
            mid: mid,
            payloadSecret: payloadSecret,
            baseURL: baseURL
        )

        if !forceRefresh,
           currentContext == context,
           initState == .ready,
           cache[pageUrl] != nil {
            EmbedLogger.log("[EmbedWidgetDataManager] initialize cache hit, skip request. pageUrl=\(pageUrl)")
            return nil
        }

        if !forceRefresh,
           currentContext == context,
           initState == .loading,
           let runningTask = initTask {
            let _: Void = await runningTask.value
            return initError
        }

        if forceRefresh {
            EmbedLogger.log("[EmbedWidgetDataManager] initialize forceRefresh=true, clearing cache for pageUrl=\(pageUrl)")
            cache.removeValue(forKey: pageUrl)
        }

        currentContext = context
        initError = nil
        initState = .loading

        if forceRefresh {
            // Immediately reset analytics tracking for re-entry, so stale visibility/session state
            // does not block EMBED_VIEW on fast return-and-scroll flows.
            EmbedAnalyticsManager.shared.beginPageIfNeeded(
                pageUrl: pageUrl,
                folderInfos: [],
                baseURL: baseURL,
                forceNewSession: true
            )
        }

        let task = Task { @MainActor in
            do {
                let pageID = EmbedAPI.extractPageIdFromPageUrl(pageUrl) ?? "nil"
                EmbedLogger.log("[EmbedWidgetDataManager] initialize start. pageUrl=\(pageUrl), pageId=\(pageID), mid=\(mid)")
                let response = try await EmbedAPI.fetchPageBundle(
                    pageUrl: pageUrl,
                    mid: mid,
                    payloadSecret: payloadSecret,
                    baseURL: baseURL
                )
                EmbedLogger.log("[EmbedWidgetDataManager] initialize success. pageBundle.count=\(response.pageBundle.count)")
                self.cache[pageUrl] = CacheEntry(
                    pageInfo: response.pageBundle
                )
                EmbedAnalyticsManager.shared.beginPageIfNeeded(
                    pageUrl: pageUrl,
                    folderInfos: response.pageBundle,
                    baseURL: baseURL,
                    forceNewSession: false
                )
                self.initState = .ready
            } catch {
                self.initState = .failed
                self.initError = self.classifyError(error, pageUrl: pageUrl, position: .BELOW_BUY_BUTTON)
                EmbedLogger.log("[EmbedWidgetDataManager] initialize failed. error=\(self.initError?.message ?? error.localizedDescription)")
            }
        }

        initTask = task
        let _: Void = await task.value
        initTask = nil
        return initError
    }

    func getWidgetsForPositionResult(position: EmbedPosition) async -> WidgetLoadResult {
        guard let context = currentContext else {
            return WidgetLoadResult(
                widgets: [],
                pageUrl: "",
                error: EmbedWidgetLoadError(
                    statusCode: .notInitialized,
                    message: "SDK not initialized. Please call EmbedIOSSDK.initialize(pageUrl:mid:secret:) first.",
                    pageUrl: "",
                    position: position
                )
            )
        }

        if initState == .loading || initTask != nil {
            return WidgetLoadResult(
                widgets: [],
                pageUrl: context.pageUrl,
                error: EmbedWidgetLoadError(
                    statusCode: .initializing,
                    message: "SDK initialization is still in progress.",
                    pageUrl: context.pageUrl,
                    position: position
                )
            )
        }

        if initState == .failed, let initError {
            return WidgetLoadResult(
                widgets: [],
                pageUrl: context.pageUrl,
                error: initError.withPosition(position)
            )
        }

        guard let cached = cache[context.pageUrl] else {
            return WidgetLoadResult(
                widgets: [],
                pageUrl: context.pageUrl,
                error: EmbedWidgetLoadError(
                    statusCode: .systemError,
                    message: "Initialization completed but cache data is missing.",
                    pageUrl: context.pageUrl,
                    position: position
                )
            )
        }

        let filtered = filterWidgetsByPosition(cached.pageInfo, position: position)
        if filtered.isEmpty {
            if cached.pageInfo.isEmpty {
                return noDataResult(
                    statusCode: .noData,
                    message: "No data: API returned pageBundle as empty array.",
                    pageUrl: context.pageUrl,
                    position: position
                )
            }
            return noDataResult(
                statusCode: .noData,
                message: "No data: No widget available for this position after filtering.",
                pageUrl: context.pageUrl,
                position: position
            )
        }

        return WidgetLoadResult(
            widgets: filtered,
            pageUrl: context.pageUrl,
            error: nil
        )
    }

    private func getFloatingMediaPositionForEmbedPosition(_ position: EmbedPosition) -> String? {
        switch position {
        case .FIXED_BOTTOM_LEFT:
            return "BottomLeft"
        case .FIXED_BOTTOM_RIGHT:
            return "BottomRight"
        case .FIXED_TOP_LEFT:
            return "TopLeft"
        case .FIXED_TOP_RIGHT:
            return "TopRight"
        case .FIXED_CENTER_LEFT:
            return "CenterLeft"
        case .FIXED_CENTER_RIGHT:
            return "CenterRight"
        default:
            return nil
        }
    }

    private func filterWidgetsByPosition(_ widgets: [EmbedFolderInfo], position: EmbedPosition) -> [EmbedFolderInfo] {
        let positionString = position.rawValue
        let expectedFloatingMediaPosition = getFloatingMediaPositionForEmbedPosition(position)
        let isFixedPosition = expectedFloatingMediaPosition != nil

        let filteredWidgets = widgets.filter { folderInfo in
            let isFloatingMedia = folderInfo.layout?.lowercased() == "floatingmedia"

            if isFixedPosition {
                if isFloatingMedia {
                    let widgetFloatingMediaPosition = folderInfo.resolvedFloatingMediaPosition
                    return widgetFloatingMediaPosition == expectedFloatingMediaPosition
                }
                return false
            }

            if isFloatingMedia {
                return false
            }

            if let embedLocation = folderInfo.embedLocation {
                let embedLocationUpper = embedLocation.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let positionStringTrimmed = positionString.trimmingCharacters(in: .whitespacesAndNewlines)
                return embedLocationUpper == positionStringTrimmed
            }
            return false
        }

        return filteredWidgets.sorted { folderInfo1, folderInfo2 in
            let timestamp1 = folderInfo1.timestamp ?? 0
            let timestamp2 = folderInfo2.timestamp ?? 0
            return timestamp1 > timestamp2
        }
    }

    public func clearCache(for pageUrl: String? = nil) {
        if let pageUrl = pageUrl {
            cache.removeValue(forKey: pageUrl)
            if currentContext?.pageUrl == pageUrl {
                currentContext = nil
                initTask = nil
                initState = .idle
                initError = nil
            }
        } else {
            cache.removeAll()
            currentContext = nil
            initTask = nil
            initState = .idle
            initError = nil
        }
    }
}

// MARK: - EmbedWidgetView (SwiftUI - Auto-loading by position)
/**
 * @struct EmbedWidgetView
 * @description A SwiftUI view that automatically loads and displays embed widgets by position.
 *              Data source comes from shared initialization cache.
 */
@available(iOS 16.0, *)
public struct EmbedWidgetView: View {
    private let position: EmbedPosition
    private let onError: ((EmbedWidgetLoadError) -> Void)?
    private let onClick: ((EmbedWidgetClickEvent) -> Void)?
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var folderInfos: [EmbedFolderInfo] = []
    @State private var currentPageUrl: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var hasStartedLoading: Bool = false
    @State private var initRetryCount: Int = 0
    private let maxInitRetryCount: Int = 20
    
    /**
     * @function init
     * @description Initializes EmbedWidgetView with position only.
     *              Data must already be initialized via EmbedIOSSDK.initialize(pageUrl:mid:secret:).
     *
     * @param {EmbedPosition} position - The position where the widget should be displayed.
     * @param {(EmbedWidgetLoadError) -> Void?} onError - Optional callback when SDK load fails and widget cannot render.
     *
     * @returns {EmbedWidgetView} A new EmbedWidgetView instance.
     */
    public init(
        position: EmbedPosition,
        onError: ((EmbedWidgetLoadError) -> Void)? = nil,
        onClick: ((EmbedWidgetClickEvent) -> Void)? = nil
    ) {
        self.position = position
        self.onError = onError
        self.onClick = onClick
    }
    
    public var body: some View {
        if !hasStartedLoading {
            DispatchQueue.main.async {
                if !self.hasStartedLoading {
                    self.hasStartedLoading = true
                    EmbedLogger.log("[EmbedWidgetView] body - first render load for position: \(self.position.rawValue)")
                    Task {
                        await self.loadWidgets()
                    }
                }
            }
        }

        return Group {
            if isLoading {
                EmptyView()
            } else if errorMessage != nil {
                EmptyView()
            } else if folderInfos.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(folderInfos, id: \.folderId) { folderInfo in
                        EmbedView(folderInfo: folderInfo, pageUrl: currentPageUrl, onClick: onClick)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .inactive || newPhase == .background {
                EmbedIOSSDK.notifyPageDidLeave()
            }
        }
    }
    
    /**
     * @function loadWidgets
     * @description Loads widgets from the shared data manager based on the specified position.
     *              Uses cached data if available to avoid multiple API calls.
     */
    private func loadWidgets() async {
        EmbedLogger.log("[EmbedWidgetView] loadWidgets called - position: \(position.rawValue)")
        
        // 使用 MainActor 確保狀態檢查和設置是原子操作
        let shouldLoad = await MainActor.run {
            if self.isLoading {
                EmbedLogger.log("[EmbedWidgetView] Already loading, skipping...")
                return false
            }
            if self.hasStartedLoading && !self.folderInfos.isEmpty {
                EmbedLogger.log("[EmbedWidgetView] Already loaded with \(self.folderInfos.count) widgets, skipping...")
                return false
            }
            EmbedLogger.log("[EmbedWidgetView] Setting loading state to true")
            self.isLoading = true
            self.errorMessage = nil
            return true
        }
        
        guard shouldLoad else {
            EmbedLogger.log("[EmbedWidgetView] Should not load, returning early")
            return
        }

        let result = await EmbedWidgetDataManager.shared.getWidgetsForPositionResult(position: position)
        let widgets = result.widgets
        EmbedLogger.log("[EmbedWidgetView] Received \(widgets.count) widgets from data manager")

        if let loadError = result.error {
            let isInitStateError =
                loadError.statusCode == EmbedWidgetLoadError.StatusCode.initializing.rawValue ||
                loadError.statusCode == EmbedWidgetLoadError.StatusCode.notInitialized.rawValue

            if isInitStateError && initRetryCount < maxInitRetryCount {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = nil
                    self.currentPageUrl = result.pageUrl
                    self.initRetryCount += 1
                }

                // Wait for initialization to complete, then retry.
                try? await Task.sleep(nanoseconds: 300_000_000)
                await loadWidgets()
                return
            }

            await MainActor.run {
                EmbedLogger.log("[EmbedWidgetView] ERROR: statusCode=\(loadError.statusCode), message: \(loadError.message)")
                self.errorMessage = loadError.message
                self.folderInfos = []
                self.currentPageUrl = result.pageUrl
                self.isLoading = false
                self.onError?(loadError)
            }
            return
        }
        
        EmbedLogger.log("[EmbedWidgetView] Widgets for position \(position.rawValue): \(widgets.count)")
        
        await MainActor.run {
            self.folderInfos = widgets
            self.currentPageUrl = result.pageUrl
            self.isLoading = false
            self.initRetryCount = 0
        }
    }
}

// MARK: - EmbedView (SwiftUI)
@available(iOS 16.0, *)
public struct EmbedView: View {
    private let folderInfo: EmbedFolderInfo
	private let pageUrl: String
    private let onClick: ((EmbedWidgetClickEvent) -> Void)?

    @State private var contentHeight: CGFloat = 0
    @State private var isLightboxPresented = false
    @State private var pendingLightboxMessageJSON: String?
    // 當 widget property position == fixed 時切換為 true，整個 WebView 會變成 fullscreen fixed
    @State private var isFullscreenFixed = false
    @State private var lightboxLoadFailed = false
    @State private var hasTrackedVisibility = false
    @State private var visibilityProbeTick = 0

    private var lightboxURL: URL {
        EmbedHTMLBuilder.lightBoxURL(pageUrl: pageUrl)
    }

    /**
     * @function init
     * @description Initializes EmbedView with folder information and page URL.
     *
     * @param {EmbedFolderInfo} folderInfo - The folder information for the embed widget.
     * @param {String} pageUrl - The page URL where the widget is displayed.
     *
     * @returns {EmbedView} A new EmbedView instance.
     */
    public init(folderInfo: EmbedFolderInfo, pageUrl: String, onClick: ((EmbedWidgetClickEvent) -> Void)? = nil) {
        self.folderInfo = folderInfo
        self.pageUrl = pageUrl
        self.onClick = onClick
    }

    public var body: some View {
        Group {
            ZStack {
                EmbedWebView(
                    folderId: folderInfo.folderId,
                    pageUrl: pageUrl,
                    layout: folderInfo.layout,
                    contentHeight: $contentHeight,
                    onEvent: handleEmbedEvent
                )
                .frame(maxWidth: .infinity)
                .frame(height: {
                    let isFloatingMedia = folderInfo.layout?.lowercased() == "floatingmedia"
                    if isFloatingMedia {
                        // FloatingMedia 強制使用 224px 高度
                        return 224
                    } else if isFullscreenFixed {
                        return UIScreen.main.bounds.height
                    } else {
                        return max(contentHeight, 60)
                    }
                }())
                .background(Color.clear)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                trackEmbedVisibilityIfNeeded(proxy: proxy)
                            }
                            .onChange(of: proxy.frame(in: .global)) { _ in
                                trackEmbedVisibilityIfNeeded(proxy: proxy)
                            }
                            .onChange(of: visibilityProbeTick) { _ in
                                trackEmbedVisibilityIfNeeded(proxy: proxy)
                            }
                    }
                )
                .ignoresSafeArea(edges: isFullscreenFixed ? .all : .init())
                .interactiveDismissDisabledCompat(isFullscreenFixed)
                .zIndex(isFullscreenFixed ? 1 : 0)
            }
        }
        // Lightbox（fullscreen）
        .fullScreenCover(isPresented: $isLightboxPresented) {
            ZStack(alignment: .topTrailing) {
                // Lightbox 內容
                LightboxWebView(
                    url: lightboxURL,
                    messageJSON: $pendingLightboxMessageJSON,
                    onEvent: handleEmbedEvent,
                    loadFailed: $lightboxLoadFailed
                )
                .background(Color.black.opacity(0.95))
                .ignoresSafeArea()
                
                // 只在載入失敗時顯示關閉按鈕
                if lightboxLoadFailed {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: {
                                handleLightboxToggle(false)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.white)
                                    .background(
                                        Circle()
                                            .fill(Color.black.opacity(0.5))
                                            .frame(width: 36, height: 36)
                                    )
                            }
                            .padding(.top, 8)
                            .padding(.trailing, 16)
                        }
                        Spacer()
                    }
                }
            }
            .interactiveDismissDisabled(false) // 允許下拉關閉
            .onAppear {
                // 重置載入失敗狀態
                lightboxLoadFailed = false
            }
        }
        .onAppear {
            // Returning to the same page should allow visibility tracking to run again.
            hasTrackedVisibility = false
            visibilityProbeTick = 0
            Task { @MainActor in
                // Retry visibility checks for a short period to handle fast return-and-scroll races.
                for _ in 0..<20 {
                    if hasTrackedVisibility { break }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    visibilityProbeTick += 1
                }
            }
        }
    }


    // MARK: - Event handler
    private func handleEmbedEvent(_ event: EmbedWebView.EmbedEvent) {
        switch event.type {
        case "resize":
            handleResizeEventPayload(event.payload)
			break
        case "click":
            guard let item = event.payload["data"] as? [String: Any] else {
                return
            }

            func extractString(_ value: Any?) -> String? {
                if let string = value as? String, !string.isEmpty {
                    return string
                }
                if let number = value as? NSNumber {
                    return number.stringValue
                }
                return nil
            }

            let resolvedMediaId =
                extractString(item["mediaId"]) ??
                extractString(item["mediaID"]) ??
                extractString(item["media_id"])

            let clickEvent = EmbedWidgetClickEvent(
                folderId: (item["folderId"] as? String) ?? folderInfo.folderId,
                folderName: (item["folderName"] as? String) ?? folderInfo.folderName,
                position: folderInfo.embedLocation ?? folderInfo.resolvedFloatingMediaPosition ?? folderInfo.layout,
                mediaId: resolvedMediaId,
                url: pageUrl
            )
            print(
                "[EmbedWidgetClick] {folderId: \(clickEvent.folderId), folderName: \(clickEvent.folderName ?? "nil"), position: \(clickEvent.position ?? "nil"), mediaId: \(clickEvent.mediaId ?? "nil"), url: \(clickEvent.url ?? "nil")}"
            )
            onClick?(clickEvent)

            let disabled = (item["disabledLightBox"] as? Bool) ?? false
            if disabled {
                return
            }
            let messagePayload: [String: Any] = [
                "eventType": "click",
                "item": item
            ]
            guard JSONSerialization.isValidJSONObject(messagePayload),
                  let jsonData = try? JSONSerialization.data(withJSONObject: messagePayload),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return
            }
            pendingLightboxMessageJSON = jsonString
            handleLightboxToggle(true)
        case "toggleLB":
            let openValue = event.payload["open"]
            let shouldOpen: Bool? = {
                switch openValue {
                case let bool as Bool:
                    return bool
                case let number as NSNumber:
                    return number.boolValue
                case let string as String:
                    let lowered = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if ["true", "1", "yes"].contains(lowered) { return true }
                    if ["false", "0", "no"].contains(lowered) { return false }
                    return nil
                default:
                    return nil
                }
            }()

            guard let open = shouldOpen else {
                return
            }
            handleLightboxToggle(open)
            if !open {
                pendingLightboxMessageJSON = nil
            }
        default:
            break
        }
    }

    // MARK: - lightbox
    private func handleLightboxToggle(_ shouldOpen: Bool) {
        // 確保在主線程上執行
        DispatchQueue.main.async {
            self.isLightboxPresented = shouldOpen
            if !shouldOpen {
                self.pendingLightboxMessageJSON = nil
                self.lightboxLoadFailed = false // 重置載入失敗狀態
            }
        }
    }

    // MARK: - resize handling (保留原始邏輯，並加入 fixed detection)
    private func handleResizeEventPayload(_ payload: [String: Any]) {
        // 對於 FloatingMedia，忽略 resize 事件，強制使用 224px 高度
        let isFloatingMedia = folderInfo.layout?.lowercased() == "floatingmedia"
        if isFloatingMedia {
            contentHeight = 224
            return
        }
        
        let property = payload["property"] as? [String: Any]
        let rawHeightFromProperty = extractRawHeightString(from: property)
        let shouldDefer = shouldDeferHeightSync(rawHeightFromProperty, property: property)
        let resolvedHeight = extractNumericHeight(from: payload, property: property)

        // 如果 widget 指定 position: fixed，切換為 fullscreen fixed（避免被外層壓扁）
        if let position = property?["position"] as? String, position.lowercased() == "fixed" {
            // 切到 fullscreen
            isFullscreenFixed = true
        } else {
            // 如果沒有 fixed，並且目前是 fullscreen（先前某個元素是 fixed），我們可以選擇自動關閉 fullscreen
            // 視需求決定是否要自動還原；這裡採用：若 property 沒有 position=fixed，維持原狀（不自動還原）
            // 若你想自動還原，將下面註解打開：
            // isFullscreenFixed = false
        }

        if shouldDefer {
            let fallbackHeight = resolvedHeight ?? UIScreen.main.bounds.height
            if fallbackHeight > 0 {
                contentHeight = max(contentHeight, fallbackHeight)
            }
            return
        }

        if let height = resolvedHeight {
            contentHeight = height
        }
    }

    // MARK: - helpers (same as original)
    private func extractNumericHeight(from payload: [String: Any], property: [String: Any]?) -> CGFloat? {
        var candidates: [Any?] = []
        candidates.append(payload["height"])
        if let size = payload["size"] as? [String: Any] {
            candidates.append(size["height"])
        }
        if let data = payload["data"] as? [String: Any] {
            candidates.append(data["height"])
        }
        if let property {
            let propertyKeys = ["height", "minHeight", "maxHeight", "--height", "--tagnology-height"]
            for key in propertyKeys {
                candidates.append(property[key])
            }
        }

        for candidate in candidates {
            if let height = normalizeHeightValue(candidate) {
                return height
            }
        }
        return nil
    }

    private func extractRawHeightString(from property: [String: Any]?) -> String? {
        guard let property else { return nil }
        let keys = ["height", "minHeight", "maxHeight", "--height", "--tagnology-height"]
        for key in keys {
            if let stringValue = property[key] as? String {
                return stringValue
            }
        }
        return nil
    }

    private func shouldDeferHeightSync(_ rawHeight: String?, property: [String: Any]?) -> Bool {
        if let position = property?["position"] as? String, position.lowercased() == "fixed" {
            return true
        }
        guard let rawHeight else {
            return false
        }
        let unitCharacterSet = CharacterSet.letters.union(CharacterSet(charactersIn: "%"))
        return rawHeight.rangeOfCharacter(from: unitCharacterSet) != nil
    }

    private func normalizeHeightValue(_ value: Any?) -> CGFloat? {
        switch value {
        case let number as NSNumber:
            return CGFloat(truncating: number)
        case let string as String:
            let allowedCharacters = CharacterSet(charactersIn: "0123456789.-")
            let sanitized = string.unicodeScalars.filter { allowedCharacters.contains($0) }
            guard let numericValue = Double(String(String.UnicodeScalarView(sanitized))) else {
                return nil
            }
            return CGFloat(numericValue)
        default:
            return nil
        }
    }

    private func trackEmbedVisibilityIfNeeded(proxy: GeometryProxy) {
        if hasTrackedVisibility {
            return
        }

        let frame = proxy.frame(in: .global)
        if frame.width <= 0 || frame.height <= 0 {
            return
        }

        let screenBounds = UIScreen.main.bounds
        let intersection = frame.intersection(screenBounds)
        if intersection.isNull || intersection.width <= 0 || intersection.height <= 0 {
            return
        }

        let totalArea = frame.width * frame.height
        guard totalArea > 0 else { return }

        let visibleArea = intersection.width * intersection.height
        let visibleRatio = visibleArea / totalArea

        if visibleRatio >= 0.3 {
            let didTrack = EmbedAnalyticsManager.shared.markWidgetVisible(
                folderId: folderInfo.folderId,
                baseURL: EmbedAPI.defaultBaseURL
            )
            if didTrack {
                hasTrackedVisibility = true
            }
        }
    }
}

// MARK: - EmbedWebView (UIViewRepresentable)
struct EmbedWebView: UIViewRepresentable {
    let folderId: String
    let pageUrl: String
    let layout: String?
    @Binding var contentHeight: CGFloat
    let onEvent: (EmbedEvent) -> Void

    struct EmbedEvent {
        let type: String
        let payload: [String: Any]
        let jsonString: String
    }

    static func makeEvent(from body: Any) -> EmbedEvent? {
        guard let payload = body as? [String: Any],
              let eventType = payload[EmbedBridge.eventTypeKey] as? String,
              JSONSerialization.isValidJSONObject(payload),
              let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        return EmbedEvent(type: eventType, payload: payload, jsonString: jsonString)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, onEvent: onEvent)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        // iOS 16+ 使用新的 API 替代已棄用的 javaScriptEnabled (iOS 14.0+)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        // iOS 16+ 直接支援 mediaTypesRequiringUserActionForPlayback (iOS 10.0+)
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: EmbedBridge.resizeHandlerName)
        configuration.userContentController.add(context.coordinator, name: EmbedBridge.eventHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        // 若不允許 scroll，fixed 內部元素仍會相對於 viewport 定位（我們已 inject CSS workaround）
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        
        // 確保 WebView 可以接收用戶交互
        webView.isUserInteractionEnabled = true
        webView.allowsBackForwardNavigationGestures = false
        
        context.coordinator.webView = webView

        loadWidget(into: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // no-op for now
    }

    private func loadWidget(into webView: WKWebView) {
        let htmlString = EmbedHTMLBuilder.buildHTML(folderId: folderId, pageUrl: pageUrl, layout: layout)
        webView.loadHTMLString(htmlString, baseURL: EmbedHTMLBuilder.assetBaseURL)
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private var parent: EmbedWebView
        private let onEvent: (EmbedEvent) -> Void
        weak var webView: WKWebView?

        init(parent: EmbedWebView, onEvent: @escaping (EmbedEvent) -> Void) {
            self.parent = parent
            self.onEvent = onEvent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case EmbedBridge.resizeHandlerName:
                guard var payload = message.body as? [String: Any] else { 
                    return 
                }
                let reportedHeight: CGFloat? = {
                    if let numericValue = payload["height"] as? NSNumber {
                        return CGFloat(truncating: numericValue)
                    }
                    return nil
                }()
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if let height = reportedHeight {
                        self.parent.contentHeight = height
                    }
                    payload[EmbedBridge.eventTypeKey] = payload[EmbedBridge.eventTypeKey] ?? "resize"
                    if let embedEvent = EmbedWebView.makeEvent(from: payload) {
                        self.onEvent(embedEvent)
                    }
                }
            case EmbedBridge.eventHandlerName:
                handleEventMessage(message.body)
            default: break
            }
        }

        private func handleEventMessage(_ body: Any) {
            guard let embedEvent = EmbedWebView.makeEvent(from: body) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onEvent(embedEvent)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 初次載入時回報高度
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                guard let self = self else { return }
                if let number = result as? NSNumber {
                    let height = CGFloat(truncating: number)
                    DispatchQueue.main.async {
                        self.parent.contentHeight = max(height, self.parent.contentHeight)
                    }
                }
            }
        }
    }
}

// MARK: - LightboxWebView (UIViewRepresentable)
struct LightboxWebView: UIViewRepresentable {
    let url: URL
    @Binding var messageJSON: String?
    let onEvent: (EmbedWebView.EmbedEvent) -> Void
    @Binding var loadFailed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent, loadFailed: $loadFailed) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // iOS 16+ 使用新的 API 替代已棄用的 javaScriptEnabled (iOS 14.0+)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        // iOS 16+ 直接支援 mediaTypesRequiringUserActionForPlayback (iOS 10.0+)
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: EmbedBridge.eventHandlerName)

        // 注入 bridge helper 至 Lightbox（同時支援 postMessage）
        let scriptSource = """
        (function() {
            if (window.\(EmbedBridge.bridgeInjectionFlag)) { return; }
            window.\(EmbedBridge.bridgeInjectionFlag) = true;

            const handlerName = '\(EmbedBridge.eventHandlerName)';
            const notifyNative = function(payload) {
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[handlerName]) {
                        window.webkit.messageHandlers[handlerName].postMessage(payload);
                    }
                } catch (error) {
                    console.log('[LightboxBridge] notify native error', error);
                }
            };

            const originalPostMessage = window.postMessage;
            window.postMessage = function(message, targetOrigin, transfer) {
                notifyNative(message);
                if (typeof originalPostMessage === 'function') {
                    return originalPostMessage.call(this, message, targetOrigin, transfer);
                }
            };

            window.addEventListener('message', function(event) {
                if (event && event.data) {
                    notifyNative(event.data);
                }
            });
        })();
        """
        let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear

        context.coordinator.webView = webView
        context.coordinator.pendingMessageJSON = messageJSON

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.pendingMessageJSON = messageJSON
        context.coordinator.flushPendingMessage()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var pendingMessageJSON: String?
        private var isContentLoaded = false
        private let onEvent: (EmbedWebView.EmbedEvent) -> Void
        @Binding var loadFailed: Bool

        init(onEvent: @escaping (EmbedWebView.EmbedEvent) -> Void, loadFailed: Binding<Bool>) {
            self.onEvent = onEvent
            self._loadFailed = loadFailed
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isContentLoaded = true
            flushPendingMessage()
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            EmbedLogger.log("[LightboxWebView] Navigation failed: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.loadFailed = true
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            EmbedLogger.log("[LightboxWebView] Provisional navigation failed: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.loadFailed = true
            }
        }

        func flushPendingMessage() {
            guard isContentLoaded,
                  let jsonString = pendingMessageJSON,
                  let webView else { return }

            // Dispatch MessageEvent into the lightbox page
            let script = """
            window.dispatchEvent(new MessageEvent('message', { data: \(jsonString), origin: '\(EmbedHTMLBuilder.origin)' }));
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
            pendingMessageJSON = nil
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == EmbedBridge.eventHandlerName,
                  let embedEvent = EmbedWebView.makeEvent(from: message.body) else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.onEvent(embedEvent)
            }
        }
    }
}

// MARK: - EmbedHTMLBuilder (HTML + Safari 14 workaround)
enum EmbedHTMLBuilder {
    static let assetBaseURL = URL(string: "https://embed.tagnology.co")!
    
    /**
     * @function lightBoxURL
     * @description Generates the lightbox URL with the specified page URL.
     *
     * @param {String} pageUrl - The page URL to include in the lightbox query parameter.
     *
     * @returns {URL} The lightbox URL with the page parameter.
     */
    static func lightBoxURL(pageUrl: String) -> URL {
        return URL(string: "https://embed.tagnology.co/lightBox?page=\(pageUrl)")!
    }
    
    static let origin = "https://embed.tagnology.co"

    /**
     * @function buildHTML
     * @description Builds the HTML string for embedding the widget.
     *
     * @param {String} folderId - The folder ID for the embed widget.
     * @param {String} pageUrl - The page URL where the widget is displayed.
     * @param {String?} layout - Optional layout type (e.g., "FloatingMedia").
     *
     * @returns {String} The HTML string containing the embed iframe.
     */
    static func buildHTML(folderId: String, pageUrl: String, layout: String? = nil) -> String {
        // 構建 iframe src URL
        var iframeSrc = "https://embed.tagnology.co/display?folderId=\(folderId)&page=\(pageUrl)"
        
        // 如果 layout 為 FloatingMedia，添加 fullScreen=true 參數
        let isFloatingMedia = layout?.lowercased() == "floatingmedia"
        if isFloatingMedia {
            iframeSrc += "&fullScreen=true"
        }

        // 根據 layout 決定 iframe 的 CSS 樣式
        // FloatingMedia 需要適應容器大小，其他 layout 使用全螢幕 fixed（Safari 14 workaround）
        let iframeCSS: String
        let containerCSS: String
        if isFloatingMedia {
            // FloatingMedia：使用容器 div 限制大小，iframe 適應容器（參考 test.html 結構）
            containerCSS = """
                #embed-container {
                    width: 100%;
                    height: 100%;
                    max-width: 126px !important;
                    max-height: 224px !important;
                    position: relative;
                    overflow: hidden !important;
                    background: transparent;
                    top: 0 !important;
                    left: 0 !important;
                    margin: 0 !important;
                    padding: 0 !important;
                    visibility: visible !important;
                    opacity: 1 !important;
                    z-index: 1 !important;
                    display: block !important;
                }
            """
            iframeCSS = """
                iframe {
                    border: none !important;
                    width: 126px !important;
                    height: 224px !important;
                    max-width: 126px !important;
                    max-height: 224px !important;
                    position: relative !important;
                    display: block !important;
                    overflow: hidden !important;
                    background: transparent;
                    box-sizing: border-box !important;
                    visibility: visible !important;
                    opacity: 1 !important;
                    z-index: 1 !important;
                }
            """
        } else {
            // 其他 layout：使用全螢幕 fixed（Safari 14 workaround）
            containerCSS = ""
            iframeCSS = """
                iframe {
                    border: 0;
                    width: 100vw !important;
                    height: 100vh !important;
                    position: fixed !important;
                    top: 0;
                    left: 0;
                    overflow: hidden;
                    -webkit-overflow-scrolling: touch;
                    background: transparent;
                }
            """
        }

        // 這裡注入 CSS 的重點是：解 Safari 14 iframe + position:fixed 的 bug
        // 並仍保留 JS 來解析 widget 傳來的 property，並把 property 套到 iframe.style
        return """
        <!DOCTYPE html>
        <html lang="zh-Hant">
        <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
            <style>
                /* 基本 reset */
                html, body {
                    margin: 0;
                    padding: 0;
                    background: transparent;
                    height: 100%;
                    width: 100%;
                    overflow: hidden;
                }
                
                /* FloatingMedia 專用：限制 body/html 高度並確保正確定位 */
                \(isFloatingMedia ? """
                html, body {
                    max-height: 224px !important;
                    display: flex !important;
                    align-items: flex-start !important;
                    justify-content: flex-start !important;
                }
                """ : "")

                /* 容器樣式（僅 FloatingMedia 使用） */
                \(containerCSS)
                /* Iframe 樣式（根據 layout 類型動態設定） */
                \(iframeCSS)
            </style>
        </head>
        <body>
            \(isFloatingMedia ? """
            <div id="embed-container">
                <iframe id="embed-frame" src="\(iframeSrc)" scrolling="no" frameborder="0" allow="fullscreen; autoplay; picture-in-picture" playsinline></iframe>
            </div>
            """ : """
            <iframe id="embed-frame" src="\(iframeSrc)" scrolling="no" frameborder="0" allow="fullscreen; autoplay; picture-in-picture" playsinline></iframe>
            """)
            <script>
            const frame = document.getElementById('embed-frame');

            function notifyNativeResize(height) {
                if (!height || Number.isNaN(Number(height))) {
                    return;
                }
                if (window.webkit?.messageHandlers?.tagnologyResize) {
                    window.webkit.messageHandlers.tagnologyResize.postMessage({ height: Number(height) });
                }
            }

            function applyFrameHeight(rawHeight) {
                if (!frame) { return null; }
                const parsedHeight = normalizeHeightValue(rawHeight);
                if (!parsedHeight) { return null; }
                frame.style.height = parsedHeight + 'px';
                return parsedHeight;
            }

            function normalizeHeightValue(value) {
                if (typeof value === 'number' && Number.isFinite(value)) {
                    return value;
                }
                if (typeof value === 'string') {
                    const sanitized = value.replace(/[^0-9.\\-]/g, '');
                    const numericValue = parseFloat(sanitized);
                    return Number.isNaN(numericValue) ? null : numericValue;
                }
                return null;
            }

            function extractHeightFromPayload(data) {
                if (!data) return null;
                const directCandidates = [
                    data.height,
                    data.size?.height,
                    data.data?.height
                ];
                const property = data.property || {};
                const propertyCandidates = [
                    property.height,
                    property.minHeight,
                    property.maxHeight,
                    property['--height'],
                    property['--tagnology-height']
                ];
                const candidate = [...directCandidates, ...propertyCandidates].find((item) => item !== undefined && item !== null);
                return normalizeHeightValue(candidate);
            }

            function getRawHeightFromProperty(property) {
                if (!property || typeof property !== 'object') return null;
                const propertyCandidates = [
                    property.height,
                    property.minHeight,
                    property.maxHeight,
                    property['--height'],
                    property['--tagnology-height']
                ];
                const candidate = propertyCandidates.find((v) => v !== undefined && v !== null);
                return typeof candidate === 'string' ? candidate : null;
            }

            function shouldDeferHeightSync(rawHeight, property) {
                if (property && String(property.position).toLowerCase() === 'fixed') return true;
                if (!rawHeight) return false;
                return /[a-z%]/i.test(rawHeight);
            }

            function notifyNativeEvent(payload) {
                if (!payload) return;
                if (window.webkit?.messageHandlers?.tagnologyEvent) {
                    window.webkit.messageHandlers.tagnologyEvent.postMessage(payload);
                }
            }

            function handleResizeEvent(data) {
                const property = (data && typeof data === 'object') ? data.property : null;
                const container = document.getElementById('embed-container');
                const isFloatingMedia = container !== null; // 如果有容器，就是 FloatingMedia
                
                if (property && frame) {
                    Object.keys(property).forEach((key) => {
                        if (!Object.prototype.hasOwnProperty.call(property, key)) return;
                        const value = property[key];
                        if (value === undefined || value === null) return;
                        
                        // 對於 FloatingMedia，忽略 position 屬性（保持 relative）
                        if (isFloatingMedia && key.toLowerCase() === 'position') {
                            return;
                        }
                        
                        // 套用到 iframe 上（frame.style）
                        frame.style.setProperty(String(key), String(value), 'important');
                    });
                    
                    // 對於 FloatingMedia，強制確保 position 是 relative
                    if (isFloatingMedia) {
                        frame.style.setProperty('position', 'relative', 'important');
                    }
                }

                const rawPropertyHeight = getRawHeightFromProperty(property);
                const shouldSkipAutoHeight = shouldDeferHeightSync(rawPropertyHeight, property);
                const reportedHeight = frame?.getBoundingClientRect().height ?? 0;
                if (shouldSkipAutoHeight) {
                    if (reportedHeight) {
                        notifyNativeResize(reportedHeight);
                    }
                    // 同時通知完整 payload 給 native（包含 property）
                    const payloadForNative = (data && typeof data === 'object') ? { ...data } : {};
                    payloadForNative.eventType = payloadForNative.eventType || 'resize';
                    payloadForNative.property = property;
                    payloadForNative.height = payloadForNative.height ?? reportedHeight;
                    notifyNativeEvent(payloadForNative);
                    return;
                }

                const height = extractHeightFromPayload(data) ?? reportedHeight;
                if (height) {
                    const appliedHeight = applyFrameHeight(height);
                    notifyNativeResize(appliedHeight ?? height);
                }

                const payloadForNative = (data && typeof data === 'object') ? { ...data } : {};
                payloadForNative.eventType = payloadForNative.eventType || 'resize';
                payloadForNative.property = property;
                payloadForNative.height = payloadForNative.height ?? height ?? reportedHeight ?? null;
                notifyNativeEvent(payloadForNative);
            }

            // 接收來自 widget 的 message
            window.addEventListener('message', (event) => {
                const origin = event?.origin || '';
                if (origin && !origin.includes('tagnology.co')) {
                    return;
                }
                const data = event?.data || {};
                if (!data) return;
                if (data.eventType === 'resize') {
                    handleResizeEvent(data);
                    return;
                }
                notifyNativeEvent(data);
            });

            // load event: report initial height
            window.addEventListener('load', () => {
                const initialHeight = frame?.getBoundingClientRect().height || 400;
                applyFrameHeight(initialHeight);
                notifyNativeResize(initialHeight);
            });
            </script>
        </body>
        </html>
        """
    }
}
