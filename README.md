# EmbedIOSSDK

Developed by Tagnology, an SDK that can be embedded into iOS apps.

## Features

- ✅ SwiftUI integration
- ✅ Floating media support with click-through overlay
- ✅ Lightbox functionality
- ✅ Smart hit-testing for interactive elements
- ✅ Support for fixed position widgets
- ✅ Fullscreen mode support
- ✅ Automatic resize handling

## Requirements

- iOS 16.0+
- Swift 5.0+
- Xcode 14.0+

## Installation

### CocoaPods

Add the following to your `Podfile`:

```ruby
pod 'EmbedIOSSDK', '~> 1.0.0'
```

Then run:

```bash
pod install
```

### Manual Installation

1. Copy the `embed.swift` file to your project
2. Ensure your project targets iOS 16.0 or higher

## Usage

### Basic Usage

進入頁面後，先呼叫 `EmbedIOSSDK.initialize(pageUrl:mid:secret:)`。  
初始化成功後，再用 `EmbedWidgetView(position:)` 顯示各版位。

```swift
import SwiftUI
import EmbedIOSSDK

struct ContentView: View {
    @State private var pageUrl: String = "https://partnertest4.91app.com/SalePage/Index/9323753"
    @State private var mid: String = "41458"
    @State private var secret: String = "YOUR_PAYLOAD_SECRET_BASE64"
    @State private var isEmbedInitialized = false
    @State private var showBelowBuyButtonWidget = true

    var body: some View {
        ScrollView {
            VStack {
                if !isEmbedInitialized {
                    ProgressView()
                }

                // Display widget below buy button
                if isEmbedInitialized && showBelowBuyButtonWidget {
                    EmbedWidgetView(
                        position: EmbedIOSSDK.BELOW_BUY_BUTTON,
                        onError: { _ in
                            // SDK error: notify App to hide this slot
                            showBelowBuyButtonWidget = false
                        },
                        onClick: { click in
                            // click.folderId
                            // click.folderName
                            // click.position
                            // click.mediaId (optional)
                            // click.url (equals initialize(pageUrl: ...) value)
                        }
                    )
                }

                // Display widget below main product info
                if isEmbedInitialized {
                    EmbedWidgetView(position: EmbedIOSSDK.BELOW_MAIN_PRODUCT_INFO)
                }
            }
        }
        .task {
            let initError = await EmbedIOSSDK.initialize(
                pageUrl: pageUrl,
                mid: mid,
                secret: secret,
                forceRefresh: true // optional, avoid stale in-memory cache during debug
            )
            isEmbedInitialized = (initError == nil)
        }
    }
}
```

### Initialization Request Details

SDK 會呼叫：

- `[POST] {BASE_URL}/widget/pageBundle`

Request body 為 AES-256-GCM 加密後 payload：

```js
const requestBody = encryptPayload({
  mid: MID,
  id: PAGE_ID,
  url: PAGE_URL,
  payloadSecret: PAYLOAD_SECRET
});
```

`PAGE_ID` 由 `PAGE_URL` 解析：

- `https://partnertest4.91app.com/SalePage/Index/9323753` -> `9323753`
- `https://partnertest4.91app.com/v2/official/SalePageCategory/481477?sortMode=Newest` -> `category_481477`

### Position Enum

The `position` parameter accepts the following values from `EmbedIOSSDK.Position`:

**Standard Positions:**

- `EmbedIOSSDK.BELOW_BUY_BUTTON` - Display below the buy button
- `EmbedIOSSDK.BELOW_MAIN_PRODUCT_INFO` - Display below main product information
- `EmbedIOSSDK.ABOVE_RECOMMENDATION` - Display above recommendation section
- `EmbedIOSSDK.ABOVE_FILTER` - Display above filter section

**Fixed FloatingMedia Positions:**

- `EmbedIOSSDK.FIXED_BOTTOM_LEFT` - Fixed at bottom left corner
- `EmbedIOSSDK.FIXED_BOTTOM_RIGHT` - Fixed at bottom right corner
- `EmbedIOSSDK.FIXED_TOP_LEFT` - Fixed at top left corner
- `EmbedIOSSDK.FIXED_TOP_RIGHT` - Fixed at top right corner
- `EmbedIOSSDK.FIXED_CENTER_LEFT` - Fixed at center left
- `EmbedIOSSDK.FIXED_CENTER_RIGHT` - Fixed at center right

**Note:** Fixed positions are only for FloatingMedia widgets. The SDK automatically filters widgets based on the `floatingMediaPosition` field when using fixed positions.

