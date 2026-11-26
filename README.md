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

## Release Notes

### 1.0.19

- `EmbedWidgetClickEvent` 新增 `trackingUrl: String?`：版位被點擊時，以與網頁版 91app script 相同的規則，在目前頁面網址（`initialize(pageUrl:)` 傳入的網址）加上 UTM 參數，例如 `https://{shop}/SalePage/Index/{id}?utm_source=embed_tagnology&utm_id=<folderId>&utm_content=<mediaId>&utm_medium=<嵌入位置>&utm_campaign=<內容牆名稱>&utm_term=<來源頁網址>`。App 可直接用它做成效追蹤，比照網頁版網址帶 UTM 的情境。
  - init 參數 `trackingUrl` 預設 nil，既有呼叫端不需改程式。
- 新增 `EmbedIOSSDK.setLinkClickHandler(_:)`：與 `setLinkHandler` 相同，但 handler 收到 `EmbedLinkClickEvent`，含被點擊的連結 `url`、SDK 組好完整 UTM 的 `trackingUrl`（以被點擊的商品連結為主，`utm_medium=LINK`），以及 `folderId`、`folderName`、`position`、`mediaId`、`pageUrl`。
  - `setLinkHandler` 照舊可用、收到的網址不變；兩者共用同一個 handler，以最後設定的為準。
- SDK 沒有值的 UTM 欄位保留參數、值留空（例如 `utm_content=`）。
- 精選動態（Highlight）的點擊資料沒有 `mediaId`：`EmbedWidgetClickEvent.mediaId`／`utm_content` 改用網頁預抓清單（`mediaList`）的第一則，也就是 Lightbox 開啟時顯示的那則；網頁沒有預抓到（排在第 7 個以後的精選動態，或預抓還沒完成）時仍為空。
- 測試：`EmbedTrackingURLTests`。

### 1.0.18

- 新增錯誤碼 `APP_SDK_DISABLED`：商家在 Tagnology 後台尚未開通「App SDK」權限（預設關閉）時，`/widget/pageBundle` 與 `/widget/floatingPositions` 回 HTTP 403 + `errorCode: "APP_SDK_DISABLED"`。`initialize` 會回傳 `statusCode = 403`（`EmbedWidgetLoadError.StatusCode.appSdkDisabled`）、`errorCode = EmbedAPI.appSdkDisabledErrorCode` 的錯誤；`EmbedWidgetView` 的 `onError` 與 `getFloatingPositions` 的 `onError` 也會收到同樣的錯誤。App 收到時**不要顯示任何版位、不要重試**。
  - `EmbedWidgetLoadError` 新增選填欄位 `errorCode: String?`（init 參數預設 nil），既有呼叫端不需改程式。
  - `StatusCode` 新增 `appSdkDisabled = 403`；若 App 對 `StatusCode` 做窮舉 `switch`，需補上這個 case 或 `default`。
  - 舊版 SDK（1.0.17 以前）收到同樣回應時回報 `500`，一樣不會顯示版位。
  - 失敗結果不寫入快取，後台開通後下次 `initialize` 即恢復顯示。
- 測試：`EmbedAppSdkDisabledTests`。

### 1.0.17

- 新增 `EmbedIOSSDK.setLinkHandler(_:)`：使用者點擊版位或 Lightbox 內的商品卡等連結時，SDK 先把完整網址交給 App，App 回傳 `true` 代表已自行開啟（例如轉成 App 內的原生商品頁），SDK 就不開外部瀏覽器（91APP 回報商品在瀏覽器開啟後，收藏、加入購物車、登入狀態與 App 不同步）。
  - App 回傳 `true` 時，若 Lightbox 正開著，SDK 會自動關閉 Lightbox（重新載入讓影片停止），App 的原生頁不會被 Lightbox 蓋住。
  - App 回傳 `false`，或未設定 handler：維持原本行為，交給系統開啟（瀏覽器或對應 App）。未呼叫 `setLinkHandler` 的整合不受影響。
  - 只有離開 `embed.tagnology.co` 的連結會交給 handler；版位與 Lightbox 自身的頁面不會。
  - 與 Android SDK v1.0.8 的 `EmbedAndroidSDK.setLinkHandler` 行為相同。

