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

- `[POST] {BASE_URL}/91app/pageBundle`

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
- `https://partnertest4.91app.com/v2/official/SalePageCategory/481477?sortMode=Newest` -> `481477`

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
  - `secret` (String, required): `payloadSecret`（Base64 且 decode 後必須是 32 bytes）
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

## License

MIT License - see LICENSE file for details

## Support

For support, please contact: wayne.zhang@tagnology.co
