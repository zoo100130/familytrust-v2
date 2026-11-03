// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title  FamilyTrustV2：可升級的鏈上信託（撥款 + 承購市場 + 支付 + 做市報價）
/// @notice 單一檔案，在 Remix 用「Deploy with Proxy」部署（UUPS）。
///         initialize 的 c 一次貼上，例如：
///         ["代幣Proxy","出資人","受益人",120,500,24,2500,12,3,6,3,600]
///
///  功能：
///  - 撥款排程：出資人存入，每期到期由擁有者領取（拉式付款）
///  - 承購市場：任何期數持有人（受益人或承購人）都能掛單出售，售價受年化上限保護
///  - 做市報價：做市商託管資金、掛出「以 X% 年化收購」的常駐報價，持有人可立即成交
///  - 期數轉讓：承購人可把持有的期數轉給他人（場外成交）
///  - 支付：出資人提名、受益人同意的收款方；受益人可「領取並直接付款」或從錢包付款，每段期間有上限
///  - 有上限的暫停：只凍結受益人，承購人不受影響
///  - 升級：升級管理員（預設出資人）可升級，也可永久凍結升級
contract FamilyTrustV2 is Initializable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // ───────────────────────── 型別 ─────────────────────────
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

    struct Listing {
        uint256 fromId;
        uint256 toId;
        uint256 price;
        bool active;
        address seller;
        address buyer;
    }

    struct Bid {
        address maker;      // 做市商
        uint256 aprBps;     // 願意收購的年化（越低出價越高）
        uint256 budget;     // 剩餘託管資金（鏈上整數）
        uint256 maxPeriods; // 還願意收幾期
        bool active;
    }

    struct Payee {
        bool proposed;      // 出資人已提名
        bool approved;      // 受益人已同意
        uint256 cap;        // 每段期間付款上限（鏈上整數，0 = 不限）
        string label;       // 名稱，例如「仁愛醫院」
    }

    // ───────────────────────── 錯誤 ─────────────────────────
    error NotSettlor();
    error NotBeneficiary();
    error NotUpgradeAdmin();
    error UpgradesFrozen();
    error InvalidParams();
    error ZeroAmount();
    error InvalidRange();
    error OverFunded();
    error InsufficientFunds();
    error NotFullyFunded();
    error NothingToClaim();
    error PeriodAlreadyDue();
    error PeriodNotOwned();
    error AlreadyListed();
    error PriceTooHigh();
    error AprTooHigh();
    error ListingNotActive();
    error CannotBuyOwn();
    error SettlorCannotBuy();
    error TrustPaused();
    error AlreadyPaused();
    error NotPaused();
    error PauseTooLong();
    error PauseBudgetExceeded();
    error BidNotActive();
    error NotBidMaker();
    error BidTooSmall();
    error BeneficiaryCannotTransfer();
    error PayeeNotApproved();
    error PayCapExceeded();
    error Reentrancy();

    // ───────────────────────── 事件 ─────────────────────────
    event Funded(address indexed from, uint256 amount);
    event Claimed(address indexed to, uint256 periods, uint256 amount);
    event Listed(uint256 indexed listingId, address indexed seller, uint256 fromId, uint256 toId, uint256 price);
    event ListingCancelled(uint256 indexed listingId);
    event PeriodsSold(uint256 indexed listingId, address indexed buyer, uint256 price);
    event BidPlaced(uint256 indexed bidId, address indexed maker, uint256 aprBps, uint256 budget, uint256 maxPeriods);
    event BidCancelled(uint256 indexed bidId, uint256 refund);
    event BidFilled(uint256 indexed bidId, address indexed seller, uint256 fromId, uint256 toId, uint256 price);
    event PeriodsTransferred(address indexed from, address indexed to, uint256 fromId, uint256 toId);
    event PayeeProposed(address indexed payee, uint256 cap, string label);
    event PayeeApproved(address indexed payee);
    event PayeeRemoved(address indexed payee, address by);
    event Paid(address indexed payee, uint256 amount, bool fromTrust, string memo);
    event Paused(address by, uint256 until);
    event Unpaused(address by);
    event UpgradeAdminChanged(address indexed admin);
    event UpgradesFrozenForever();

    // ───────────────────────── 儲存（只能往後加）─────────────────────────
    IERC20 public token;
    address public settlor;
    address public beneficiary;
    address public upgradeAdmin;
    bool public upgradesFrozen;

    uint256 public unit;
    uint256 public startTime;
    uint256 public interval;
    uint256 public amountPerPeriod;
    uint256 public totalPeriods;
    uint256 public maxAprBps;
    uint256 public periodsPerYear;
    uint256 public maxPausePeriods;
    uint256 public pauseBudgetPeriods;
    uint256 public payWindow;

    mapping(uint256 => bool) public claimed;
    mapping(uint256 => address) internal _holder; // 0 = 仍屬受益人
    uint256 public claimedCount;

    uint256 public pausedUntil;
    uint256 public pauseUsedPeriods;

    Listing[] internal _listings;
    mapping(uint256 => uint256) internal _listedIn; // 掛單編號 + 1；0 = 沒掛

    Bid[] internal _bids;
    uint256 public bidEscrow; // 做市商託管中的資金，不屬於信託資金池

    mapping(address => Payee) internal _payees;
    address[] internal _payeeList;
    mapping(address => mapping(uint256 => uint256)) public paidInWindow; // 收款方 => 期間編號 => 已付

    uint256 private _lock;

    uint256[40] private __gap;

    uint256 private constant BPS = 10_000;

    // ───────────────────────── 修飾器 ─────────────────────────
    modifier onlySettlor() {
        if (msg.sender != settlor) revert NotSettlor();
        _;
    }

    modifier onlyBeneficiary() {
        if (msg.sender != beneficiary) revert NotBeneficiary();
        _;
    }

    modifier nonReentrant() {
        if (_lock == 1) revert Reentrancy();
        _lock = 1;
        _;
        _lock = 0;
    }

    // ───────────────────────── 初始化 ─────────────────────────
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(Config calldata c) external initializer {
        if (
            c.token == address(0) || c.settlor == address(0) || c.beneficiary == address(0)
                || c.beneficiary == c.settlor || c.intervalSeconds == 0 || c.amountPerPeriodTokens == 0
                || c.totalPeriods == 0 || c.periodsAlreadyDue >= c.totalPeriods || c.periodsPerYear == 0
                || c.maxAprBps == 0 || c.maxAprBps > BPS * 10 || c.maxPausePeriods > c.pauseBudgetPeriods
                || c.payWindowSeconds == 0
        ) revert InvalidParams();

        uint256 u = 10 ** IERC20Metadata(c.token).decimals();
        token = IERC20(c.token);
        settlor = c.settlor;
        beneficiary = c.beneficiary;
        upgradeAdmin = c.settlor;
        unit = u;
        interval = c.intervalSeconds;
        amountPerPeriod = c.amountPerPeriodTokens * u;
        totalPeriods = c.totalPeriods;
        maxAprBps = c.maxAprBps;
        periodsPerYear = c.periodsPerYear;
        maxPausePeriods = c.maxPausePeriods;
        pauseBudgetPeriods = c.pauseBudgetPeriods;
        payWindow = c.payWindowSeconds;
        startTime = block.timestamp - c.periodsAlreadyDue * c.intervalSeconds;
        emit UpgradeAdminChanged(c.settlor);
    }

    // ───────────────────────── 升級 ─────────────────────────
    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != upgradeAdmin) revert NotUpgradeAdmin();
        if (upgradesFrozen) revert UpgradesFrozen();
    }

    /// @notice 把升級權交給別人（例如之後的多簽）
    function setUpgradeAdmin(address admin) external {
        if (msg.sender != upgradeAdmin) revert NotUpgradeAdmin();
        if (admin == address(0)) revert InvalidParams();
        upgradeAdmin = admin;
        emit UpgradeAdminChanged(admin);
    }

    /// @notice 永久放棄升級權：規則從此固定
    function freezeUpgrades() external {
        if (msg.sender != upgradeAdmin) revert NotUpgradeAdmin();
        upgradesFrozen = true;
        emit UpgradesFrozenForever();
    }

    function version() external pure returns (string memory) {
        return "2.0.0";
    }

    // ───────────────────────── 存入與領取 ─────────────────────────
    function fund(uint256 amountTokens) external onlySettlor nonReentrant {
        uint256 amount = amountTokens * unit;
        if (amount == 0) revert ZeroAmount();
        if (poolBalance() + amount > unpaidLiabilities()) revert OverFunded();
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount);
    }

    /// @notice 領取自己持有、已到期的期數（受益人與承購人共用）
    function claim() external nonReentrant {
        uint256 amount = _claimDue(msg.sender);
        token.safeTransfer(msg.sender, amount);
    }

    /// @notice 受益人領取到期款，其中 amount 直接付給已核可的收款方，其餘轉給受益人
    function claimAndPay(address payee, uint256 amount, string calldata memo) external onlyBeneficiary nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 total = _claimDue(msg.sender);
        if (amount > total) revert InsufficientFunds();
        _checkPayee(payee, amount);
        token.safeTransfer(payee, amount);
        if (total > amount) token.safeTransfer(msg.sender, total - amount);
        emit Paid(payee, amount, true, memo);
    }

    /// @notice 受益人從自己的錢包付款給收款方（需先 approve），留下鏈上付款紀錄
    function payFromWallet(address payee, uint256 amount, string calldata memo) external onlyBeneficiary nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _checkPayee(payee, amount);
        token.safeTransferFrom(msg.sender, payee, amount);
        emit Paid(payee, amount, false, memo);
    }

    function _claimDue(address who) internal returns (uint256 amount) {
        bool blocked = who == beneficiary && _isPaused();
        uint256 due = _dueCount();
        uint256 count;
        for (uint256 i = 0; i < due; i++) {
            if (blocked || claimed[i] || periodOwner(i) != who) continue;
            claimed[i] = true;
            count++;
        }
        if (count == 0) {
            if (blocked) revert TrustPaused();
            revert NothingToClaim();
        }
        amount = count * amountPerPeriod;
        if (poolBalance() < amount + _reservedForOthers(who)) revert InsufficientFunds();
        claimedCount += count;
        emit Claimed(who, count, amount);
    }

    // ───────────────────────── 支付收款方 ─────────────────────────
    /// @notice 出資人提名收款方（例如醫院、安養院），受益人同意後才能付款
    function proposePayee(address payee, uint256 capTokens, string calldata label) external onlySettlor {
        if (payee == address(0) || payee == beneficiary || payee == settlor) revert InvalidParams();
        Payee storage p = _payees[payee];
        if (!p.proposed) _payeeList.push(payee);
        p.proposed = true;
        p.approved = false; // 條件改變就要重新同意
        p.cap = capTokens * unit;
        p.label = label;
        emit PayeeProposed(payee, p.cap, label);
    }

    function approvePayee(address payee) external onlyBeneficiary {
        Payee storage p = _payees[payee];
        if (!p.proposed) revert PayeeNotApproved();
        p.approved = true;
        emit PayeeApproved(payee);
    }

    /// @notice 出資人或受益人任一方都可以移除收款方
    function removePayee(address payee) external {
        if (msg.sender != settlor && msg.sender != beneficiary) revert NotBeneficiary();
        Payee storage p = _payees[payee];
        p.proposed = false;
        p.approved = false;
        emit PayeeRemoved(payee, msg.sender);
    }

    function _checkPayee(address payee, uint256 amount) internal {
        Payee storage p = _payees[payee];
        if (!p.proposed || !p.approved) revert PayeeNotApproved();
        uint256 w = block.timestamp / payWindow;
        uint256 used = paidInWindow[payee][w] + amount;
        if (p.cap != 0 && used > p.cap) revert PayCapExceeded();
        paidInWindow[payee][w] = used;
    }

    // ───────────────────────── 暫停 ─────────────────────────
    function pause(uint256 periods) external onlySettlor {
        if (_isPaused()) revert AlreadyPaused();
        if (periods == 0 || periods > maxPausePeriods) revert PauseTooLong();
        if (pauseUsedPeriods + periods > pauseBudgetPeriods) revert PauseBudgetExceeded();
        pauseUsedPeriods += periods;
        pausedUntil = block.timestamp + periods * interval;
        emit Paused(msg.sender, pausedUntil);
    }

    function unpause() external onlySettlor {
        if (!_isPaused()) revert NotPaused();
        pausedUntil = block.timestamp;
        emit Unpaused(msg.sender);
    }

    // ───────────────────────── 承購市場（任何持有人都能賣）─────────────────────────
    function listPeriods(uint256 fromId, uint256 toId, uint256 priceTokens) external returns (uint256 listingId) {
        _checkSellable(msg.sender, fromId, toId);
        uint256 price = priceTokens * unit;
        if (price == 0) revert ZeroAmount();
        if (price >= (toId - fromId + 1) * amountPerPeriod) revert PriceTooHigh();
        if (price < quote(fromId, toId, maxAprBps)) revert AprTooHigh();
        listingId = _listings.length;
        _listings.push(Listing(fromId, toId, price, true, msg.sender, address(0)));
        for (uint256 i = fromId; i <= toId; i++) _listedIn[i] = listingId + 1;
        emit Listed(listingId, msg.sender, fromId, toId, price);
    }

    function cancelListing(uint256 listingId) external {
        Listing storage l = _activeListing(listingId);
        if (msg.sender != l.seller) revert PeriodNotOwned();
        l.active = false;
        _unlist(l.fromId, l.toId);
        emit ListingCancelled(listingId);
    }

    function buy(uint256 listingId) external nonReentrant {
        Listing storage l = _activeListing(listingId);
        if (msg.sender == l.seller || msg.sender == beneficiary) revert CannotBuyOwn();
        if (msg.sender == settlor) revert SettlorCannotBuy();
        if (l.seller == beneficiary && _isPaused()) revert TrustPaused();
        if (l.fromId < _dueCount()) revert PeriodAlreadyDue();
        if (l.price < quote(l.fromId, l.toId, maxAprBps)) revert AprTooHigh();
        if (!_isFullyFunded()) revert NotFullyFunded();
        l.active = false;
        l.buyer = msg.sender;
        _unlist(l.fromId, l.toId);
        _setHolder(l.fromId, l.toId, msg.sender);
        token.safeTransferFrom(msg.sender, l.seller, l.price);
        emit PeriodsSold(listingId, msg.sender, l.price);
    }

    // ───────────────────────── 做市報價 ─────────────────────────
    /// @notice 做市商掛出常駐收購報價：以 aprBps 年化收購，最多 maxPeriods 期，資金先託管在合約
    function placeBid(uint256 aprBps, uint256 budgetTokens, uint256 maxPeriods_) external nonReentrant returns (uint256 bidId) {
        if (msg.sender == beneficiary) revert CannotBuyOwn();
        if (msg.sender == settlor) revert SettlorCannotBuy();
        if (aprBps > maxAprBps) revert AprTooHigh();
        uint256 budget = budgetTokens * unit;
        if (budget == 0 || maxPeriods_ == 0) revert ZeroAmount();
        token.safeTransferFrom(msg.sender, address(this), budget);
        bidEscrow += budget;
        bidId = _bids.length;
        _bids.push(Bid(msg.sender, aprBps, budget, maxPeriods_, true));
        emit BidPlaced(bidId, msg.sender, aprBps, budget, maxPeriods_);
    }

    function cancelBid(uint256 bidId) external nonReentrant {
        if (bidId >= _bids.length || !_bids[bidId].active) revert BidNotActive();
        Bid storage b = _bids[bidId];
        if (msg.sender != b.maker) revert NotBidMaker();
        uint256 refund = b.budget;
        b.active = false;
        b.budget = 0;
        bidEscrow -= refund;
        if (refund > 0) token.safeTransfer(b.maker, refund);
        emit BidCancelled(bidId, refund);
    }

    /// @notice 持有人把期數直接賣給做市商報價，立即拿到錢
    function sellToBid(uint256 bidId, uint256 fromId, uint256 toId) external nonReentrant {
        if (bidId >= _bids.length || !_bids[bidId].active) revert BidNotActive();
        Bid storage b = _bids[bidId];
        if (msg.sender == b.maker) revert CannotBuyOwn();
        _checkSellable(msg.sender, fromId, toId);
        uint256 n = toId - fromId + 1;
        if (n > b.maxPeriods) revert BidTooSmall();
        uint256 price = quote(fromId, toId, b.aprBps);
        if (price > b.budget) revert BidTooSmall();
        b.budget -= price;
        b.maxPeriods -= n;
        bidEscrow -= price;
        if (b.maxPeriods == 0 || b.budget == 0) {
            uint256 rest = b.budget;
            b.active = false;
            b.budget = 0;
            bidEscrow -= rest;
            if (rest > 0) token.safeTransfer(b.maker, rest);
        }
        _setHolder(fromId, toId, b.maker);
        token.safeTransfer(msg.sender, price);
        emit BidFilled(bidId, msg.sender, fromId, toId, price);
    }

    // ───────────────────────── 期數轉讓 ─────────────────────────
    /// @notice 承購人把期數轉給別人（受益人不能直接轉，避免繞過定價保護）
    function transferPeriods(address to, uint256 fromId, uint256 toId) external {
        if (msg.sender == beneficiary) revert BeneficiaryCannotTransfer();
        if (to == address(0) || to == settlor || to == msg.sender) revert InvalidParams();
        if (fromId > toId || toId >= totalPeriods) revert InvalidRange();
        for (uint256 i = fromId; i <= toId; i++) {
            if (claimed[i] || periodOwner(i) != msg.sender) revert PeriodNotOwned();
            if (_listedIn[i] != 0) revert AlreadyListed();
        }
        _setHolder(fromId, toId, to);
        emit PeriodsTransferred(msg.sender, to, fromId, toId);
    }

    // ───────────────────────── 內部 ─────────────────────────
    function _checkSellable(address seller, uint256 fromId, uint256 toId) internal view {
        if (seller == settlor) revert SettlorCannotBuy();
        if (seller == beneficiary && _isPaused()) revert TrustPaused();
        if (fromId > toId || toId >= totalPeriods) revert InvalidRange();
        if (fromId < _dueCount()) revert PeriodAlreadyDue();
        for (uint256 i = fromId; i <= toId; i++) {
            if (periodOwner(i) != seller) revert PeriodNotOwned();
            if (_listedIn[i] != 0) revert AlreadyListed();
        }
        if (!_isFullyFunded()) revert NotFullyFunded();
    }

    function _setHolder(uint256 fromId, uint256 toId, address to) internal {
        address h = to == beneficiary ? address(0) : to;
        for (uint256 i = fromId; i <= toId; i++) _holder[i] = h;
    }

    function _activeListing(uint256 listingId) internal view returns (Listing storage l) {
        if (listingId >= _listings.length) revert ListingNotActive();
        l = _listings[listingId];
        if (!l.active) revert ListingNotActive();
    }

    function _unlist(uint256 fromId, uint256 toId) internal {
        for (uint256 i = fromId; i <= toId; i++) _listedIn[i] = 0;
    }

    function _isPaused() internal view returns (bool) {
        return block.timestamp < pausedUntil;
    }

    function _dueCount() internal view returns (uint256 n) {
        if (block.timestamp < startTime) return 0;
        n = (block.timestamp - startTime) / interval;
        if (n > totalPeriods) n = totalPeriods;
    }

    function _reservedForOthers(address exclude) internal view returns (uint256 total) {
        for (uint256 i = 0; i < totalPeriods; i++) {
            if (claimed[i]) continue;
            address h = _holder[i];
            if (h != address(0) && h != exclude) total += amountPerPeriod;
        }
    }

    function _isFullyFunded() internal view returns (bool) {
        return poolBalance() >= unpaidLiabilities();
    }

    // ───────────────────────── 查詢 ─────────────────────────
    /// @notice 信託資金池（不含做市商託管的錢）
    function poolBalance() public view returns (uint256) {
        return token.balanceOf(address(this)) - bidEscrow;
    }

    function periodOwner(uint256 i) public view returns (address) {
        address h = _holder[i];
        return h == address(0) ? beneficiary : h;
    }

    function dueTime(uint256 i) public view returns (uint256) {
        return startTime + (i + 1) * interval;
    }

    function unpaidLiabilities() public view returns (uint256) {
        return (totalPeriods - claimedCount) * amountPerPeriod;
    }

    function coverageBps() external view returns (uint256) {
        uint256 owed = unpaidLiabilities();
        if (owed == 0) return BPS;
        return poolBalance() * BPS / owed;
    }

    function paused() external view returns (bool) {
        return _isPaused();
    }

    function pauseBudgetLeft() external view returns (uint256) {
        return pauseBudgetPeriods - pauseUsedPeriods;
    }

    function claimable(address who) external view returns (uint256 periods, uint256 amount) {
        if (who == beneficiary && _isPaused()) return (0, 0);
        uint256 due = _dueCount();
        for (uint256 i = 0; i < due; i++) {
            if (!claimed[i] && periodOwner(i) == who) periods++;
        }
        amount = periods * amountPerPeriod;
    }

    function nextPayout() external view returns (bool exists, uint256 periodId, uint256 time) {
        uint256 due = _dueCount();
        if (due >= totalPeriods) return (false, 0, 0);
        return (true, due, dueTime(due));
    }

    function quote(uint256 fromId, uint256 toId, uint256 aprBps) public view returns (uint256) {
        if (fromId > toId || toId >= totalPeriods) revert InvalidRange();
        uint256 due = _dueCount();
        if (fromId < due) revert PeriodAlreadyDue();
        return _presentValue(fromId + 1 - due, toId - fromId + 1, aprBps);
    }

    function impliedAprBps(uint256 listingId) external view returns (uint256) {
        Listing storage l = _listings[listingId];
        if (!l.active || l.fromId < _dueCount()) return 0;
        return _impliedApr(l.price, l.fromId + 1 - _dueCount(), l.toId - l.fromId + 1);
    }

    function listingDiscountBps(uint256 listingId) external view returns (uint256) {
        Listing storage l = _listings[listingId];
        uint256 face = (l.toId - l.fromId + 1) * amountPerPeriod;
        return (face - l.price) * BPS / face;
    }

    function listingsCount() external view returns (uint256) {
        return _listings.length;
    }

    function bidsCount() external view returns (uint256) {
        return _bids.length;
    }

    function getListings() external view returns (Listing[] memory) {
        return _listings;
    }

    function getBids() external view returns (Bid[] memory) {
        return _bids;
    }

    /// @notice 一次讀出所有期數的擁有者、是否已領、到期時間（給前端與做市商）
    function getPeriods() external view returns (address[] memory owners, bool[] memory claimedArr, uint256[] memory dueTimes) {
        uint256 n = totalPeriods;
        owners = new address[](n);
        claimedArr = new bool[](n);
        dueTimes = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            owners[i] = periodOwner(i);
            claimedArr[i] = claimed[i];
            dueTimes[i] = dueTime(i);
        }
    }

    function getPayees()
        external
        view
        returns (address[] memory addrs, bool[] memory approved, uint256[] memory caps, uint256[] memory usedNow, string[] memory labels)
    {
        uint256 n = _payeeList.length;
        uint256 w = block.timestamp / payWindow;
        addrs = new address[](n);
        approved = new bool[](n);
        caps = new uint256[](n);
        usedNow = new uint256[](n);
        labels = new string[](n);
        for (uint256 i = 0; i < n; i++) {
            address a = _payeeList[i];
            Payee storage p = _payees[a];
            addrs[i] = a;
            approved[i] = p.proposed && p.approved;
            caps[i] = p.proposed ? p.cap : type(uint256).max; // 已移除的收款方回傳 max
            usedNow[i] = paidInWindow[a][w];
            labels[i] = p.label;
        }
    }

    // ───────────────────────── 定價數學（單利）─────────────────────────
    function _presentValue(uint256 firstWait, uint256 count, uint256 aprBps) internal view returns (uint256 pv) {
        uint256 scale = BPS * periodsPerYear;
        for (uint256 j = 0; j < count; j++) {
            pv += amountPerPeriod * scale / (scale + aprBps * (firstWait + j));
        }
    }

    function _impliedApr(uint256 price, uint256 firstWait, uint256 count) internal view returns (uint256) {
        uint256 lo = 0;
        uint256 hi = BPS * 100; // 10000%
        for (uint256 k = 0; k < 40; k++) {
            uint256 mid = (lo + hi) / 2;
            if (_presentValue(firstWait, count, mid) > price) lo = mid;
            else hi = mid;
        }
        return hi;
    }
}