### 1.0.16

- 返回同一頁時保留版位：從分類頁進商品頁再返回，版位維持離開前的內容與高度，不再重新載入（91APP 回報返回後版位重新顯示載入中，高度 132pt → 265pt → 449pt 從頭變化，下方廣告與商品列表跟著跳動）。
  - SwiftUI 會在 view 消失時取消、再出現時重跑 `EmbedWidgetView` 的載入工作；同一頁、同一版位已載入完成時改為直接沿用，不重建 WebView。
  - 離開時尚未載入完成或載入失敗的版位，返回時仍會重新載入。
  - `EmbedWidgetView` 被移除後重新建立（例如 Host App 重建整個頁面或改變 `pageUrl`）仍會重新載入。

### 1.0.15

- 只透過 Swift Package Manager 發佈：CocoaPods 已淘汰，CocoaPods 上最後可用的版本是 1.0.14。
- `initialize` 新增讀取時間上限 `timeout`（預設 `EmbedIOSSDK.defaultInitializeTimeout` = 3 秒）：超過時間仍未取得頁面資料就回傳 `408` 逾時錯誤，App 不顯示版位即可（91APP 要求比照 App 內其他版位，API 超過 3 秒不顯示）。
  - 計時從呼叫 `initialize` 開始；即使連線卡住不回應，`initialize` 也會在時限到時回傳。
  - 同時發出的浮窗版位請求共用同一個時限，逾時只會讓 `getFloatingPositions()` 回傳 `[]`，不會拖慢 `initialize`。
  - `timeout` 傳 `0`、負數或 `.infinity` 代表不限時（舊行為）。逾時的頁面不會寫入快取，下次 `initialize` 會重新請求。
  - 只限制取得資料的時間；版位內容的網頁載入與繪製不在此限。
- Lightbox 載入中也能關閉：內容顯示前右上角一律顯示關閉按鈕（原本只在頁面載入失敗時才有），內容顯示後改用頁面自己的關閉鈕。點擊後 10 秒內頁面仍未顯示內容（未回 `toggleLB open=true`）就停止轉圈、只留關閉按鈕，關閉後 Lightbox 頁面會重新載入（91APP 回報頁面沒回應時只能一直轉圈、無法關閉）。
- iOS 17 以上，SDK 的 WebView 改為跨 App 啟動保留 HTTP 快取：版位與 Lightbox 網頁的 JS、CSS 不必每次開 App 都重新下載（91APP 回報 `initialize` 後版位還要約 3.8 秒才出現）。模擬行動網路量測，重新啟動 App 後 `initialize` 完成到版位回報高度由約 5.6 秒降到約 0.6 秒。
  - 仍使用 SDK 專屬的 data store，不與 Host App 共用 cookie。
  - 每次啟動第一次 `initialize` 時清除前次啟動留下的 cookie、localStorage 等資料，只保留 HTTP 快取，與 1.0.11 起「cookie 不跨啟動保存」相同。
  - 網頁 HTML 依伺服器的快取設定（目前 10 分鐘）重新取得，網頁更新最晚 10 分鐘後生效。
  - iOS 16 沒有可指定的 data store，維持只存在記憶體。

### 1.0.14

- 修正點擊版位開啟 Lightbox 時的短暫黑屏：版位出現時就預先載入 Lightbox 頁面（與 Web 版預先建立隱藏的 Lightbox iframe 相同），同一頁的所有版位共用並重複使用，點擊後不必再等整個頁面載入。
- Lightbox 頁面回報 `readyLB` 後才送出點擊訊息；內容顯示前改顯示載入指示，不再只有黑底。
- 修正 Lightbox 底部的貼文說明與商品連結被切掉：Lightbox 內容改為留在 Safe Area 內，並關閉 WebView 的自動 inset 調整（原本會把整頁往下推一個狀態列高度）。
- 修正 Lightbox 與版位內的商品連結點了沒反應：網頁以 `window.open` 開啟的連結原本會被 WKWebView 丟棄，現在非 embed.tagnology.co 的連結交給系統開啟（瀏覽器或對應 App），與 Android SDK 相同。
- 修正影音浮窗的 `onClick` 回報 `position`：改回報實際顯示的 `FIXED_*` 版位（例如 `FIXED_BOTTOM_RIGHT`），不再回報 pageBundle 預設的 `embedLocation`。
- App 在背景時若系統回收 WebContent 程序，版位會自動重新載入，不再停在空白。
- 移除 GitHub Actions CI（macOS runner 成本過高），改用本地執行 `scripts/test-local.sh`，見〈本地測試〉。

