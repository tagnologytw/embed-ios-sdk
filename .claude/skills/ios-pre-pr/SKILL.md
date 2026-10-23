---
name: ios-pre-pr
description: embed-ios-sdk 發 PR 前的標準驗證程序：本地單元測試＋在 iOS 模擬器用 ectest 實際操作所有版位、Lightbox、商品連結與異常情境，確認不跑版、不出現全黑畫面。修改 Sources/ 後、準備 commit / push / 開 PR 或更新 PR 前一律執行。
---

# iOS SDK 發 PR 前驗證

GitHub Actions CI 已移除，這份程序就是合併前的唯一把關。每一步都要實際做、看到結果；沒做到的步驟在 PR 裡明寫「未驗證」，不可寫成已通過。

## 審核標準（任一不符即不可發 PR）

1. **不可跑版**：版位內容完整（圖片、標題文字不被裁切、不重疊、不被其他元件蓋住）；Lightbox 上方不壓到狀態列，下方貼文說明與商品卡片完整露出。
2. **不可出現全黑畫面**（91APP 回報的問題）：點擊版位後 Lightbox 必須立刻有內容或載入指示。`scripts/sim-record.sh stop` 回報 `FAIL black screen` 即不通過；`WARN near-black` 需看 contact sheet 確認畫面上有 UI（標題、關閉鈕、進度條或轉圈）。
3. 點商品連結要有反應（開啟外部瀏覽器或對應 App），回到 App 後 Lightbox 狀態正常。
4. `onClick` 回報的 `position` 等於實際顯示的版位（浮窗回報 `FIXED_*`）。
5. 單元測試、實機建置全部通過。

## 環境

- SDK repo：`embed-ios-sdk/`；測試 App：同層的 `../ectest`（CocoaPods 以 `:path => '../embed-ios-sdk'` 引用，改 SDK 不需 `pod install`）。
- 測試頁：partnertest7 商品頁 `https://partnertest7.91app.com/SalePage/Index/9394400`（mid 41461）。
- 模擬器操作一律用 `mcp__Claude_Code_iOS_Simulator__control`（tap / swipe / screenshot / button）；錄影與黑畫面檢查用 `scripts/sim-record.sh`（需要 ffmpeg）。
- 先 `attach` 開模擬器面板讓使用者看得到。

## 步驟

### 1. 本地測試

```bash
scripts/test-local.sh
```

失敗就先修，不往下做。

### 2. 建置並安裝 ectest

```bash
UDID=<booted iPhone udid>   # xcrun simctl list devices booted
DD=$TMPDIR/ectest-dd
cd ../ectest
xcodebuild build -workspace ectest.xcworkspace -scheme ectest -destination "id=$UDID" -derivedDataPath $DD CODE_SIGNING_ALLOWED=NO -quiet
xcrun simctl install $UDID $DD/Build/Products/Debug-iphonesimulator/ectest.app
xcrun simctl launch --console-pty --terminate-running-process $UDID tagnology.co.ectest -embedLogging > $TMPDIR/ectest.log 2>&1 &
```

- `-embedLogging` 會開 SDK log（`[EmbedWebView]`、`[LightboxSession]`、`[EmbedWidgetClick]`、`[EmbedAnalytics]`）。用 `run_in_background` 或 `&` 啟動，log 從檔案讀。
- **模擬器特性**：`simctl launch` 剛安裝的 App 時，App 可能還沒成為前景，WebView 會停著不畫。啟動後先在空白處 tap 一下，再判斷版位是否空白。

### 3. 版型測試頁：逐一切換所有版位

「版型測試」分頁上方選「版位」，每個版位等約 5 秒截圖。partnertest7 目前預期：