### Fixed Position Widgets Example

For fixed position widgets (FloatingMedia), you can overlay them on your content:

```swift
struct ProductPageView: View {
    @State private var isEmbedInitialized: Bool = true
    @State private var showFixedWidget: Bool = true

    var body: some View {
        ZStack {
            // Your main content
            ScrollView {
                // ... your content
            }

            // Fixed position widget overlay
            if isEmbedInitialized && showFixedWidget {
                VStack {
                    Spacer()
                    HStack {
                        EmbedWidgetView(position: EmbedIOSSDK.FIXED_BOTTOM_LEFT)
                        Spacer()
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }
}
```

### Parameters

- **`initialize(pageUrl:mid:secret:baseURL:forceRefresh:)`** (required before widget render)
  - `pageUrl` (String, required): 當前頁面 URL
  - `mid` (String, required): 商店 MID
  - `secret` (String, required): `payloadSecret`（Base64 且 decode 後必須是 32 bytes）。**各商店（mid）獨立一組**，由 Tagnology 於開通時逐店簽發，僅對該 mid 有效；單一金鑰外洩影響範圍僅限該商店，可單獨重新簽發
  - `baseURL` (String, optional): API 網域，預設 `https://embed.tagnology.co/api`
  - `forceRefresh` (Bool, optional): 是否忽略 in-memory cache 重新打 API（預設 `false`）
- **`position`** (EmbedIOSSDK.Position, required): The position where the widget should be displayed. See Position Enum above for available values.
- **`onError`** ((EmbedWidgetLoadError) -> Void, optional): Called for non-`200` status codes. Use this callback to hide the slot in your App.

### Error Callback (Hide Slot)

When callback status code is non-`200` (no data or error), `onError` will be triggered.  
`EmbedWidgetLoadError` includes:

- `statusCode`: callback status code
    - `200` 正常（不會 callback）
    - `204` 無資料（API 回傳 `pageBundle = []` 或該版位過濾後無資料）
    - `422` 初始化參數錯誤（例如 pageUrl 無法取出 ID、secret 格式錯誤）
    - `425` 初始化進行中
    - `428` 尚未初始化（尚未呼叫 `initialize`）
    - `500` 系統錯誤
    - `408` timeout
    - `520` 其他錯誤
- `message`: error message
- `pageUrl`: current page URL
- `position`: current widget position

**Behavior:** `204/422/500/408/520` 建議隱藏版位；`425/428` 建議等待或先完成初始化後再渲染。

### Advanced Usage

The SDK uses a shared data manager to cache initialization data and avoid multiple API calls for the same page URL.  
After a successful `initialize`, all `EmbedWidgetView(position:)` share the same in-memory page bundle.

To clear the cache manually:

```swift
EmbedWidgetDataManager.shared.clearCache(for: pageUrl) // Clear specific page
EmbedWidgetDataManager.shared.clearCache() // Clear all cache
```

## WebView 設定

SDK 的所有 widget 均渲染於 SDK **內部自行建立**的 `WKWebView`。`WKWebViewConfiguration` 為 per-instance 設定，因此：

- Host App 對自家 WebView 的任何政策調整（關閉 JS 開窗、收緊媒體自動播放等）**不會影響** widget 的 WebView；
- SDK 的設定也**不會外溢**影響 Host App 內的其他 WebView。

整合時**不需要、也無法**調整下列任何設定。

### WKWebViewConfiguration

| 設定 | 值 | 說明 |
|---|---|---|
| `defaultWebpagePreferences.allowsContentJavaScript` | `true` | widget 本體為 JavaScript，必要設定（iOS 14+ API，取代已棄用的 `javaScriptEnabled`） |
| `allowsInlineMediaPlayback` | `true` | FloatingMedia 影音自動播放所必需 |
| `mediaTypesRequiringUserActionForPlayback` | `[]`（空集合） | 允許影音不經使用者手勢即自動播放，FloatingMedia 所必需 |
| `websiteDataStore` | 系統預設 | Cookie 存於 App 的預設 `WKWebsiteDataStore`。widget 功能不依賴 Host 站台的 cookie |
| `customUserAgent` | 未設定 | 使用系統預設 User-Agent，後端不依賴特定 UA |

SDK **未設定** `javaScriptCanOpenWindowsAutomatically`（即維持預設 `false`），也未實作 `WKUIDelegate`，因此 widget 的 WebView 無法開啟任何新視窗——widget 不使用 `window.open`，所有導頁行為都經 JS bridge 交由 Host App 處理（見下方）。