### 1.0.13

- SDK 程式碼與 1.0.12 相同，無 API 變更。
- 範例改用 partnertest7 測試頁（mid 41461），並讓嵌入版位在 `initialize` 成功後即載入，不必等待 `getFloatingPositions()`；`getFloatingPositions()` 只決定影音浮窗要放在哪些 `FIXED_*` 版位。
- CI 改為執行時自動挑選可用的 iOS 模擬器。

### 1.0.12

- 新增 `EmbedIOSSDK.getFloatingPositions()`：`initialize` 會同時呼叫 `/widget/floatingPositions` 取得此頁應出現的浮窗版位，初始化後直接取用、不需再帶參數；App 只需為回傳的 `FIXED_*` 版位建立 `EmbedWidgetView`，避免建立空版位。
- 浮窗版位請求失敗不會讓 `initialize` 失敗，只會讓 `getFloatingPositions()` 回傳 `[]` 並透過 `onError` 回報。
- 新增 `EmbedAPI.fetchFloatingPositions(...)`（會 throw）與 `EmbedPosition.isFloatingPosition`。
- 範例改為依 `getFloatingPositions()` 結果動態放入浮窗版位，移除 5 秒後偵測高度再隱藏的做法。

### 1.0.11

- Widget 與 Lightbox 改用 SDK 私有、共用的 `WKWebsiteDataStore.nonPersistent()`，不再與 Host App 共用預設 cookie jar。
- SDK WebView 的 cookie 與其他網站資料只保留於記憶體，不會寫入磁碟或跨 App 啟動保存；Host App 清除預設 store 也不會影響 SDK store。
- 集中管理 Widget 與 Lightbox 的 WebView 設定，確保 JavaScript 與影音播放政策一致。

### 1.0.10

- 同一固定位置若有多個 FloatingMedia widget，會全部依時間順序垂直顯示，間距為 8pt。
- 固定浮窗改用內容總高度，不再強制單一 224pt 高度。
- 底部固定浮窗會避開 Safe Area，避免被 Host App 的底部 action bar 或系統區域遮擋。

### 1.0.9

- `EmbedWidgetView` 新增選填的 `pageUrl`；網址改變時會自動清除舊狀態並重新載入，不需額外使用 `.id(pageUrl)`。
- 若 View 要求的 `pageUrl` 與 SDK 已初始化頁面不同，會透過 `onError` 回傳 `409 pageMismatch`，不再靜默顯示前一頁內容。
- 初始化加入競態保護；較舊頁面的延遲成功或失敗結果不會覆蓋目前頁面。
- 新增公開的 `EmbedIOSSDK.setLoggingEnabled(_:)`，並移除 Lightbox 載入後延遲執行的 DOM 探查程式。

## Installation

### Swift Package Manager (Recommended)

In Xcode, go to **File > Add Package Dependencies...** and enter:

