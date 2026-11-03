// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IFamilyTrustV2：規格書
/// @notice 只定義資料結構、錯誤、事件，沒有任何邏輯。
interface IFamilyTrustV2 {
    /// @notice 部署設定（initialize 一次傳入）
    struct Config {
        address token;                 // 代幣 Proxy 地址
        address settlor;               // 出資人
        address beneficiary;           // 受益人
        uint256 intervalSeconds;       // 每期間隔（秒）
        uint256 amountPerPeriodTokens; // 每期顆數
        uint256 totalPeriods;          // 總期數
        uint256 maxAprBps;             // 承購年化上限（萬分比）
        uint256 periodsPerYear;        // 定價時一年幾期
        uint256 maxPausePeriods;       // 單次暫停上限
        uint256 pauseBudgetPeriods;    // 累計暫停上限
        uint256 periodsAlreadyDue;     // 部署時已到期幾期
        uint256 payWindowSeconds;      // 付款上限的計算期間（秒）
    }

    /// @notice 一張掛單（任何持有人都能賣）
    struct Listing {
        uint256 fromId;
        uint256 toId;
        uint256 price;
        bool active;
        address seller;
        address buyer;
    }

    /// @notice 做市商的常駐收購報價
    struct Bid {
        address maker;
        uint256 aprBps;
        uint256 budget;
        uint256 maxPeriods;
        bool active;
    }

    /// @notice 收款方（出資人提名、受益人同意）
    struct Payee {
        bool proposed;
        bool approved;
        uint256 cap;
        string label;
    }

    // ── 身分 ──
    error NotSettlor();
    error NotBeneficiary();
    error NotUpgradeAdmin();
    error CannotBuyOwn();
    error SettlorCannotBuy();
    error NotBidMaker();
    error BeneficiaryCannotTransfer();
    // ── 參數 ──
    error InvalidParams();
    error ZeroAmount();
    error InvalidRange();
    // ── 資金 ──
    error OverFunded();
    error InsufficientFunds();
    error NotFullyFunded();
    // ── 時間 ──
    error NothingToClaim();
    error PeriodAlreadyDue();
    // ── 市場 ──
    error PeriodNotOwned();
    error AlreadyListed();
    error PriceTooHigh();
    error AprTooHigh();
    error ListingNotActive();
    error BidNotActive();
    error BidTooSmall();
    // ── 支付 ──
    error PayeeNotApproved();
    error PayCapExceeded();
    // ── 暫停與升級 ──
    error TrustPaused();
    error AlreadyPaused();
    error NotPaused();
    error PauseTooLong();
    error PauseBudgetExceeded();
    error UpgradesFrozen();
    error Reentrancy();

    event Funded(address indexed from, uint256 amount);
    event Claimed(address indexed to, uint256 periods, uint256 amount);
    event Listed(uint256 indexed listingId, address indexed seller, uint256 fromId, uint256 toId, uint256 price);
    event ListingCancelled(uint256 indexed listingId);
    event PeriodsSold(uint256 indexed listingId, address indexed buyer, uint256 price);
    event PeriodsTransferred(address indexed from, address indexed to, uint256 fromId, uint256 toId);
    event BidPlaced(uint256 indexed bidId, address indexed maker, uint256 aprBps, uint256 budget, uint256 maxPeriods);
    event BidCancelled(uint256 indexed bidId, uint256 refund);
    event BidFilled(uint256 indexed bidId, address indexed seller, uint256 fromId, uint256 toId, uint256 price);
    event PayeeProposed(address indexed payee, uint256 cap, string label);
    event PayeeApproved(address indexed payee);
    event PayeeRemoved(address indexed payee, address by);
    event Paid(address indexed payee, uint256 amount, bool fromTrust, string memo);
    event Paused(address by, uint256 until);
    event Unpaused(address by);
    event UpgradeAdminChanged(address indexed admin);
    event UpgradesFrozenForever();
}
