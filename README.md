# FamilyTrust V2

可升級（UUPS）的鏈上信託：出資人存入、受益人每期領取，未來期數可以折價賣給承購人或做市商，到期款也能直接付給核可的收款方。

**網站**：https://zoo100130.github.io/familytrust-v2/
網址加 `?trust=<Proxy 地址>` 載入合約，加 `?demo=1` 看示範資料。

## 功能

| 類別 | 內容 |
|---|---|
| 撥款 | 出資人存入、每期到期由擁有者領取、有上限的暫停（只凍結受益人） |
| 承購市場 | 任何持有人都能掛單出售，售價受年化上限保護 |
| 支付 | 出資人提名、受益人同意的收款方；領取並直付、錢包付款、每段期間上限 |
| 做市商 | 常駐收購報價（資金託管）、賣給報價立即成交、轉售、轉讓 |
| 升級 | UUPS，升級管理員可升級或永久凍結 |
| 資料分享 | 受益人授權出資人查看財務紀錄（`RecordConsent`，選用） |

## 檔案

| 路徑 | 說明 |
|---|---|
| `contracts/FamilyTrustV2.sol` | 組裝模組與升級權限，**部署只部署這份** |
| `contracts/interfaces/IFamilyTrustV2.sol` | 規格書：資料結構、錯誤、事件 |
| `contracts/storage/TrustStorage.sol` | 全部狀態變數（升級時只能往後加） |
| `contracts/modules/TrustSchedule.sol` | 撥款排程：存入、每期歸屬、領取、擔保率 |
| `contracts/modules/SettlorControls.sol` | 出資人有上限的暫停 |
| `contracts/modules/ListingMarket.sol` | 承購市場：掛單、承購、轉讓、報價 |
| `contracts/modules/BidBook.sol` | 做市商收購報價：掛報價、賣給報價、取消 |
| `contracts/modules/Payments.sol` | 支付：收款方提名與核可、領取並直付、錢包付款 |
| `contracts/libraries/PeriodPricing.sol` | 時間價值純數學：現值與隱含年化 |
| `contracts/RecordConsent.sol` | 受益人授權查詢（獨立部署，不需參數） |
| `index.html` | 前端控制台（單一檔案，ethers.js 6） |
| `DEPLOY.md` | 在 Remix 匯入與部署的步驟 |
| `DESIGN.md` | 介面設計規範 |

## 繼承關係

```
IFamilyTrustV2（規格）
   └─ TrustStorage（全部狀態）
        └─ TrustSchedule（核心）
             ├─ SettlorControls
             ├─ ListingMarket ── 使用 PeriodPricing
             │    └─ BidBook
             └─ Payments
FamilyTrustV2 = Initializable + UUPSUpgradeable + SettlorControls + BidBook + Payments
```

模組之間用「掛勾」溝通：`TrustSchedule` 宣告 `_isPaused()`，由 `SettlorControls` 實作。

## 開啟 GitHub Pages

Settings → Pages → Build and deployment：Source 選 **Deploy from a branch**，Branch 選 **main / (root)** → Save。

舊版（不可升級合約）在 https://github.com/zoo100130/dapp_family-trust_test