```
https://github.com/tagnologytw/embed-ios-sdk.git
```

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tagnologytw/embed-ios-sdk.git", from: "1.0.19")
]
```

Then import the module where needed:

```swift
import EmbedIOSSDK
```

### CocoaPods（已淘汰）

CocoaPods 已淘汰：CocoaPods Trunk 已停止接受新版本，EmbedIOSSDK 在 CocoaPods 上最後可用的版本是 1.0.14。1.0.15 起只透過 Swift Package Manager 發佈，請改用上方的 SPM 安裝方式。

仍在使用 CocoaPods 的專案只能停留在 1.0.14：

```ruby
pod 'EmbedIOSSDK', '1.0.14'
```

Then run:

```bash
pod install
```

### Manual Installation

1. Copy the `Sources/EmbedIOSSDK/embed.swift` file to your project
2. Ensure your project targets iOS 16.0 or higher

## Usage

### Basic Usage

進入頁面後，先呼叫 `EmbedIOSSDK.initialize(pageUrl:mid:secret:)`。  
初始化成功後，再用 `EmbedWidgetView(position:pageUrl:)` 顯示各版位。傳入 `pageUrl` 後，頁面網址改變時 View 會清除舊內容並重新取得對應版位。

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
                        pageUrl: pageUrl,
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
                            // click.trackingUrl (page URL + UTM, same as the web script)
                        }
                    )
                }

                // Display widget below main product info
                if isEmbedInitialized {
                    EmbedWidgetView(
                        position: EmbedIOSSDK.BELOW_MAIN_PRODUCT_INFO,
                        pageUrl: pageUrl
                    )
                }
            }
        }
        .task(id: pageUrl) {
            isEmbedInitialized = false
            let initError = await EmbedIOSSDK.initialize(
                pageUrl: pageUrl,
                mid: mid,
                secret: secret,
                forceRefresh: true // optional, avoid stale in-memory cache during debug
            )
            guard !Task.isCancelled else { return }
            isEmbedInitialized = (initError == nil)
        }
    }
}
```

### Open Links in the App (`setLinkHandler`)

使用者點擊版位或 Lightbox 內的商品卡（或其他離開 `embed.tagnology.co` 的連結）時，預設由系統開啟（Safari 或對應 App）。App 若想改開自己的原生頁（例如商品頁），在 App 啟動時設定一次 link handler：

```swift
// 例如在 App 啟動時（AppDelegate / App init）設定一次，整個 App 共用
EmbedIOSSDK.setLinkHandler { url in
    // url 為完整網址，例如 https://{shop}/SalePage/Index/{id}?utm_source=embed_tagnology
    // App 能以原生頁開啟就導過去並回傳 true；否則回傳 false
    return AppNavigator.open(url)
}
```

| handler 回傳 | SDK 行為 |
|---|---|
| `true` | 不開外部瀏覽器；若 Lightbox 正開著，SDK 會自動關閉（並重新載入讓影片停止），App 的原生頁不會被蓋住 |
| `false` | 與未設定相同，交給系統開啟（瀏覽器或對應 App） |
| 未設定 / `setLinkHandler(nil)` | 全部交給系統開啟（1.0.16 以前的行為） |

注意事項：

- handler 在主執行緒同步呼叫，請只做判斷並開始導頁，不要在裡面做耗時工作。
- 網址原封不動傳入（含 `utm_*` 等 query），解析方式由 App 決定；SDK 不針對特定電商平台判斷。
- 只有離開 `embed.tagnology.co` 的連結會交給 handler（商品頁、Instagram、`tel:`、`mailto:`、`line:` 等），版位與 Lightbox 自身的頁面不會。
- Lightbox 是以 `fullScreenCover` 顯示，回傳 `true` 後 SDK 才開始關閉它。App 以 push 方式導頁沒有問題；若 App 是以 modal（`present`）開原生頁，請等 Lightbox 關閉後再 present（例如延遲約 0.5 秒），否則 UIKit 會因為已有 modal 而不顯示。
- 點擊成效追蹤由版位網頁在開啟連結前送出，不受 handler 影響。

#### 取得連結的 trackingUrl（`setLinkClickHandler`）

App 若要用 UTM 追蹤商品連結點擊，改用 `setLinkClickHandler`。回傳值的意義與 `setLinkHandler` 相同；兩者共用同一個 handler，以最後設定的為準。

```swift
EmbedIOSSDK.setLinkClickHandler { event in
    // event.url          被點擊的連結（原封不動，與 setLinkHandler 收到的相同）
    // event.trackingUrl  被點擊的連結 + SDK 組好的完整 UTM；非 http(s) 連結（tel:、mailto:）為 nil
    // event.folderId / event.folderName / event.position / event.mediaId / event.pageUrl
    return AppNavigator.open(event.url)
}
```

`trackingUrl` 規則（與網頁版 `Helper.AddUTMParams` 相同）：

| 參數 | 值 |
|---|---|
| `utm_source` | `embed_tagnology` |
| `utm_content` | `mediaId` |
| `utm_medium` | `LINK` |
| `utm_id` | `folderId` |
| `utm_campaign` | 內容牆名稱 |
| `utm_term` | 來源頁網址（`initialize(pageUrl:)` 的完整網址） |

