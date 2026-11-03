# 在 Remix 部署 FamilyTrustV2

## 1. 把 repo 匯入 Remix

任選一種：

- **Git 外掛（整個專案）**：Remix 左側 Git 圖示 → **Clone** → 貼上
  `https://github.com/zoo100130/familytrust-v2` → Clone。
  完成後 Files 會出現一個新的 workspace，合約在 `contracts/`。
- **只匯入合約檔**：Remix 首頁 → **Import from GitHub / URL** → 貼上
  `https://github.com/zoo100130/familytrust-v2/blob/main/contracts/FamilyTrustV2.sol`

`@openzeppelin/...` 的 import 由 Remix 自動從 npm 下載，不用另外安裝。

## 2. 編譯

1. 打開 `contracts/FamilyTrustV2.sol`。
2. Solidity Compiler → 版本 **0.8.24 以上**。
3. Advanced Configurations → 勾 **Enable optimization**（runs 200）。
4. Compile。出現「Stack too deep」就再勾 **viaIR** 重新編譯。

## 3. 部署（UUPS Proxy）

1. Deploy & Run → Environment：**Browser Extension → Sepolia Testnet - MetaMask**，Account 選出資人。
2. Contract：**FamilyTrustV2**。
3. 勾 **Deploy with Proxy**；Verify 先關。
4. initialize 的 `c`（12 欄）：

   ```
   ["代幣Proxy","出資人","受益人",每期秒數,每期顆數,總期數,年化上限bps,一年幾期,單次暫停上限,累計暫停上限,已到期期數,付款上限期間秒數]
   ```

   範例：

   ```
   ["0x1A842710547581b77DEec6be633859C40B66B707","0x075265238245eA9370F5CDAcBE953F8e3E9F46c5","0x505D85f2f1242E8839aB7Eeb62169cdA6234A22a",300,500,24,2500,12,3,6,3,1800]
   ```

5. Deploy，MetaMask 會簽兩次（實作合約、Proxy）。
6. **之後一律使用 `ERC1967Proxy` 的地址。**

## 4. 開前端

```
https://zoo100130.github.io/familytrust-v2/?trust=<Proxy 地址>
```

出資人頁存入 → 支付頁提名收款方 → 受益人同意 → 做市商頁掛收購報價。

## 5. 之後要升級

改好合約後重新編譯 → Deploy & Run 勾 **Upgrade with Proxy** → 填原本的 Proxy 地址 → Deploy。
地址與資金不變。永久固定規則：在「規則與權限」按「永久凍結升級」。

## 檔案

| 路徑 | 說明 |
|---|---|
| `contracts/FamilyTrustV2.sol` | 可升級信託（撥款、承購、支付、做市報價） |
| `contracts/RecordConsent.sol` | 受益人授權查詢紀錄（獨立部署，不需參數） |
| `index.html` | 前端控制台（配合 FamilyTrustV2） |
| `DESIGN.md` | 介面設計規範 |
