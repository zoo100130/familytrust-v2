# DESIGN.md — FamilyTrust 信託前端

風格參考：Better Stack（observability 儀表板）。冷調近黑底、柔和靛藍主色、資料密集但留白克制。
本檔給 AI coding agent 與協作者讀：改 UI 前先讀這份，不要另創顏色或字級。

---

## 1. Visual Theme & Atmosphere

- **氣質**：監控台，不是行銷頁。像在看一個「正在運作的信託」：數字、狀態、倒數、事件流。
- **密度**：中高。一屏要能看到關鍵 KPI + 24 期狀態格，不靠捲動。
- **原則**：顏色只用來表達「狀態」，不用來裝飾。主色靛藍只給「主要動作」與「目前選取」。
- **深色優先**。淺色模式為次要，跟隨系統 `prefers-color-scheme`。

## 2. Color Palette & Roles

| Token | Dark | Light | 角色 |
|---|---|---|---|
| `--bg` | `#0f101a` | `#f6f7fb` | 畫布 |
| `--surface` | `#161826` | `#ffffff` | 卡片 |
| `--surface-2` | `#1d2033` | `#eef0f7` | 卡片內嵌區、輸入框 |
| `--border` | `#272a3f` | `#dcdfeb` | 1px 分隔線 |
| `--text` | `#e6e8f2` | `#141626` | 主要文字 |
| `--muted` | `#8b90a8` | `#5a5f78` | 次要文字、標籤 |
| `--primary` | `#98a4f7` | `#5664d9` | 主要按鈕、選取中分頁、連結 |
| `--primary-weak` | `#98a4f71f` | `#5664d914` | 主色淡底 |
| `--success` | `#4fd18b` | `#1f9d5c` | 到期可領、存足、正常 |
| `--warning` | `#f2b84b` | `#a86b00` | 掛單中、需注意 |
| `--danger` | `#f27171` | `#c93b3b` | 暫停、錯誤、被擋下 |
| `--s1` | `#3987e5` | `#2a78d6` | 圖表系列 1：受益人 |
| `--s2` | `#d95926` | `#eb6834` | 圖表系列 2：承購人（已售期數） |

圖表系列色已用 dataviz 驗證器檢查（深淺兩種模式、色盲 ΔE ≥ 24）。系列色只代表「錢付給誰」，不可拿來表示成功／失敗。

期數狀態固定對應：已領 = muted 灰、到期可領 = success、受益人持有 = s1 淡底、掛單中 = warning 虛線框、已售 = s2 淡底。

## 3. Typography Rules

- 拉丁字：`Inter`（替代 Helvetica Now Display/Text）；中文：`Noto Sans TC`；等寬：`JetBrains Mono`。
- **所有金額、期數、地址、倒數一律等寬 + `font-variant-numeric: tabular-nums`**，數字欄位要能對齊。

| 用途 | 大小 / 字重 / 行高 |
|---|---|
| Hero 數字（可領金額） | 40px / 600 / 1.1，等寬 |
| KPI 數字 | 22px / 600 / 1.2，等寬 |
| 頁面標題 | 20px / 600 |
| 卡片標題 | 14px / 600 |
| 內文 | 14px / 400 / 1.6 |
| 標籤 | 12px / 500，muted（不用全大寫、不加字距，避免模板感） |
| 表格 | 13px |
| 地址、hash | 12px 等寬 |

## 4. Component Stylings

- **Button / primary**：`--primary` 底、`#0f101a` 字、圓角 8px、高 36px、字重 600。hover 亮 8%，disabled 40% 透明。
- **Button / secondary**：透明底、1px `--border`、`--text` 字。
- **Button / danger**：透明底、`--danger` 字與框（暫停）。
- **Card**：`--surface` 底、1px `--border`、圓角 12px、padding 16–20px，無陰影。
- **KPI tile**：eyebrow 標籤 + KPI 數字 + 一行 muted 說明；狀態用左側 3px 色條，不用整塊上色。
- **Status pill**：圓角 999px、12px、色字 + 12% 透明同色底，前面 6px 圓點。
- **Period cell**：正方、圓角 6px、等寬期數編號，hover 顯示 tooltip（到期時間、擁有者）。
- **Tabs**：底線式，選取中 = `--primary` 2px 底線 + `--text`；未選 = muted。分頁旁可附「你」小標。
- **Input**：`--surface-2` 底、1px `--border`、圓角 8px、focus 2px `--primary` outline。
- **Table**：無外框，列間 1px `--border`，表頭 muted 12px。數字欄靠右。
- **Toast**：右下角，`--surface` 底 + 左側狀態色條，交易 hash 連 Etherscan。

## 5. Layout Principles

- **產品外殼**：左側 240px 側欄（品牌、信託切換器、分組導覽：工作台／分析／系統、底部錢包），右側頂列（麵包屑、狀態、重新整理、錢包）。< 960px 側欄收成抽屜。
- **頁面**：總覽、出資人、受益人、承購人、現金流、承購市場與定價、帳簿、規則與權限、設定。網址 hash 對應頁面（`#cashflow`）。
- **圖表**：內嵌 SVG，無外部函式庫；一律單一 y 軸、2px 線、4px 圓角柱、虛線「現在」標記、滑鼠十字線 + tooltip；未到期用斜線紋理表示，不只靠顏色。

- 間距 4px 基準：4 / 8 / 12 / 16 / 24 / 32。
- 內容最大寬 1200px，置中，左右 gutter ≥ 16px。
- 頂列：品牌、網路、合約地址、錢包。其下為角色分頁。
- 總覽：KPI 列（auto-fit，最小 170px）→ 期數格 → 兩欄（掛單 | 事件）。
- 角色頁：左 2/3 主要動作，右 1/3 相關數字；< 900px 疊成單欄。

## 6. Depth & Elevation

- 不用陰影分層，用底色階：`--bg` < `--surface` < `--surface-2`。
- 唯一例外：toast 與 tooltip 使用 `0 8px 24px rgba(0,0,0,.35)`。

## 7. Do's and Don'ts

**Do**
- 每個數字都標單位（FTUSD、期、%）。
- 被合約擋下的原因用中文顯示，同時保留錯誤名稱（`AprTooHigh`）供 Q&A。
- 角色頁只放該角色能做的動作；其他人的資訊用唯讀呈現。
- 交易進行中按鈕顯示「簽名中… / 上鏈中…」。

**Don't**
- 不用漸層、插畫、emoji 當裝飾。
- 不用紅綠以外的顏色表示成功/失敗。
- 不把地址全長塞進表格，用 `0x1234…abcd` + 複製。
- 不在前端存私鑰或任何使用者資料（合約地址存在 localStorage 可以）。

## 8. Responsive Behavior

- 斷點：≥ 900px 兩欄；< 900px 單欄；< 520px 期數格 6 欄、KPI 2 欄。
- 觸控目標 ≥ 40px。
- 表格在窄螢幕水平捲動，不換行壓縮數字。

## 9. Agent Prompt Guide

- 主色 `#98a4f7`、畫布 `#0f101a`、卡片 `#161826`、框線 `#272a3f`。
- 「新增一個 KPI」：用 `.kpi` 元件、等寬數字、左側狀態色條。
- 「新增一個角色動作」：放進該角色分頁的主要欄，按鈕用 primary，錯誤走 `ZH` 對照表。
- 範例 prompt：*「依 DESIGN.md，在承購人分頁加一張卡片顯示我持有期數的到期日列表，數字等寬、靠右對齊。」*