- SDK 沒有值的欄位保留參數、值留空（例如 `utm_campaign=`）。
- 連結若已由網頁帶上 `utm_source=embed_tagnology`，沿用網頁的值（Lightbox 內可能已切換到別則貼文，網頁才知道目前是哪一則），SDK 只補上缺的欄位。
- 連結原有的其他來源 UTM 會被取代，與網頁版相同；其他 query 與 `#` 保留。

### Debug Logging

SDK internal diagnostic logging is disabled by default. Enable it while debugging through the public API:

```swift
#if DEBUG
EmbedIOSSDK.setLoggingEnabled(true)
#endif
```

Call `EmbedIOSSDK.setLoggingEnabled(false)` to disable it again. Logging only controls console output and does not enable additional DOM inspection or JavaScript probes.

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
If multiple FloatingMedia widgets use the same fixed position, the SDK renders all of them vertically with 8pt spacing. Keep the host view width at `126` points, but do not force its height to `224`; the SDK calculates the combined height automatically.

### Fixed Position Widgets Example

浮窗（FloatingMedia）版位請在 `initialize` 成功後呼叫 `EmbedIOSSDK.getFloatingPositions()`，只為回傳的 `FIXED_*` 版位建立 `EmbedWidgetView`，就不會產生空版位。

- 不用帶參數：`initialize` 時 SDK 已用同一組 `pageUrl` / `mid` / `secret` 一併取得浮窗版位。
- 回傳 `[EmbedPosition]`；此頁沒有浮窗時回傳 `[]`。
- 尚未初始化、初始化失敗或浮窗請求失敗時也回傳 `[]`，錯誤透過選填的 `onError` 回傳；浮窗請求失敗不影響一般版位。
- 初始化進行中呼叫會等待完成後再回傳。

```swift
struct ProductPageView: View {
    let pageUrl: String
    let mid: String
    let secret: String

    @State private var isEmbedInitialized = false
    @State private var floatingPositions: [EmbedIOSSDK.Position] = []

    var body: some View {
        ZStack {
            // Your main content
            ScrollView {
                // ... your content
            }

            // 只放入 SDK 回傳的浮窗版位
            if isEmbedInitialized {
                ForEach(floatingPositions, id: \.rawValue) { position in
                    EmbedWidgetView(
                        position: position,
                        pageUrl: pageUrl,
                        onError: { _ in
                            floatingPositions.removeAll { $0 == position }
                        }
                    )
                    .frame(width: 126)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(for: position))
                }
            }
        }
        .task(id: pageUrl) {
            isEmbedInitialized = false
            floatingPositions = []

            let initError = await EmbedIOSSDK.initialize(pageUrl: pageUrl, mid: mid, secret: secret)
            guard !Task.isCancelled, initError == nil else { return }

            floatingPositions = await EmbedIOSSDK.getFloatingPositions()
            guard !Task.isCancelled else { return }
            isEmbedInitialized = true
        }
    }

    private func alignment(for position: EmbedIOSSDK.Position) -> Alignment {
        switch position {
        case .FIXED_TOP_LEFT: return .topLeading
        case .FIXED_TOP_RIGHT: return .topTrailing
        case .FIXED_CENTER_LEFT: return .leading
        case .FIXED_CENTER_RIGHT: return .trailing
        case .FIXED_BOTTOM_LEFT: return .bottomLeading
        default: return .bottomTrailing
        }
    }
}
```

完整範例見 `example/ContentView.swift`。

#### Floating Positions Request Details

`initialize` 會與 `/widget/pageBundle` 同時呼叫：

- `[POST] {BASE_URL}/widget/floatingPositions`

```json
{
  "mid": 41458,
  "pageUrl": "https://partnertest4.91app.com/SalePage/Index/8778040",
  "secret": "<payloadSecret>"
}
```

Response：

```json
{ "message": "success", "positions": ["FIXED_BOTTOM_RIGHT"] }
```

