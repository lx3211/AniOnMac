# AniOnMac

**繁體中文** | [English](README.md)

將 Windows `.ani` 動畫游標轉成 macOS 可用的游標，保留動畫順序、速度與定位點

## 使用方式
### 使用 Release 版

1. 從 GitHub Releases 下載 `AniOnMac-macOS-universal.zip`，解壓後開啟 `AniOnMac.app`
2. 建立主題，選擇模式
3. 選擇或拖入 `.ani` 檔案
4. 調整尺寸與定位點，按下「套用主題」

- 註：首次開啟時可能被 [macOS 安全機制](https://support.apple.com/zh-tw/102445)攔截
  1. 到「系統設定 → 隱私權與安全性」
  1. 按「強制打開」，再確認「打開」

### 若無法開啟 Release 版

1. 在 GitHub 點選 **Code → Download ZIP**，解壓縮專案
2. 開啟「終端機」，執行以下指令並完成編譯工具安裝（已安裝可跳過）

   ```sh
   xcode-select --install
   ```

3. 輸入 `cd `（後面留一個空格），將解壓後的專案資料夾拖入終端機，再按 Enter
4. 確認 Python 3 可用；若找不到指令，先從 [Python 官網](https://www.python.org/downloads/macos/)安裝 Python 3

   ```sh
   python3 --version
   ```

5. 編譯 App

   ```sh
   sh development/build.sh
   ```

6. 完成後，開啟專案最外層產生的 `AniOnMac.app`
7. 接續上述 Release 版本開啟 app 後步驟

## 功能

| 模式 | 用途 |
| --- | --- |
| Arrow | 普通游標 |
| Pointing | 連結或互動元件上的手指，不是滑鼠按下狀態 |
| IBeam | 文字選取 |
| Wait | 系統等待游標，何時出現由 macOS 與應用程式決定 |

1. 可自訂多個主題，設定自動儲存，可復原上一次設定
1. 可即時預覽動畫效果，並以 macOS points 1:1 顯示
1. 提供四種游標模式個別單獨設定
    - 個別尺寸設定與重設
    - 一鍵套用整個主題通用尺寸
1. 選取或拖曳 ANI 檔案至檔案區，即可在預覽區看到效果
1. 可拖曳或輸入數值調整定位點，按下「使用 ANI 預設」可恢復原始定位點
1. ANI 保存副本，移動原始檔不影響已匯入主題
1. 提供中英文介面

## 適用版本與限制

| 項目 | 狀態 |
| --- | --- |
| 最低建置目標 | macOS 14 |
| Apple Silicon | 已在 macOS 26.6.2 實機測試 |
| Intel | 包含 x86_64 原生執行檔，尚未實機測試 |
| macOS 14 / 15 | 保留舊游標名稱映射，尚未實機測試 |
| macOS 26 以上 | 使用 ArrowS / IBeamS 名稱，未來系統更新仍需驗證 |

## 資料儲存

`~/Library/Application Support/AniOnMac/`

| 路徑 | 內容 |
| --- | --- |
| `library.json` | 主題、語言、上一次設定 |
| `assets/` | 匯入的 ANI 副本 |
| `previews/` | 動畫預覽影格 |
| `backups/` | 每個主題最多一份系統游標備份 |
| `native-reset-recovery.cape` | 最近一次恢復原生外觀前的救援檔 |

清除模式只解除主題中的引用，不直接刪除 ANI 副本

## 專案結構

```text
AniOnMac/
├── AniOnMac.app/              # 本機建置的 App，下載版包含此檔案
├── README.md                  # 英文說明（預設）
├── README.tw.md               # 繁體中文說明
└── development/               # 程式碼與開發工具
    ├── app/
    │   ├── Studio.swift       # 主題、儲存、套用與復原
    │   └── Views.swift        # 介面、拖放與動畫預覽
    ├── native/
    │   ├── ANIConverter.swift # ANI 解碼、定位點對齊與轉檔
    │   ├── cursorctl.m        # 系統游標套用、備份與驗證
    │   ├── native_defaults.h  # 讀取 macOS 原生游標
    │   └── CursorRefresh.m    # 即時刷新與按鈕游標
    ├── resources/             # 中英文文字與 App 圖示
    ├── tests/                 # 轉檔與套用狀態測試
    ├── tools/                 # 圖示產生工具
    ├── build.sh               # 建置 Universal App
    ├── test.sh                # 執行測試
    └── package.sh             # 打包發佈 ZIP
```