另外，widget 的 WebView 會設定 `scrollView.isScrollEnabled = false`（高度由內容自動回報，不需內部捲動）、`isOpaque = false` 與透明背景（與 Host 頁面融合）。

### JavaScript Bridge

對應 Android 的 `addJavascriptInterface`，iOS 端註冊兩個 `WKScriptMessageHandler`：

| Handler | 方向 | 用途 |
|---|---|---|
| `tagnologyResize` | JS → Native | widget 內容高度變化時回報，原生端據此調整版位高度 |
| `tagnologyEvent` | JS → Native | 傳遞 widget 事件（點擊等）。點擊事件經 `EmbedWidgetView(onClick:)` callback 交由 Host App 決定導頁方式 |

Bridge 僅接收 SDK 自家 widget 頁面（載入自 `https://embed.tagnology.co`）發出的訊息，Host App 無需（也不應）另行註冊或呼叫。

### Lightbox

點擊 widget 內容時，SDK 以原生 `fullScreenCover` 開啟 Lightbox（另一個 SDK 內部的 `WKWebView`，載入 `https://embed.tagnology.co/lightBox`），**不使用** `window.open` 或系統瀏覽器。Lightbox 的 WebView 設定與上表相同（同樣允許 JS 與影音自動播放），關閉後即釋放。

### Mixed Content

widget HTML 與所有資源（JS / CSS / 影音）均由 `https://embed.tagnology.co` 以 HTTPS 載入，不存在 mixed content；SDK 亦未放寬 WKWebView 預設的 mixed content 封鎖政策。

### Cookie / User-Agent 政策

- SDK 不讀取、不依賴 Host 站台或 Host App 的任何 cookie；widget 所需資料均經 `/widget/pageBundle` API 以加密 payload 取得。
- 未設定 `customUserAgent`，一律使用系統預設 UA。

### Host App 需要注意的唯一事項

**ATS（App Transport Security）**：請確保 App 未封鎖對 `embed.tagnology.co` 的 HTTPS 連線。預設 ATS 設定即允許所有 HTTPS 連線，一般無需任何調整。

## Analytics Event Logging

SDK supports `/api/widget/log` events aligned with web `91app.js` behavior:

- `PAGE_VIEW`: sent once per page session, only when `/widget/pageBundle` returns non-empty `pageBundle`.
- `EMBED_VIEW`: sent when widget becomes visible in viewport (with de-dup per page session).
- `DWELL_TIME`: sent on page leave with both `dwellTime` and `widgetDwellTime`.
- `WIDGET_CLICK` (App callback): delivered via `EmbedWidgetView(onClick:)` for app-side tracking.

Leave-page trigger options:

- Primary: call `EmbedIOSSDK.notifyPageDidLeave()` when leaving the product page.
- Fallback: SDK also triggers leave handling on `scenePhase` changes to `.inactive` / `.background`.

Notes:

- If `pageBundle` is empty, SDK skips `PAGE_VIEW` / `EMBED_VIEW` / `DWELL_TIME`.
- `DWELL_TIME` is sent only when stay duration is greater than 5000 ms.
- SDK prints outbound log payloads in console for verification during testing.

### Widget Click Callback (`onClick`)

`EmbedWidgetView` supports click callback so app can send its own analytics:

```swift
EmbedWidgetView(
    position: EmbedIOSSDK.BELOW_BUY_BUTTON,
    onError: { _ in },
    onClick: { click in
        // click.folderId, click.folderName, click.position, click.mediaId, click.url
    }
)
```

Callback payload fields:

- `folderId` (`String`): widget folder id.
- `folderName` (`String?`): widget folder name.
- `position` (`String?`): widget position (embed location/floating position).
- `mediaId` (`String?`): media id from widget click payload. This field may be `nil` if widget does not provide it.
- `url` (`String?`): always equals the page URL passed to `EmbedIOSSDK.initialize(pageUrl:...)`.

Debug output:

- SDK prints click payload summary with `[EmbedWidgetClick] ...` when user clicks widget content.

## Test Status (2026-05-26)

Verified with `ectest` integration flow:

- ✅ Re-entering product page re-triggers `PAGE_VIEW` (new session with `forceRefresh: true`).
- ✅ `EMBED_VIEW` re-triggers after returning to product page, including fast return-and-scroll scenarios.
- ✅ `DWELL_TIME` includes both `dwellTime` and `widgetDwellTime`.
- ✅ No analytics event is sent when `/widget/pageBundle` returns empty `pageBundle`.

## License

MIT License - see LICENSE file for details

## Support

For support, please contact: wayne.zhang@tagnology.co