- `mid` 為數字字串時以 int 送出，否則以 string 送出。
- 無法辨識或非 `FIXED_*` 的值會被忽略，重複值會去除。
- 若需要自行處理錯誤，可改用會 throw 的 `EmbedAPI.fetchFloatingPositions(pageUrl:mid:secret:baseURL:)`。

### Parameters

- **`initialize(pageUrl:mid:secret:baseURL:forceRefresh:timeout:)`** (required before widget render)
  - `pageUrl` (String, required): 當前頁面 URL
  - `mid` (String, required): 商店 MID
  - `secret` (String, required): `payloadSecret`（Base64 且 decode 後必須是 32 bytes）。**各商店（mid）獨立一組**，由 Tagnology 於開通時逐店簽發，僅對該 mid 有效；單一金鑰外洩影響範圍僅限該商店，可單獨重新簽發
  - `baseURL` (String, optional): API 網域，預設 `https://embed.tagnology.co/api`
  - `forceRefresh` (Bool, optional): 是否忽略 in-memory cache 重新打 API（預設 `false`）
  - `timeout` (TimeInterval, optional): 取得頁面資料的時間上限，預設 `EmbedIOSSDK.defaultInitializeTimeout`（3 秒）。超過即回傳 `408`，請不要顯示版位；`0`、負數或 `.infinity` 代表不限時
- **`getFloatingPositions(onError:)`** (call after `initialize`, before mounting `FIXED_*` widgets)
  - 不需帶參數，沿用 `initialize` 的 `pageUrl` / `mid` / `secret` / `baseURL`
  - `onError` ((EmbedWidgetLoadError) -> Void, optional): 無法取得版位時回呼（`428` 尚未初始化、初始化失敗的錯誤、`500` / `408` / `520` 浮窗請求失敗），此時函式回傳 `[]`；錯誤中的 `position` 對此呼叫無意義
- **`position`** (EmbedIOSSDK.Position, required): The position where the widget should be displayed. See Position Enum above for available values.
- **`pageUrl`** (String, optional): The page this view should display. Passing it is recommended; changing it reloads the view and prevents content from the previously initialized page from being rendered. Omitting it preserves the legacy shared-current-page behavior.
- **`onError`** ((EmbedWidgetLoadError) -> Void, optional): Called for non-`200` status codes. Use this callback to hide the slot in your App.

### Error Callback (Hide Slot)

When callback status code is non-`200` (no data or error), `onError` will be triggered.  
`EmbedWidgetLoadError` includes:

- `statusCode`: callback status code
    - `200` 正常（不會 callback）
    - `204` 無資料（API 回傳 `pageBundle = []` 或該版位過濾後無資料）
    - `409` `EmbedWidgetView` 要求的 `pageUrl` 與 SDK 目前初始化頁面不一致
    - `422` 初始化參數錯誤（例如 pageUrl 無法取出 ID、secret 格式錯誤）
    - `425` 初始化進行中
    - `428` 尚未初始化（尚未呼叫 `initialize`）
    - `403` 商家未開通 App SDK（`errorCode == "APP_SDK_DISABLED"`，Tagnology 後台「編輯權限」→ App SDK，預設關閉）
    - `500` 系統錯誤
    - `408` timeout（含 `initialize` 超過 `timeout` 仍未取得資料）
    - `520` 其他錯誤
- `message`: error message
- `errorCode`: 伺服器錯誤碼（沒有時為 `nil`）；目前只有 `APP_SDK_DISABLED`（搭配 `403`）
- `pageUrl`: requested page URL（未傳入 `EmbedWidgetView` 時則為目前初始化頁面）
- `position`: current widget position

**Behavior:** `204/403/422/500/408/520` 建議隱藏版位（`403` + `APP_SDK_DISABLED` 代表整個商家未開通，所有版位都不要顯示、不要重試）；`409/425/428` 會先等待初始化完成，若重試後仍失敗才透過 `onError` 回傳。

### Advanced Usage

The SDK uses a shared data manager to cache initialization data and avoid multiple API calls for the same page URL.  
After a successful `initialize`, all `EmbedWidgetView(position:pageUrl:)` read from the shared in-memory page bundle. Pass the same `pageUrl` to both APIs so the view can reject stale data.

When the host app changes pages, make the initialization task depend on `pageUrl`:

```swift
.task(id: pageUrl) {
    await EmbedIOSSDK.initialize(
        pageUrl: pageUrl,
        mid: mid,
        secret: secret
    )
}
```

If the page changes again before initialization completes, the newer request supersedes the older request. The SDK cancels the previous request when possible and always ignores stale results, so an older page cannot overwrite the current page cache or initialization state. Check `Task.isCancelled` before updating host App state after `initialize` returns.

The matching widget view does not need an additional `.id(pageUrl)` workaround:

```swift
EmbedWidgetView(
    position: EmbedIOSSDK.BELOW_BUY_BUTTON,
    pageUrl: pageUrl
)
```

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
| `websiteDataStore` | SDK 內共享的 store：iOS 17+ 為 SDK 專屬的 `WKWebsiteDataStore(forIdentifier:)`，iOS 16 為 `WKWebsiteDataStore.nonPersistent()` | Widget 與 Lightbox 共用 SDK 自有的 store，不會使用 Host App 的預設 cookie jar；跨 App 啟動只保留 HTTP 快取，cookie 等其他資料在每次啟動第一次 `initialize` 時清除 |
| `customUserAgent` | 未設定 | 使用系統預設 User-Agent，後端不依賴特定 UA |

SDK **未設定** `javaScriptCanOpenWindowsAutomatically`（即維持預設 `false`），WebView 內不會開啟新視窗。SDK 實作 `WKUIDelegate` 與 `WKNavigationDelegate`：widget 與 Lightbox 內以 `window.open` 或連結開啟的網址（例如 Lightbox 內的商品卡片），只要不是 `embed.tagnology.co`，不在 SDK 的 WebView 內換頁，交給系統開啟（瀏覽器或對應 App，1.0.14 起）；App 若以 `EmbedIOSSDK.setLinkHandler(_:)` 設定 link handler，會先交給 App 決定是否自行開啟（1.0.17 起，見〈Open Links in the App〉）。

另外，widget 的 WebView 會設定 `scrollView.isScrollEnabled = false`（高度由內容自動回報，不需內部捲動）、`isOpaque = false` 與透明背景（與 Host 頁面融合）。

### JavaScript Bridge

對應 Android 的 `addJavascriptInterface`，iOS 端註冊兩個 `WKScriptMessageHandler`：

| Handler | 方向 | 用途 |
|---|---|---|
| `tagnologyResize` | JS → Native | widget 內容高度變化時回報，原生端據此調整版位高度 |
| `tagnologyEvent` | JS → Native | 傳遞 widget 事件（點擊等）。點擊時 SDK 先呼叫 `EmbedWidgetView(onClick:)` 通知 Host App（僅供追蹤，見〈Widget Click Callback〉），再開啟 Lightbox；`onClick` 不影響後續動作 |

Bridge 僅接收 SDK 自家 widget 頁面（載入自 `https://embed.tagnology.co`）發出的訊息，Host App 無需（也不應）另行註冊或呼叫。

### Lightbox

點擊 widget 內容時，SDK 以原生 `fullScreenCover` 顯示 Lightbox（另一個 SDK 內部的 `WKWebView`，載入 `https://embed.tagnology.co/lightBox`）。Lightbox 在版位出現時即預先載入，同一頁的所有版位共用，關閉後保留供下次點擊使用（1.0.14 起）。內容顯示前右上角一律有關閉按鈕；點擊後 10 秒仍未顯示內容就停止轉圈、只留關閉按鈕，關閉後 Lightbox 頁面會重新載入（1.0.15 起）。Lightbox 的 WebView 設定與上表相同（同樣允許 JS 與影音自動播放）。使用者在 Lightbox 內點商品卡片時，商品網址先交給 App 的 link handler（有設定時），未處理再交由系統開啟；App 處理後 SDK 會關閉 Lightbox（見〈Open Links in the App〉）。

### Mixed Content

widget HTML 與所有資源（JS / CSS / 影音）均由 `https://embed.tagnology.co` 以 HTTPS 載入，不存在 mixed content；SDK 亦未放寬 WKWebView 預設的 mixed content 封鎖政策。

### Cookie / User-Agent 政策