| 版位 | 預期 |
|---|---|
| BELOW_BUY_BUTTON | Highlight（圓形限動＋標題），folder `1qx9bub1mmuh2qe3` |
| BELOW_MAIN_PRODUCT_INFO | 2×2 Grid，folder `1xh7q372ashlmmudhf4` |
| ABOVE_RECOMMENDATION | 2×2 Grid，folder `1qx9bub1mmuh24y5` |
| ABOVE_FILTER | 無版位，狀態列顯示 `onError ... statusCode=204` |
| FIXED_BOTTOM_RIGHT | 右下影音浮窗（126 寬），folder `1qx9bub1mmuh7bm6` |
| 其他 FIXED_* | 無版位（`floatingPositions` 只有 FIXED_BOTTOM_RIGHT） |

後台設定若變動，以 log 的 `floatingPositions=` 與 `EMBED_VIEW` 的 `embedLocation`/`folderId` 為準，並在報告說明。每個版位檢查審核標準 1。

### 4. Lightbox（每一種版型都要點）

對 Highlight、Grid、影音浮窗各做一次：

```bash
scripts/sim-record.sh start <name> $UDID
# 用 simulator tool tap 版位內容
sleep 4
scripts/sim-record.sh stop <name>     # exit 1 = 全黑畫面
```

- 用 Read 看 `sheet.png`：點擊後約 0.5 秒內要出現 Lightbox 內容或轉圈，不可只有黑底。
- 全螢幕截圖確認：上方標題列在狀態列下方；下方貼文說明、商品卡片完整（審核標準 1）。
- 關閉（X／關閉）後再點**另一則**內容，確認開到正確的那一則且一樣快（預載重用）。
- 限動點右半邊切到下一則，確認商品卡片完整露出。
- 點一張商品卡片：應跳到 Safari 開啟商品頁（log 有 `[EmbedLinkOpener] open url=`）；點左上「◀ ectest」回 App，Lightbox 仍正常，可關閉。
- 從 log 確認 `[EmbedWidgetClick]` 的 `position`：浮窗為 `FIXED_BOTTOM_RIGHT`，一般版位為其 embedLocation。

### 5. 商品頁分頁

切到「商品頁」分頁，往下捲過購買按鈕下方、商品資訊下方、推薦上方三個版位與右下浮窗，確認不跑版、版位高度正確（下一張卡片沒有蓋到版位、版位下方沒有大片多餘空白）。點浮窗開 Lightbox 一次。

### 6. 異常情境

- **背景回收**：模擬 iOS 回收 WebContent 程序：
  ```bash
  ps -o pid,ppid,command -A | grep com.apple.WebKit.WebContent | grep -v grep   # 取 App 啟動後新產生的 pid
  kill -9 <pid...>
  ```
  log 要出現 `web content process terminated ... reloading`，10 秒內版位重新出現，之後點擊 Lightbox 仍正常。
- **背景／前景**：`button HOME` 等 5 秒，再 `xcrun simctl launch $UDID tagnology.co.ectest` 回前景；版位仍在，log 有 `DWELL_TIME sent`。

### 7. 第二台裝置

在不同 safe area 的機型（例如有瀏海的 iPhone 16e，與動態島機型不同）重做步驟 2～4 的 Highlight 與浮窗 Lightbox，確認審核標準 1、2。

### 8. 深色模式（回報，不擋 PR）

```bash
xcrun simctl ui $UDID appearance dark   # 看完改回 light
```

記錄版位文字在深色背景是否可讀；目前 Highlight 標題在深色背景幾乎看不到（版位背景透明、網頁文字為深色），屬已知問題，有改善或變差都要寫進報告。

## 收尾

- 再跑一次 `scripts/test-local.sh`（修過程式就必須重跑）。
- 關閉模擬器上開著的 Lightbox，把外觀改回 light，關掉額外開的模擬器。
- PR 描述加「模擬器測試」段落：機型與 iOS 版本、逐項結果（通過／不通過／未驗證）、`sim-record.sh` 的結果、發現但未修的問題。不寫沒有實際做的項目。