- SDK 不讀取、不依賴 Host 站台或 Host App 的任何 cookie；widget 所需資料均經 `/widget/pageBundle` API 以加密 payload 取得。
- SDK 內的 Widget 與 Lightbox WebView 共用一個 SDK 專屬的 store（iOS 17+ 為 `WKWebsiteDataStore(forIdentifier:)`，iOS 16 為 `WKWebsiteDataStore.nonPersistent()`）；Host App 同步到預設 store 的登入 cookie 不會進入 SDK WebView，Host App 清除預設 store 時也不會清除 SDK 的 store。
- SDK WebView 的 cookie、localStorage 等網站資料不會跨 App 啟動保留：每次啟動第一次 `initialize` 時清除前次留下的資料，只保留 HTTP 快取（網頁的 JS、CSS），讓版位不必每次開 App 都重新下載。
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

`EmbedWidgetView` supports click callback so app can send its own analytics. The callback is notification-only: it returns nothing, so it can't stop or replace the Lightbox, which the SDK opens right after it.

```swift
EmbedWidgetView(
    position: EmbedIOSSDK.BELOW_BUY_BUTTON,
    pageUrl: pageUrl,
    onError: { _ in },
    onClick: { click in
        // click.folderId, click.folderName, click.position, click.mediaId, click.url, click.trackingUrl
    }
)
```

Callback payload fields:

- `folderId` (`String`): widget folder id.
- `folderName` (`String?`): widget folder name.
- `position` (`String?`): widget position (embed location/floating position).
- `mediaId` (`String?`): media id from widget click payload. This field may be `nil` if widget does not provide it.
- `url` (`String?`): always equals the page URL passed to `EmbedIOSSDK.initialize(pageUrl:...)`.
- `trackingUrl` (`String?`): `url` with the UTM parameters the web 91app script adds to the page URL when a widget is clicked. `nil` if `url` is not an http(s) URL.

`trackingUrl` 規則（與網頁版 `91app.js` 點擊版位時相同）：

| 參數 | 值 |
|---|---|
| `utm_source` | `embed_tagnology` |
| `utm_id` | `folderId` |
| `utm_content` | `mediaId`（精選動態用預抓清單的第一則；都沒有時留空） |
| `utm_medium` | 版位的 `embedLocation`（沒有時為 `CUSTOMIZED`） |
| `utm_campaign` | 內容牆名稱（沒有時為 `folderId`） |
| `utm_term` | 來源頁網址（`pageUrl` 去掉 query 與 `#`） |

- `pageUrl` 原有的其他 query 與 `#` 會保留；先前的 `embed_tagnology` UTM 會被這次點擊覆蓋。
- 若 `pageUrl` 已帶其他來源的 `utm_source`（例如 `facebook`），不覆蓋對方的 UTM，只把 `utm_content` 改成 `<原 utm_content>+embed_tagnology`（原本沒有則為 `embed_tagnology`）。
- 網址編碼與瀏覽器 `URLSearchParams` 相同（空白為 `+`，`+` 為 `%2B`）。
- 網頁版還會把這組 UTM 存在 localStorage，使用者在同一個網站換頁時繼續帶上；SDK 只回傳網址，換頁後要不要沿用由 App 決定。

Debug output:

- SDK prints click payload summary with `[EmbedWidgetClick] ...` when user clicks widget content.

## 本地測試

GitHub Actions CI 已移除，發版或合併前請在本機執行：

```bash
scripts/test-local.sh
```

依序執行 `swift package dump-package`、在 iOS 模擬器跑單元測試、以及 `generic/platform=iOS` 的實機建置。加上 `--pod-lint` 會再跑 `pod lib lint`；設定 `SIMULATOR_ID=<udid>` 可指定模擬器。

接著依 [`.claude/skills/ios-pre-pr/SKILL.md`](.claude/skills/ios-pre-pr/SKILL.md) 在模擬器用 `ectest` 實際操作所有版位與 Lightbox（Claude Code 會以 `ios-pre-pr` skill 載入）。審核標準：不可跑版、不可出現全黑畫面。`scripts/sim-record.sh start|stop <name>` 會錄下點擊過程、產生 contact sheet，並以 ffmpeg `blackdetect` 檢查全黑畫面。

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
